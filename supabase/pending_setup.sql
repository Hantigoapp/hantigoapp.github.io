-- HantiGo: SQL-ka weli sugaya (2026-11-13). Hal mar ku orod Supabase -> SQL Editor. Mar kale haddii la orodsiiyo waxba ma jabiyo.
-- Waxa ku jira: sales, autopay, signups, customer_info, start_date, activity (isla faylasha supabase/).

-- ===== sales.sql =====

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

insert into public.payments (user_id, email, plan, amount, days, phone, method, status, waafi_ref, source, created_at, done_at)
select p.id, p.email, coalesce(p.plan, 'person'),
       case when coalesce(p.plan, 'person') = 'business' then 7 else 3 end, 30, p.phone,
       case when p.pay_ref ilike '%[WaafiPay]%' then 'WaafiPay' else 'EVC Plus' end, 'approved',
       nullif(left(regexp_replace(coalesce(p.pay_ref, ''), '^(\[[^]]*\]\s*)+', ''), 60), ''),
       'hore', coalesce(p.pay_requested_at, now()), coalesce(p.pay_requested_at, now())
  from public.profiles p
 where p.pay_status = 'ok' and not coalesce(p.is_admin, false)
   and not exists (select 1 from public.payments x where x.user_id = p.id);

-- ===== autopay.sql =====

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
alter table public.payments add column if not exists source text;   -- toos (automatic) | gacanta (admin), shared with sales.sql
create index if not exists payments_user_idx on public.payments (user_id, created_at desc);

alter table public.payments enable row level security;
drop policy if exists payments_read on public.payments;
create policy payments_read on public.payments
  for select using (user_id = auth.uid() or public.is_admin());

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

-- ===== signups.sql =====

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

-- ===== customer_info.sql =====

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

-- ===== start_date.sql =====

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

-- ===== activity.sql =====

create table if not exists public.activity_log (
  id          bigserial primary key,
  owner_id    uuid not null references auth.users on delete cascade,  -- whose account (person or company owner)
  actor_id    uuid,                                                   -- who made the change
  actor_email text,
  at          timestamptz not null default now(),                     -- when the change was made (phone time, if sane)
  synced_at   timestamptz not null default now(),                     -- when it reached the server
  action      text not null check (action in ('add', 'edit', 'delete', 'bulk')),
  kind        text,                                                   -- tx, debt, bill, goal, inv
  mode        text not null default 'person',                         -- person (Shakhsi) or business (Shirkad)
  item_id     text,
  before      jsonb,                                                  -- the entry before (edit, delete)
  after       jsonb,                                                  -- the entry after (add, edit)
  n           int not null default 1                                  -- bulk: how many entries changed at once
);
create index if not exists activity_log_owner_at on public.activity_log (owner_id, at desc);

alter table public.activity_log enable row level security;
revoke all on table public.activity_log from public, anon, authenticated;
revoke all on sequence public.activity_log_id_seq from public, anon, authenticated;

create or replace function public.log_user_data_changes() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me_id    uuid := auth.uid();
  me_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  ch       jsonb;
  cnt      int;
begin
  select coalesce(jsonb_agg(c), '[]'::jsonb) into ch from (
  select case when o.e is null then 'add' when n.e is null then 'delete' else 'edit' end as action,
         coalesce(n.e, o.e) ->> 'kind' as kind,
         coalesce(coalesce(n.e, o.e) ->> 'mode', 'person') as mode,
         coalesce(n.id, o.id) as item_id,
         o.e - 'u' as before,
         n.e - 'u' as after,
         case when coalesce(n.e ->> 'u', '') ~ '^[0-9]{10,14}$' then (n.e ->> 'u')::bigint end as u
    from (select e ->> 'id' id, e from jsonb_array_elements(
            case when tg_op = 'UPDATE' then coalesce(old.items, '[]'::jsonb) else '[]'::jsonb end) e
           where e ->> 'kind' in ('tx', 'debt', 'bill', 'goal', 'inv')) o
    full join
         (select e ->> 'id' id, e from jsonb_array_elements(coalesce(new.items, '[]'::jsonb)) e
           where e ->> 'kind' in ('tx', 'debt', 'bill', 'goal', 'inv')) n
      on n.id = o.id
   where (o.e is null or n.e is null or (o.e - 'u') is distinct from (n.e - 'u'))
     and not ((o.e is null or n.e is null) and coalesce(n.e, o.e) ->> 'kind' = 'bill'
              and coalesce(coalesce(n.e, o.e) ->> 'amount', '0') in ('0', '', '0.0'))
  ) c;

  cnt := jsonb_array_length(ch);
  if cnt = 0 then return new; end if;

  if cnt > 100 then
    insert into activity_log (owner_id, actor_id, actor_email, action, mode, n)
    select new.user_id, me_id, nullif(me_email, ''), 'bulk', mode, count(*)
      from jsonb_to_recordset(ch) as x(mode text) group by mode;
  else
    insert into activity_log (owner_id, actor_id, actor_email, at, action, kind, mode, item_id, before, after)
    select new.user_id, me_id, nullif(me_email, ''),
           case when action <> 'delete' and u is not null
                     and to_timestamp(u / 1000.0) between now() - interval '60 days' and now() + interval '5 minutes'
                then to_timestamp(u / 1000.0) else now() end,
           action, kind, mode, item_id, before, after
      from jsonb_to_recordset(ch) as x(action text, kind text, mode text, item_id text, before jsonb, after jsonb, u bigint);
  end if;
  return new;
exception when others then
  raise warning 'activity log skipped: %', sqlerrm;
  return new;
end $$;
revoke all on function public.log_user_data_changes() from public, anon, authenticated;

drop trigger if exists user_data_activity on public.user_data;
create trigger user_data_activity
  after insert or update of items on public.user_data
  for each row execute function public.log_user_data_changes();

create or replace function public.activity_list(owner uuid default null, since timestamptz default null,
                                                upto timestamptz default null, lim int default 500)
returns table (id bigint, at timestamptz, actor_email text, action text, kind text, mode text,
               item_id text, before jsonb, after jsonb, n int)
language plpgsql stable security definer set search_path = public as $$
declare o uuid := coalesce(owner, auth.uid()); r text; me text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if o <> auth.uid() then
    r := public.team_role(o);
    if r is null then raise exception 'not a member'; end if;
  end if;
  return query
    select a.id, a.at, a.actor_email, a.action, a.kind, a.mode, a.item_id, a.before, a.after, a.n
      from activity_log a
     where a.owner_id = o
       and (since is null or a.at >= since)
       and (upto is null or a.at < upto)
       and (o = auth.uid()
            or (a.mode = 'business' and (r = 'manager' or lower(coalesce(a.actor_email, '')) = me)))
     order by a.at desc, a.id desc
     limit least(greatest(coalesce(lim, 500), 1), 2000);
end $$;
revoke all on function public.activity_list(uuid, timestamptz, timestamptz, int) from public, anon;
grant execute on function public.activity_list(uuid, timestamptz, timestamptz, int) to authenticated;

select (select relrowsecurity from pg_class where oid = 'public.activity_log'::regclass) as rls_on,
       (select count(*) from pg_trigger where tgname = 'user_data_activity') as trigger_on;

-- ===== hubin: dhammaan waa inay noqdaan true =====
select
  to_regclass('public.payments') is not null                                   as payments_ok,
  exists(select 1 from pg_proc where proname='autopay_grant')                  as autopay_ok,
  exists(select 1 from pg_proc where proname='admin_signups')                  as signups_ok,
  exists(select 1 from pg_proc where proname='admin_customer_info')            as customer_info_ok,
  exists(select 1 from pg_proc where proname='admin_start_dates')              as start_date_ok,
  exists(select 1 from pg_trigger where tgname='user_data_activity')           as activity_ok;
