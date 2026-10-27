-- Allow request participants and team admins to remove an obsolete request.
drop policy if exists "participants delete requests" on public.change_requests;
create policy "participants delete requests" on public.change_requests
  for delete to authenticated
  using (
    public.is_team_member(team_id)
    and (requester_id = auth.uid() or assignee_id = auth.uid() or public.is_team_admin(team_id))
  );

-- Publish request changes so teammates see deletions and status updates immediately.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'change_requests'
     ) then
    execute 'alter publication supabase_realtime add table public.change_requests';
  end if;
end
$$;
