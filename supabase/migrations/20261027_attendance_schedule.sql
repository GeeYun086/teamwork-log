-- Teamwork Log: individual recurring schedules, weekly exceptions, check-out, and lateness.
-- Run once in Supabase SQL Editor after the original schema.sql.

alter table public.attendance add column if not exists check_in_at timestamptz;
alter table public.attendance add column if not exists checked_out_at timestamptz;
alter table public.attendance add column if not exists scheduled_start_at timestamptz;
alter table public.attendance add column if not exists late_minutes integer;
update public.attendance set check_in_at=uploaded_at where check_in_at is null;

create table if not exists public.work_schedules (
  team_id uuid not null,
  user_id uuid not null,
  workdays smallint[] not null default array[1,3,5]::smallint[],
  start_time time not null default time '09:00',
  updated_by uuid references auth.users on delete set null,
  updated_at timestamptz not null default now(),
  primary key(team_id,user_id),
  foreign key(team_id,user_id) references public.team_members(team_id,user_id) on delete cascade,
  check(cardinality(workdays)=3 and workdays <@ array[1,2,3,4,5,6,7]::smallint[])
);

create table if not exists public.weekly_schedule_overrides (
  team_id uuid not null,
  user_id uuid not null,
  week_start date not null,
  workdays smallint[] not null,
  start_time time not null,
  updated_by uuid references auth.users on delete set null,
  updated_at timestamptz not null default now(),
  primary key(team_id,user_id,week_start),
  foreign key(team_id,user_id) references public.team_members(team_id,user_id) on delete cascade,
  check(cardinality(workdays)=3 and workdays <@ array[1,2,3,4,5,6,7]::smallint[])
);

insert into public.work_schedules(team_id,user_id)
select team_id,user_id from public.team_members
on conflict(team_id,user_id) do nothing;

update public.attendance a
set check_in_at=coalesce(a.check_in_at,a.uploaded_at),
    scheduled_start_at=((a.work_date+coalesce((select o.start_time from public.weekly_schedule_overrides o where o.team_id=a.team_id and o.user_id=a.user_id and o.week_start=a.work_date-(extract(isodow from a.work_date)::integer-1)),s.start_time)) at time zone 'Asia/Seoul'),
    late_minutes=greatest(0,floor(extract(epoch from (coalesce(a.check_in_at,a.uploaded_at)-((a.work_date+coalesce((select o.start_time from public.weekly_schedule_overrides o where o.team_id=a.team_id and o.user_id=a.user_id and o.week_start=a.work_date-(extract(isodow from a.work_date)::integer-1)),s.start_time)) at time zone 'Asia/Seoul')))/60)::integer)
from public.work_schedules s
where a.team_id=s.team_id and a.user_id=s.user_id
  and a.work_date>=date '2026-10-27'
  and extract(isodow from a.work_date)::smallint=any(coalesce((select o.workdays from public.weekly_schedule_overrides o where o.team_id=a.team_id and o.user_id=a.user_id and o.week_start=a.work_date-(extract(isodow from a.work_date)::integer-1)),s.workdays));

create or replace function public.seed_member_work_schedule()
returns trigger language plpgsql security definer set search_path=public
as $$ begin
  insert into public.work_schedules(team_id,user_id) values(new.team_id,new.user_id)
  on conflict(team_id,user_id) do nothing;
  return new;
end $$;
drop trigger if exists team_member_default_schedule on public.team_members;
create trigger team_member_default_schedule after insert on public.team_members
for each row execute function public.seed_member_work_schedule();

alter table public.work_schedules enable row level security;
alter table public.weekly_schedule_overrides enable row level security;
grant select,insert,update on public.work_schedules,public.weekly_schedule_overrides to authenticated;
drop policy if exists "members see team schedules" on public.work_schedules;
create policy "members see team schedules" on public.work_schedules for select to authenticated using(public.is_team_member(team_id));
drop policy if exists "members manage own schedule admins manage all" on public.work_schedules;
create policy "members manage own schedule admins manage all" on public.work_schedules for all to authenticated using(public.is_team_member(team_id) and (user_id=auth.uid() or public.is_team_admin(team_id))) with check(public.is_team_member(team_id) and (user_id=auth.uid() or public.is_team_admin(team_id)));
drop policy if exists "members see team weekly schedules" on public.weekly_schedule_overrides;
create policy "members see team weekly schedules" on public.weekly_schedule_overrides for select to authenticated using(public.is_team_member(team_id));
drop policy if exists "members manage own weekly schedule admins manage all" on public.weekly_schedule_overrides;
create policy "members manage own weekly schedule admins manage all" on public.weekly_schedule_overrides for all to authenticated using(public.is_team_member(team_id) and (user_id=auth.uid() or public.is_team_admin(team_id))) with check(public.is_team_member(team_id) and (user_id=auth.uid() or public.is_team_admin(team_id)));

create or replace function public.stamp_attendance()
returns trigger language plpgsql set search_path=public
as $$
declare
  days smallint[];
  starts_at time;
  monday date;
begin
  if tg_op='INSERT' then
    new.uploaded_at=now();
    new.check_in_at=now();
    new.work_date=coalesce(new.work_date,(now() at time zone 'Asia/Seoul')::date);
    if new.work_date >= date '2026-10-27' then
      monday=new.work_date-(extract(isodow from new.work_date)::integer-1);
      select workdays,start_time into days,starts_at
        from public.weekly_schedule_overrides
        where team_id=new.team_id and user_id=new.user_id and week_start=monday;
      if not found then
        select workdays,start_time into days,starts_at
          from public.work_schedules where team_id=new.team_id and user_id=new.user_id;
      end if;
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

drop trigger if exists attendance_server_timestamp on public.attendance;
create trigger attendance_server_timestamp before insert or update on public.attendance
for each row execute function public.stamp_attendance();

-- Replace the previous blocked status with the requested waiting status.
alter table public.tasks drop constraint if exists tasks_status_check;
update public.tasks set status='대기' where status='막힘';
alter table public.tasks add constraint tasks_status_check check(status in ('예정','진행 중','완료','대기'));
