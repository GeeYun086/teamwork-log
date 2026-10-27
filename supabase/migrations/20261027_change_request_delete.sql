-- Allow request participants and team admins to remove an obsolete request.
drop policy if exists "participants delete requests" on public.change_requests;
create policy "participants delete requests" on public.change_requests
  for delete to authenticated
  using (
    public.is_team_member(team_id)
    and (requester_id = auth.uid() or assignee_id = auth.uid() or public.is_team_admin(team_id))
  );
