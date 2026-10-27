-- Store one browser push subscription per device and team member.
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_subscriptions_team_id_idx
  on public.push_subscriptions(team_id);

create table if not exists public.attendance_push_events (
  attendance_id uuid not null references public.attendance(id) on delete cascade,
  event_type text not null check (event_type in ('check_in', 'check_out', 'backfill')),
  created_at timestamptz not null default now(),
  primary key (attendance_id, event_type)
);

alter table public.push_subscriptions enable row level security;
alter table public.attendance_push_events enable row level security;

drop policy if exists "members manage own push subscriptions" on public.push_subscriptions;
create policy "members manage own push subscriptions"
  on public.push_subscriptions
  for all to authenticated
  using (user_id = auth.uid() and public.is_team_member(team_id))
  with check (user_id = auth.uid() and public.is_team_member(team_id));
