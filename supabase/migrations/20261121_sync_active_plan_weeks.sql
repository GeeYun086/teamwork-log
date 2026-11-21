create or replace function public.sync_active_task_plan_weeks()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  old_team_id uuid;
  old_week_no integer;
  new_week_no integer;
  should_remove_old_week boolean := false;
begin
  if tg_op <> 'INSERT' then
    old_team_id := old.team_id;
    old_week_no := case when old.due_date is null then old.week_no else greatest(1, ((date_trunc('week', old.due_date)::date - date '2026-10-26') / 7) + 1) end;
  end if;

  if tg_op <> 'DELETE' then
    new_week_no := case when new.due_date is null then new.week_no else greatest(1, ((date_trunc('week', new.due_date)::date - date '2026-10-26') / 7) + 1) end;
    if new.deleted_at is null and not exists (
      select 1 from public.teams t
       where t.id = new.team_id and new_week_no = any(coalesce(t.plan_week_numbers, array[1,2,3,4]))
    ) then
      update public.teams
         set plan_week_numbers = array_append(coalesce(plan_week_numbers, array[1,2,3,4]), new_week_no)
       where id = new.team_id;
    end if;
  end if;

  if tg_op = 'DELETE' then
    should_remove_old_week := true;
  elsif tg_op = 'UPDATE' then
    should_remove_old_week := (old.deleted_at is null and new.deleted_at is not null)
      or old.team_id is distinct from new.team_id
      or old_week_no is distinct from new_week_no;
  end if;

  if should_remove_old_week and old_team_id is not null and old_week_no is not null
     and exists (
       select 1 from public.teams t
        where t.id = old_team_id and old_week_no = any(coalesce(t.plan_week_numbers, array[1,2,3,4]))
     )
     and not exists (
       select 1 from public.tasks t
        where t.team_id = old_team_id and t.deleted_at is null
          and (case when t.due_date is null then t.week_no else greatest(1, ((date_trunc('week', t.due_date)::date - date '2026-10-26') / 7) + 1) end) = old_week_no
     ) then
    update public.teams
       set plan_week_numbers = array_remove(coalesce(plan_week_numbers, array[1,2,3,4]), old_week_no)
     where id = old_team_id;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists sync_active_task_plan_weeks on public.tasks;
create trigger sync_active_task_plan_weeks
after insert or update or delete on public.tasks
for each row execute function public.sync_active_task_plan_weeks();
