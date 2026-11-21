-- Team wide plan weeks can grow beyond the original four week MVP window.
alter table public.teams
  add column if not exists plan_week_count integer not null default 4;

update public.teams set plan_week_count=4 where plan_week_count is null or plan_week_count<4;
alter table public.teams drop constraint if exists teams_plan_week_count_check;
alter table public.teams add constraint teams_plan_week_count_check check (plan_week_count >= 4);

do $$
declare check_row record;
begin
  for check_row in
    select conname from pg_constraint
    where conrelid = 'public.tasks'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%week_no%'
  loop
    execute format('alter table public.tasks drop constraint %I', check_row.conname);
  end loop;
end $$;
alter table public.tasks add constraint tasks_week_no_positive check (week_no >= 1);

create or replace function public.extend_team_plan_weeks(target_team_id uuid, target_week integer)
returns integer
language plpgsql security definer set search_path=public
as $$
declare next_count integer;
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 업무 주차를 추가할 수 있습니다';
  end if;
  if target_week is null or target_week < 4 then
    raise exception '주차는 4주차 이후의 값이어야 합니다';
  end if;
  update public.teams
    set plan_week_count = greatest(plan_week_count, target_week)
    where id = target_team_id
    returning plan_week_count into next_count;
  if next_count is null then raise exception '팀 공간을 찾을 수 없습니다'; end if;
  return next_count;
end
$$;
revoke all on function public.extend_team_plan_weeks(uuid,integer) from public, anon;
grant execute on function public.extend_team_plan_weeks(uuid,integer) to authenticated;
