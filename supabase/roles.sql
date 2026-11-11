-- HantiGo: doorarka shirkadda (company roles) - Shaqaale (staff) iyo Maamule (manager)
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run. Safe to run more than once.
-- Needs team.sql and isolation.sql first (already run).
--
--   Milkiile (owner)  : everything, as before.
--   Maamule  (manager): all company items (money, salaries, statistics, receipts, debts, leave, bills).
--   Shaqaale (staff)  : only the entries and leave they made themselves + company name/logo/currency.
--                       Staff can add or fix only their own entries, and can never approve their own leave.

-- 1. Role column (every existing member starts as Shaqaale) ---------------------
alter table public.team_members add column if not exists role text not null default 'staff';
alter table public.team_members drop constraint if exists team_members_role_check;
alter table public.team_members add constraint team_members_role_check check (role in ('staff', 'manager'));

create or replace function public.team_role(owner uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from team_members
   where owner_id = owner
     and lower(member_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
$$;
revoke execute on function public.team_role(uuid) from public, anon;
grant  execute on function public.team_role(uuid) to authenticated;

-- 2. my_companies now also says the role ------------------------------------------
drop function if exists public.my_companies();
create function public.my_companies()
returns table (owner_id uuid, owner_email text, active boolean, role text)
language sql stable security definer set search_path = public as $$
  select t.owner_id, p.email, public.owner_active(t.owner_id), t.role
    from team_members t join profiles p on p.id = t.owner_id
   where lower(t.member_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
$$;
revoke execute on function public.my_companies() from public, anon;
grant  execute on function public.my_companies() to authenticated;

-- 3. team_load: manager gets the whole company, staff only their own -------------
create or replace function public.team_load(owner uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare result jsonb; r text := public.team_role(owner);
        me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if r is null then raise exception 'not a member'; end if;
  if not public.owner_active(owner) then raise exception 'owner inactive'; end if;
  if r = 'manager' then
    select coalesce(jsonb_agg(
             case when e ->> 'kind' = 'settings'
                  then (e - 'myName' - 'budgets')
                       || jsonb_build_object('budgets', jsonb_build_object('business', coalesce(e -> 'budgets' -> 'business', 'null'::jsonb)))
                  else e end), '[]'::jsonb) into result
      from user_data d, jsonb_array_elements(d.items) e
     where d.user_id = owner
       and (e ->> 'mode' = 'business' or e ->> 'kind' = 'settings');
  else
    select coalesce(jsonb_agg(
             case when e ->> 'kind' = 'settings' then (e - 'myName' - 'budgets' - 'invNo') else e end), '[]'::jsonb) into result
      from user_data d, jsonb_array_elements(d.items) e
     where d.user_id = owner
       and (e ->> 'kind' = 'settings'
            or (e ->> 'mode' = 'business' and e ->> 'kind' = 'cat')
            or (e ->> 'mode' = 'business' and e ->> 'kind' in ('tx', 'leave')
                and (lower(coalesce(e ->> 'by', '')) = me or (e ->> 'kind' = 'leave' and lower(coalesce(e ->> 'who', '')) = me))));
  end if;
  return result;
end $$;
revoke execute on function public.team_load(uuid) from public, anon;
grant  execute on function public.team_load(uuid) to authenticated;

-- 4. team_save: manager saves company items (and receipts), staff only their own ----
create or replace function public.team_save(owner uuid, upserts jsonb, deletes text[]) returns void
language plpgsql security definer set search_path = public as $$
declare clean jsonb; dels text[]; r text := public.team_role(owner);
        me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if r is null then raise exception 'not a member'; end if;
  if not public.owner_active(owner) then raise exception 'owner inactive'; end if;
  if r = 'manager' then
    select coalesce(jsonb_agg(u || '{"mode":"business"}'::jsonb), '[]'::jsonb) into clean
      from jsonb_array_elements(coalesce(upserts, '[]'::jsonb)) u
     where u ->> 'kind' in ('tx', 'goal', 'bill', 'cat', 'debt', 'leave', 'inv')
       and not exists (select 1 from user_data d, jsonb_array_elements(d.items) e
                        where d.user_id = owner and e ->> 'id' = u ->> 'id'
                          and coalesce(e ->> 'mode', 'person') <> 'business');
    dels := coalesce(deletes, '{}');
  else
    -- staff: new or own entries only; their leave is always a request (sick days are noted at once)
    select coalesce(jsonb_agg(
             case when u ->> 'kind' = 'leave'
                  then u || jsonb_build_object('mode', 'business', 'by', me, 'who', me,
                                               'status', case when u ->> 'type' = 'buka' then 'ok' else 'wait' end)
                  when u ->> 'kind' = 'tx' then u || jsonb_build_object('mode', 'business', 'by', me)
                  else u || '{"mode":"business"}'::jsonb end), '[]'::jsonb) into clean
      from jsonb_array_elements(coalesce(upserts, '[]'::jsonb)) u
     where u ->> 'kind' in ('tx', 'leave', 'cat')
       and not exists (select 1 from user_data d, jsonb_array_elements(d.items) e
                        where d.user_id = owner and e ->> 'id' = u ->> 'id'
                          and (coalesce(e ->> 'mode', 'person') <> 'business'
                               or e ->> 'kind' in ('leave', 'cat')
                               or lower(coalesce(e ->> 'by', '')) <> me));
    select coalesce(array_agg(x), '{}') into dels
      from unnest(coalesce(deletes, '{}')) x
     where exists (select 1 from user_data d, jsonb_array_elements(d.items) e
                    where d.user_id = owner and e ->> 'id' = x
                      and e ->> 'kind' in ('tx', 'leave')
                      and lower(coalesce(e ->> 'by', '')) = me
                      and (e ->> 'kind' = 'tx' or e ->> 'status' = 'wait' or e ->> 'type' = 'buka'));
  end if;
  insert into user_data (user_id, items) values (owner, '[]'::jsonb) on conflict (user_id) do nothing;
  update user_data
     set items = public.merge_items(items, clean, dels, true), updated_at = now()
   where user_id = owner;
end $$;
revoke execute on function public.team_save(uuid, jsonb, text[]) from public, anon;
grant  execute on function public.team_save(uuid, jsonb, text[]) to authenticated;

-- 5. Check: one row per staff member with their role -----------------------------
select member_email, role from public.team_members order by owner_id, member_email;
