-- Let each signed-in team member delete only their own saved reports.
drop policy if exists "users delete own reports" on public.reports;
create policy "users delete own reports" on public.reports
  for delete to authenticated
  using (user_id = auth.uid() and public.is_team_member(team_id));
grant delete on public.reports to authenticated;
