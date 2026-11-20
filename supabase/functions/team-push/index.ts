import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'POST only' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL'), anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'), vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY');
  const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY');
  if (!supabaseUrl || !anonKey || !serviceKey || !vapidPublicKey || !vapidPrivateKey) return json({ error: 'Push service is not configured' }, 503);

  const authorization = request.headers.get('Authorization');
  if (!authorization) return json({ error: 'Authentication required' }, 401);
  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return json({ error: 'Authentication required' }, 401);

  let body: { event?: string; entity_id?: string; attendance_id?: string; team_id?: string; schedule_scope?: string; week_start?: string | null };
  try { body = await request.json(); } catch { return json({ error: 'Invalid JSON body' }, 400); }
  const event = body.event || '';
  const entityId = body.entity_id || body.attendance_id || '';
  if (!entityId || !['check_in', 'check_out', 'backfill', 'report', 'request', 'request_comment', 'schedule'].includes(event)) return json({ error: 'Invalid notification event' }, 400);

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  let teamId = '', actorId = '', recipientIds: string[] = [], title = '', detail = '', date = '', eventKey = '';
  if (['check_in', 'check_out', 'backfill'].includes(event)) {
    const { data: attendance, error } = await admin.from('attendance').select('id,team_id,user_id,work_date,uploaded_at,checked_out_at,is_backfilled').eq('id', entityId).maybeSingle();
    if (error || !attendance) return json({ error: 'Attendance record not found' }, 404);
    if (attendance.user_id !== user.id) return json({ error: 'You cannot notify for this record' }, 403);
    if (event === 'check_out' && !attendance.checked_out_at) return json({ error: 'Checkout is not recorded yet' }, 409);
    if (event === 'backfill' && !attendance.is_backfilled) return json({ error: 'This is not a backfill record' }, 409);
    teamId = attendance.team_id; actorId = attendance.user_id; date = attendance.work_date;
    title = event === 'check_in' ? '출근 인증' : event === 'check_out' ? '퇴근 인증' : '출퇴근 기록 등록';
    detail = event === 'check_in' ? '출근 사진을 등록했어요.' : event === 'check_out' ? '퇴근 사진을 등록했어요.' : `${date} 출퇴근 사진을 사후 등록했어요.`;
  } else if (event === 'report') {
    const { data: report } = await admin.from('reports').select('id,team_id,user_id,work_date,updated_at').eq('id', entityId).maybeSingle();
    if (!report) return json({ error: 'Report not found' }, 404);
    if (report.user_id !== user.id) return json({ error: 'You cannot notify for this report' }, 403);
    const { data: member } = await admin.from('team_members').select('display_name').eq('team_id', report.team_id).eq('user_id', report.user_id).maybeSingle();
    if (!member) return json({ error: 'Team membership required' }, 403);
    teamId = report.team_id; actorId = report.user_id; date = report.work_date; title = '퇴근 보고 등록'; detail = `${member.display_name}님이 퇴근 보고를 저장했어요.`;
    const { data: teamMembers } = await admin.from('team_members').select('user_id').eq('team_id', report.team_id);
    recipientIds = (teamMembers || []).map(row => row.user_id).filter(id => id !== actorId);
    eventKey = `report:${entityId}:${report.updated_at}`;
  } else if (event === 'request') {
    const { data: item } = await admin.from('change_requests').select('id,team_id,requester_id,assignee_id,task_id').eq('id', entityId).maybeSingle();
    if (!item) return json({ error: 'Request not found' }, 404);
    if (item.requester_id !== user.id) return json({ error: 'You cannot notify for this request' }, 403);
    const [{ data: task }, { data: member }] = await Promise.all([
      item.task_id ? admin.from('tasks').select('title').eq('id', item.task_id).maybeSingle() : Promise.resolve({ data: null }),
      admin.from('team_members').select('display_name').eq('team_id', item.team_id).eq('user_id', user.id).maybeSingle()
    ]);
    teamId = item.team_id; actorId = user.id; recipientIds = [item.assignee_id]; title = '새 수정 요청'; detail = `${member?.display_name || '팀원'}님이 ${task?.title || '업무 수정'} 요청을 보냈어요.`;
  } else if (event === 'schedule') {
    if (!body.team_id || !['base', 'weekly'].includes(body.schedule_scope || '')) return json({ error: 'Invalid schedule details' }, 400);
    const table = body.schedule_scope === 'weekly' ? 'weekly_schedule_overrides' : 'work_schedules';
    let query = admin.from(table).select('team_id,user_id,workdays,start_times,end_times,start_time,end_time,updated_by,updated_at').eq('team_id', body.team_id).eq('user_id', entityId);
    if (body.schedule_scope === 'weekly') {
      if (!body.week_start) return json({ error: 'Week start is required' }, 400);
      query = query.eq('week_start', body.week_start);
    }
    const { data: schedule } = await query.maybeSingle();
    if (!schedule) return json({ error: 'Schedule not found' }, 404);
    if (schedule.updated_by !== user.id) return json({ error: 'You cannot notify for this schedule change' }, 403);
    const [{ data: actor }, { data: target }, { data: teamMembers }] = await Promise.all([
      admin.from('team_members').select('display_name,role').eq('team_id', schedule.team_id).eq('user_id', user.id).maybeSingle(),
      admin.from('team_members').select('display_name').eq('team_id', schedule.team_id).eq('user_id', schedule.user_id).maybeSingle(),
      admin.from('team_members').select('user_id').eq('team_id', schedule.team_id)
    ]);
    if (!actor || !target) return json({ error: 'Team membership required' }, 403);
    if (schedule.user_id !== user.id && actor.role !== 'admin') return json({ error: 'Only an admin can change another member schedule' }, 403);
    teamId = schedule.team_id; actorId = user.id;
    recipientIds = (teamMembers || []).map(row => row.user_id).filter(id => id !== actorId);
    const days = (schedule.workdays || []).map((day: number) => {
      const labels = ['월', '화', '수', '목', '금', '토', '일'];
      const key = String(day);
      return `${labels[day - 1] || ''} ${schedule.start_times?.[key] || schedule.start_time}~${schedule.end_times?.[key] || schedule.end_time}`;
    }).join(', ');
    title = body.schedule_scope === 'weekly' ? '주간 근무 일정 변경' : '기본 근무 일정 변경';
    detail = `${actor.display_name}님이 ${target.display_name}님의 ${body.schedule_scope === 'weekly' ? `${body.week_start} 주간` : '기본'} 근무 일정을 변경했어요.${days ? ` ${days}` : ''}`;
    eventKey = `schedule:${table}:${schedule.team_id}:${schedule.user_id}:${body.week_start || 'base'}:${schedule.updated_at}`;
  } else {
    const { data: comment } = await admin.from('change_request_comments').select('id,team_id,request_id,author_id,body').eq('id', entityId).maybeSingle();
    if (!comment) return json({ error: 'Comment not found' }, 404);
    if (comment.author_id !== user.id) return json({ error: 'You cannot notify for this comment' }, 403);
    const { data: item } = await admin.from('change_requests').select('requester_id,assignee_id,task_id').eq('id', comment.request_id).maybeSingle();
    if (!item || (item.requester_id !== user.id && item.assignee_id !== user.id)) return json({ error: 'Request participant required' }, 403);
    const [{ data: task }, { data: member }] = await Promise.all([
      item.task_id ? admin.from('tasks').select('title').eq('id', item.task_id).maybeSingle() : Promise.resolve({ data: null }),
      admin.from('team_members').select('display_name').eq('team_id', comment.team_id).eq('user_id', user.id).maybeSingle()
    ]);
    teamId = comment.team_id; actorId = user.id; recipientIds = [user.id === item.requester_id ? item.assignee_id : item.requester_id]; title = '수정 요청 댓글'; detail = `${member?.display_name || '팀원'}님이 ${task?.title || '수정 요청'}에 댓글을 남겼어요.`;
  }

  if (!recipientIds.length) {
    const { data: members } = await admin.from('team_members').select('user_id').eq('team_id', teamId).neq('user_id', actorId);
    recipientIds = (members || []).map(row => row.user_id);
  }
  // A single event can be triggered by several clients; only send it once.
  if (!eventKey) eventKey = `${event}:${entityId}`;
  const { error: eventError } = await admin.from('push_delivery_events').insert({ event_key: eventKey });
  if (eventError?.code === '23505') return json({ sent: 0, duplicate: true });
  if (eventError) return json({ error: 'Could not record notification event' }, 500);
  const [{ data: member }, { data: subscriptions }] = await Promise.all([
    admin.from('team_members').select('display_name').eq('team_id', teamId).eq('user_id', actorId).maybeSingle(),
    admin.from('push_subscriptions').select('endpoint,p256dh,auth').eq('team_id', teamId).in('user_id', recipientIds)
  ]);
  if (!member) return json({ error: 'Team membership required' }, 403);
  if (!subscriptions?.length) {
    await admin.from('push_delivery_events').delete().eq('event_key', eventKey);
    return json({ sent: 0, failed: 0, total: 0 });
  }
  webpush.setVapidDetails(Deno.env.get('VAPID_SUBJECT') || 'mailto:admin@teamwork-log.app', vapidPublicKey, vapidPrivateKey);
  const payload = JSON.stringify({ title, body: `${detail}${date ? ` (${date})` : ''}`, url: '/', tag: `team-${eventKey}` });
  const results = await Promise.all((subscriptions || []).map(async subscription => {
    try {
      await webpush.sendNotification({ endpoint: subscription.endpoint, keys: { p256dh: subscription.p256dh, auth: subscription.auth } }, payload, { TTL: 60, urgency: 'normal' });
      return true;
    } catch (error) {
      const statusCode = (error as { statusCode?: number }).statusCode;
      if (statusCode === 404 || statusCode === 410) await admin.from('push_subscriptions').delete().eq('endpoint', subscription.endpoint);
      console.error('Push delivery failed:', statusCode || error); return false;
    }
  }));
  const sent = results.filter(Boolean).length, failed = results.length - sent;
  // A failed or partial attempt stays retryable. The stable notification tag
  // replaces an earlier banner on devices that received the first attempt.
  if (failed > 0) await admin.from('push_delivery_events').delete().eq('event_key', eventKey);
  return json({ sent, failed, total: results.length });
});

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
}
