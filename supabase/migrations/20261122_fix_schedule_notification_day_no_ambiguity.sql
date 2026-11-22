-- Qualify the unnest output so PL/pgSQL cannot confuse it with a local variable.
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
    (case days.day_number
      when 1 then '월' when 2 then '화' when 3 then '수' when 4 then '목'
      when 5 then '금' when 6 then '토' else '일' end)
      || ' ' || coalesce(new.start_times->>days.day_number::text, to_char(new.start_time, 'HH24:MI'))
      || '~' || coalesce(new.end_times->>days.day_number::text, to_char(new.end_time, 'HH24:MI')),
    ', ' order by days.day_number
  ) into schedule_text
  from unnest(new.workdays) as days(day_number);

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

revoke all on function public.notify_work_schedule_change() from public, anon, authenticated;
