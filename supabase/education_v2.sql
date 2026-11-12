-- HantiGo Education V2 foundation.
-- Additive only. Run AFTER education.sql. Does not replace legacy tables or RPCs.
-- Existing classes/students/payments remain intact; legacy class membership is copied
-- into a historical enrolment linked to an explicitly unclassified stage.

begin;

-- 1. A company may enable any combination of education stages under one owner account.
create table if not exists public.education_stages (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  stage_code text not null check (stage_code in ('primary','middle','secondary','university','vocational','unclassified')),
  name text not null check (length(btrim(name)) between 1 and 120),
  enabled boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,id),
  unique(owner_id,stage_code)
);

-- 2. Academic calendar: academic years and terms/semesters.
create table if not exists public.education_periods (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  parent_period_id uuid,
  period_type text not null check (period_type in ('academic_year','term','semester')),
  name text not null check (length(btrim(name)) between 1 and 100),
  starts_on date,
  ends_on date,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,id),
  foreign key(owner_id,parent_period_id) references public.education_periods(owner_id,id) on delete restrict,
  check (starts_on is null or ends_on is null or ends_on >= starts_on),
  check ((period_type='academic_year' and parent_period_id is null) or
         (period_type in ('term','semester') and parent_period_id is not null))
);

-- 3. University / vocational organization structure.
create table if not exists public.education_departments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  parent_department_id uuid,
  department_type text not null check (department_type in ('faculty','department','training_unit')),
  name text not null check (length(btrim(name)) between 1 and 140),
  code text not null default '',
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,id),
  foreign key(owner_id,parent_department_id) references public.education_departments(owner_id,id) on delete restrict
);

create table if not exists public.education_programmes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  stage_id uuid not null,
  department_id uuid,
  name text not null check (length(btrim(name)) between 1 and 160),
  programme_type text not null default 'academic' check (programme_type in ('academic','vocational','short_course')),
  duration_value numeric(8,2),
  duration_unit text not null default 'year' check (duration_unit in ('day','week','month','year','semester')),
  award_name text not null default '',
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,id),
  foreign key(owner_id,stage_id) references public.education_stages(owner_id,id) on delete restrict,
  foreign key(owner_id,department_id) references public.education_departments(owner_id,id) on delete restrict,
  check (duration_value is null or duration_value > 0)
);

-- 4. Subjects / university courses / vocational units.
create table if not exists public.education_courses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  stage_id uuid not null,
  programme_id uuid,
  course_code text not null default '',
  name text not null check (length(btrim(name)) between 1 and 160),
  credits numeric(7,2),
  duration_hours numeric(9,2),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,id),
  foreign key(owner_id,stage_id) references public.education_stages(owner_id,id) on delete restrict,
  foreign key(owner_id,programme_id) references public.education_programmes(owner_id,id) on delete restrict,
  check (credits is null or credits >= 0),
  check (duration_hours is null or duration_hours >= 0)
);

-- 5. Classes, groups and cohorts. legacy_class_id preserves a direct bridge to V1.
create table if not exists public.education_cohorts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  stage_id uuid not null,
  period_id uuid,
  programme_id uuid,
  legacy_class_id uuid,
  name text not null check (length(btrim(name)) between 1 and 120),
  teacher_name text not null default '',
  room text not null default '',
  capacity integer,
  status text not null default 'active' check (status in ('planned','active','completed','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,id),
  foreign key(owner_id,stage_id) references public.education_stages(owner_id,id) on delete restrict,
  foreign key(owner_id,period_id) references public.education_periods(owner_id,id) on delete restrict,
  foreign key(owner_id,programme_id) references public.education_programmes(owner_id,id) on delete restrict,
  foreign key(owner_id,legacy_class_id) references public.education_classes(owner_id,id) on delete restrict,
  check (capacity is null or capacity > 0)
);

-- 6. Enrolment history. A student may have many past enrolments, but one active at a time.
create table if not exists public.education_enrolments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  student_id uuid not null,
  cohort_id uuid not null,
  enrolled_on date not null default current_date,
  ended_on date,
  status text not null default 'active' check (status in ('active','completed','transferred','withdrawn')),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,id),
  foreign key(owner_id,student_id) references public.education_students(owner_id,id) on delete restrict,
  foreign key(owner_id,cohort_id) references public.education_cohorts(owner_id,id) on delete restrict,
  check (ended_on is null or ended_on >= enrolled_on)
);
create unique index if not exists education_one_active_enrolment_per_student
  on public.education_enrolments(owner_id,student_id) where status='active';

-- 7. Attendance, assessment and results.
create table if not exists public.education_attendance (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  enrolment_id uuid not null,
  attendance_date date not null,
  status text not null check (status in ('present','absent','late','excused')),
  note text not null default '',
  recorded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(owner_id,id),
  foreign key(owner_id,enrolment_id) references public.education_enrolments(owner_id,id) on delete restrict,
  unique(owner_id,enrolment_id,attendance_date)
);

create table if not exists public.education_assessments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  cohort_id uuid not null,
  course_id uuid,
  name text not null check (length(btrim(name)) between 1 and 140),
  assessment_type text not null default 'exam' check (assessment_type in ('exam','quiz','assignment','practical','project','other')),
  held_on date,
  max_score numeric(10,2) not null check (max_score > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,id),
  foreign key(owner_id,cohort_id) references public.education_cohorts(owner_id,id) on delete restrict,
  foreign key(owner_id,course_id) references public.education_courses(owner_id,id) on delete restrict
);

create table if not exists public.education_results (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  assessment_id uuid not null,
  enrolment_id uuid not null,
  score numeric(10,2) not null check (score >= 0),
  grade text not null default '',
  remarks text not null default '',
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,id),
  foreign key(owner_id,assessment_id) references public.education_assessments(owner_id,id) on delete restrict,
  foreign key(owner_id,enrolment_id) references public.education_enrolments(owner_id,id) on delete restrict,
  unique(owner_id,assessment_id,enrolment_id)
);

-- 8. Fee obligations are separate from payments; V1 payment history is retained.
create table if not exists public.education_fee_obligations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  student_id uuid not null,
  enrolment_id uuid,
  description text not null check (length(btrim(description)) between 1 and 180),
  amount numeric(14,2) not null check (amount > 0),
  due_on date,
  status text not null default 'open' check (status in ('open','part_paid','paid','waived','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id,id),
  foreign key(owner_id,student_id) references public.education_students(owner_id,id) on delete restrict,
  foreign key(owner_id,enrolment_id) references public.education_enrolments(owner_id,id) on delete restrict
);

create table if not exists public.education_certificates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  student_id uuid not null,
  enrolment_id uuid,
  certificate_no text not null,
  title text not null check (length(btrim(title)) between 1 and 180),
  issued_on date not null default current_date,
  award_result text not null default '',
  created_at timestamptz not null default now(),
  unique(owner_id,id),
  unique(owner_id,certificate_no),
  foreign key(owner_id,student_id) references public.education_students(owner_id,id) on delete restrict,
  foreign key(owner_id,enrolment_id) references public.education_enrolments(owner_id,id) on delete restrict
);

-- 9. Safe legacy bridge: do not guess whether old classes were primary/secondary/etc.
insert into public.education_stages(owner_id,stage_code,name,enabled,sort_order)
select distinct c.owner_id,'unclassified','Heer aan weli la kala saarin',true,0
from public.education_classes c
on conflict(owner_id,stage_code) do nothing;

insert into public.education_periods(owner_id,period_type,name,is_active)
select distinct c.owner_id,'academic_year',left(btrim(c.academic_year),100),false
from public.education_classes c
where length(btrim(c.academic_year))>0
on conflict do nothing;

insert into public.education_cohorts(owner_id,stage_id,period_id,legacy_class_id,name,teacher_name,room,status)
select c.owner_id,s.id,
       (select p.id from public.education_periods p
         where p.owner_id=c.owner_id and p.period_type='academic_year'
           and p.name=left(btrim(c.academic_year),100) order by p.created_at limit 1),
       c.id,c.name,c.teacher_name,c.room,'active'
from public.education_classes c
join public.education_stages s on s.owner_id=c.owner_id and s.stage_code='unclassified'
on conflict do nothing;

insert into public.education_enrolments(owner_id,student_id,cohort_id,enrolled_on,status,notes)
select s.owner_id,s.id,g.id,s.enrolled_on,
       case when s.status='inactive' then 'withdrawn' else 'active' end,
       'Waxaa si otomaatig ah looga soo guuriyey diiwaankii Education V1; heerka waxbarasho wali lama kala saarin.'
from public.education_students s
join public.education_cohorts g on g.owner_id=s.owner_id and g.legacy_class_id=s.class_id
where s.class_id is not null
on conflict do nothing;

-- 10. Company-scoped indexes and strict client access.
create index if not exists education_periods_owner_parent_idx on public.education_periods(owner_id,parent_period_id);
create index if not exists education_programmes_owner_stage_idx on public.education_programmes(owner_id,stage_id);
create index if not exists education_courses_owner_programme_idx on public.education_courses(owner_id,programme_id);
create index if not exists education_cohorts_owner_stage_period_idx on public.education_cohorts(owner_id,stage_id,period_id);
create index if not exists education_enrolments_owner_student_idx on public.education_enrolments(owner_id,student_id,enrolled_on desc);
create index if not exists education_attendance_owner_date_idx on public.education_attendance(owner_id,attendance_date desc);
create index if not exists education_results_owner_assessment_idx on public.education_results(owner_id,assessment_id);
create index if not exists education_fee_obligations_owner_student_idx on public.education_fee_obligations(owner_id,student_id,due_on);

do $$
declare t text;
begin
  foreach t in array array[
    'education_stages','education_periods','education_departments','education_programmes',
    'education_courses','education_cohorts','education_enrolments','education_attendance',
    'education_assessments','education_results','education_fee_obligations','education_certificates'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from anon, authenticated',t);
  end loop;
end $$;

-- Snapshot only; V2 writes will be added through separately reviewed guarded RPCs.
create or replace function public.education_v2_get(p_owner uuid)
returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare result jsonb;
begin
  if not public.education_authorized(p_owner,false) then
    raise exception 'not authorized or Education module disabled';
  end if;
  select jsonb_build_object(
    'stages',coalesce((select jsonb_agg(to_jsonb(x) order by x.sort_order,x.name) from public.education_stages x where x.owner_id=p_owner),'[]'::jsonb),
    'periods',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_on nulls last,x.name) from public.education_periods x where x.owner_id=p_owner),'[]'::jsonb),
    'departments',coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from public.education_departments x where x.owner_id=p_owner),'[]'::jsonb),
    'programmes',coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from public.education_programmes x where x.owner_id=p_owner),'[]'::jsonb),
    'courses',coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from public.education_courses x where x.owner_id=p_owner),'[]'::jsonb),
    'cohorts',coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from public.education_cohorts x where x.owner_id=p_owner),'[]'::jsonb),
    'enrolments',coalesce((select jsonb_agg(to_jsonb(x) order by x.enrolled_on desc) from public.education_enrolments x where x.owner_id=p_owner),'[]'::jsonb),
    'attendance',coalesce((select jsonb_agg(to_jsonb(x) order by x.attendance_date desc) from public.education_attendance x where x.owner_id=p_owner),'[]'::jsonb),
    'assessments',coalesce((select jsonb_agg(to_jsonb(x) order by x.held_on desc nulls last) from public.education_assessments x where x.owner_id=p_owner),'[]'::jsonb),
    'results',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.education_results x where x.owner_id=p_owner),'[]'::jsonb),
    'fee_obligations',coalesce((select jsonb_agg(to_jsonb(x) order by x.due_on nulls last) from public.education_fee_obligations x where x.owner_id=p_owner),'[]'::jsonb),
    'certificates',coalesce((select jsonb_agg(to_jsonb(x) order by x.issued_on desc) from public.education_certificates x where x.owner_id=p_owner),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.education_v2_get(uuid) from public,anon;
grant execute on function public.education_v2_get(uuid) to authenticated;

commit;

-- Read-only verification queries. Every V2 table should show RLS enabled;
-- anon/authenticated direct SELECT must be false.
select c.relname,c.relrowsecurity
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname like 'education_%'
order by c.relname;

select has_table_privilege('anon','public.education_stages','select') as anon_select,
       has_table_privilege('authenticated','public.education_stages','select') as authenticated_select,
       has_function_privilege('anon','public.education_v2_get(uuid)','execute') as anon_rpc,
       has_function_privilege('authenticated','public.education_v2_get(uuid)','execute') as authenticated_rpc;
