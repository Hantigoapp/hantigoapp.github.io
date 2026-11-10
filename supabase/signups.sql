-- HantiGo: extra details for the "Macaamiil cusub" (new sign-ups) box in admin.html.
-- Gives the admin, and only the admin, each customer's company name, last sign-in
-- and whether they have started using the app. Nothing is changed in the tables.
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.

create or replace function public.admin_signups()
returns table (id uuid, company text, last_seen timestamptz, items int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  return query
    select u.id,
           nullif(trim(u.raw_user_meta_data ->> 'company'), ''),
           u.last_sign_in_at,
           coalesce(jsonb_array_length(d.items), 0)
      from auth.users u
      left join public.user_data d on d.user_id = u.id;
end $$;

revoke execute on function public.admin_signups() from public, anon;
grant  execute on function public.admin_signups() to authenticated;
