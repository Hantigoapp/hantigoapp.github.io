-- HantiGo: automatic payment with EVC Plus / WaafiPay (no manual approval).
-- The customer types their EVC Plus or WaafiPay number in the app and taps "Bixi".
-- The Edge Function "pay-auto" asks WaafiPay to charge that number; the customer
-- confirms with their PIN on the phone; when WaafiPay says APPROVED the account opens
-- for 30 days and a PDF receipt is emailed to the customer, with a copy to the admin.
-- The manual way (send money, fill the form, admin presses Ansixi) keeps working.
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.

create table if not exists public.payments (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  email        text,
  plan         text,
  amount       numeric(10,2) not null,
  currency     text not null default 'USD',
  days         int  not null default 30,
  phone        text,
  method       text,                                  -- EVC Plus | WaafiPay
  status       text not null default 'pending',       -- pending | approved | failed | unknown
  waafi_tx     text,
  waafi_ref    text,
  error        text,
  receipt_no   text,
  receipt_sent boolean not null default false,
  created_at   timestamptz not null default now(),
  done_at      timestamptz
);
create index if not exists payments_user_idx on public.payments (user_id, created_at desc);

alter table public.payments enable row level security;
drop policy if exists payments_read on public.payments;
create policy payments_read on public.payments
  for select using (user_id = auth.uid() or public.is_admin());
-- No insert/update/delete policies: only the Edge Function (service role) writes here.

-- Opens the account after WaafiPay approved. Safe to call twice (only the first call adds days).
create or replace function public.autopay_grant(pid uuid) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare pay payments; until timestamptz;
begin
  update payments set status = 'approved', done_at = now()
   where id = pid and status in ('pending', 'unknown')
   returning * into pay;
  if not found then
    select p.paid_until into until from payments x join profiles p on p.id = x.user_id where x.id = pid;
    return until;
  end if;
  update profiles
     set paid_until = greatest(coalesce(paid_until, now()), now()) + make_interval(days => greatest(pay.days, 1)),
         phone      = coalesce(pay.phone, phone),
         pay_ref    = left('[Toos] [' || pay.method || '] ' || coalesce(pay.waafi_tx, ''), 60),
         pay_status = 'ok',
         pay_shot   = null
   where id = pay.user_id
   returning paid_until into until;
  return until;
end $$;

revoke execute on function public.autopay_grant(uuid) from public, anon, authenticated;
grant  execute on function public.autopay_grant(uuid) to service_role;
