-- Weekday-specific scheduled end times and shared team announcements.
-- Run after 20261027_daily_start_times.sql.

alter table public.work_schedules
  add column if not exists end_time time not null default time '18:00',
  add column if not exists end_times jsonb not null default '{}'::jsonb;
alter table public.weekly_schedule_overrides
  add column if not exists end_time time not null default time '18:00',
  add column if not exists end_times jsonb not null default '{}'::jsonb;

update public.work_schedules s
set end_times=(select coalesce(jsonb_object_agg(d.day::text,to_char(s.end_time,'HH24:MI')),'{}'::jsonb)
               from unnest(s.workdays) as d(day))
where end_times='{}'::jsonb;
update public.weekly_schedule_overrides s
set end_times=(select coalesce(jsonb_object_agg(d.day::text,to_char(s.end_time,'HH24:MI')),'{}'::jsonb)
               from unnest(s.workdays) as d(day))
where end_times='{}'::jsonb;

alter table public.attendance add column if not exists scheduled_end_at timestamptz;
alter table public.attendance add column if not exists early_minutes integer;

create or replace function public.stamp_attendance()
returns trigger language plpgsql set search_path=public
as $$
declare
  days smallint[];
  daily_starts jsonb;
  daily_ends jsonb;
  fallback_start time;
  fallback_end time;
  starts_at time;
  ends_at time;
  monday date;
  weekday_key text;
begin
  if tg_op='INSERT' then
    new.uploaded_at=now();
    new.check_in_at=now();
    new.work_date=coalesce(new.work_date,(now() at time zone 'Asia/Seoul')::date);
    if new.work_date >= date '2026-10-27' then
      monday=new.work_date-(extract(isodow from new.work_date)::integer-1);
      select workdays,start_times,end_times,start_time,end_time
        into days,daily_starts,daily_ends,fallback_start,fallback_end
        from public.weekly_schedule_overrides
        where team_id=new.team_id and user_id=new.user_id and week_start=monday;
      if not found then
        select workdays,start_times,end_times,start_time,end_time
          into days,daily_starts,daily_ends,fallback_start,fallback_end
          from public.work_schedules where team_id=new.team_id and user_id=new.user_id;
      end if;
      weekday_key=extract(isodow from new.work_date)::integer::text;
      starts_at=coalesce(nullif(daily_starts->>weekday_key,'')::time,fallback_start);
      ends_at=coalesce(nullif(daily_ends->>weekday_key,'')::time,fallback_end);
      if days is not null and extract(isodow from new.work_date)::smallint=any(days) then
        new.scheduled_start_at=((new.work_date+starts_at) at time zone 'Asia/Seoul');
        new.scheduled_end_at=((new.work_date+ends_at) at time zone 'Asia/Seoul');
        new.late_minutes=greatest(0,floor(extract(epoch from (new.check_in_at-new.scheduled_start_at))/60)::integer);
        new.early_minutes=null;
      else
        new.scheduled_start_at=null;
        new.scheduled_end_at=null;
        new.late_minutes=null;
        new.early_minutes=null;
      end if;
    end if;
  else
    new.uploaded_at=old.uploaded_at;
    if new.changed_at is distinct from old.changed_at or new.photo_path is distinct from old.photo_path then new.changed_at=now();
    else new.changed_at=old.changed_at; end if;
    new.check_in_at=old.check_in_at;
    new.scheduled_start_at=old.scheduled_start_at;
    new.scheduled_end_at=old.scheduled_end_at;
    new.late_minutes=old.late_minutes;
    if old.checked_out_at is null and new.checked_out_at is not null then
      new.checked_out_at=now();
      if old.scheduled_end_at is not null then
        new.early_minutes=greatest(0,floor(extract(epoch from (old.scheduled_end_at-new.checked_out_at))/60)::integer);
      else
        new.early_minutes=null;
      end if;
    elsif old.checked_out_at is not null then
      new.checked_out_at=old.checked_out_at;
      new.early_minutes=old.early_minutes;
    else
      new.early_minutes=old.early_minutes;
    end if;
  end if;
  return new;
end $$;

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams on delete cascade,
  author_id uuid not null references auth.users on delete cascade,
  title text not null,
  body text not null default '',
  due_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.announcement_responses (
  team_id uuid not null references public.teams on delete cascade,
  announcement_id uuid not null references public.announcements on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  status text not null check(status in ('확인함','완료')),
  updated_at timestamptz not null default now(),
  primary key(announcement_id,user_id)
);
alter table public.announcements enable row level security;
alter table public.announcement_responses enable row level security;
grant select,insert,update,delete on public.announcements to authenticated;
grant select,insert,update on public.announcement_responses to authenticated;
drop policy if exists "members see team announcements" on public.announcements;
create policy "members see team announcements" on public.announcements for select to authenticated using(public.is_team_member(team_id));
drop policy if exists "admins manage team announcements" on public.announcements;
create policy "admins manage team announcements" on public.announcements for all to authenticated using(public.is_team_admin(team_id)) with check(public.is_team_admin(team_id));
drop policy if exists "members see team announcement responses" on public.announcement_responses;
create policy "members see team announcement responses" on public.announcement_responses for select to authenticated using(public.is_team_member(team_id));
drop policy if exists "members save own announcement response" on public.announcement_responses;
create policy "members save own announcement response" on public.announcement_responses for insert to authenticated with check(public.is_team_member(team_id) and user_id=auth.uid());
drop policy if exists "members update own announcement response" on public.announcement_responses;
create policy "members update own announcement response" on public.announcement_responses for update to authenticated using(public.is_team_member(team_id) and user_id=auth.uid()) with check(public.is_team_member(team_id) and user_id=auth.uid());
