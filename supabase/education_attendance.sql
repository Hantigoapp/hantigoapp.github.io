-- HantiGo Education: attendance table
-- Run once in Supabase Dashboard -> SQL Editor.
-- Adds attendance records without changing existing student or class data.

create table if not exists public.education_attendance (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  class_id uuid not null references public.education_classes(id) on delete restrict,
  student_id uuid not null references public.education_students(id) on delete restrict,
  attendance_date date not null default current_date,
  status text not null check (status in ('present', 'absent', 'excused')),
  marked_by uuid not null,
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint education_attendance_one_per_student_per_day
    unique (student_id, attendance_date)
);

create index if not exists education_attendance_class_date_idx
  on public.education_attendance (class_id, attendance_date);

create index if not exists education_attendance_owner_date_idx
  on public.education_attendance (owner_id, attendance_date);

alter table public.education_attendance enable row level security;

drop policy if exists education_attendance_admin_all
  on public.education_attendance;

create policy education_attendance_admin_all
  on public.education_attendance
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

revoke all on public.education_attendance from anon, public;
grant select, insert, update, delete
  on public.education_attendance to authenticated;
