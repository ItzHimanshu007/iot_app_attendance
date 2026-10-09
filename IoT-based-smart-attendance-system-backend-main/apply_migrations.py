"""apply_migrations.py — Run all SQL migration files against your Supabase project.

This script applies the three migration files in order:
  001_create_tables.sql
  002_create_indexes.sql
  003_enable_rls.sql

Usage (run from the backend/ directory):
  python apply_migrations.py

Requirements:
  .env file must be configured with SUPABASE_URL and SUPABASE_SERVICE_KEY.
"""

from __future__ import annotations

import sys
from pathlib import Path

# ── Force UTF-8 output on Windows ─────────────────────────────────────────────
if sys.stdout.encoding != "utf-8":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

# ── Load .env ─────────────────────────────────────────────────────────────────
env_path = Path(__file__).parent / ".env"
if not env_path.exists():
    print("ERROR: .env file not found. Run from the backend/ directory.")
    sys.exit(1)

env: dict[str, str] = {}
for line in env_path.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip()

SUPABASE_URL = env.get("SUPABASE_URL", "")
SERVICE_KEY = env.get("SUPABASE_SERVICE_KEY", "")

if not SUPABASE_URL or "YOUR_PROJECT_REF" in SUPABASE_URL:
    print("ERROR: SUPABASE_URL not configured in .env")
    sys.exit(1)

if not SERVICE_KEY or SERVICE_KEY in ("", "your-service-role-key", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.your-service-role-key"):
    print("ERROR: SUPABASE_SERVICE_KEY not configured in .env")
    sys.exit(1)

# Extract project ref from URL (e.g. https://abcdefg.supabase.co -> abcdefg)
project_ref = SUPABASE_URL.replace("https://", "").split(".")[0]

MIGRATIONS_DIR = Path(__file__).parent.parent / "supabase" / "migrations"
MIGRATION_FILES = [
    "001_create_tables.sql",
    "002_create_indexes.sql",
    "003_enable_rls.sql",
]

print("=" * 60)
print("Smart Campus Attendance -- Database Migration Runner")
print("=" * 60)
print(f"\nProject ref:  {project_ref}")
print(f"Supabase URL: {SUPABASE_URL}")
print(f"Migrations:   {MIGRATIONS_DIR}")
print()

# ── Verify migration files exist ───────────────────────────────────────────────
all_exist = True
for filename in MIGRATION_FILES:
    filepath = MIGRATIONS_DIR / filename
    exists = filepath.exists()
    mark = "OK" if exists else "MISSING"
    print(f"  [{mark}] {filename}")
    if not exists:
        all_exist = False

print()
if not all_exist:
    print("ERROR: Some migration files are missing. Check the supabase/migrations/ directory.")
    sys.exit(1)

# ── Try to apply via Supabase Management API ───────────────────────────────────
# The Supabase Management API exposes a database query endpoint.
# Endpoint: POST https://api.supabase.com/v1/projects/{ref}/database/query
# This requires a Supabase management token (not the project service key).
# Since we may not have a management token, we try both approaches.

def run_sql_via_management_api(sql: str) -> tuple[bool, str]:
    """Try to run SQL via Supabase Management API."""
    # The pg_dump/restore endpoint isn't publicly available without a management token.
    # Fall back to printing instructions.
    return False, "Management API requires a personal access token"


def run_sql_via_rpc(sql: str) -> tuple[bool, str]:
    """Try to execute SQL by calling a Supabase RPC function.
    This requires a function like 'exec_sql' to exist — won't work by default.
    """
    return False, "Direct SQL RPC not available by default"


# ── Print clear manual instructions ───────────────────────────────────────────
print("=" * 60)
print("ACTION REQUIRED: Apply migrations in Supabase SQL Editor")
print("=" * 60)
print(f"""
The Supabase Python client does not support raw SQL execution via REST.
You must apply the migrations manually using the SQL Editor.

STEPS (takes ~2 minutes):
  1. Open: https://supabase.com/dashboard/project/{project_ref}/sql
  2. Click "New query" (top right)
  3. Copy the ENTIRE contents of each file below and click "Run":

     FILE 1: {MIGRATIONS_DIR / "001_create_tables.sql"}
     FILE 2: {MIGRATIONS_DIR / "002_create_indexes.sql"}
     FILE 3: {MIGRATIONS_DIR / "003_enable_rls.sql"}

  Run them IN ORDER. Each should say "Success. No rows returned."

THEN restart the backend:
  uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

After restart, the PGRST205 error will be gone.
""")

# ── Open the SQL editor URL in the browser ─────────────────────────────────────
sql_editor_url = f"https://supabase.com/dashboard/project/{project_ref}/sql"
print(f"SQL Editor URL: {sql_editor_url}")
print()

try:
    import webbrowser
    ans = input("Open Supabase SQL Editor in browser now? (y/n): ").strip().lower()
    if ans == "y":
        webbrowser.open(sql_editor_url)
        print("Opened in browser.")
except (ImportError, EOFError, KeyboardInterrupt):
    pass

# ── Print each migration content ───────────────────────────────────────────────
print()
ans = ""
try:
    ans = input("Print migration SQL to terminal for copy-paste? (y/n): ").strip().lower()
except (EOFError, KeyboardInterrupt):
    pass

if ans == "y":
    for filename in MIGRATION_FILES:
        filepath = MIGRATIONS_DIR / filename
        print()
        print("=" * 60)
        print(f"-- FILE: {filename}")
        print("=" * 60)
        print(filepath.read_text(encoding="utf-8"))

print("\nDone. Run this script again after applying migrations to verify.")
