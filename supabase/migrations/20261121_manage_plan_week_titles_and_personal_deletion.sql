alter table public.teams
  add column if not exists plan_week_titles jsonb not null default '{}'::jsonb;

create table if not exists public.member_hidden_plan_weeks (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  week_no integer not null check (week_no >= 1),
  created_at timestamptz not null default now(),
  primary key (team_id, user_id, week_no)
);

alter table public.member_hidden_plan_weeks enable row level security;
drop policy if exists "Members can view own hidden plan weeks" on public.member_hidden_plan_weeks;
create policy "Members can view own hidden plan weeks"
  on public.member_hidden_plan_weeks for select to authenticated
  using (user_id = auth.uid() and public.is_team_member(team_id));
drop policy if exists "Members can restore own hidden plan weeks" on public.member_hidden_plan_weeks;
create policy "Members can restore own hidden plan weeks"
  on public.member_hidden_plan_weeks for delete to authenticated
  using (user_id = auth.uid() and public.is_team_member(team_id));
grant select, delete on public.member_hidden_plan_weeks to authenticated;

create or replace function public.update_team_plan_week_title(target_team_id uuid, target_week integer, target_title text)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare next_titles jsonb;
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 주차 이름을 수정할 수 있습니다';
  end if;
  if target_week is null or target_week < 1 or target_title is null or length(btrim(target_title)) = 0 or length(btrim(target_title)) > 40 then
    raise exception '주차 이름은 1~40자로 입력해 주세요';
  end if;
  update public.teams
    set plan_week_titles = coalesce(plan_week_titles, '{}'::jsonb) || jsonb_build_object(target_week::text, btrim(target_title))
    where id = target_team_id
    returning plan_week_titles into next_titles;
  if next_titles is null then raise exception '팀 공간을 찾을 수 없습니다'; end if;
  return next_titles;
end
$$;
revoke all on function public.update_team_plan_week_title(uuid,integer,text) from public, anon;
grant execute on function public.update_team_plan_week_title(uuid,integer,text) to authenticated;

create or replace function public.delete_my_plan_week(target_team_id uuid, target_week integer)
returns void
language plpgsql security definer set search_path=public
as $$
declare week_start date; week_end date;
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 내 주차를 삭제할 수 있습니다';
  end if;
  if target_week is null or target_week < 1 then raise exception '올바른 주차가 아닙니다'; end if;

  week_start := date '2026-10-26' + ((target_week - 1) * 7);
  week_end := week_start + 7;
  delete from public.tasks
   where team_id = target_team_id
     and owner_id = auth.uid()
     and ((due_date is null and week_no = target_week)
       or (due_date >= week_start and due_date < week_end));

  insert into public.member_hidden_plan_weeks(team_id, user_id, week_no)
  values (target_team_id, auth.uid(), target_week)
  on conflict (team_id, user_id, week_no) do nothing;
end
$$;
revoke all on function public.delete_my_plan_week(uuid,integer) from public, anon;
grant execute on function public.delete_my_plan_week(uuid,integer) to authenticated;
