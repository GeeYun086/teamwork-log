-- A one-off weekly schedule can only be changed before its Monday starts.
-- Apply the rule in the database as well as the UI so every client follows it.
create or replace function public.enforce_weekly_schedule_change_window()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  target_week date;
begin
  target_week := case when tg_op = 'DELETE' then old.week_start else new.week_start end;

  if target_week <= (now() at time zone 'Asia/Seoul')::date then
    raise exception 'A weekly schedule can only be changed through the Sunday before that week starts.'
      using errcode = '22023';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists weekly_schedule_change_window on public.weekly_schedule_overrides;
create trigger weekly_schedule_change_window
before insert or update or delete on public.weekly_schedule_overrides
for each row execute function public.enforce_weekly_schedule_change_window();
