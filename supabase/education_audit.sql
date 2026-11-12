-- HantiGo Education: read-only schema and security audit
-- Run in Supabase Dashboard -> SQL Editor.
-- This script does not change data, policies, grants, or tables.

-- 1) Exact columns for the three existing Education tables.
select
  c.table_name,
  c.ordinal_position,
  c.column_name,
  c.data_type,
  c.is_nullable,
  c.column_default
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name in (
    'education_classes',
    'education_students',
    'education_fee_payments'
  )
order by c.table_name, c.ordinal_position;

-- 2) Row Level Security status for those tables.
select
  n.nspname as schema_name,
  cl.relname as table_name,
  cl.relrowsecurity as rls_enabled,
  cl.relforcerowsecurity as rls_forced
from pg_class cl
join pg_namespace n on n.oid = cl.relnamespace
where n.nspname = 'public'
  and cl.relkind = 'r'
  and cl.relname in (
    'education_classes',
    'education_students',
    'education_fee_payments'
  )
order by cl.relname;

-- 3) Existing RLS policies (if any).
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'education_classes',
    'education_students',
    'education_fee_payments'
  )
order by tablename, policyname;

-- 4) Table privileges currently granted to API roles.
select
  table_name,
  grantee,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in (
    'education_classes',
    'education_students',
    'education_fee_payments'
  )
  and grantee in ('anon', 'authenticated')
order by table_name, grantee, privilege_type;
