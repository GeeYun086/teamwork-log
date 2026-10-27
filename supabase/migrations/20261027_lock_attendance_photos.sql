-- Keep the original check-in photo immutable after its initial upload.
-- Run after 20261027_end_times_and_announcements.sql.

create or replace function public.prevent_attendance_photo_replacement()
returns trigger language plpgsql set search_path=public
as $$
begin
  if new.photo_path is distinct from old.photo_path then
    raise exception 'Attendance photos cannot be changed after submission';
  end if;
  return new;
end $$;

drop trigger if exists attendance_photo_immutable on public.attendance;
create trigger attendance_photo_immutable
before update of photo_path on public.attendance
for each row execute function public.prevent_attendance_photo_replacement();

-- Upsert uses UPDATE when the daily object already exists, so rejecting this
-- policy prevents even an old client from overwriting the uploaded object.
drop policy if exists "members update own attendance photos" on storage.objects;
