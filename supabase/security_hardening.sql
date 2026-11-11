-- HantiGo: harden helper-function execution privileges.
-- Run AFTER schema.sql, team.sql, isolation.sql, roles.sql and pricing.sql.
-- Safe to run more than once. This does NOT change business data or staff roles.
--
-- Why:
-- PostgreSQL grants EXECUTE on newly-created functions to PUBLIC by default.
-- RLS policies need is_admin() and has_access(), so authenticated users retain
-- access to those two helpers. Internal team helpers are callable only from
-- the SECURITY DEFINER RPCs owned by the database owner.
--
-- 1. Remove default PUBLIC/anon access from internal helpers.
revoke all on function public.is_team_member(uuid) from public, anon;
revoke all on function public.owner_active(uuid) from public, anon;
revoke all on function public.team_role(uuid) from public, anon;
revoke all on function public.merge_items(jsonb, jsonb, text[], boolean) from public, anon;

-- 2. RLS policy helpers: only signed-in users need to execute these.
revoke all on function public.is_admin() from public, anon;
revoke all on function public.has_access() from public, anon;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.has_access() to authenticated;

-- 3. Keep privileged RPCs unavailable to anonymous/public callers.
-- Authenticated grants are restored explicitly for the app's supported calls.
revoke all on function public.admin_extend(uuid, int) from public, anon;
grant execute on function public.admin_extend(uuid, int) to authenticated;

revoke all on function public.set_my_phone(text) from public, anon;
grant execute on function public.set_my_phone(text) to authenticated;

revoke all on function public.set_my_plan(text) from public, anon;
grant execute on function public.set_my_plan(text) to authenticated;

revoke all on function public.admin_set_plan(uuid, text) from public, anon;
grant execute on function public.admin_set_plan(uuid, text) to authenticated;

revoke all on function public.my_companies() from public, anon;
grant execute on function public.my_companies() to authenticated;

revoke all on function public.team_load(uuid) from public, anon;
grant execute on function public.team_load(uuid) to authenticated;

revoke all on function public.team_save(uuid, jsonb, text[]) from public, anon;
grant execute on function public.team_save(uuid, jsonb, text[]) to authenticated;

revoke all on function public.my_save(jsonb, text[]) from public, anon;
grant execute on function public.my_save(jsonb, text[]) to authenticated;

-- 4. Verify the three application tables still have RLS enabled.
select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('profiles', 'user_data', 'team_members')
order by c.relname;

-- 5. Verify helper execution grants (PUBLIC must be false).
select
  p.oid::regprocedure as function_name,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as signed_in_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('is_admin', 'has_access', 'is_team_member', 'owner_active', 'team_role')
order by p.proname;
