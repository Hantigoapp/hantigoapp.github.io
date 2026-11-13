-- HantiGo: show in admin.html the "registration start date" each customer chose
-- on the sign-up form (Shakhsi and Shirkad). The app saves it in the sign-up
-- details (user metadata "start_date"); this only READS it, for the admin only.
-- It does not change the trial or paid dates. Nothing in the tables is changed.
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.

create or replace function public.admin_start_dates()
returns table (id uuid, start_date text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  return query
    select u.id, nullif(trim(u.raw_user_meta_data ->> 'start_date'), '')
      from auth.users u;
end $$;

revoke execute on function public.admin_start_dates() from public, anon;
grant  execute on function public.admin_start_dates() to authenticated;
