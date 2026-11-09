-- HantiGo: let a person delete their own account from inside the app
-- (required by Google Play and the App Store).
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  -- remove this person from any company staff lists
  delete from public.team_members
   where lower(member_email) = lower(coalesce(auth.jwt() ->> 'email', ''));
  -- deleting the login also deletes profile, data and own staff list (on delete cascade)
  delete from auth.users where id = auth.uid();
end $$;

revoke execute on function public.delete_my_account() from public, anon;
grant  execute on function public.delete_my_account() to authenticated;
