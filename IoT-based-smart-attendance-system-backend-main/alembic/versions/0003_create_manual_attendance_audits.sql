-- =============================================================================
-- Migration 0003: Create manual_attendance_audits table
-- =============================================================================
-- Direction  : ADDITIVE ONLY — no data deleted, no columns dropped
-- Safe to run: idempotent via IF NOT EXISTS guards
-- Applies to : Supabase (PostgreSQL 14+)
-- =============================================================================

CREATE TABLE IF NOT EXISTS manual_attendance_audits (
    id UUID PRIMARY KEY,
    teacher_id UUID NOT NULL REFERENCES users(id),
    student_id UUID NOT NULL REFERENCES users(id),
    session_id UUID NOT NULL REFERENCES attendance_sessions(id),
    previous_status VARCHAR(20),
    new_status VARCHAR(20) NOT NULL,
    operation VARCHAR(20) NOT NULL,
    operation_id UUID NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS for manual_attendance_audits
ALTER TABLE manual_attendance_audits ENABLE ROW LEVEL SECURITY;

-- Create policy to allow teachers and admins to read/insert
CREATE POLICY "Allow authenticated teachers and admins full access" ON manual_attendance_audits
    FOR ALL
    TO authenticated
    USING (auth.jwt()->>'role' IN ('teacher', 'admin'));
