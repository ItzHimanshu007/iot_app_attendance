-- =============================================================================
-- Staff Attendance System — Supabase schema v1
-- =============================================================================
-- Run once on a NEW Supabase project:
--   Supabase Dashboard → SQL Editor → paste this file → Run
--   (or: supabase db push, if you use the Supabase CLI)
--
-- The script is idempotent: re-running it does not drop data.
--
-- Security model
--   * The Flutter app talks to Supabase ONLY for authentication.
--   * All reads/writes go through the FastAPI backend with the service-role key
--     (which bypasses RLS).
--   * RLS is enabled on every table. Signed-in users may read their own profile,
--     device and attendance; sensitive tables (face templates, beacon secrets,
--     challenges, attempts, audit log) have NO client policies at all.
-- =============================================================================

-- ── Helpers ──────────────────────────────────────────────────────────────────

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ── staff: one profile per auth user ─────────────────────────────────────────

create table if not exists public.staff (
  id           uuid primary key references auth.users (id) on delete cascade,
  email        text not null,
  full_name    text not null,
  employee_id  text,
  department   text,
  designation  text,
  phone        text,
  role         text not null default 'staff'
               check (role in ('staff', 'admin')),
  status       text not null default 'pending'
               check (status in ('pending', 'active', 'disabled')),
  approved_by  uuid references public.staff (id) on delete set null,
  approved_at  timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create unique index if not exists staff_email_key
  on public.staff (lower(email));
create unique index if not exists staff_employee_id_key
  on public.staff (lower(employee_id)) where employee_id is not null;
create index if not exists staff_status_idx on public.staff (status);

drop trigger if exists staff_set_updated_at on public.staff;
create trigger staff_set_updated_at
  before update on public.staff
  for each row execute function public.set_updated_at();

-- Create the staff row automatically when someone signs up.
-- The app sends full_name / employee_id / department / designation / phone
-- as user metadata (supabase.auth.signUp(data: {...})).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.staff (id, email, full_name, employee_id, department, designation, phone)
  values (
    new.id,
    new.email,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
             split_part(new.email, '@', 1)),
    nullif(trim(new.raw_user_meta_data ->> 'employee_id'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'department'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'designation'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'phone'), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── devices: the phone bound to each staff member ────────────────────────────

create table if not exists public.devices (
  id                   uuid primary key default gen_random_uuid(),
  staff_id             uuid not null references public.staff (id) on delete cascade,
  device_fingerprint   text not null,
  device_model         text,
  device_manufacturer  text,
  os_version           text,
  app_version          text,
  is_active            boolean not null default true,
  registered_at        timestamptz not null default now(),
  last_seen_at         timestamptz,
  deactivated_at       timestamptz,
  deactivation_reason  text
);

-- One active phone per staff member, and one active owner per phone.
create unique index if not exists devices_one_active_per_staff
  on public.devices (staff_id) where is_active;
create unique index if not exists devices_one_owner_per_fingerprint
  on public.devices (device_fingerprint) where is_active;

-- ── face_templates: enrolled face signatures (NO photos) ─────────────────────

create table if not exists public.face_templates (
  staff_id       uuid primary key references public.staff (id) on delete cascade,
  embeddings     jsonb not null,          -- [[f32 × dim], ...] L2-normalised
  embedding_dim  integer not null check (embedding_dim between 64 and 1024),
  sample_count   integer not null check (sample_count >= 1),
  model_version  text not null,
  status         text not null default 'pending'
                 check (status in ('pending', 'approved', 'rejected')),
  reviewed_by    uuid references public.staff (id) on delete set null,
  reviewed_at    timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

drop trigger if exists face_templates_set_updated_at on public.face_templates;
create trigger face_templates_set_updated_at
  before update on public.face_templates
  for each row execute function public.set_updated_at();

-- ── beacons: ESP32 BLE beacons placed on campus ──────────────────────────────

create table if not exists public.beacons (
  id              uuid primary key default gen_random_uuid(),  -- advertised in BLE payload
  name            text not null,
  location        text,
  secret          text not null,          -- HMAC key, generated by the backend
  rssi_threshold  integer not null default -85 check (rssi_threshold between -120 and 0),
  is_active       boolean not null default true,
  last_used_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

drop trigger if exists beacons_set_updated_at on public.beacons;
create trigger beacons_set_updated_at
  before update on public.beacons
  for each row execute function public.set_updated_at();

-- ── campus_settings: single-row configuration ────────────────────────────────

create table if not exists public.campus_settings (
  id                       integer primary key default 1 check (id = 1),
  campus_name              text not null default 'My Campus',
  timezone                 text not null default 'Asia/Kolkata',
  latitude                 double precision,
  longitude                double precision,
  radius_m                 integer not null default 500 check (radius_m between 50 and 20000),
  -- off     : GPS is not checked
  -- flag    : GPS is checked; outside/inaccurate is flagged for admin review
  -- enforce : outside the radius (or no GPS) is rejected
  geofence_mode            text not null default 'flag'
                           check (geofence_mode in ('off', 'flag', 'enforce')),
  max_location_accuracy_m  integer not null default 150 check (max_location_accuracy_m > 0),
  work_start_time          time not null default '09:00',
  late_grace_minutes       integer not null default 15 check (late_grace_minutes >= 0),
  face_match_threshold     real not null default 0.55
                           check (face_match_threshold > 0 and face_match_threshold < 1),
  updated_at               timestamptz not null default now()
);

insert into public.campus_settings (id) values (1) on conflict (id) do nothing;

drop trigger if exists campus_settings_set_updated_at on public.campus_settings;
create trigger campus_settings_set_updated_at
  before update on public.campus_settings
  for each row execute function public.set_updated_at();

-- ── attendance_challenges: one-time nonces for the mark-attendance flow ──────

create table if not exists public.attendance_challenges (
  id                  uuid primary key default gen_random_uuid(),
  staff_id            uuid not null references public.staff (id) on delete cascade,
  action              text not null check (action in ('check_in', 'check_out')),
  beacon_id           uuid not null references public.beacons (id) on delete cascade,
  liveness_steps      text[] not null,
  device_fingerprint  text not null,
  created_at          timestamptz not null default now(),
  expires_at          timestamptz not null,
  consumed_at         timestamptz
);

create index if not exists attendance_challenges_staff_idx
  on public.attendance_challenges (staff_id, created_at desc);

-- ── attendance: one row per staff member per day ─────────────────────────────

create table if not exists public.attendance (
  id                     uuid primary key default gen_random_uuid(),
  staff_id               uuid not null references public.staff (id) on delete cascade,
  attendance_date        date not null,
  status                 text not null
                         check (status in ('present', 'late', 'absent', 'on_leave')),
  check_in_at            timestamptz,
  check_out_at           timestamptz,
  check_in_beacon_id     uuid references public.beacons (id) on delete set null,
  check_out_beacon_id    uuid references public.beacons (id) on delete set null,
  check_in_rssi          integer,
  check_out_rssi         integer,
  check_in_face_score    real,
  check_out_face_score   real,
  check_in_latitude      double precision,
  check_in_longitude     double precision,
  check_in_accuracy_m    real,
  check_in_distance_m    real,
  check_out_distance_m   real,
  device_fingerprint     text,
  flags                  text[] not null default '{}',
  is_manual              boolean not null default false,
  manual_reason          text,
  marked_by              uuid references public.staff (id) on delete set null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (staff_id, attendance_date)
);

create index if not exists attendance_date_idx on public.attendance (attendance_date);

drop trigger if exists attendance_set_updated_at on public.attendance;
create trigger attendance_set_updated_at
  before update on public.attendance
  for each row execute function public.set_updated_at();

-- ── attendance_attempts: every success and failure (proxy-attempt log) ───────

create table if not exists public.attendance_attempts (
  id                  uuid primary key default gen_random_uuid(),
  staff_id            uuid references public.staff (id) on delete cascade,
  action              text not null,           -- challenge_check_in, submit_check_out, ...
  success             boolean not null,
  reason_code         text,
  message             text,
  beacon_id           uuid,
  rssi                integer,
  face_score          real,
  latitude            double precision,
  longitude           double precision,
  accuracy_m          real,
  device_fingerprint  text,
  ip_address          text,
  created_at          timestamptz not null default now()
);

create index if not exists attendance_attempts_created_idx
  on public.attendance_attempts (created_at desc);
create index if not exists attendance_attempts_staff_idx
  on public.attendance_attempts (staff_id, created_at desc);

-- ── admin_audit_log: every admin action ──────────────────────────────────────

create table if not exists public.admin_audit_log (
  id               uuid primary key default gen_random_uuid(),
  admin_id         uuid references public.staff (id) on delete set null,
  action           text not null,
  target_staff_id  uuid references public.staff (id) on delete set null,
  details          jsonb not null default '{}',
  created_at       timestamptz not null default now()
);

create index if not exists admin_audit_log_created_idx
  on public.admin_audit_log (created_at desc);

-- ── Row Level Security ───────────────────────────────────────────────────────

alter table public.staff                  enable row level security;
alter table public.devices                enable row level security;
alter table public.face_templates         enable row level security;
alter table public.beacons                enable row level security;
alter table public.campus_settings        enable row level security;
alter table public.attendance_challenges  enable row level security;
alter table public.attendance             enable row level security;
alter table public.attendance_attempts    enable row level security;
alter table public.admin_audit_log        enable row level security;

drop policy if exists "staff: read own profile" on public.staff;
create policy "staff: read own profile" on public.staff
  for select to authenticated
  using ((select auth.uid()) = id);

drop policy if exists "devices: read own" on public.devices;
create policy "devices: read own" on public.devices
  for select to authenticated
  using ((select auth.uid()) = staff_id);

drop policy if exists "attendance: read own" on public.attendance;
create policy "attendance: read own" on public.attendance
  for select to authenticated
  using ((select auth.uid()) = staff_id);

drop policy if exists "campus settings: read" on public.campus_settings;
create policy "campus settings: read" on public.campus_settings
  for select to authenticated
  using (true);

-- face_templates, beacons, attendance_challenges, attendance_attempts and
-- admin_audit_log intentionally have NO policies → only the backend
-- (service role) can read or write them.
