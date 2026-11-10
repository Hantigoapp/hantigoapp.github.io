-- HantiGo: xogta shirkad kasta way gooni u tahay (company data isolation hardening)
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run. Safe to run more than once.
--
-- Already true before this file (schema.sql + team.sql):
--   * user_data rows are readable/writable only by their owner (RLS user_id = auth.uid()).
--   * Staff reach a company only through team_load/team_save, and only if the owner added their email.
--   * profiles are readable only by the person themself (or the HantiGo admin).
-- This file adds:
--   1. Staff no longer receive the owner's personal (Shakhsi) settings, only company settings.
--   2. RLS is switched on for every HantiGo table, and nobody can delete a user_data row directly.

-- 1. team_load: company items + company-only settings ---------------------------------
create or replace function public.team_load(owner uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare result jsonb;
begin
  if not public.is_team_member(owner) then raise exception 'not a member'; end if;
  if not public.owner_active(owner) then raise exception 'owner inactive'; end if;
  select coalesce(jsonb_agg(
           case when e ->> 'kind' = 'settings'
                then (e - 'myName' - 'budgets')
                     || jsonb_build_object('budgets', jsonb_build_object('business', coalesce(e -> 'budgets' -> 'business', 'null'::jsonb)))
                else e end), '[]'::jsonb) into result
    from user_data d, jsonb_array_elements(d.items) e
   where d.user_id = owner
     and (e ->> 'mode' = 'business' or e ->> 'kind' = 'settings');
  return result;
end $$;
revoke execute on function public.team_load(uuid) from public, anon;
grant  execute on function public.team_load(uuid) to authenticated;

-- 2. RLS on, no direct deletes -------------------------------------------------
alter table public.profiles     enable row level security;
alter table public.user_data    enable row level security;
alter table public.team_members enable row level security;
drop policy if exists "data delete" on public.user_data;
revoke delete on public.user_data from anon, authenticated;

-- 3. Check (shows one row per table; rls_on must be true) --------
select relname as table_name, relrowsecurity as rls_on
  from pg_class where relnamespace = 'public'::regnamespace
   and relname in ('profiles', 'user_data', 'team_members') order by 1;
