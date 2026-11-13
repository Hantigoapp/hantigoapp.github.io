-- HantiGo: show in admin.html (and on the receipt the admin sends) who each customer is:
-- full name and phone number from the sign-up form, and the company name
-- (sign-up, or later Akoon -> Shirkaddaada). Read-only: nothing in the tables is changed.
-- Only an admin (profiles.is_admin) can call it; everyone else gets "not admin".
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.

create or replace function public.admin_customer_info()
returns table (id uuid, full_name text, phone text, company text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  return query
    select u.id,
           nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
           nullif(trim(u.raw_user_meta_data ->> 'phone'), ''),
           coalesce(
             (select nullif(trim(x ->> 'coName'), '')
                from jsonb_array_elements(coalesce(d.items, '[]'::jsonb)) x
               where x ->> 'kind' = 'settings' and nullif(trim(x ->> 'coName'), '') is not null
               limit 1),
             nullif(trim(u.raw_user_meta_data ->> 'company'), ''))
      from auth.users u
      left join public.user_data d on d.user_id = u.id;
end $$;

revoke execute on function public.admin_customer_info() from public, anon;
grant  execute on function public.admin_customer_info() to authenticated;
