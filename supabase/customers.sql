-- customers.sql · HantiGo · 2026-11-17
-- Registered customers (kind 'cust': name, phone, email) live in the company's user_data like every other item.
-- The owner can register customers without this file. Run it so a company MANAGER (Maamule) can register them too:
-- it is roles.sql's team_save with 'cust' added to what a manager may save. Staff still cannot save or see customers.
-- Safe to run more than once. Run it AFTER roles.sql (and re-run it if roles.sql is ever run again).

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
     where u ->> 'kind' in ('tx', 'goal', 'bill', 'cat', 'debt', 'leave', 'inv', 'cust')
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

-- Check: should return true
select position('''cust''' in pg_get_functiondef('public.team_save(uuid, jsonb, text[])'::regprocedure)) > 0 as managers_can_save_customers;
