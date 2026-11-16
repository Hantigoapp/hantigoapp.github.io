-- HantiGo: receipt numbers that count up each day: HG-261116-001, HG-261116-002, ...
-- The day follows Somalia time (Africa/Mogadishu) and starts again at 001 every day.
-- The number is made inside the database in one step, so two receipts can never get
-- the same number, even when the admin and an automatic payment send one at the same time.
-- Used by admin.html (Ansixi / +30 / +1 sano) and the pay-auto Edge Function.
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.

create table if not exists public.receipt_counters (
  day date primary key,
  n   int  not null default 0
);
alter table public.receipt_counters enable row level security;   -- no policies: only the function below touches it

create or replace function public.next_receipt_no() returns text
language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'Africa/Mogadishu')::date; k int;
begin
  if not (public.is_admin() or coalesce(auth.role(), '') = 'service_role') then raise exception 'not admin'; end if;
  insert into receipt_counters as c (day, n) values (d, 1)
    on conflict (day) do update set n = c.n + 1
  returning n into k;
  return 'HG-' || to_char(d, 'YYMMDD') || '-' || case when k < 1000 then lpad(k::text, 3, '0') else k::text end;
end $$;

revoke execute on function public.next_receipt_no() from public, anon;
grant  execute on function public.next_receipt_no() to authenticated, service_role;

-- Check: select public.next_receipt_no();  (as admin in the app; in the SQL Editor it says 'not admin', that is fine)
