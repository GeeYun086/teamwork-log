-- Team members can review team-wide change requests and attendance evidence.
-- Apply 10 minutes of check-in grace consistently to stored attendance fees.

drop policy if exists "participants see requests" on public.change_requests;
drop policy if exists "team members read all requests" on public.change_requests;
create policy "team members read all requests" on public.change_requests
  for select to authenticated
  using (public.is_team_member(team_id));

drop policy if exists "request participants read comments" on public.change_request_comments;
drop policy if exists "team members read request comments" on public.change_request_comments;
create policy "team members read request comments" on public.change_request_comments
  for select to authenticated
  using (public.is_team_member(team_id));

drop policy if exists "owners and admins read attendance photos" on storage.objects;
drop policy if exists "team members read attendance photos" on storage.objects;
create policy "team members read attendance photos" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'attendance-photos'
    and public.is_team_member(((storage.foldername(name))[1])::uuid)
  );

create or replace function public.team_server_time()
returns timestamptz language sql stable
as $$ select now() $$;
revoke all on function public.team_server_time() from public, anon;
grant execute on function public.team_server_time() to authenticated;

-- late_minutes continues to store the raw delay from the scheduled start.
-- The UI subtracts the 10-minute grace window before showing late minutes.
create or replace function public.apply_attendance_lateness_rules()
returns trigger language plpgsql set search_path = public
as $$
declare
  raw_minutes integer;
begin
  if new.scheduled_start_at is null or new.check_in_at is null then
    new.late_minutes = null;
    new.late_fee_krw = 0;
    return new;
  end if;

  raw_minutes := greatest(
    0,
    floor(extract(epoch from (new.check_in_at - new.scheduled_start_at)) / 60)::integer
  );
  new.late_minutes := raw_minutes;

  if raw_minutes <= 10 or raw_minutes >= 60 then
    new.late_fee_krw := 0;
  elsif extract(isodow from new.work_date) = 3 then
    new.late_fee_krw := least((raw_minutes - 10) * 1000, 10000);
  elsif raw_minutes >= 30 then
    new.late_fee_krw := 5000;
  elsif raw_minutes >= 20 then
    new.late_fee_krw := 3000;
  else
    new.late_fee_krw := 1000;
  end if;

  return new;
end
$$;

-- Run after attendance_server_timestamp so scheduled_start_at/check_in_at are final.
drop trigger if exists zzz_attendance_lateness_rules on public.attendance;
create trigger zzz_attendance_lateness_rules
before insert or update on public.attendance
for each row execute function public.apply_attendance_lateness_rules();

-- Recalculate existing rows from the actual check-in timestamp, not photo upload time.
alter table public.attendance disable trigger attendance_server_timestamp;
update public.attendance
set late_minutes = case
      when scheduled_start_at is not null and check_in_at is not null
        then greatest(0, floor(extract(epoch from (check_in_at - scheduled_start_at)) / 60)::integer)
      else null
    end,
    late_fee_krw = case
      when scheduled_start_at is null or check_in_at is null then 0
      when floor(extract(epoch from (check_in_at - scheduled_start_at)) / 60)::integer <= 10 then 0
      when floor(extract(epoch from (check_in_at - scheduled_start_at)) / 60)::integer >= 60 then 0
      when extract(isodow from work_date) = 3 then least(
        greatest(0, floor(extract(epoch from (check_in_at - scheduled_start_at)) / 60)::integer - 10) * 1000,
        10000
      )
      when floor(extract(epoch from (check_in_at - scheduled_start_at)) / 60)::integer >= 30 then 5000
      when floor(extract(epoch from (check_in_at - scheduled_start_at)) / 60)::integer >= 20 then 3000
      else 1000
    end;
alter table public.attendance enable trigger attendance_server_timestamp;
