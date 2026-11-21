alter table public.tasks add column if not exists trash_week_no integer;

create table if not exists public.trashed_plan_weeks (
  team_id uuid not null references public.teams(id) on delete cascade,
  week_no integer not null check (week_no >= 1),
  title text not null,
  deleted_by uuid not null references auth.users(id) on delete restrict,
  deleted_at timestamptz not null default now(),
  task_count integer not null default 0,
  permanently_deleted_at timestamptz,
  primary key (team_id, week_no)
);
alter table public.trashed_plan_weeks enable row level security;
drop policy if exists "Team members can view trashed plan weeks" on public.trashed_plan_weeks;
create policy "Team members can view trashed plan weeks"
  on public.trashed_plan_weeks for select to authenticated
  using (public.is_team_member(team_id));
grant select on public.trashed_plan_weeks to authenticated;

create or replace function public.delete_my_plan_week(target_team_id uuid, target_week integer)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 내 업무를 휴지통으로 옮길 수 있습니다';
  end if;
  if target_week is null or target_week < 1 then raise exception '올바른 주차가 아닙니다'; end if;
  update public.tasks
     set deleted_at = now(), deleted_by = auth.uid(), trash_week_no = null
   where team_id = target_team_id and owner_id = auth.uid() and deleted_at is null
     and ((due_date is null and week_no = target_week)
       or (due_date is not null and greatest(1, ((date_trunc('week', due_date)::date - date '2026-10-26') / 7) + 1) = target_week));
end;
$$;
revoke all on function public.delete_my_plan_week(uuid,integer) from public, anon;
grant execute on function public.delete_my_plan_week(uuid,integer) to authenticated;

create or replace function public.trash_plan_week(target_team_id uuid, target_week integer)
returns integer
language plpgsql security definer set search_path=public
as $$
declare saved_title text; moved_count integer;
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 팀 주차를 휴지통으로 옮길 수 있습니다';
  end if;
  if target_week is null or target_week < 1 then raise exception '올바른 주차가 아닙니다'; end if;
  if exists (select 1 from public.trashed_plan_weeks where team_id=target_team_id and week_no=target_week) then
    raise exception '이미 삭제되었거나 휴지통에 있는 주차입니다';
  end if;
  select coalesce(plan_week_titles->>target_week::text,
         case target_week when 1 then '기초 정리' when 2 then '핵심 구현' when 3 then '검토·보완' when 4 then '마무리' else target_week::text||'주차 업무' end)
    into saved_title from public.teams where id=target_team_id;
  if saved_title is null then raise exception '팀 공간을 찾을 수 없습니다'; end if;

  insert into public.trashed_plan_weeks(team_id,week_no,title,deleted_by,deleted_at,task_count)
  values (target_team_id,target_week,saved_title,auth.uid(),now(),0);
  update public.tasks
     set deleted_at=now(), deleted_by=auth.uid(), trash_week_no=target_week
   where team_id=target_team_id and deleted_at is null
     and ((due_date is null and week_no=target_week)
       or (due_date is not null and greatest(1, ((date_trunc('week', due_date)::date - date '2026-10-26') / 7) + 1)=target_week));
  get diagnostics moved_count = row_count;
  update public.trashed_plan_weeks set task_count=moved_count
   where team_id=target_team_id and week_no=target_week;
  return moved_count;
end;
$$;
revoke all on function public.trash_plan_week(uuid,integer) from public, anon;
grant execute on function public.trash_plan_week(uuid,integer) to authenticated;

create or replace function public.restore_trashed_plan_week(target_team_id uuid, target_week integer)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then raise exception '팀원만 주차를 복원할 수 있습니다'; end if;
  if not exists (select 1 from public.trashed_plan_weeks where team_id=target_team_id and week_no=target_week and permanently_deleted_at is null) then
    raise exception '복원할 주차를 휴지통에서 찾지 못했습니다';
  end if;
  update public.tasks set deleted_at=null,deleted_by=null,trash_week_no=null
   where team_id=target_team_id and trash_week_no=target_week and deleted_at is not null;
  delete from public.trashed_plan_weeks where team_id=target_team_id and week_no=target_week;
end;
$$;
revoke all on function public.restore_trashed_plan_week(uuid,integer) from public, anon;
grant execute on function public.restore_trashed_plan_week(uuid,integer) to authenticated;

create or replace function public.permanently_delete_trashed_plan_week(target_team_id uuid, target_week integer)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then raise exception '팀원만 주차를 완전히 삭제할 수 있습니다'; end if;
  if not exists (select 1 from public.trashed_plan_weeks where team_id=target_team_id and week_no=target_week and permanently_deleted_at is null) then
    raise exception '완전히 삭제할 주차를 휴지통에서 찾지 못했습니다';
  end if;
  delete from public.tasks where team_id=target_team_id and trash_week_no=target_week and deleted_at is not null;
  update public.trashed_plan_weeks set permanently_deleted_at=now()
   where team_id=target_team_id and week_no=target_week;
end;
$$;
revoke all on function public.permanently_delete_trashed_plan_week(uuid,integer) from public, anon;
grant execute on function public.permanently_delete_trashed_plan_week(uuid,integer) to authenticated;

create or replace function public.restore_trashed_plan_task(target_team_id uuid, target_task_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then raise exception '팀원만 업무를 복원할 수 있습니다'; end if;
  update public.tasks set deleted_at=null,deleted_by=null,trash_week_no=null
   where id=target_task_id and team_id=target_team_id and deleted_at is not null
     and deleted_by=auth.uid() and trash_week_no is null;
  if not found then raise exception '복원할 권한이 있는 휴지통 업무를 찾지 못했습니다'; end if;
end;
$$;
revoke all on function public.restore_trashed_plan_task(uuid,uuid) from public, anon;
grant execute on function public.restore_trashed_plan_task(uuid,uuid) to authenticated;

create or replace function public.permanently_delete_trashed_plan_task(target_team_id uuid, target_task_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then raise exception '팀원만 휴지통 업무를 삭제할 수 있습니다'; end if;
  delete from public.tasks where id=target_task_id and team_id=target_team_id
    and deleted_at is not null and deleted_by=auth.uid() and trash_week_no is null;
  if not found then raise exception '완전히 삭제할 휴지통 업무를 찾지 못했습니다'; end if;
end;
$$;
revoke all on function public.permanently_delete_trashed_plan_task(uuid,uuid) from public, anon;
grant execute on function public.permanently_delete_trashed_plan_task(uuid,uuid) to authenticated;

