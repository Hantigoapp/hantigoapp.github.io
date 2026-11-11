-- HantiGo: Taariikhda isbeddelka (activity history)
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run.
-- Safe to run again. Needs schema.sql, team.sql and roles.sql first.
--
-- What it does: every time an account's entries are saved (website, installed app,
-- APK, owner, manager or staff, online or after offline sync), the database itself
-- compares the old and new entries and writes one row per change:
-- who (email), when, what (the entry before and after), and whether it was added,
-- corrected or deleted. Nobody can write or change these rows from the app.
-- History starts from the moment this file is run.

-- 1. Table -----------------------------------------------------------------------
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

-- 2. Trigger: compare old and new entries on every save ---------------------------
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
     -- empty expense templates the app creates by itself (amount 0) are not history
     and not ((o.e is null or n.e is null) and coalesce(n.e, o.e) ->> 'kind' = 'bill'
              and coalesce(coalesce(n.e, o.e) ->> 'amount', '0') in ('0', '', '0.0'))
  ) c;

  cnt := jsonb_array_length(ch);
  if cnt = 0 then return new; end if;

  if cnt > 100 then
    -- a backup restore or first upload: one summary row per mode instead of hundreds
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
  -- the history must never stop a save: if logging fails, the entry is still saved
  raise warning 'activity log skipped: %', sqlerrm;
  return new;
end $$;
revoke all on function public.log_user_data_changes() from public, anon, authenticated;

drop trigger if exists user_data_activity on public.user_data;
create trigger user_data_activity
  after insert or update of items on public.user_data
  for each row execute function public.log_user_data_changes();

-- 3. Reading the history ------------------------------------------------------------
-- owner (own account): everything, Shakhsi and Shirkad
-- company manager: all Shirkad changes of that company
-- staff: only their own Shirkad changes
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

-- 4. Check: should say rls_on = true and trigger_on = 1
select (select relrowsecurity from pg_class where oid = 'public.activity_log'::regclass) as rls_on,
       (select count(*) from pg_trigger where tgname = 'user_data_activity') as trigger_on;
