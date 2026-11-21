create table if not exists public.member_plan_weeks (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  week_no integer not null check (week_no > 4),
  created_at timestamptz not null default now(),
  primary key (team_id, user_id, week_no)
);

alter table public.member_plan_weeks enable row level security;
drop policy if exists "Members can view their own plan weeks" on public.member_plan_weeks;
create policy "Members can view their own plan weeks" on public.member_plan_weeks
  for select to authenticated
  using (auth.uid() = user_id and public.is_team_member(team_id));
grant select on public.member_plan_weeks to authenticated;

-- Dynamic empty weeks belong to the person who added them. Team-wide weeks are
-- derived from active cards, so empty weeks never appear in the shared view.
update public.teams
   set plan_week_count = 4,
       plan_week_numbers = array[1,2,3,4]
 where id = '43377ee1-b4c2-4e42-9b43-e36ae1c121aa';

-- Preserve the requesting admin's W5/W6 while removing the obsolete shared W7.
insert into public.member_plan_weeks(team_id,user_id,week_no)
select '43377ee1-b4c2-4e42-9b43-e36ae1c121aa'::uuid,
       '82ea407f-2e8f-41dd-9510-59495a9b517d'::uuid,
       weeks.week_no
from (values (5),(6)) as weeks(week_no)
where exists (
  select 1 from public.team_members m
   where m.team_id='43377ee1-b4c2-4e42-9b43-e36ae1c121aa'
     and m.user_id='82ea407f-2e8f-41dd-9510-59495a9b517d'
)
on conflict (team_id,user_id,week_no) do nothing;

-- Stop the legacy task trigger from putting extended weeks back into the shared list.
drop trigger if exists sync_active_task_plan_weeks on public.tasks;

create or replace function public.extend_team_plan_weeks(target_team_id uuid, target_week integer)
returns integer
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 주차를 추가할 수 있습니다';
  end if;
  if target_week is null or target_week < 1 then raise exception '올바른 주차가 아닙니다'; end if;
  if target_week <= 4 then return 4; end if;
  if exists(select 1 from public.trashed_plan_weeks
      where team_id=target_team_id and week_no=target_week
        and permanently_deleted_at is null
        and (scope='team' or (scope='mine' and deleted_by=auth.uid()))) then
    raise exception '휴지통에서 이 주차를 복원하거나 완전히 삭제한 뒤 추가할 수 있습니다';
  end if;
  insert into public.member_plan_weeks(team_id,user_id,week_no)
  values(target_team_id,auth.uid(),target_week)
  on conflict (team_id,user_id,week_no) do nothing;
  return target_week;
end;
$$;
revoke all on function public.extend_team_plan_weeks(uuid,integer) from public, anon;
grant execute on function public.extend_team_plan_weeks(uuid,integer) to authenticated;

create or replace function public.delete_my_plan_week(target_team_id uuid, target_week integer)
returns uuid
language plpgsql security definer set search_path=public
as $$
declare saved_title text; moved_count integer; trash_id uuid;
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 내 주차를 휴지통으로 옮길 수 있습니다';
  end if;
  if target_week is null or target_week < 1 then raise exception '올바른 주차가 아닙니다'; end if;
  select coalesce(plan_week_titles->>target_week::text,
    case target_week when 1 then '기초 정리' when 2 then '핵심 구현' when 3 then '검토·보완' when 4 then '마무리' else target_week::text||'주차 업무' end)
    into saved_title from public.teams where id=target_team_id;
  if saved_title is null then raise exception '팀 공간을 찾을 수 없습니다'; end if;
  insert into public.trashed_plan_weeks(team_id,week_no,title,deleted_by,deleted_at,task_count,scope)
    values(target_team_id,target_week,saved_title,auth.uid(),now(),0,'mine') returning id into trash_id;
  update public.tasks set deleted_at=now(),deleted_by=auth.uid(),trash_week_no=target_week,trash_week_id=trash_id
   where team_id=target_team_id and owner_id=auth.uid() and deleted_at is null
     and ((due_date is null and week_no=target_week)
       or (due_date is not null and greatest(1,((date_trunc('week',due_date)::date-date '2026-10-26')/7)+1)=target_week));
  get diagnostics moved_count=row_count;
  update public.trashed_plan_weeks set task_count=moved_count where id=trash_id;
  delete from public.member_plan_weeks where team_id=target_team_id and user_id=auth.uid() and week_no=target_week;
  return trash_id;
end;
$$;
revoke all on function public.delete_my_plan_week(uuid,integer) from public, anon;
grant execute on function public.delete_my_plan_week(uuid,integer) to authenticated;

create or replace function public.restore_trashed_plan_week(target_team_id uuid, target_trash_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
declare trashed public.trashed_plan_weeks%rowtype;
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 주차를 복원할 수 있습니다';
  end if;
  select * into trashed from public.trashed_plan_weeks
   where id=target_trash_id and team_id=target_team_id
     and permanently_deleted_at is null
     and (scope='team' or deleted_by=auth.uid());
  if not found then raise exception '복원할 주차를 휴지통에서 찾지 못했습니다'; end if;
  update public.tasks set deleted_at=null,deleted_by=null,trash_week_no=null,trash_week_id=null
   where team_id=target_team_id and trash_week_id=target_trash_id and deleted_at is not null;
  if trashed.scope='mine' and trashed.week_no>4 then
    insert into public.member_plan_weeks(team_id,user_id,week_no)
    values(target_team_id,auth.uid(),trashed.week_no)
    on conflict (team_id,user_id,week_no) do nothing;
  end if;
  delete from public.trashed_plan_weeks where id=target_trash_id;
end;
$$;
revoke all on function public.restore_trashed_plan_week(uuid,uuid) from public, anon;
grant execute on function public.restore_trashed_plan_week(uuid,uuid) to authenticated;

-- Enable realtime updates for per-member empty week rows when available.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname='supabase_realtime' and schemaname='public' and tablename='member_plan_weeks'
  ) then
    alter publication supabase_realtime add table public.member_plan_weeks;
  end if;
exception when undefined_object then
  null;
end $$;
