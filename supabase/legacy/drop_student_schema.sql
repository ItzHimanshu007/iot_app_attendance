-- =============================================================================
-- ONLY if you reuse the OLD student-attendance Supabase project.
-- A brand-new project is strongly recommended instead (the old project's keys
-- were committed to a public GitHub repo and must be considered compromised).
--
-- This permanently deletes the old student/teacher tables and their data.
-- =============================================================================

drop table if exists public.manual_attendance_audits cascade;
drop table if exists public.attendance_records       cascade;
drop table if exists public.attendance_sessions      cascade;
drop table if exists public.timetables               cascade;
drop table if exists public.enrollments              cascade;
drop table if exists public.subjects                 cascade;
drop table if exists public.esp32_devices            cascade;
drop table if exists public.classrooms               cascade;
drop table if exists public.registered_devices       cascade;
drop table if exists public.notifications            cascade;
drop table if exists public.users                    cascade;

-- The old project may also have a signup trigger on auth.users that writes to
-- public.users. The new migration replaces the trigger named
-- on_auth_user_created; if your old trigger had another name, remove it in
-- Dashboard → Database → Triggers (schema "auth").

-- Old demo accounts (teacher@/student@/admin@smartcampus.local) used passwords
-- that are public in the repo history — delete them in Authentication → Users.
