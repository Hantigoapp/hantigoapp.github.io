-- HantiGo: let staff save leave requests and sick reports (kind 'leave') into the company account.
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.
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
revoke execute on function public.team_save(uuid, jsonb, text[]) from public, anon;
grant  execute on function public.team_save(uuid, jsonb, text[]) to authenticated;
