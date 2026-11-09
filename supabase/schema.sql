-- HantiGo database setup
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.

-- 1. Tables ---------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users on delete cascade,
  email        text,
  phone        text,                                   -- EVC number the customer pays from
  trial_until  timestamptz not null default now() + interval '7 days',
  paid_until   timestamptz,
  is_admin     boolean not null default false,
  created_at   timestamptz not null default now()
);

create table if not exists public.user_data (
  user_id     uuid primary key references auth.users on delete cascade,
  items       jsonb not null default '[]'::jsonb,       -- all transactions, bills, goals, settings
  updated_at  timestamptz not null default now()
);

alter table public.profiles  enable row level security;
alter table public.user_data enable row level security;

-- 2. Helper functions ------------------------------------------------------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false)
$$;

create or replace function public.has_access() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles
    where id = auth.uid()
      and (is_admin or trial_until > now() or paid_until > now())
  )
$$;

-- 3. Row level security ----------------------------------------------------
drop policy if exists "profile read" on public.profiles;
create policy "profile read" on public.profiles
  for select using (id = auth.uid() or public.is_admin());

drop policy if exists "data read" on public.user_data;
create policy "data read" on public.user_data
  for select using (user_id = auth.uid());

drop policy if exists "data insert" on public.user_data;
create policy "data insert" on public.user_data
  for insert with check (user_id = auth.uid() and public.has_access());

drop policy if exists "data update" on public.user_data;
create policy "data update" on public.user_data
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.has_access());

-- 4. Create a profile for every new account --------------------------------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, is_admin)
  values (new.id, new.email, lower(new.email) = 'asad.moallim@gmail.com')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 5. Actions the app can call ----------------------------------------------
-- Customer saves the EVC number they pay from.
create or replace function public.set_my_phone(p text) returns void
language sql security definer set search_path = public as $$
  update profiles set phone = left(trim(p), 20) where id = auth.uid()
$$;

-- Admin adds paid days to a customer (days <= 0 stops the subscription).
create or replace function public.admin_extend(target uuid, days int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'not admin';
  end if;
  update profiles
     set paid_until = case
       when days <= 0 then null
       else greatest(coalesce(paid_until, now()), now()) + make_interval(days => days)
     end
   where id = target;
end $$;

revoke execute on function public.set_my_phone(text)      from public, anon;
revoke execute on function public.admin_extend(uuid, int) from public, anon;
grant  execute on function public.set_my_phone(text)      to authenticated;
grant  execute on function public.admin_extend(uuid, int) to authenticated;

-- 6. Owner account already signed up before this script? Make it admin.
update public.profiles set is_admin = true where lower(email) = 'asad.moallim@gmail.com';
