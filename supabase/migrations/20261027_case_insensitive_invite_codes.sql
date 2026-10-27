-- Allow copied custom invite codes to work regardless of their letter casing.
create or replace function public.join_team(code text, member_name text)
returns table(id uuid, name text, invite_code text) language plpgsql security definer set search_path=public
as $$ declare t public.teams; begin
  if auth.uid() is null then raise exception '로그인이 필요합니다'; end if;
  select * into t from public.teams as team where upper(trim(team.invite_code))=upper(trim(code));
  if t.id is null then raise exception '초대 코드를 확인해 주세요'; end if;
  insert into public.team_members(team_id,user_id,display_name)
  values(t.id,auth.uid(),coalesce(nullif(trim(member_name),''),'팀원'))
  on conflict(team_id,user_id) do update set display_name=excluded.display_name;
  return query select t.id,t.name,t.invite_code;
end $$;
grant execute on function public.join_team(text,text) to authenticated;
