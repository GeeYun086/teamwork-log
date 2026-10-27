-- Add a one-time immutable photo for the end-of-day check-out record.
-- The existing attendance timestamp trigger stamps checked_out_at with now().

alter table public.attendance
  add column if not exists checkout_photo_path text;

create or replace function public.prevent_checkout_photo_replacement()
returns trigger language plpgsql set search_path=public
as $$
begin
  if old.checkout_photo_path is not null
     and new.checkout_photo_path is distinct from old.checkout_photo_path then
    raise exception 'Checkout photos cannot be changed after submission';
  end if;
  return new;
end $$;

drop trigger if exists attendance_checkout_photo_immutable on public.attendance;
create trigger attendance_checkout_photo_immutable
before update of checkout_photo_path on public.attendance
for each row execute function public.prevent_checkout_photo_replacement();
