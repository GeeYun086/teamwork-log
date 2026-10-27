-- Adds a distinct check-in target for each scheduled weekday.
-- Run after 20261027_attendance_schedule.sql.

alter table public.work_schedules
  add column if not exists start_times jsonb not null default '{}'::jsonb;
alter table public.weekly_schedule_overrides
  add column if not exists start_times jsonb not null default '{}'::jsonb;

update public.work_schedules s
set start_times=(select coalesce(jsonb_object_agg(d.day::text,to_char(s.start_time,'HH24:MI')),'{}'::jsonb)
                 from unnest(s.workdays) as d(day))
where start_times='{}'::jsonb;
update public.weekly_schedule_overrides s
set start_times=(select coalesce(jsonb_object_agg(d.day::text,to_char(s.start_time,'HH24:MI')),'{}'::jsonb)
                 from unnest(s.workdays) as d(day))
where start_times='{}'::jsonb;

create or replace function public.stamp_attendance()
returns trigger language plpgsql set search_path=public
as $$
declare
  days smallint[];
  daily_times jsonb;
  fallback_time time;
  starts_at time;
  monday date;
  weekday_key text;
begin
  if tg_op='INSERT' then
    new.uploaded_at=now();
    new.check_in_at=now();
    new.work_date=coalesce(new.work_date,(now() at time zone 'Asia/Seoul')::date);
    if new.work_date >= date '2026-10-27' then
      monday=new.work_date-(extract(isodow from new.work_date)::integer-1);
      select workdays,start_times,start_time into days,daily_times,fallback_time
        from public.weekly_schedule_overrides
        where team_id=new.team_id and user_id=new.user_id and week_start=monday;
      if not found then
        select workdays,start_times,start_time into days,daily_times,fallback_time
          from public.work_schedules where team_id=new.team_id and user_id=new.user_id;
      end if;
      weekday_key=extract(isodow from new.work_date)::integer::text;
      starts_at=coalesce(nullif(daily_times->>weekday_key,'')::time,fallback_time);
      if days is not null and extract(isodow from new.work_date)::smallint=any(days) then
        new.scheduled_start_at=((new.work_date+starts_at) at time zone 'Asia/Seoul');
        new.late_minutes=greatest(0,floor(extract(epoch from (new.check_in_at-new.scheduled_start_at))/60)::integer);
      else
        new.scheduled_start_at=null;
        new.late_minutes=null;
      end if;
    end if;
  else
    new.uploaded_at=old.uploaded_at;
    if new.changed_at is distinct from old.changed_at or new.photo_path is distinct from old.photo_path then new.changed_at=now();
    else new.changed_at=old.changed_at; end if;
    new.check_in_at=old.check_in_at;
    new.scheduled_start_at=old.scheduled_start_at;
    new.late_minutes=old.late_minutes;
    if old.checked_out_at is null and new.checked_out_at is not null then
      new.checked_out_at=now();
    elsif old.checked_out_at is not null then
      new.checked_out_at=old.checked_out_at;
    end if;
  end if;
  return new;
end $$;
