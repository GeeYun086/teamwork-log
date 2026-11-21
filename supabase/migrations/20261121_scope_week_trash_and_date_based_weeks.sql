alter table public.teams
  add column if not exists plan_week_numbers integer[] not null default array[1,2,3,4];

update public.teams
   set plan_week_numbers = array(
     select week_no from generate_series(1, greatest(4, plan_week_count)) as weeks(week_no)
   );

alter table public.trashed_plan_weeks
  add column if not exists scope text not null default 'team',
  add column if not exists id uuid default gen_random_uuid();
update public.trashed_plan_weeks set id=gen_random_uuid() where id is null;
alter table public.trashed_plan_weeks alter column id set not null;
alter table public.trashed_plan_weeks drop constraint if exists trashed_plan_weeks_pkey;
alter table public.trashed_plan_weeks add constraint trashed_plan_weeks_pkey primary key (id);
alter table public.trashed_plan_weeks drop constraint if exists trashed_plan_weeks_scope_check;
alter table public.trashed_plan_weeks add constraint trashed_plan_weeks_scope_check check (scope in ('mine','team'));
create unique index if not exists trashed_plan_weeks_active_team_unique
  on public.trashed_plan_weeks(team_id, week_no) where scope='team' and permanently_deleted_at is null;
create unique index if not exists trashed_plan_weeks_active_mine_unique
  on public.trashed_plan_weeks(team_id, week_no, deleted_by) where scope='mine' and permanently_deleted_at is null;

-- The return types and week identifier changed; PostgreSQL requires dropping
-- the old signatures before recreating these functions.
drop function if exists public.delete_my_plan_week(uuid, integer);
drop function if exists public.trash_plan_week(uuid, integer);
drop function if exists public.restore_trashed_plan_week(uuid, integer);
drop function if exists public.permanently_delete_trashed_plan_week(uuid, integer);

alter table public.tasks add column if not exists trash_week_id uuid;
update public.tasks t
   set trash_week_id=w.id
  from public.trashed_plan_weeks w
 where t.team_id=w.team_id and t.trash_week_no=w.week_no and t.deleted_by=w.deleted_by
   and t.deleted_at is not null and w.scope='team' and t.trash_week_id is null;

create or replace function public.extend_team_plan_weeks(target_team_id uuid, target_week integer)
returns integer
language plpgsql security definer set search_path=public
as $$
declare next_count integer;
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 주차를 추가할 수 있습니다';
  end if;
  if target_week is null or target_week < 1 then raise exception '올바른 주차가 아닙니다'; end if;
  if exists(select 1 from public.trashed_plan_weeks where team_id=target_team_id and week_no=target_week and scope='team' and permanently_deleted_at is null) then
    raise exception '휴지통에서 이 주차를 복원하거나 완전히 삭제한 뒤 추가할 수 있습니다';
  end if;
  update public.teams
     set plan_week_count=greatest(plan_week_count,target_week),
         plan_week_numbers=case when target_week=any(coalesce(plan_week_numbers,array[1,2,3,4])) then coalesce(plan_week_numbers,array[1,2,3,4]) else array_append(coalesce(plan_week_numbers,array[1,2,3,4]),target_week) end
   where id=target_team_id
   returning plan_week_count into next_count;
  if not found then raise exception '팀 공간을 찾을 수 없습니다'; end if;
  return next_count;
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
  if auth.uid() is null or not public.is_team_member(target_team_id) then raise exception '팀원만 내 주차를 휴지통으로 옮길 수 있습니다'; end if;
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
  return trash_id;
end;
$$;
revoke all on function public.delete_my_plan_week(uuid,integer) from public, anon;
grant execute on function public.delete_my_plan_week(uuid,integer) to authenticated;

create or replace function public.trash_plan_week(target_team_id uuid, target_week integer)
returns uuid
language plpgsql security definer set search_path=public
as $$
declare saved_title text; moved_count integer; trash_id uuid;
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then raise exception '팀원만 전체 주차를 휴지통으로 옮길 수 있습니다'; end if;
  if target_week is null or target_week < 1 then raise exception '올바른 주차가 아닙니다'; end if;
  select coalesce(plan_week_titles->>target_week::text,
    case target_week when 1 then '기초 정리' when 2 then '핵심 구현' when 3 then '검토·보완' when 4 then '마무리' else target_week::text||'주차 업무' end)
    into saved_title from public.teams where id=target_team_id;
  if saved_title is null then raise exception '팀 공간을 찾을 수 없습니다'; end if;
  insert into public.trashed_plan_weeks(team_id,week_no,title,deleted_by,deleted_at,task_count,scope)
    values(target_team_id,target_week,saved_title,auth.uid(),now(),0,'team') returning id into trash_id;
  update public.tasks set deleted_at=now(),deleted_by=auth.uid(),trash_week_no=target_week,trash_week_id=trash_id
   where team_id=target_team_id and deleted_at is null
     and ((due_date is null and week_no=target_week)
       or (due_date is not null and greatest(1,((date_trunc('week',due_date)::date-date '2026-10-26')/7)+1)=target_week));
  get diagnostics moved_count=row_count;
  update public.trashed_plan_weeks set task_count=moved_count where id=trash_id;
  update public.teams set plan_week_numbers=array_remove(coalesce(plan_week_numbers,array[1,2,3,4]),target_week) where id=target_team_id;
  return trash_id;
end;
$$;
revoke all on function public.trash_plan_week(uuid,integer) from public, anon;
grant execute on function public.trash_plan_week(uuid,integer) to authenticated;

create or replace function public.restore_trashed_plan_week(target_team_id uuid, target_trash_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
declare trashed public.trashed_plan_weeks%rowtype;
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then raise exception '팀원만 주차를 복원할 수 있습니다'; end if;
  select * into trashed from public.trashed_plan_weeks where id=target_trash_id and team_id=target_team_id and permanently_deleted_at is null;
  if not found then raise exception '복원할 주차를 휴지통에서 찾지 못했습니다'; end if;
  update public.tasks set deleted_at=null,deleted_by=null,trash_week_no=null,trash_week_id=null
   where team_id=target_team_id and trash_week_id=target_trash_id and deleted_at is not null;
  if trashed.scope='team' then
    update public.teams set plan_week_numbers=case when trashed.week_no=any(coalesce(plan_week_numbers,array[1,2,3,4])) then coalesce(plan_week_numbers,array[1,2,3,4]) else array_append(coalesce(plan_week_numbers,array[1,2,3,4]),trashed.week_no) end where id=target_team_id;
  end if;
  delete from public.trashed_plan_weeks where id=target_trash_id;
end;
$$;
revoke all on function public.restore_trashed_plan_week(uuid,uuid) from public, anon;
grant execute on function public.restore_trashed_plan_week(uuid,uuid) to authenticated;

create or replace function public.permanently_delete_trashed_plan_week(target_team_id uuid, target_trash_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then raise exception '팀원만 주차를 완전히 삭제할 수 있습니다'; end if;
  if not exists(select 1 from public.trashed_plan_weeks where id=target_trash_id and team_id=target_team_id and permanently_deleted_at is null) then
    raise exception '완전히 삭제할 주차를 휴지통에서 찾지 못했습니다';
  end if;
  delete from public.tasks where team_id=target_team_id and trash_week_id=target_trash_id and deleted_at is not null;
  update public.trashed_plan_weeks set permanently_deleted_at=now() where id=target_trash_id and team_id=target_team_id;
end;
$$;
revoke all on function public.permanently_delete_trashed_plan_week(uuid,uuid) from public, anon;
grant execute on function public.permanently_delete_trashed_plan_week(uuid,uuid) to authenticated;

create or replace function public.restore_trashed_plan_task(target_team_id uuid, target_task_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then raise exception '팀원만 업무를 복원할 수 있습니다'; end if;
  update public.tasks set deleted_at=null,deleted_by=null,trash_week_no=null,trash_week_id=null
   where id=target_task_id and team_id=target_team_id and deleted_at is not null and deleted_by=auth.uid()
     and trash_week_no is null and trash_week_id is null;
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
  delete from public.tasks where id=target_task_id and team_id=target_team_id and deleted_at is not null
    and deleted_by=auth.uid() and trash_week_no is null and trash_week_id is null;
  if not found then raise exception '완전히 삭제할 휴지통 업무를 찾지 못했습니다'; end if;
end;
$$;
revoke all on function public.permanently_delete_trashed_plan_task(uuid,uuid) from public, anon;
grant execute on function public.permanently_delete_trashed_plan_task(uuid,uuid) to authenticated;
