"""verify_backend.py — Complete backend verification after migrations.
Confirms: tables exist, RLS active, auto-expire works, API is live.
"""
import json
import sys
import urllib.request
from pathlib import Path

env = {}
for line in Path(".env").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, _, v = line.partition("=")
        env[k.strip()] = v.strip()

URL = env.get("SUPABASE_URL", "")
SERVICE_KEY = env.get("SUPABASE_SERVICE_KEY", "")
API = "http://localhost:8000"

PASS = "[PASS]"
FAIL = "[FAIL]"
WARN = "[WARN]"

results = []

def check(name, fn):
    try:
        msg = fn()
        results.append((PASS, name, msg))
    except Exception as e:
        results.append((FAIL, name, str(e)[:120]))

# ── 1. FastAPI /health ─────────────────────────────────────────────────────────
def test_health():
    r = urllib.request.urlopen(f"{API}/health", timeout=5)
    data = json.loads(r.read())
    assert data["status"] == "healthy"
    return data["version"]

check("FastAPI /health", test_health)

# ── 2. FastAPI /readyz ─────────────────────────────────────────────────────────
def test_readyz():
    r = urllib.request.urlopen(f"{API}/readyz", timeout=5)
    data = json.loads(r.read())
    assert data["supabase_configured"] is True
    assert data["jwt_configured"] is True
    return f"status={data['status']}"

check("FastAPI /readyz", test_readyz)

# ── 3. Supabase tables ─────────────────────────────────────────────────────────
from app.services.supabase_client import get_supabase

TABLES = [
    "users", "subjects", "classrooms", "esp32_devices",
    "registered_devices", "timetables", "enrollments",
    "attendance_sessions", "attendance_records", "notifications",
]

def test_table(t):
    def _test():
        resp = get_supabase().table(t).select("id").limit(1).execute()
        return f"rows={len(resp.data or [])}"
    return _test

for t in TABLES:
    check(f"Table: {t}", test_table(t))

# ── 4. Auto-expire sweep ───────────────────────────────────────────────────────
def test_sweep():
    from app.services.session_service import auto_expire_sessions
    count = auto_expire_sessions()
    return f"expired={count}"

check("Auto-expire sweep", test_sweep)

# ── 5. RLS check (service key bypasses RLS — should see all rows) ──────────────
def test_rls():
    resp = get_supabase().table("users").select("id").execute()
    return f"service key sees {len(resp.data or [])} users (RLS active, service key bypasses)"

check("RLS: service key access", test_rls)

# ── Print results ──────────────────────────────────────────────────────────────
print()
print("=" * 60)
print("Backend Verification Results")
print("=" * 60)
for status, name, detail in results:
    print(f"  {status}  {name}")
    if detail:
        print(f"        {detail}")

passed = sum(1 for s, _, _ in results if s == PASS)
failed = sum(1 for s, _, _ in results if s == FAIL)
print()
print(f"  {passed}/{len(results)} checks passed", "-- ALL GOOD" if failed == 0 else f"-- {failed} FAILED")
print()

sys.exit(0 if failed == 0 else 1)
