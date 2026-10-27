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

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY');
  const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY');
  if (!supabaseUrl || !anonKey || !serviceKey || !vapidPublicKey || !vapidPrivateKey) {
    return json({ error: 'Push service is not configured' }, 503);
  }

  const authorization = request.headers.get('Authorization');
  if (!authorization) return json({ error: 'Authentication required' }, 401);
  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return json({ error: 'Authentication required' }, 401);

  let body: { attendance_id?: string; event?: string };
  try { body = await request.json(); }
  catch { return json({ error: 'Invalid JSON body' }, 400); }
  if (!body.attendance_id || !['check_in', 'check_out', 'backfill'].includes(body.event || '')) {
    return json({ error: 'Invalid attendance notification event' }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: attendance, error: attendanceError } = await admin.from('attendance')
    .select('id,team_id,user_id,work_date,uploaded_at,check_in_at,checked_out_at,is_backfilled')
    .eq('id', body.attendance_id).maybeSingle();
  if (attendanceError || !attendance) return json({ error: 'Attendance record not found' }, 404);
  if (attendance.user_id !== user.id) return json({ error: 'You cannot notify for this record' }, 403);
  if (body.event === 'check_out' && !attendance.checked_out_at) return json({ error: 'Checkout is not recorded yet' }, 409);
  if (body.event === 'backfill' && !attendance.is_backfilled) return json({ error: 'This is not a backfill record' }, 409);

  const [{ data: member }, { data: subscriptions }] = await Promise.all([
    admin.from('team_members').select('display_name').eq('team_id', attendance.team_id).eq('user_id', user.id).maybeSingle(),
    admin.from('push_subscriptions').select('endpoint,p256dh,auth').eq('team_id', attendance.team_id)
  ]);
  if (!member) return json({ error: 'Team membership required' }, 403);

  const date = attendance.work_date;
  const formatTime = (value: string | null) => value
    ? new Intl.DateTimeFormat('ko-KR', { timeZone: 'Asia/Seoul', hour: '2-digit', minute: '2-digit' }).format(new Date(value))
    : '';
  let title = '출퇴근 기록';
  let detail = `${member.display_name}님이 출퇴근 기록을 등록했어요.`;
  if (body.event === 'check_in') {
    title = '출근 인증';
    detail = `${member.display_name}님이 ${formatTime(attendance.uploaded_at)} 출근 사진을 등록했어요.`;
  } else if (body.event === 'check_out') {
    title = '퇴근 인증';
    detail = `${member.display_name}님이 퇴근 사진을 등록했어요.`;
  } else {
    title = '사후 출퇴근 등록';
    detail = `${member.display_name}님이 ${date} 출퇴근 기록을 사후 등록했어요.`;
  }

  webpush.setVapidDetails(Deno.env.get('VAPID_SUBJECT') || 'mailto:admin@teamwork-log.app', vapidPublicKey, vapidPrivateKey);
  const payload = JSON.stringify({
    title,
    body: `${detail} (${date})`,
    url: '/',
    tag: `attendance-${attendance.id}-${body.event}`
  });
  const results = await Promise.all((subscriptions || []).map(async (subscription) => {
    try {
      await webpush.sendNotification({
        endpoint: subscription.endpoint,
        keys: { p256dh: subscription.p256dh, auth: subscription.auth }
      }, payload, { TTL: 60, urgency: 'normal' });
      return true;
    } catch (error) {
      const statusCode = (error as { statusCode?: number }).statusCode;
      if (statusCode === 404 || statusCode === 410) {
        await admin.from('push_subscriptions').delete().eq('endpoint', subscription.endpoint);
      }
      console.error('Push delivery failed:', statusCode || error);
      return false;
    }
  }));

  return json({ sent: results.filter(Boolean).length, failed: results.length - results.filter(Boolean).length, total: results.length });
});

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}
