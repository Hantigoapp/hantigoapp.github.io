-- HantiGo: shaqaale badan oo isku akoon shirkad ah (company staff accounts)
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.
-- Safe to run more than once.

-- 1. Who may work in which company account ---------------------------------
create table if not exists public.team_members (
  owner_id     uuid not null references auth.users on delete cascade,
  member_email text not null,
  created_at   timestamptz not null default now(),
  primary key (owner_id, member_email)
);
alter table public.team_members enable row level security;

drop policy if exists "team owner manages" on public.team_members;
create policy "team owner manages" on public.team_members
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists "team member reads" on public.team_members;
create policy "team member reads" on public.team_members
  for select using (lower(member_email) = lower(coalesce(auth.jwt() ->> 'email', '')));

-- 2. Helpers -----------------------------------------------------------------
create or replace function public.is_team_member(owner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from team_members
                 where owner_id = owner
                   and lower(member_email) = lower(coalesce(auth.jwt() ->> 'email', '')))
$$;

create or replace function public.owner_active(owner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles
                 where id = owner and (is_admin or trial_until > now() or paid_until > now()))
$$;

-- Company accounts the signed-in person was added to.
create or replace function public.my_companies()
returns table (owner_id uuid, owner_email text, active boolean)
language sql stable security definer set search_path = public as $$
  select t.owner_id, p.email, public.owner_active(t.owner_id)
    from team_members t join profiles p on p.id = t.owner_id
   where lower(t.member_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
$$;

-- Staff read only the company (business) part of the owner's data.
create or replace function public.team_load(owner uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare result jsonb;
begin
  if not public.is_team_member(owner) then raise exception 'not a member'; end if;
  if not public.owner_active(owner) then raise exception 'owner inactive'; end if;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into result
    from user_data d, jsonb_array_elements(d.items) e
   where d.user_id = owner
     and (e ->> 'mode' = 'business' or e ->> 'kind' = 'settings');
  return result;
end $$;

-- Merge changes item by item, so the owner and staff never overwrite each other.
create or replace function public.merge_items(cur jsonb, upserts jsonb, deletes text[], only_business boolean)
returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select e as x from jsonb_array_elements(coalesce(cur, '[]'::jsonb)) e
     where coalesce(e ->> 'id', '') not in (select coalesce(u ->> 'id', '') from jsonb_array_elements(upserts) u)
       and not (coalesce(e ->> 'id', '') = any(deletes)
                and (not only_business or coalesce(e ->> 'mode', 'person') = 'business'))
    union all
    select u from jsonb_array_elements(upserts) u
  ) s
$$;

-- Staff save into the owner's company data.
create or replace function public.team_save(owner uuid, upserts jsonb, deletes text[]) returns void
language plpgsql security definer set search_path = public as $$
declare clean jsonb;
begin
  if not public.is_team_member(owner) then raise exception 'not a member'; end if;
  if not public.owner_active(owner) then raise exception 'owner inactive'; end if;
  select coalesce(jsonb_agg(u || '{"mode":"business"}'::jsonb), '[]'::jsonb) into clean
    from jsonb_array_elements(coalesce(upserts, '[]'::jsonb)) u
   where u ->> 'kind' in ('tx', 'goal', 'bill', 'cat', 'debt', 'leave')
     and not exists (select 1 from user_data d, jsonb_array_elements(d.items) e
                      where d.user_id = owner and e ->> 'id' = u ->> 'id'
                        and coalesce(e ->> 'mode', 'person') <> 'business');
  insert into user_data (user_id, items) values (owner, '[]'::jsonb) on conflict (user_id) do nothing;
  update user_data
     set items = public.merge_items(items, clean, coalesce(deletes, '{}'), true), updated_at = now()
   where user_id = owner;
end $$;

-- The owner saves the same way once the company has staff.
create or replace function public.my_save(upserts jsonb, deletes text[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.has_access() then raise exception 'no access'; end if;
  insert into user_data (user_id, items) values (auth.uid(), '[]'::jsonb) on conflict (user_id) do nothing;
  update user_data
     set items = public.merge_items(items, coalesce(upserts, '[]'::jsonb), coalesce(deletes, '{}'), false), updated_at = now()
   where user_id = auth.uid();
end $$;

revoke execute on function public.my_companies()                 from public, anon;
revoke execute on function public.team_load(uuid)                from public, anon;
revoke execute on function public.team_save(uuid, jsonb, text[]) from public, anon;
revoke execute on function public.my_save(jsonb, text[])         from public, anon;
grant  execute on function public.my_companies()                 to authenticated;
grant  execute on function public.team_load(uuid)                to authenticated;
grant  execute on function public.team_save(uuid, jsonb, text[]) to authenticated;
grant  execute on function public.my_save(jsonb, text[])         to authenticated;
