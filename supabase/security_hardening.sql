-- HantiGo: harden table and helper-function privileges.
-- Run AFTER schema.sql, team.sql, isolation.sql, roles.sql and pricing.sql.
-- Safe to run repeatedly. Does not alter finance records or staff assignments.
--
-- SECURITY MODEL:
-- profiles: signed-in user can read permitted profiles; changes only through
--           SECURITY DEFINER RPCs (set_my_phone/admin_*).
-- user_data: signed-in owner can read/insert/update their own row via RLS;
--            direct DELETE is disabled (app uses my_save/team_save).
-- team_members: owner manages memberships; listed member can read their own
--               membership rows. Staff do not get write permission.
-- Team data is accessed through team_load/team_save, which check membership,
-- active subscription and role on the server.

-- 1. Ensure RLS is enabled on every application table.
alter table public.profiles enable row level security;
alter table public.user_data enable row level security;
alter table public.team_members enable row level security;

-- 2. Explicit table privileges: no anonymous table access.
revoke all on table public.profiles from anon;
revoke all on table public.user_data from anon;
revoke all on table public.team_members from anon;

-- Profiles are read-only through the client; writes use guarded RPCs.
revoke all on table public.profiles from authenticated;
grant select on table public.profiles to authenticated;

-- User data: no direct DELETE; RLS restricts rows and WITH CHECK enforces access.
revoke all on table public.user_data from authenticated;
grant select, insert, update on table public.user_data to authenticated;

-- Membership management remains available to the company owner only via RLS.
-- Team members can SELECT their own membership row via the separate policy.
revoke all on table public.team_members from authenticated;
grant select, insert, update, delete on table public.team_members to authenticated;

-- 3. Remove default PUBLIC/anon execution from internal helpers.
revoke all on function public.is_team_member(uuid) from public, anon;
revoke all on function public.owner_active(uuid) from public, anon;
revoke all on function public.team_role(uuid) from public, anon;
revoke all on function public.merge_items(jsonb, jsonb, text[], boolean) from public, anon;

-- RLS policy helpers must remain executable by signed-in users.
revoke all on function public.is_admin() from public, anon;
revoke all on function public.has_access() from public, anon;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.has_access() to authenticated;

-- 4. Explicitly restrict app RPCs to authenticated users.
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

-- 5. Verification A: all app tables must report rls_enabled = true.
select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('profiles', 'user_data', 'team_members')
order by c.relname;

-- 6. Verification B: anon_can_execute should be false for every listed function.
select
  p.oid::regprocedure as function_name,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as signed_in_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'is_admin', 'has_access', 'is_team_member', 'owner_active', 'team_role',
    'my_companies', 'team_load', 'team_save', 'my_save',
    'admin_extend', 'admin_set_plan', 'set_my_plan', 'set_my_phone'
  )
order by p.proname;

-- 7. Verification C: client table grants.
select
  table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('profiles', 'user_data', 'team_members')
  and grantee in ('anon', 'authenticated')
order by table_name, grantee, privilege_type;

-- 8. Remaining app/admin RPCs from account/location/payment/sales/signups SQL.
-- These are SECURITY DEFINER functions with their own auth.uid()/is_admin()
-- checks; keep them callable by signed-in users only.
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

revoke all on function public.set_my_location(text, text) from public, anon;
grant execute on function public.set_my_location(text, text) to authenticated;

revoke all on function public.request_payment(text, text, text) from public, anon;
grant execute on function public.request_payment(text, text, text) to authenticated;

revoke all on function public.admin_pay_decide(uuid, boolean, int) from public, anon;
grant execute on function public.admin_pay_decide(uuid, boolean, int) to authenticated;

revoke all on function public.admin_signups() from public, anon;
grant execute on function public.admin_signups() to authenticated;

revoke all on function public.admin_record_sale(uuid, numeric, int, text, text, text) from public, anon;
grant execute on function public.admin_record_sale(uuid, numeric, int, text, text, text) to authenticated;

revoke all on function public.admin_delete_sale(uuid) from public, anon;
grant execute on function public.admin_delete_sale(uuid) to authenticated;

-- 9. Payment history is read-only through the client. All writes go through
-- the guarded request_payment/admin_* SECURITY DEFINER RPCs.
-- Run this script after supabase/sales.sql has created public.payments.
alter table public.payments enable row level security;
revoke all on table public.payments from anon, authenticated;
grant select on table public.payments to authenticated;

-- 10. Full RPC verification list: anon_can_execute should be false.
select
  p.oid::regprocedure as function_name,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as signed_in_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'is_admin', 'has_access', 'is_team_member', 'owner_active', 'team_role',
    'my_companies', 'team_load', 'team_save', 'my_save',
    'admin_extend', 'admin_set_plan', 'set_my_plan', 'set_my_phone',
    'delete_my_account', 'set_my_location', 'request_payment',
    'admin_pay_decide', 'admin_signups', 'admin_record_sale', 'admin_delete_sale'
  )
order by p.proname;
