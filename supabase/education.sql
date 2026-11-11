-- HantiGo Education module: classes, students and fee payments.
-- Run after business_modules.sql. Additive; existing Core data is untouched.

create table if not exists public.education_classes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 100),
  academic_year text not null default '',
  teacher_name text not null default '',
  room text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, id)
);

create table if not exists public.education_students (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  student_no text not null check (length(btrim(student_no)) between 1 and 40),
  full_name text not null check (length(btrim(full_name)) between 1 and 140),
  guardian_name text not null default '',
  guardian_phone text not null default '',
  class_id uuid,
  enrolled_on date not null default current_date,
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, id),
  unique (owner_id, student_no),
  constraint education_students_class_fk
    foreign key (owner_id, class_id) references public.education_classes(owner_id, id) on delete set null
);

create table if not exists public.education_fee_payments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  student_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  paid_on date not null default current_date,
  method text not null default '',
  note text not null default '',
  created_at timestamptz not null default now(),
  constraint education_fee_student_fk
    foreign key (owner_id, student_id) references public.education_students(owner_id, id) on delete cascade
);

create index if not exists education_students_owner_class_idx on public.education_students(owner_id,class_id);
create index if not exists education_payments_owner_date_idx on public.education_fee_payments(owner_id,paid_on desc);
create index if not exists education_payments_student_idx on public.education_fee_payments(owner_id,student_id,paid_on desc);

alter table public.education_classes enable row level security;
alter table public.education_students enable row level security;
alter table public.education_fee_payments enable row level security;
revoke all on public.education_classes,public.education_students,public.education_fee_payments from anon,authenticated;

create or replace function public.education_authorized(p_owner uuid,p_write boolean default false)
returns boolean language plpgsql stable security definer set search_path=public,pg_temp as $$
declare r text;
begin
  if auth.uid() is null or p_owner is null then return false; end if;
  if auth.uid()=p_owner then
    if not public.has_access() then return false; end if;
  else
    r:=public.team_role(p_owner);
    if r is null or not public.owner_active(p_owner) then return false; end if;
    if p_write and r<>'manager' then return false; end if;
  end if;
  return exists(select 1 from public.company_modules
    where owner_id=p_owner and module_id='education' and enabled);
end;
$$;

create or replace function public.education_get(p_owner uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
  if not public.education_authorized(p_owner,false) then raise exception 'not authorized or Education module disabled'; end if;
  select jsonb_build_object(
    'classes',coalesce((select jsonb_agg(to_jsonb(c) order by c.name) from public.education_classes c where c.owner_id=p_owner),'[]'::jsonb),
    'students',coalesce((select jsonb_agg(to_jsonb(s) order by s.full_name) from public.education_students s where s.owner_id=p_owner),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(to_jsonb(p) order by p.paid_on desc,p.created_at desc) from public.education_fee_payments p where p.owner_id=p_owner),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

create or replace function public.education_class_save(p_owner uuid,p_record jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare rid uuid; nm text;
begin
  if not public.education_authorized(p_owner,true) then raise exception 'not authorized'; end if;
  nm:=btrim(coalesce(p_record->>'name',''));
  if length(nm) not between 1 and 100 then raise exception 'class name required'; end if;
  rid:=coalesce(nullif(p_record->>'id','')::uuid,gen_random_uuid());
  insert into public.education_classes(id,owner_id,name,academic_year,teacher_name,room,updated_at)
  values(rid,p_owner,nm,left(coalesce(p_record->>'academic_year',''),30),left(coalesce(p_record->>'teacher_name',''),120),left(coalesce(p_record->>'room',''),50),now())
  on conflict(id) do update set name=excluded.name,academic_year=excluded.academic_year,teacher_name=excluded.teacher_name,room=excluded.room,updated_at=now()
  where education_classes.owner_id=p_owner;
  if not found then raise exception 'class not found'; end if;
  return rid;
end;
$$;

create or replace function public.education_student_save(p_owner uuid,p_record jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare rid uuid; sid text; nm text; cid uuid;
begin
  if not public.education_authorized(p_owner,true) then raise exception 'not authorized'; end if;
  sid:=btrim(coalesce(p_record->>'student_no','')); nm:=btrim(coalesce(p_record->>'full_name',''));
  if length(sid) not between 1 and 40 or length(nm) not between 1 and 140 then raise exception 'student number and full name required'; end if;
  cid:=nullif(p_record->>'class_id','')::uuid;
  if cid is not null and not exists(select 1 from public.education_classes where id=cid and owner_id=p_owner) then raise exception 'invalid class'; end if;
  rid:=coalesce(nullif(p_record->>'id','')::uuid,gen_random_uuid());
  insert into public.education_students(id,owner_id,student_no,full_name,guardian_name,guardian_phone,class_id,enrolled_on,status,updated_at)
  values(rid,p_owner,sid,nm,left(coalesce(p_record->>'guardian_name',''),120),left(coalesce(p_record->>'guardian_phone',''),40),cid,coalesce(nullif(p_record->>'enrolled_on','')::date,current_date),case when p_record->>'status'='inactive' then 'inactive' else 'active' end,now())
  on conflict(id) do update set student_no=excluded.student_no,full_name=excluded.full_name,guardian_name=excluded.guardian_name,guardian_phone=excluded.guardian_phone,class_id=excluded.class_id,enrolled_on=excluded.enrolled_on,status=excluded.status,updated_at=now()
  where education_students.owner_id=p_owner;
  if not found then raise exception 'student not found'; end if;
  return rid;
end;
$$;

create or replace function public.education_payment_add(p_owner uuid,p_record jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare rid uuid; sid uuid; amt numeric;
begin
  if not public.education_authorized(p_owner,true) then raise exception 'not authorized'; end if;
  sid:=nullif(p_record->>'student_id','')::uuid; amt:=nullif(p_record->>'amount','')::numeric;
  if sid is null or not exists(select 1 from public.education_students where id=sid and owner_id=p_owner) then raise exception 'select a valid student'; end if;
  if amt is null or amt<=0 then raise exception 'amount must be positive'; end if;
  insert into public.education_fee_payments(owner_id,student_id,amount,paid_on,method,note)
  values(p_owner,sid,amt,coalesce(nullif(p_record->>'paid_on','')::date,current_date),left(coalesce(p_record->>'method',''),40),left(coalesce(p_record->>'note',''),250))
  returning id into rid;
  return rid;
end;
$$;

create or replace function public.education_record_delete(p_owner uuid,p_kind text,p_id uuid)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer;
begin
  if not public.education_authorized(p_owner,true) then raise exception 'not authorized'; end if;
  if p_kind='class' then delete from public.education_classes where id=p_id and owner_id=p_owner;
  elsif p_kind='student' then delete from public.education_students where id=p_id and owner_id=p_owner;
  elsif p_kind='payment' then delete from public.education_fee_payments where id=p_id and owner_id=p_owner;
  else raise exception 'invalid record type'; end if;
  get diagnostics n=row_count;
  return n>0;
end;
$$;

revoke all on function public.education_authorized(uuid,boolean) from public,anon;
revoke all on function public.education_get(uuid) from public,anon;
revoke all on function public.education_class_save(uuid,jsonb) from public,anon;
revoke all on function public.education_student_save(uuid,jsonb) from public,anon;
revoke all on function public.education_payment_add(uuid,jsonb) from public,anon;
revoke all on function public.education_record_delete(uuid,text,uuid) from public,anon;
grant execute on function public.education_get(uuid) to authenticated;
grant execute on function public.education_class_save(uuid,jsonb) to authenticated;
grant execute on function public.education_student_save(uuid,jsonb) to authenticated;
grant execute on function public.education_payment_add(uuid,jsonb) to authenticated;
grant execute on function public.education_record_delete(uuid,text,uuid) to authenticated;

-- Verification: all Education tables must have RLS and no direct client table grants.
select relname,relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and relname in ('education_classes','education_students','education_fee_payments') order by relname;
select has_table_privilege('anon','public.education_students','select') anon_select,
       has_table_privilege('authenticated','public.education_students','select') client_select;
