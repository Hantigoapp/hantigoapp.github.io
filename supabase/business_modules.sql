-- HantiGo Business Module Manager foundation.
-- Additive migration: run AFTER the existing migrations, including security_hardening.sql.
-- This file does not modify user_data, existing finance tables, or existing RPC signatures.
-- Safe to run repeatedly.

-- 1. Stable module catalog. IDs are permanent API identifiers; labels can be localized in the app.
create table if not exists public.business_module_catalog (
  module_id text primary key,
  category text not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint business_module_catalog_id_check
    check (module_id ~ '^[a-z][a-z0-9_]{1,47}$')
);

insert into public.business_module_catalog (module_id, category, sort_order)
values
  ('education', 'education', 10),
  ('hotel', 'hospitality', 20),
  ('restaurant', 'hospitality', 30),
  ('retail', 'commerce', 40),
  ('wholesale', 'commerce', 50),
  ('construction', 'projects', 60),
  ('agriculture', 'production', 70),
  ('livestock', 'production', 80),
  ('transport', 'logistics', 90),
  ('manufacturing', 'production', 100),
  ('services', 'services', 110),
  ('fishing', 'production', 120)
on conflict (module_id) do update
  set category = excluded.category,
      sort_order = excluded.sort_order,
      active = true;

-- 2. One row per module per company-owner account.
-- Disabled rows are retained so a module can be switched off without deleting its history/settings.
create table if not exists public.company_modules (
  owner_id uuid not null references auth.users(id) on delete cascade,
  module_id text not null references public.business_module_catalog(module_id),
  enabled boolean not null default true,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (owner_id, module_id)
);

alter table public.business_module_catalog enable row level security;
alter table public.company_modules enable row level security;

-- No direct client table access. All access is through the guarded RPCs below.
revoke all on table public.business_module_catalog from anon, authenticated;
revoke all on table public.company_modules from anon, authenticated;

-- 3. Read the module selection for the owner or an authenticated member of that company.
create or replace function public.business_modules_get(p_owner uuid)
returns table (module_id text, category text, sort_order integer, enabled boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if auth.uid() <> p_owner and public.team_role(p_owner) is null then
    raise exception 'not a company member';
  end if;

  if not public.owner_active(p_owner) then
    raise exception 'company inactive';
  end if;

  return query
  select c.module_id, c.category, c.sort_order, coalesce(m.enabled, false)
    from public.business_module_catalog c
    left join public.company_modules m
      on m.owner_id = p_owner and m.module_id = c.module_id
   where c.active
   order by c.sort_order, c.module_id;
end;
$$;

-- 4. Only the company owner may change the selected modules.
-- This replaces the full selection atomically and retains disabled rows.
create or replace function public.business_modules_set(p_module_ids text[])
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  requested text[];
  unknown_ids text[];
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if not public.has_access() then
    raise exception 'no access';
  end if;

  requested := coalesce(p_module_ids, '{}'::text[]);

  if cardinality(requested) > 30 then
    raise exception 'too many modules';
  end if;

  if exists (
    select 1 from unnest(requested) as x
    where x is null or length(x) = 0
  ) then
    raise exception 'invalid module id';
  end if;

  if cardinality(requested) <> (
    select count(distinct x) from unnest(requested) as x
  ) then
    raise exception 'duplicate module id';
  end if;

  select array_agg(x) into unknown_ids
    from unnest(requested) as x
   where not exists (
     select 1 from public.business_module_catalog c
      where c.module_id = x and c.active
   );

  if coalesce(cardinality(unknown_ids), 0) > 0 then
    raise exception 'unknown or inactive module id(s): %', array_to_string(unknown_ids, ',');
  end if;

  insert into public.company_modules
    (owner_id, module_id, enabled, updated_by, updated_at)
  select auth.uid(), c.module_id, c.module_id = any(requested), auth.uid(), now()
    from public.business_module_catalog c
   where c.active
  on conflict (owner_id, module_id) do update
    set enabled = excluded.enabled,
        updated_by = excluded.updated_by,
        updated_at = now();
end;
$$;

revoke all on function public.business_modules_get(uuid) from public, anon;
revoke all on function public.business_modules_set(text[]) from public, anon;
grant execute on function public.business_modules_get(uuid) to authenticated;
grant execute on function public.business_modules_set(text[]) to authenticated;

-- 5. Verification: RLS must be enabled and anonymous users must have no table access.
select c.relname as table_name, c.relrowsecurity as rls_enabled
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public'
   and c.relname in ('business_module_catalog', 'company_modules')
 order by c.relname;

select
  has_table_privilege('anon', 'public.business_module_catalog', 'SELECT') as anon_catalog_select,
  has_table_privilege('authenticated', 'public.business_module_catalog', 'SELECT') as client_catalog_select,
  has_table_privilege('anon', 'public.company_modules', 'SELECT') as anon_company_modules_select,
  has_table_privilege('authenticated', 'public.company_modules', 'SELECT') as client_company_modules_select;

select
  p.oid::regprocedure as function_name,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('business_modules_get', 'business_modules_set')
order by p.proname;
