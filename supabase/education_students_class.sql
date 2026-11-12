-- HantiGo Education: allow Admin to put registered students in a class
-- Run once in Supabase Dashboard -> SQL Editor (only if the page asks for it).
-- Only Admin (public.is_admin()) may change a student's class. No data is deleted.

alter table public.education_students enable row level security;

drop policy if exists education_students_admin_update
  on public.education_students;

create policy education_students_admin_update
  on public.education_students
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant update on public.education_students to authenticated;
