-- HantiGo: read-only role and RLS audit.
-- Run AFTER the full setup sequence in README.md. This script changes no data or permissions.
-- Review every result; an empty or unexpected result needs investigation.

-- A. Required application tables: every row must have rls_enabled = true.
select c.relname as table_name, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as force_rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('profiles', 'user_data', 'team_members', 'payments')
order by c.relname;

-- B. Policies on application tables. Confirm owner-only write policies and
-- member-only SELECT policy for team_members are present.
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('profiles', 'user_data', 'team_members', 'payments')
order by tablename, policyname;

-- C. Direct table grants. anon should have no privileges. payments should be
-- SELECT-only for authenticated; profiles should be SELECT-only.
select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('profiles', 'user_data', 'team_members', 'payments')
  and grantee in ('anon', 'authenticated')
order by table_name, grantee, privilege_type;

-- D. Role-aware RPC grants. anon_can_execute must be false for every row.
select p.oid::regprocedure as function_name,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_can_execute,
       p.prosecdef as security_definer,
       p.proconfig as function_settings
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('my_companies', 'team_role', 'team_load', 'team_save',
                    'my_save', 'is_team_member', 'owner_active', 'merge_items')
order by p.proname;

-- E. Current staff roles. Existing members should be either staff or manager.
select owner_id, member_email, role
from public.team_members
order by owner_id, member_email;

-- Manual negative tests are still required with separate test accounts:
-- 1. Staff A cannot read Staff B's entries or another company's data.
-- 2. Staff cannot approve/decline leave, edit another person's entry,
--    change team roles, or add/remove members.
-- 3. Manager can manage company records and approve leave, but cannot read
--    the owner's personal records or manage team membership/roles.
-- 4. Owner can manage the company and team; customer can read only own profile,
--    own data, and own payment history.
-- 5. An unauthenticated/anon client cannot read or write any application table
--    or execute authenticated RPCs.
-- Use disposable test accounts and dummy records only.


-- F. Review every SECURITY DEFINER function in public. A null/empty search_path
-- should be treated as a finding and fixed before production.
select p.oid::regprocedure as function_name,
       p.proconfig as function_settings,
       case when coalesce(array_to_string(p.proconfig, ','), '') ilike '%search_path=%'
            then 'review configured search_path'
            else 'CHECK: no function-level search_path' end as search_path_review
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
order by p.proname;

