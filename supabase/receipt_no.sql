-- HantiGo: receipt numbers that keep counting: HG-261116-001, HG-261116-002, HG-261117-003, ...
-- The date part is the day the receipt was made (Somalia time, Africa/Mogadishu).
-- The last part NEVER starts again: it carries on from the last receipt, day after day.
-- The number is made inside the database in one step (a sequence), so two receipts can never
-- get the same number, even when the admin and an automatic payment send one at the same time.
-- Used by admin.html (Ansixi / +30 / +1 sano) and the pay-auto Edge Function.
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run. Safe to run again.

create sequence if not exists public.receipt_seq start 1;

-- If an earlier version of this file (counting per day) was run, carry on after those numbers.
do $$ begin
  if to_regclass('public.receipt_counters') is not null then
    perform setval('public.receipt_seq', s, true)
      from (select coalesce(sum(n), 0)::bigint as s from public.receipt_counters) t
     where s > 0 and s > (select case when is_called then last_value else 0 end from public.receipt_seq);
    drop table public.receipt_counters;
  end if;
end $$;

create or replace function public.next_receipt_no() returns text
language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'Africa/Mogadishu')::date; k bigint;
begin
  if not (public.is_admin() or coalesce(auth.role(), '') = 'service_role') then raise exception 'not admin'; end if;
  k := nextval('public.receipt_seq');
  return 'HG-' || to_char(d, 'YYMMDD') || '-' || case when k < 1000 then lpad(k::text, 3, '0') else k::text end;
end $$;

revoke all on sequence public.receipt_seq from public, anon, authenticated;
revoke execute on function public.next_receipt_no() from public, anon;
grant  execute on function public.next_receipt_no() to authenticated, service_role;
