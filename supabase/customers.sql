-- customers.sql · HantiGo · 2026-11-17
-- Registered customers (kind 'cust': name, phone, email) live in the company's user_data like every other item.
-- The OWNER (Milkiile) can register customers and staff without this file.
-- Run it so the owner can give a MANAGER (Maamule) permission to register customers and new staff:
--   1. team_members.can_register (default false): the owner ticks it per manager in Akoon -> Shaqaalaha.
--   2. team_save: a manager may save customers ('cust') and add NEW employees (bill with emp) only when the
--      owner gave can_register. Everything a manager could do before stays the same. Staff never can.
-- Safe to run more than once. Run it AFTER roles.sql (and re-run it if roles.sql is ever run again).

alter table public.team_members add column if not exists can_register boolean not null default false;

create or replace function public.team_save(owner uuid, upserts jsonb, deletes text[]) returns void
language plpgsql security definer set search_path = public as $$
declare clean jsonb; dels text[]; r text := public.team_role(owner);
        me text := lower(coalesce(auth.jwt() ->> 'email', ''));
        may_reg boolean := coalesce((select t.can_register from team_members t
                                      where t.owner_id = owner and lower(t.member_email) = me), false);
begin
  if r is null then raise exception 'not a member'; end if;
  if not public.owner_active(owner) then raise exception 'owner inactive'; end if;
  if r = 'manager' then
    select coalesce(jsonb_agg(u || '{"mode":"business"}'::jsonb), '[]'::jsonb) into clean
      from jsonb_array_elements(coalesce(upserts, '[]'::jsonb)) u
     where u ->> 'kind' in ('tx', 'goal', 'bill', 'cat', 'debt', 'leave', 'inv', 'cust')
       -- customers and NEW employees only with the owner's permission
       and (may_reg or not (u ->> 'kind' = 'cust'
                            or (u ->> 'kind' = 'bill' and coalesce(u ->> 'emp', '') not in ('', '0', 'false')
                                and not exists (select 1 from user_data d, jsonb_array_elements(d.items) e
                                                 where d.user_id = owner and e ->> 'id' = u ->> 'id'))))
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

-- Check: both should be true
select exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'team_members' and column_name = 'can_register') as permission_column_ready,
       position('may_reg' in pg_get_functiondef('public.team_save(uuid, jsonb, text[])'::regprocedure)) > 0 as managers_need_permission;
