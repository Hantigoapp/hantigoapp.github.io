-- HantiGo Education V2 academic structure write API.
-- Run after education_v2_rpc.sql. Additive; V1 and first-slice V2 APIs are unchanged.

begin;

create or replace function public.education_v2_department_save(p_owner uuid,p_record jsonb)
returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  rid uuid;
  parent_key uuid;
  dtype text;
  nm text;
  code_value text;
  enabled_value boolean;
begin
  if not public.education_authorized(p_owner,true) then raise exception 'not authorized'; end if;
  parent_key:=nullif(p_record->>'parent_department_id','')::uuid;
  dtype:=lower(btrim(coalesce(p_record->>'department_type','')));
  nm:=btrim(coalesce(p_record->>'name',''));
  code_value:=left(btrim(coalesce(p_record->>'code','')),40);
  enabled_value:=coalesce((p_record->>'enabled')::boolean,true);
  if dtype not in ('faculty','department','training_unit') then raise exception 'invalid department type'; end if;
  if length(nm) not between 1 and 140 then raise exception 'department name required'; end if;
  if parent_key is not null and not exists(
    select 1 from public.education_departments
    where id=parent_key and owner_id=p_owner and enabled
  ) then raise exception 'parent department must belong to this company and be enabled'; end if;
  if dtype='faculty' and parent_key is not null then raise exception 'faculty cannot have a parent department'; end if;
  if dtype='department' and parent_key is not null and not exists(
    select 1 from public.education_departments
    where id=parent_key and owner_id=p_owner and department_type='faculty'
  ) then raise exception 'department parent must be a faculty'; end if;
  if dtype='training_unit' and parent_key is not null and not exists(
    select 1 from public.education_departments
    where id=parent_key and owner_id=p_owner and department_type in ('faculty','department','training_unit')
  ) then raise exception 'invalid training unit parent'; end if;

  rid:=nullif(p_record->>'id','')::uuid;
  if rid is null then rid:=gen_random_uuid(); end if;
  insert into public.education_departments(id,owner_id,parent_department_id,department_type,name,code,enabled,updated_at)
  values(rid,p_owner,parent_key,dtype,nm,code_value,enabled_value,now())
  on conflict(id) do update set
    parent_department_id=excluded.parent_department_id,department_type=excluded.department_type,
    name=excluded.name,code=excluded.code,enabled=excluded.enabled,updated_at=now()
  where education_departments.owner_id=p_owner;
  if not found then raise exception 'department not found'; end if;
  return rid;
end;
$$;

create or replace function public.education_v2_programme_save(p_owner uuid,p_record jsonb)
returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  rid uuid;
  stage_key uuid;
  department_key uuid;
  nm text;
  ptype text;
  duration_value numeric(8,2);
  duration_unit_value text;
  award_value text;
  enabled_value boolean;
begin
  if not public.education_authorized(p_owner,true) then raise exception 'not authorized'; end if;
  stage_key:=nullif(p_record->>'stage_id','')::uuid;
  department_key:=nullif(p_record->>'department_id','')::uuid;
  nm:=btrim(coalesce(p_record->>'name',''));
  ptype:=lower(coalesce(nullif(p_record->>'programme_type',''),'academic'));
  duration_value:=nullif(p_record->>'duration_value','')::numeric;
  duration_unit_value:=lower(coalesce(nullif(p_record->>'duration_unit',''),'year'));
  award_value:=left(btrim(coalesce(p_record->>'award_name','')),120);
  enabled_value:=coalesce((p_record->>'enabled')::boolean,true);
  if stage_key is null or not exists(
    select 1 from public.education_stages where id=stage_key and owner_id=p_owner and enabled
  ) then raise exception 'select an enabled stage belonging to this company'; end if;
  if length(nm) not between 1 and 160 then raise exception 'programme name required'; end if;
  if ptype not in ('academic','vocational','short_course') then raise exception 'invalid programme type'; end if;
  if duration_unit_value not in ('day','week','month','year','semester') then raise exception 'invalid duration unit'; end if;
  if duration_value is not null and duration_value<=0 then raise exception 'duration must be positive'; end if;
  if department_key is not null and not exists(
    select 1 from public.education_departments where id=department_key and owner_id=p_owner and enabled
  ) then raise exception 'department must belong to this company and be enabled'; end if;

  rid:=nullif(p_record->>'id','')::uuid;
  if rid is null then rid:=gen_random_uuid(); end if;
  insert into public.education_programmes(
    id,owner_id,stage_id,department_id,name,programme_type,duration_value,duration_unit,award_name,enabled,updated_at
  ) values(
    rid,p_owner,stage_key,department_key,nm,ptype,duration_value,duration_unit_value,award_value,enabled_value,now()
  )
  on conflict(id) do update set
    stage_id=excluded.stage_id,department_id=excluded.department_id,name=excluded.name,
    programme_type=excluded.programme_type,duration_value=excluded.duration_value,
    duration_unit=excluded.duration_unit,award_name=excluded.award_name,
    enabled=excluded.enabled,updated_at=now()
  where education_programmes.owner_id=p_owner;
  if not found then raise exception 'programme not found'; end if;
  return rid;
end;
$$;

create or replace function public.education_v2_course_save(p_owner uuid,p_record jsonb)
returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  rid uuid;
  stage_key uuid;
  programme_key uuid;
  code_value text;
  nm text;
  credits_value numeric(7,2);
  hours_value numeric(9,2);
  enabled_value boolean;
begin
  if not public.education_authorized(p_owner,true) then raise exception 'not authorized'; end if;
  stage_key:=nullif(p_record->>'stage_id','')::uuid;
  programme_key:=nullif(p_record->>'programme_id','')::uuid;
  code_value:=left(btrim(coalesce(p_record->>'course_code','')),40);
  nm:=btrim(coalesce(p_record->>'name',''));
  credits_value:=nullif(p_record->>'credits','')::numeric;
  hours_value:=nullif(p_record->>'duration_hours','')::numeric;
  enabled_value:=coalesce((p_record->>'enabled')::boolean,true);
  if stage_key is null or not exists(
    select 1 from public.education_stages where id=stage_key and owner_id=p_owner and enabled
  ) then raise exception 'select an enabled stage belonging to this company'; end if;
  if length(nm) not between 1 and 160 then raise exception 'course name required'; end if;
  if credits_value is not null and credits_value<0 then raise exception 'credits cannot be negative'; end if;
  if hours_value is not null and hours_value<0 then raise exception 'duration hours cannot be negative'; end if;
  if programme_key is not null and not exists(
    select 1 from public.education_programmes
    where id=programme_key and owner_id=p_owner and stage_id=stage_key and enabled
  ) then raise exception 'programme must be enabled and belong to the selected stage and company'; end if;

  rid:=nullif(p_record->>'id','')::uuid;
  if rid is null then rid:=gen_random_uuid(); end if;
  insert into public.education_courses(
    id,owner_id,stage_id,programme_id,course_code,name,credits,duration_hours,enabled,updated_at
  ) values(
    rid,p_owner,stage_key,programme_key,code_value,nm,credits_value,hours_value,enabled_value,now()
  )
  on conflict(id) do update set
    stage_id=excluded.stage_id,programme_id=excluded.programme_id,course_code=excluded.course_code,
    name=excluded.name,credits=excluded.credits,duration_hours=excluded.duration_hours,
    enabled=excluded.enabled,updated_at=now()
  where education_courses.owner_id=p_owner;
  if not found then raise exception 'course not found'; end if;
  return rid;
end;
$$;

revoke all on function public.education_v2_department_save(uuid,jsonb) from public,anon;
revoke all on function public.education_v2_programme_save(uuid,jsonb) from public,anon;
revoke all on function public.education_v2_course_save(uuid,jsonb) from public,anon;
grant execute on function public.education_v2_department_save(uuid,jsonb) to authenticated;
grant execute on function public.education_v2_programme_save(uuid,jsonb) to authenticated;
grant execute on function public.education_v2_course_save(uuid,jsonb) to authenticated;

commit;

select p.proname,
       has_function_privilege('anon',p.oid,'execute') as anon_execute,
       has_function_privilege('authenticated',p.oid,'execute') as authenticated_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'education_v2_department_save','education_v2_programme_save','education_v2_course_save'
)
order by p.proname;
