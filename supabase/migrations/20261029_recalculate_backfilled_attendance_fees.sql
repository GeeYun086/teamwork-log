-- Correct fees stored from the upload timestamp instead of the entered check-in time.
-- In particular, 2026-10-28 backfilled check-ins were all on time but were charged
-- hundreds of minutes because uploaded_at was used as the lateness source.
begin;

alter table public.attendance disable trigger attendance_server_timestamp;

with recalculated as (
  select
    id,
    greatest(0, floor(extract(epoch from (check_in_at - scheduled_start_at)) / 60)::integer) as late_minutes
  from public.attendance
  where work_date = date '2026-10-28'
    and check_in_at is not null
    and scheduled_start_at is not null
)
update public.attendance as a
set late_minutes = r.late_minutes,
    late_fee_krw = case
      when r.late_minutes = 0 then 0
      when extract(isodow from a.work_date) = 3 then r.late_minutes * 1000
      when r.late_minutes >= 30 then 5000
      when r.late_minutes >= 20 then 3000
      when r.late_minutes >= 10 then 1000
      else 0
    end
from recalculated as r
where a.id = r.id;

alter table public.attendance enable trigger attendance_server_timestamp;
commit;
