-- Run this file in Supabase Dashboard → SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(), name text not null,
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8)),
  created_at timestamptz not null default now()
);
create table if not exists public.team_members (
  team_id uuid not null references public.teams on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  display_name text not null default '팀원', role text not null default 'member' check (role in ('admin','member')),
  joined_at timestamptz not null default now(), primary key(team_id,user_id)
);
create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(), team_id uuid not null references public.teams on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  work_date date not null default (now() at time zone 'Asia/Seoul')::date,
  photo_path text not null, checkout_photo_path text, uploaded_at timestamptz not null default now(), changed_at timestamptz,
  is_backfilled boolean not null default false, backfilled_at timestamptz, late_fee_krw integer not null default 0,
  backfilled_by uuid references auth.users on delete set null,
  unique(team_id,user_id,work_date)
);
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(), team_id uuid not null references public.teams on delete cascade,
  owner_id uuid not null references auth.users on delete cascade, title text not null,
  description text not null default '', week_no int not null check(week_no between 1 and 4),
  status text not null default '예정' check(status in ('예정','진행 중','완료','대기')),
  today_note text not null default '', done_note text not null default '', blocker text not null default '',
  next_step text not null default '', due_date date, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.change_requests (
  id uuid primary key default gen_random_uuid(), team_id uuid not null references public.teams on delete cascade,
  task_id uuid references public.tasks on delete set null, requester_id uuid not null references auth.users on delete cascade,
  assignee_id uuid not null references auth.users on delete cascade, body text not null,
  priority text not null default '보통' check(priority in ('낮음','보통','높음')),
  due_date date, status text not null default '보냄' check(status in ('보냄','확인함','진행 중','완료','보류')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(), team_id uuid not null references public.teams on delete cascade,
  user_id uuid not null references auth.users on delete cascade, work_date date not null default (now() at time zone 'Asia/Seoul')::date,
  as_is text not null default '', to_be text not null default '', updated_at timestamptz not null default now(), unique(team_id,user_id,work_date)
);

-- Use the database clock for attendance evidence, including photo replacements.
create or replace function public.stamp_attendance()
returns trigger language plpgsql set search_path=public
as $$ begin
  if tg_op='INSERT' then new.uploaded_at=now();
  else new.uploaded_at=old.uploaded_at; new.changed_at=now(); end if;
  return new;
end $$;
drop trigger if exists attendance_server_timestamp on public.attendance;
create trigger attendance_server_timestamp before insert or update on public.attendance
for each row execute function public.stamp_attendance();

create or replace function public.is_team_member(target_team uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.team_members where team_id=target_team and user_id=auth.uid()) $$;
create or replace function public.is_team_admin(target_team uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.team_members where team_id=target_team and user_id=auth.uid() and role='admin') $$;
grant execute on function public.is_team_member(uuid) to authenticated;
grant execute on function public.is_team_admin(uuid) to authenticated;

create or replace function public.create_team(team_name text, member_name text)
returns table(id uuid, name text, invite_code text) language plpgsql security definer set search_path=public
as $$ declare t public.teams; begin
  if auth.uid() is null then raise exception '로그인이 필요합니다'; end if;
  insert into public.teams(name) values (nullif(trim(team_name),'')) returning * into t;
  insert into public.team_members(team_id,user_id,display_name,role) values(t.id,auth.uid(),coalesce(nullif(trim(member_name),''),'관리자'),'admin');
  return query select t.id,t.name,t.invite_code;
end $$;
create or replace function public.join_team(code text, member_name text)
returns table(id uuid, name text, invite_code text) language plpgsql security definer set search_path=public
as $$ declare t public.teams; begin
  if auth.uid() is null then raise exception '로그인이 필요합니다'; end if;
  select * into t from public.teams where upper(trim(invite_code))=upper(trim(code));
  if t.id is null then raise exception '초대 코드를 확인해 주세요'; end if;
  insert into public.team_members(team_id,user_id,display_name) values(t.id,auth.uid(),coalesce(nullif(trim(member_name),''),'팀원'))
  on conflict(team_id,user_id) do update set display_name=excluded.display_name;
  return query select t.id,t.name,t.invite_code;
end $$;
grant execute on function public.create_team(text,text), public.join_team(text,text) to authenticated;

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.attendance enable row level security;
alter table public.tasks enable row level security;
alter table public.change_requests enable row level security;
alter table public.reports enable row level security;
create policy "team members see own teams" on public.teams for select to authenticated using(public.is_team_member(id));
create policy "team creator inserts team" on public.teams for insert to authenticated with check(true);
create policy "admins update team" on public.teams for update to authenticated using(public.is_team_admin(id)) with check(public.is_team_admin(id));
create policy "members see roster" on public.team_members for select to authenticated using(public.is_team_member(team_id));
create policy "admins manage roster" on public.team_members for all to authenticated using(public.is_team_admin(team_id)) with check(public.is_team_admin(team_id));
create policy "members see attendance" on public.attendance for select to authenticated using(public.is_team_member(team_id));
create policy "members submit own attendance" on public.attendance for insert to authenticated with check(public.is_team_member(team_id) and user_id=auth.uid());
create policy "members update own attendance" on public.attendance for update to authenticated using(public.is_team_member(team_id) and user_id=auth.uid()) with check(public.is_team_member(team_id) and user_id=auth.uid());
create policy "members see team tasks" on public.tasks for select to authenticated using(public.is_team_member(team_id));
create policy "members create own tasks, admins plan for team" on public.tasks for insert to authenticated with check(public.is_team_member(team_id) and (owner_id=auth.uid() or public.is_team_admin(team_id)));
create policy "owners update tasks, admins update all" on public.tasks for update to authenticated using(owner_id=auth.uid() or public.is_team_admin(team_id)) with check(public.is_team_member(team_id));
create policy "owners or admins delete tasks" on public.tasks for delete to authenticated using(owner_id=auth.uid() or public.is_team_admin(team_id));
create policy "participants see requests" on public.change_requests for select to authenticated using(public.is_team_member(team_id) and (requester_id=auth.uid() or assignee_id=auth.uid() or public.is_team_admin(team_id)));
create policy "members create requests" on public.change_requests for insert to authenticated with check(public.is_team_member(team_id) and requester_id=auth.uid());
create policy "participants update requests" on public.change_requests for update to authenticated using(requester_id=auth.uid() or assignee_id=auth.uid() or public.is_team_admin(team_id)) with check(public.is_team_member(team_id));
create policy "users see team reports" on public.reports for select to authenticated using(public.is_team_member(team_id));
create policy "users save own reports" on public.reports for insert to authenticated with check(public.is_team_member(team_id) and user_id=auth.uid());
create policy "users edit own reports" on public.reports for update to authenticated using(user_id=auth.uid()) with check(public.is_team_member(team_id) and user_id=auth.uid());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('attendance-photos','attendance-photos',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
create policy "owners and admins read attendance photos" on storage.objects for select to authenticated using(bucket_id='attendance-photos' and public.is_team_member(((storage.foldername(name))[1])::uuid) and ((storage.foldername(name))[2]=auth.uid()::text or public.is_team_admin(((storage.foldername(name))[1])::uuid)));
create policy "members upload own attendance photos" on storage.objects for insert to authenticated with check(bucket_id='attendance-photos' and (storage.foldername(name))[2]=auth.uid()::text and public.is_team_member(((storage.foldername(name))[1])::uuid));
create policy "members update own attendance photos" on storage.objects for update to authenticated using(bucket_id='attendance-photos' and (storage.foldername(name))[2]=auth.uid()::text and public.is_team_member(((storage.foldername(name))[1])::uuid));
