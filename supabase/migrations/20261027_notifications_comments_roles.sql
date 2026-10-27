-- Persistent in-app notifications, request comments, and safe role changes.
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams on delete cascade,
  recipient_id uuid not null references auth.users on delete cascade,
  actor_id uuid references auth.users on delete set null,
  type text not null check (type in ('attendance','report','request','request_comment')),
  title text not null,
  body text not null default '',
  entity_id uuid,
  route text not null default '/',
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists notifications_recipient_created_idx
  on public.notifications(team_id, recipient_id, created_at desc);
create table if not exists public.push_delivery_events (
  event_key text primary key,
  created_at timestamptz not null default now()
);
alter table public.push_delivery_events enable row level security;

create table if not exists public.change_request_comments (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams on delete cascade,
  request_id uuid not null references public.change_requests on delete cascade,
  author_id uuid not null references auth.users on delete cascade,
  body text not null check (length(trim(body)) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists request_comments_request_created_idx
  on public.change_request_comments(request_id, created_at);

alter table public.notifications enable row level security;
alter table public.change_request_comments enable row level security;
drop policy if exists "members read own notifications" on public.notifications;
create policy "members read own notifications" on public.notifications
  for select to authenticated using (recipient_id = auth.uid() and public.is_team_member(team_id));
drop policy if exists "members mark own notifications read" on public.notifications;
create policy "members mark own notifications read" on public.notifications
  for update to authenticated using (recipient_id = auth.uid() and public.is_team_member(team_id))
  with check (recipient_id = auth.uid() and public.is_team_member(team_id));
drop policy if exists "request participants read comments" on public.change_request_comments;
create policy "request participants read comments" on public.change_request_comments
  for select to authenticated using (
    public.is_team_member(team_id) and exists (
      select 1 from public.change_requests r where r.id = request_id
      and (r.requester_id = auth.uid() or r.assignee_id = auth.uid() or public.is_team_admin(team_id))
    )
  );
drop policy if exists "request participants add comments" on public.change_request_comments;
create policy "request participants add comments" on public.change_request_comments
  for insert to authenticated with check (
    author_id = auth.uid() and public.is_team_member(team_id) and exists (
      select 1 from public.change_requests r where r.id = request_id
      and r.team_id = change_request_comments.team_id and (r.requester_id = auth.uid() or r.assignee_id = auth.uid() or public.is_team_admin(change_request_comments.team_id))
    )
  );

create or replace function public.record_team_notification(
  target_team uuid, target_recipient uuid, target_actor uuid, target_type text,
  target_title text, target_body text, target_entity uuid, target_route text
) returns void language plpgsql security definer set search_path=public
as $$ begin
  if target_recipient is null or target_recipient = target_actor then return; end if;
  insert into public.notifications(team_id,recipient_id,actor_id,type,title,body,entity_id,route)
  values(target_team,target_recipient,target_actor,target_type,target_title,target_body,target_entity,target_route);
end $$;

create or replace function public.notify_new_change_request()
returns trigger language plpgsql security definer set search_path=public
as $$ declare task_title text; actor_name text; begin
  select title into task_title from public.tasks where id=new.task_id;
  select display_name into actor_name from public.team_members where team_id=new.team_id and user_id=new.requester_id;
  perform public.record_team_notification(new.team_id,new.assignee_id,new.requester_id,'request','새 수정 요청',
    coalesce(actor_name,'팀원') || '님이 ' || coalesce(task_title,'업무 수정') || ' 요청을 보냈어요.',new.id,'/');
  return new;
end $$;
drop trigger if exists change_request_notification_insert on public.change_requests;
create trigger change_request_notification_insert after insert on public.change_requests
for each row execute function public.notify_new_change_request();

create or replace function public.notify_saved_report()
returns trigger language plpgsql security definer set search_path=public
as $$ declare actor_name text; member record; begin
  select display_name into actor_name from public.team_members where team_id=new.team_id and user_id=new.user_id;
  for member in select user_id from public.team_members where team_id=new.team_id and user_id<>new.user_id loop
    perform public.record_team_notification(new.team_id,member.user_id,new.user_id,'report','퇴근 보고 등록',
      coalesce(actor_name,'팀원') || '님이 ' || new.work_date::text || ' 퇴근 보고를 저장했어요.',new.id,'/');
  end loop;
  return new;
end $$;
drop trigger if exists report_notification_insert on public.reports;
create trigger report_notification_insert after insert or update of updated_at on public.reports
for each row execute function public.notify_saved_report();

create or replace function public.notify_attendance_change()
returns trigger language plpgsql security definer set search_path=public
as $$ declare actor_name text; event_title text; event_body text; member record; begin
  if tg_op='INSERT' then
    event_title := case when new.is_backfilled then '출퇴근 기록 등록' else '출근 인증' end;
    event_body := case when new.is_backfilled then new.work_date::text || ' 출퇴근 사진을 등록했어요.' else new.work_date::text || ' 출근 사진을 등록했어요.' end;
  elsif old.checked_out_at is null and new.checked_out_at is not null then
    event_title := '퇴근 인증'; event_body := new.work_date::text || ' 퇴근 사진을 등록했어요.';
  else return new;
  end if;
  select display_name into actor_name from public.team_members where team_id=new.team_id and user_id=new.user_id;
  for member in select user_id from public.team_members where team_id=new.team_id and user_id<>new.user_id loop
    perform public.record_team_notification(new.team_id,member.user_id,new.user_id,'attendance',event_title,
      coalesce(actor_name,'팀원') || '님이 ' || event_body,new.id,'/');
  end loop;
  return new;
end $$;
drop trigger if exists attendance_notification_change on public.attendance;
create trigger attendance_notification_change after insert or update of checked_out_at on public.attendance
for each row execute function public.notify_attendance_change();

create or replace function public.notify_request_comment()
returns trigger language plpgsql security definer set search_path=public
as $$ declare request_row public.change_requests; actor_name text; other_user uuid; task_title text; begin
  select * into request_row from public.change_requests where id=new.request_id;
  select display_name into actor_name from public.team_members where team_id=new.team_id and user_id=new.author_id;
  select title into task_title from public.tasks where id=request_row.task_id;
  other_user := case when new.author_id=request_row.requester_id then request_row.assignee_id else request_row.requester_id end;
  perform public.record_team_notification(new.team_id,other_user,new.author_id,'request_comment','수정 요청 댓글',
    coalesce(actor_name,'팀원') || '님이 ' || coalesce(task_title,'수정 요청') || '에 댓글을 남겼어요.',new.request_id,'/');
  return new;
end $$;
drop trigger if exists request_comment_notification_insert on public.change_request_comments;
create trigger request_comment_notification_insert after insert on public.change_request_comments
for each row execute function public.notify_request_comment();

create or replace function public.set_team_member_role(target_user_id uuid, target_role text)
returns void language plpgsql security definer set search_path=public
as $$ declare current_team uuid; admin_count integer; begin
  if target_role not in ('admin','member') then raise exception '잘못된 권한입니다'; end if;
  select team_id into current_team from public.team_members
    where user_id=auth.uid() and role='admin' limit 1;
  if current_team is null then raise exception '관리자만 권한을 변경할 수 있습니다'; end if;
  if target_user_id=auth.uid() and target_role='member' then raise exception '본인 관리자 권한은 변경할 수 없습니다'; end if;
  if target_role='member' then
    select count(*) into admin_count from public.team_members where team_id=current_team and role='admin';
    if admin_count<=1 and exists(select 1 from public.team_members where team_id=current_team and user_id=target_user_id and role='admin') then
      raise exception '마지막 관리자의 권한은 해제할 수 없습니다';
    end if;
  end if;
  update public.team_members set role=target_role where team_id=current_team and user_id=target_user_id;
  if not found then raise exception '팀원을 찾을 수 없습니다'; end if;
end $$;
grant execute on function public.set_team_member_role(uuid,text) to authenticated;
revoke all on function public.record_team_notification(uuid,uuid,uuid,text,text,text,uuid,text) from public, anon, authenticated;
revoke all on function public.notify_new_change_request() from public, anon, authenticated;
revoke all on function public.notify_saved_report() from public, anon, authenticated;
revoke all on function public.notify_attendance_change() from public, anon, authenticated;
revoke all on function public.notify_request_comment() from public, anon, authenticated;

grant select on public.notifications to authenticated;
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;
grant select, insert on public.change_request_comments to authenticated;
grant all on public.push_delivery_events to service_role;

