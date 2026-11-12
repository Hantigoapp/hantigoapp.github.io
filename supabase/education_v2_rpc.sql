-- HantiGo Education V2 guarded write API, first vertical slice.
-- Run after education_v2.sql. Additive; legacy Education V1 RPCs are unchanged.
-- All writes go through security-definer RPCs and remain company-scoped.

begin;

create or replace function public.education_v2_stage_save(p_owner uuid,p_record jsonb)
returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  rid uuid;
  code text;
  nm text;
  enabled_value boolean;
  order_value integer;
begin
  if not public.education_authorized(p_owner,true) then raise exception 'not authorized'; end if;
  code:=lower(btrim(coalesce(p_record->>'stage_code','')));
  nm:=btrim(coalesce(p_record->>'name',''));
  if code not in ('primary','middle','secondary','university','vocational') then
    raise exception 'invalid education stage';
  end if;
  if length(nm) not between 1 and 120 then raise exception 'stage name required'; end if;
  enabled_value:=coalesce((p_record->>'enabled')::boolean,true);
  order_value:=coalesce(nullif(p_record->>'sort_order','')::integer,0);

  rid:=nullif(p_record->>'id','')::uuid;
  if rid is null then
    select id into rid from public.education_stages
    where owner_id=p_owner and stage_code=code;
  end if;
  rid:=coalesce(rid,gen_random_uuid());

  insert into public.education_stages(id,owner_id,stage_code,name,enabled,sort_order,updated_at)
  values(rid,p_owner,code,nm,enabled_value,order_value,now())
  on conflict(id) do update set
    stage_code=excluded.stage_code,name=excluded.name,enabled=excluded.enabled,
    sort_order=excluded.sort_order,updated_at=now()
  where education_stages.owner_id=p_owner;
  if not found then raise exception 'stage not found'; end if;
  return rid;
end;
$$;

create or replace function public.education_v2_period_save(p_owner uuid,p_record jsonb)
returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  rid uuid;
  parent_id uuid;
  ptype text;
  nm text;
  start_date date;
  end_date date;
  active_value boolean;
begin
  if not public.education_authorized(p_owner,true) then raise exception 'not authorized'; end if;
  ptype:=lower(btrim(coalesce(p_record->>'period_type','')));
  nm:=btrim(coalesce(p_record->>'name',''));
  parent_id:=nullif(p_record->>'parent_period_id','')::uuid;
  start_date:=nullif(p_record->>'starts_on','')::date;
  end_date:=nullif(p_record->>'ends_on','')::date;
  active_value:=coalesce((p_record->>'is_active')::boolean,false);
  if ptype not in ('academic_year','term','semester') then raise exception 'invalid period type'; end if;
  if length(nm) not between 1 and 100 then raise exception 'period name required'; end if;
  if ptype='academic_year' and parent_id is not null then raise exception 'academic year cannot have a parent'; end if;
  if ptype in ('term','semester') then
    if parent_id is null or not exists(
      select 1 from public.education_periods
      where id=parent_id and owner_id=p_owner and period_type='academic_year'
    ) then raise exception 'term or semester must belong to this company academic year'; end if;
  end if;
  if start_date is not null and end_date is not null and end_date<start_date then
    raise exception 'end date cannot be before start date';
  end if;

  rid:=nullif(p_record->>'id','')::uuid;
  if rid is null then
    select id into rid from public.education_periods
    where owner_id=p_owner and period_type=ptype and name=nm;
  end if;
  rid:=coalesce(rid,gen_random_uuid());

  insert into public.education_periods(id,owner_id,parent_period_id,period_type,name,starts_on,ends_on,is_active,updated_at)
  values(rid,p_owner,parent_id,ptype,nm,start_date,end_date,active_value,now())
  on conflict(id) do update set
    parent_period_id=excluded.parent_period_id,period_type=excluded.period_type,name=excluded.name,
    starts_on=excluded.starts_on,ends_on=excluded.ends_on,is_active=excluded.is_active,updated_at=now()
  where education_periods.owner_id=p_owner;
  if not found then raise exception 'period not found'; end if;
  return rid;
end;
$$;

create or replace function public.education_v2_cohort_save(p_owner uuid,p_record jsonb)
returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  rid uuid;
  stage_key uuid;
  period_key uuid;
  programme_key uuid;
  legacy_key uuid;
  nm text;
  status_value text;
  capacity_value integer;
begin
  if not public.education_authorized(p_owner,true) then raise exception 'not authorized'; end if;
  stage_key:=nullif(p_record->>'stage_id','')::uuid;
  period_key:=nullif(p_record->>'period_id','')::uuid;
  programme_key:=nullif(p_record->>'programme_id','')::uuid;
  legacy_key:=nullif(p_record->>'legacy_class_id','')::uuid;
  nm:=btrim(coalesce(p_record->>'name',''));
  status_value:=lower(coalesce(nullif(p_record->>'status',''),'active'));
  capacity_value:=nullif(p_record->>'capacity','')::integer;
  if stage_key is null or not exists(
    select 1 from public.education_stages where id=stage_key and owner_id=p_owner and enabled
  ) then raise exception 'select an enabled stage belonging to this company'; end if;
  if length(nm) not between 1 and 120 then raise exception 'cohort name required'; end if;
  if status_value not in ('planned','active','completed','archived') then raise exception 'invalid cohort status'; end if;
  if capacity_value is not null and capacity_value<=0 then raise exception 'capacity must be positive'; end if;
  if period_key is not null and not exists(
    select 1 from public.education_periods where id=period_key and owner_id=p_owner
  ) then raise exception 'invalid academic period'; end if;
  if programme_key is not null and not exists(
    select 1 from public.education_programmes
    where id=programme_key and owner_id=p_owner and stage_id=stage_key
  ) then raise exception 'programme must belong to the selected stage and company'; end if;
  if legacy_key is not null and not exists(
    select 1 from public.education_classes where id=legacy_key and owner_id=p_owner
  ) then raise exception 'invalid legacy class'; end if;

  rid:=coalesce(nullif(p_record->>'id','')::uuid,gen_random_uuid());
  insert into public.education_cohorts(
    id,owner_id,stage_id,period_id,programme_id,legacy_class_id,name,teacher_name,room,capacity,status,updated_at
  ) values (
    rid,p_owner,stage_key,period_key,programme_key,legacy_key,nm,
    left(coalesce(p_record->>'teacher_name',''),120),
    left(coalesce(p_record->>'room',''),50),capacity_value,status_value,now()
  )
  on conflict(id) do update set
    stage_id=excluded.stage_id,period_id=excluded.period_id,programme_id=excluded.programme_id,
    legacy_class_id=excluded.legacy_class_id,name=excluded.name,teacher_name=excluded.teacher_name,
    room=excluded.room,capacity=excluded.capacity,status=excluded.status,updated_at=now()
  where education_cohorts.owner_id=p_owner;
  if not found then raise exception 'cohort not found'; end if;
  return rid;
end;
$$;

create or replace function public.education_v2_enrolment_transfer(p_owner uuid,p_record jsonb)
returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  student_key uuid;
  cohort_key uuid;
  enrol_date date;
  previous_id uuid;
  previous_date date;
  rid uuid;
begin
  if not public.education_authorized(p_owner,true) then raise exception 'not authorized'; end if;
  student_key:=nullif(p_record->>'student_id','')::uuid;
  cohort_key:=nullif(p_record->>'cohort_id','')::uuid;
  enrol_date:=coalesce(nullif(p_record->>'enrolled_on','')::date,current_date);
  if student_key is null or cohort_key is null then raise exception 'student and cohort are required'; end if;

  -- Lock the company-owned student row so concurrent transfers cannot create two active enrolments.
  perform 1 from public.education_students
  where id=student_key and owner_id=p_owner and status='active'
  for update;
  if not found then raise exception 'active student not found in this company'; end if;
  if not exists(
    select 1 from public.education_cohorts
    where id=cohort_key and owner_id=p_owner and status in ('planned','active')
  ) then raise exception 'select a valid cohort belonging to this company'; end if;

  select id,enrolled_on into previous_id,previous_date
  from public.education_enrolments
  where owner_id=p_owner and student_id=student_key and status='active'
  for update;
  if previous_id is not null then
    if enrol_date<previous_date then raise exception 'new enrolment date cannot precede the current enrolment'; end if;
    if exists(select 1 from public.education_enrolments where id=previous_id and cohort_id=cohort_key) then
      raise exception 'student is already actively enrolled in this cohort';
    end if;
    update public.education_enrolments
    set status='transferred',ended_on=enrol_date,updated_at=now()
    where id=previous_id and owner_id=p_owner;
  end if;

  insert into public.education_enrolments(owner_id,student_id,cohort_id,enrolled_on,status,notes)
  values(p_owner,student_key,cohort_key,enrol_date,'active',left(coalesce(p_record->>'notes',''),500))
  returning id into rid;
  return rid;
end;
$$;

revoke all on function public.education_v2_stage_save(uuid,jsonb) from public,anon;
revoke all on function public.education_v2_period_save(uuid,jsonb) from public,anon;
revoke all on function public.education_v2_cohort_save(uuid,jsonb) from public,anon;
revoke all on function public.education_v2_enrolment_transfer(uuid,jsonb) from public,anon;
grant execute on function public.education_v2_stage_save(uuid,jsonb) to authenticated;
grant execute on function public.education_v2_period_save(uuid,jsonb) to authenticated;
grant execute on function public.education_v2_cohort_save(uuid,jsonb) to authenticated;
grant execute on function public.education_v2_enrolment_transfer(uuid,jsonb) to authenticated;

commit;

-- Read-only verification of the guarded API grants.
select p.proname,
       has_function_privilege('anon',p.oid,'execute') as anon_execute,
       has_function_privilege('authenticated',p.oid,'execute') as authenticated_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'education_v2_stage_save','education_v2_period_save',
  'education_v2_cohort_save','education_v2_enrolment_transfer'
)
order by p.proname;
