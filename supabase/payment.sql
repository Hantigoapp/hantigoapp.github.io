-- HantiGo: easier EVC payment check.
-- The customer sends their EVC number, the EVC transaction number and (optional)
-- a screenshot of the EVC message. The admin page shows it as a request with
-- "Ansixi" (open 30 days) and "Diid" (reject).
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.

alter table public.profiles add column if not exists pay_ref          text;
alter table public.profiles add column if not exists pay_shot         text;
alter table public.profiles add column if not exists pay_status       text;        -- pending | ok | no
alter table public.profiles add column if not exists pay_requested_at timestamptz;

-- Customer sends a payment request (only for their own account).
create or replace function public.request_payment(p text, ref text, shot text) returns void
language sql security definer set search_path = public as $$
  update profiles
     set phone            = left(trim(p), 20),
         pay_ref          = nullif(left(trim(coalesce(ref, '')), 60), ''),
         pay_shot         = case when shot like 'data:image/%' and length(shot) <= 400000 then shot else null end,
         pay_status       = 'pending',
         pay_requested_at = now()
   where id = auth.uid()
$$;

-- Admin approves (adds days) or rejects a request.
create or replace function public.admin_pay_decide(target uuid, approve boolean, days int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'not admin';
  end if;
  if approve then
    update profiles
       set paid_until = greatest(coalesce(paid_until, now()), now()) + make_interval(days => greatest(days, 1)),
           pay_status = 'ok',
           pay_shot   = null
     where id = target;
  else
    update profiles set pay_status = 'no' where id = target;
  end if;
end $$;

revoke execute on function public.request_payment(text, text, text)     from public, anon;
revoke execute on function public.admin_pay_decide(uuid, boolean, int)  from public, anon;
grant  execute on function public.request_payment(text, text, text)     to authenticated;
grant  execute on function public.admin_pay_decide(uuid, boolean, int)  to authenticated;
