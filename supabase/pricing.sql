-- HantiGo: price by account type.
--   Shakhsi (person)   = $3 / month
--   Shirkad (business) = $7 / month  (includes Shakhsi when one email has both)
-- Adds profiles.plan so the app and the admin page know which price applies.
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.

alter table public.profiles add column if not exists plan text not null default 'person';

-- Existing accounts: Shirkad if they signed up as Shirkad or already use Shirkad.
update public.profiles p set plan = 'business'
 where p.plan <> 'business'
   and (exists (select 1 from auth.users u where u.id = p.id and u.raw_user_meta_data ->> 'mode' = 'business')
     or exists (select 1 from public.user_data d, jsonb_array_elements(d.items) e
                 where d.user_id = p.id and e ->> 'mode' = 'business'));

-- New accounts: plan comes from the type chosen at sign-up.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, is_admin, plan)
  values (new.id, new.email, lower(new.email) = 'asad.moallim@gmail.com',
          case when new.raw_user_meta_data ->> 'mode' = 'business' then 'business' else 'person' end)
  on conflict (id) do nothing;
  return new;
end $$;

-- The app moves a customer to Shirkad when they start using Shirkad (upgrade only).
create or replace function public.set_my_plan(p text) returns void
language sql security definer set search_path = public as $$
  update profiles set plan = 'business' where id = auth.uid() and p = 'business'
$$;

-- The admin can set either plan.
create or replace function public.admin_set_plan(target uuid, p text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  update profiles set plan = case when p = 'business' then 'business' else 'person' end where id = target;
end $$;

revoke execute on function public.set_my_plan(text)          from public, anon;
revoke execute on function public.admin_set_plan(uuid, text) from public, anon;
grant  execute on function public.set_my_plan(text)          to authenticated;
grant  execute on function public.admin_set_plan(uuid, text) to authenticated;
