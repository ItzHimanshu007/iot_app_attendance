-- =============================================================================
-- Proxy Shield: face replay detection
-- =============================================================================
-- Recent live face signatures (192 numbers each, never photos) of accepted
-- check-ins. A new scan that is a near-exact copy of one of these, or of an
-- enrollment sample, was replayed by a modified app and is rejected
-- (FACE_REPLAY). Safe to run more than once. The backend keeps working
-- without this table (replay check then only compares enrollment samples).
-- =============================================================================

create table if not exists public.face_probes (
  id          uuid primary key default gen_random_uuid(),
  staff_id    uuid not null references public.staff (id) on delete cascade,
  embedding   jsonb not null,
  created_at  timestamptz not null default now()
);

create index if not exists face_probes_staff_idx
  on public.face_probes (staff_id, created_at desc);

-- Backend (service role) only: no client policies.
alter table public.face_probes enable row level security;
