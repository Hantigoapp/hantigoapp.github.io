-- HantiGo: sales list for the admin page (💰 Iibka).
-- Every time a customer pays (admin presses Ansixi / +30 maalmood / +1 sano, or the
-- automatic EVC/WaafiPay payment), one row is saved here. The admin page shows the
-- sales by day and by month and downloads them as Excel, Word or PDF.
-- Same table as supabase/autopay.sql, so the two files work together in any order.
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
alter table public.payments add column if not exists source text;   -- gacanta (admin) | toos (automatic) | hore (before this file)
create index if not exists payments_user_idx on public.payments (user_id, created_at desc);
create index if not exists payments_time_idx on public.payments (created_at desc);

alter table public.payments enable row level security;
drop policy if exists payments_read on public.payments;
create policy payments_read on public.payments
  for select using (user_id = auth.uid() or public.is_admin());

-- Admin saves a sale after approving a payment.
create or replace function public.admin_record_sale(target uuid, amount numeric, days int, method text, ref text, receipt text)
returns uuid language plpgsql security definer set search_path = public as $$
declare pid uuid;
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  if coalesce(amount, 0) <= 0 then return null; end if;
  insert into payments (user_id, email, plan, amount, days, phone, method, status, waafi_ref, receipt_no, receipt_sent, source, done_at)
  select p.id, p.email, coalesce(p.plan, 'person'), round(amount, 2), greatest(coalesce(days, 30), 1), p.phone,
         left(coalesce(nullif(trim(method), ''), 'EVC Plus'), 30), 'approved', nullif(left(trim(coalesce(ref, '')), 60), ''),
         nullif(left(trim(coalesce(receipt, '')), 40), ''), receipt is not null, 'gacanta', now()
    from profiles p where p.id = target
  returning id into pid;
  return pid;
end $$;

-- Admin removes a sale saved by mistake.
create or replace function public.admin_delete_sale(pid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not admin'; end if;
  delete from payments where id = pid;
end $$;

revoke execute on function public.admin_record_sale(uuid, numeric, int, text, text, text) from public, anon;
revoke execute on function public.admin_delete_sale(uuid)                                from public, anon;
grant  execute on function public.admin_record_sale(uuid, numeric, int, text, text, text) to authenticated;
grant  execute on function public.admin_delete_sale(uuid)                                to authenticated;

-- Payments approved before this file existed: one row each (price by plan, date of the request).
insert into public.payments (user_id, email, plan, amount, days, phone, method, status, waafi_ref, source, created_at, done_at)
select p.id, p.email, coalesce(p.plan, 'person'),
       case when coalesce(p.plan, 'person') = 'business' then 7 else 3 end, 30, p.phone,
       case when p.pay_ref ilike '%[WaafiPay]%' then 'WaafiPay' else 'EVC Plus' end, 'approved',
       nullif(left(regexp_replace(coalesce(p.pay_ref, ''), '^(\[[^]]*\]\s*)+', ''), 60), ''),
       'hore', coalesce(p.pay_requested_at, now()), coalesce(p.pay_requested_at, now())
  from public.profiles p
 where p.pay_status = 'ok' and not coalesce(p.is_admin, false)
   and not exists (select 1 from public.payments x where x.user_id = p.id);
