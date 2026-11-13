-- HantiGo: show in admin.html (and on the receipt the admin sends) who each customer is:
-- full name and phone number from the sign-up form, and the company name
-- (sign-up, or later Akoon -> Shirkaddaada), plus when they last signed in
-- ("Galay ugu dambeyn") and when their data was last saved in the app.
-- Read-only: nothing in the tables is changed.
-- Only an admin (profiles.is_admin) can call it; everyone else gets "not admin".
-- Run in Supabase: SQL Editor -> New query -> paste this file -> Run (safe to run again).

-- the list of returned columns changed, so the old version must be removed first
drop function if exists public.admin_customer_info();

create function public.admin_customer_info()
returns table (id uuid, full_name text, phone text, company text,
               last_sign_in_at timestamptz, data_updated_at timestamptz)
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
             nullif(trim(u.raw_user_meta_data ->> 'company'), '')),
           u.last_sign_in_at,
           d.updated_at
      from auth.users u
      left join public.user_data d on d.user_id = u.id;
end $$;

revoke execute on function public.admin_customer_info() from public, anon;
grant  execute on function public.admin_customer_info() to authenticated;
