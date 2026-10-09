-- =============================================================================
-- First-run setup — run AFTER the migration, then edit the values.
-- =============================================================================

-- 1. Campus location (open Google Maps, long-press the campus centre, copy lat/lng)
update public.campus_settings
set campus_name          = 'SKIT Jaipur',
    timezone             = 'Asia/Kolkata',
    latitude             = 26.8226,     -- ← replace with your campus latitude
    longitude            = 75.8644,     -- ← replace with your campus longitude
    radius_m             = 500,
    geofence_mode        = 'flag',      -- 'off' | 'flag' | 'enforce'
    work_start_time      = '09:00',
    late_grace_minutes   = 15,
    face_match_threshold = 0.60
where id = 1;

-- 2. Make yourself the first admin.
--    Sign up in the app first, then run this with your email:
update public.staff
set role = 'admin', status = 'active', approved_at = now()
where lower(email) = lower('you@example.com');   -- ← replace

-- 3. Beacons are created from the app (Admin → Beacons → Add beacon) or
--    POST /api/v1/admin/beacons. The backend generates the beacon secret
--    that you paste into firmware/staff_beacon/secrets.h.
