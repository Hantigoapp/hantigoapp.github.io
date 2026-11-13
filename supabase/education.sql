-- HantiGo Education: base tables (classes, students, fee payments).
-- These tables already exist in the live Supabase project (same definitions as the open PR #29).
-- This file lets the database be rebuilt from the repo. "if not exists" means running it
-- on the live project changes nothing that is already there. Admin-only (public.is_admin()).
-- Order: after schema.sql; then education_students_class.sql, education_attendance.sql.

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
    foreign key (owner_id, class_id) references public.education_classes(owner_id, id) on delete restrict
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
    foreign key (owner_id, student_id) references public.education_students(owner_id, id) on delete restrict
);

create index if not exists education_students_owner_class_idx on public.education_students(owner_id, class_id);
create index if not exists education_payments_owner_date_idx on public.education_fee_payments(owner_id, paid_on desc);

do $$
declare t text;
begin
  foreach t in array array['education_classes','education_students','education_fee_payments'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t||'_admin_all', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t||'_admin_all', t);
    execute format('revoke all on public.%I from anon, public', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;
