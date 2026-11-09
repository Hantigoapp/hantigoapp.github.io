-- HantiGo: remember the city each person chooses and their country (from the
-- phone's time zone), so the admin page can show where users are.
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.

alter table public.profiles add column if not exists city text;
alter table public.profiles add column if not exists country text;

-- A person sets only their own city/country (nothing else in their profile).
create or replace function public.set_my_location(c text, k text) returns void
language sql security definer set search_path = public as $$
  update profiles
     set city    = coalesce(nullif(left(trim(c), 40), ''), city),
         country = coalesce(nullif(left(trim(k), 40), ''), country)
   where id = auth.uid()
$$;

revoke execute on function public.set_my_location(text, text) from public, anon;
grant  execute on function public.set_my_location(text, text) to authenticated;
