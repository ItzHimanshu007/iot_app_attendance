-- =============================================================================
-- Migration 0002: Add subject_name to attendance_sessions
-- =============================================================================
-- Direction  : ADDITIVE ONLY — no data deleted, no columns dropped
-- Safe to run: idempotent via IF NOT EXISTS / IF EXISTS guards
-- Applies to : Supabase (PostgreSQL 14+)
-- =============================================================================

-- 1. Make subject_id optional so new sessions no longer need a subject UUID.
--    Historical rows already have a non-null subject_id; they are unaffected.
ALTER TABLE attendance_sessions
    ALTER COLUMN subject_id DROP NOT NULL;

-- 2. Add the free-text subject_name column for sessions created after this
--    migration. NULL for all historical rows — resolved at read time via
--    subject_id fallback.
ALTER TABLE attendance_sessions
    ADD COLUMN IF NOT EXISTS subject_name TEXT;

-- =============================================================================
-- Down (manual rollback — only run if you want to revert):
--
--   ALTER TABLE attendance_sessions ALTER COLUMN subject_id SET NOT NULL;
--   ALTER TABLE attendance_sessions DROP COLUMN IF EXISTS subject_name;
--
-- WARNING: rolling back SET NOT NULL will fail if any row has subject_id = NULL
-- (i.e., if new sessions were already created after the migration).
-- =============================================================================
