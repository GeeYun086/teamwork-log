alter table public.tasks
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;

create index if not exists tasks_team_trash_idx
  on public.tasks(team_id, deleted_by, deleted_at desc)
  where deleted_at is not null;

create or replace function public.trash_my_plan_task(target_team_id uuid, target_task_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 업무를 휴지통으로 옮길 수 있습니다';
  end if;
  update public.tasks t
     set deleted_at = now(), deleted_by = auth.uid()
   where t.id = target_task_id
     and t.team_id = target_team_id
     and t.deleted_at is null
     and (t.owner_id = auth.uid() or exists (
       select 1 from public.team_members m
        where m.team_id = target_team_id and m.user_id = auth.uid() and m.role = 'admin'
     ));
  if not found then raise exception '업무를 삭제할 권한이 없거나 이미 휴지통에 있습니다'; end if;
end
$$;
revoke all on function public.trash_my_plan_task(uuid,uuid) from public, anon;
grant execute on function public.trash_my_plan_task(uuid,uuid) to authenticated;

create or replace function public.restore_trashed_plan_task(target_team_id uuid, target_task_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
declare restored_week integer;
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 업무를 복원할 수 있습니다';
  end if;
  select case when due_date is null then week_no
              else greatest(1, ((date_trunc('week', due_date)::date - date '2026-10-26') / 7) + 1)
         end
    into restored_week
    from public.tasks
   where id = target_task_id and team_id = target_team_id
     and deleted_at is not null and deleted_by = auth.uid();
  if restored_week is null then raise exception '복원할 권한이 있는 휴지통 업무를 찾지 못했습니다'; end if;

  update public.tasks set deleted_at = null, deleted_by = null
   where id = target_task_id and team_id = target_team_id and deleted_by = auth.uid();
  delete from public.member_hidden_plan_weeks
   where team_id = target_team_id and user_id = auth.uid() and week_no = restored_week;
end
$$;
revoke all on function public.restore_trashed_plan_task(uuid,uuid) from public, anon;
grant execute on function public.restore_trashed_plan_task(uuid,uuid) to authenticated;

create or replace function public.permanently_delete_trashed_plan_task(target_team_id uuid, target_task_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 휴지통 업무를 삭제할 수 있습니다';
  end if;
  delete from public.tasks
   where id = target_task_id and team_id = target_team_id
     and deleted_at is not null and deleted_by = auth.uid();
  if not found then raise exception '완전히 삭제할 휴지통 업무를 찾지 못했습니다'; end if;
end
$$;
revoke all on function public.permanently_delete_trashed_plan_task(uuid,uuid) from public, anon;
grant execute on function public.permanently_delete_trashed_plan_task(uuid,uuid) to authenticated;

create or replace function public.delete_my_plan_week(target_team_id uuid, target_week integer)
returns void
language plpgsql security definer set search_path=public
as $$
declare week_start date; week_end date;
begin
  if auth.uid() is null or not public.is_team_member(target_team_id) then
    raise exception '팀원만 내 주차를 휴지통으로 옮길 수 있습니다';
  end if;
  if target_week is null or target_week < 1 then raise exception '올바른 주차가 아닙니다'; end if;

  week_start := date '2026-10-26' + ((target_week - 1) * 7);
  week_end := week_start + 7;
  update public.tasks
     set deleted_at = now(), deleted_by = auth.uid()
   where team_id = target_team_id
     and owner_id = auth.uid()
     and deleted_at is null
     and ((due_date is null and week_no = target_week)
       or (due_date >= week_start and due_date < week_end));

  insert into public.member_hidden_plan_weeks(team_id, user_id, week_no)
  values (target_team_id, auth.uid(), target_week)
  on conflict (team_id, user_id, week_no) do nothing;
end
$$;
revoke all on function public.delete_my_plan_week(uuid,integer) from public, anon;
grant execute on function public.delete_my_plan_week(uuid,integer) to authenticated;
