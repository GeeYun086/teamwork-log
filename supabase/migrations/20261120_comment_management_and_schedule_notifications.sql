-- Allow authors to manage their own comments and notify teammates of schedule changes.
alter table public.change_request_comments
  add column if not exists updated_at timestamptz not null default now();

drop policy if exists "authors update own request comments" on public.change_request_comments;
create policy "authors update own request comments" on public.change_request_comments
  for update to authenticated
  using (author_id = auth.uid() and public.is_team_member(team_id))
  with check (author_id = auth.uid() and public.is_team_member(team_id));

drop policy if exists "authors delete own request comments" on public.change_request_comments;
create policy "authors delete own request comments" on public.change_request_comments
  for delete to authenticated
  using (author_id = auth.uid() and public.is_team_member(team_id));

grant select, insert, update, delete on public.change_request_comments to authenticated;

create or replace function public.stamp_request_comment_updated_at()
returns trigger language plpgsql set search_path = public
as $$ begin
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists request_comment_updated_at on public.change_request_comments;
create trigger request_comment_updated_at before update on public.change_request_comments
for each row execute function public.stamp_request_comment_updated_at();

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('attendance','report','request','request_comment','schedule'));

create or replace function public.notify_work_schedule_change()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  actor_id uuid;
  actor_name text;
  target_name text;
  schedule_text text;
  target_week date;
  event_title text;
  event_body text;
  member record;
  day_no integer;
begin
  actor_id := new.updated_by;
  if actor_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.workdays is not distinct from new.workdays
    and old.start_times is not distinct from new.start_times
    and old.end_times is not distinct from new.end_times
    and old.start_time is not distinct from new.start_time
    and old.end_time is not distinct from new.end_time then
    return new;
  end if;

  select display_name into actor_name from public.team_members
    where team_id = new.team_id and user_id = actor_id;
  select display_name into target_name from public.team_members
    where team_id = new.team_id and user_id = new.user_id;
  if actor_name is null or target_name is null then return new; end if;

  if tg_table_name = 'weekly_schedule_overrides' then
    target_week := new.week_start;
    event_title := '주간 근무 일정 변경';
  else
    target_week := null;
    event_title := '기본 근무 일정 변경';
  end if;
  select string_agg(
    (case day_no when 1 then '월' when 2 then '화' when 3 then '수' when 4 then '목' when 5 then '금' when 6 then '토' else '일' end)
      || ' ' || coalesce(new.start_times->>day_no::text, to_char(new.start_time, 'HH24:MI'))
      || '~' || coalesce(new.end_times->>day_no::text, to_char(new.end_time, 'HH24:MI')),
    ', ' order by day_no
  ) into schedule_text
  from unnest(new.workdays) as day_no;
  event_body := coalesce(actor_name, '팀원') || '님이 ' || coalesce(target_name, '팀원') || '님의 '
    || case when target_week is null then '기본 근무 일정' else to_char(target_week, 'MM/DD') || ' 주간 근무 일정' end
    || '을 변경했어요.' || case when schedule_text is null then '' else ' ' || schedule_text end;

  for member in select user_id from public.team_members
    where team_id = new.team_id and user_id <> actor_id loop
    perform public.record_team_notification(new.team_id, member.user_id, actor_id, 'schedule',
      event_title, event_body, null, '/#schedule');
  end loop;
  return new;
end
$$;

drop trigger if exists work_schedule_notification_change on public.work_schedules;
create trigger work_schedule_notification_change
after insert or update of workdays, start_times, end_times, start_time, end_time
on public.work_schedules for each row execute function public.notify_work_schedule_change();

drop trigger if exists weekly_schedule_notification_change on public.weekly_schedule_overrides;
create trigger weekly_schedule_notification_change
after insert or update of workdays, start_times, end_times, start_time, end_time
on public.weekly_schedule_overrides for each row execute function public.notify_work_schedule_change();

revoke all on function public.stamp_request_comment_updated_at() from public, anon, authenticated;
revoke all on function public.notify_work_schedule_change() from public, anon, authenticated;
