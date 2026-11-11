-- HantiGo background push notifications.
-- Run after security_hardening.sql. Safe to run repeatedly.
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  last_sent_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions(user_id);
alter table public.push_subscriptions enable row level security;
drop policy if exists push_subscriptions_self on public.push_subscriptions;
create policy push_subscriptions_self on public.push_subscriptions
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
revoke all on table public.push_subscriptions from public, anon;
grant select, insert, update, delete on table public.push_subscriptions to authenticated;

create table if not exists public.push_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  preferences jsonb not null default '{}'::jsonb,
  timezone text not null default 'UTC',
  updated_at timestamptz not null default now(),
  constraint push_preferences_object check (jsonb_typeof(preferences) = 'object')
);
alter table public.push_preferences enable row level security;
drop policy if exists push_preferences_self on public.push_preferences;
create policy push_preferences_self on public.push_preferences
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
revoke all on table public.push_preferences from public, anon;
grant select, insert, update, delete on table public.push_preferences to authenticated;

-- The Edge Function uses service_role to send pushes; the browser never receives it.
-- No anonymous access is granted. User subscriptions/preferences are isolated by auth.uid().
