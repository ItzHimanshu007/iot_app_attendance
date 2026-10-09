"""seed_users.py — Create Supabase Auth users + public.users profile rows.

Creates:
  1. teacher@smartcampus.local  (role: teacher)
  2. student@smartcampus.local  (role: student)
  3. admin@smartcampus.local    (role: admin)

Each auth user gets a matching row in public.users where id = auth.uid().

Usage:
  python seed_users.py
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

# ── Load .env ─────────────────────────────────────────────────────────────────
env: dict[str, str] = {}
for line in Path(".env").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, _, v = line.partition("=")
        env[k.strip()] = v.strip()

SUPABASE_URL = env.get("SUPABASE_URL", "")
SERVICE_KEY  = env.get("SUPABASE_SERVICE_KEY", "")

if not SUPABASE_URL or not SERVICE_KEY:
    print("ERROR: SUPABASE_URL and SUPABASE_SERVICE_KEY must be set in .env")
    sys.exit(1)

# ── Helpers ───────────────────────────────────────────────────────────────────

def post(path: str, body: dict) -> dict:
    """POST to Supabase REST endpoint with service key auth."""
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{SUPABASE_URL}{path}",
        data=data,
        headers={
            "apikey": SERVICE_KEY,
            "Authorization": f"Bearer {SERVICE_KEY}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body_bytes = e.read()
        try:
            err = json.loads(body_bytes)
        except Exception:
            err = body_bytes.decode(errors="replace")
        raise RuntimeError(f"HTTP {e.code}: {err}") from None


def get(path: str) -> dict:
    """GET from Supabase REST endpoint."""
    req = urllib.request.Request(
        f"{SUPABASE_URL}{path}",
        headers={
            "apikey": SERVICE_KEY,
            "Authorization": f"Bearer {SERVICE_KEY}",
        },
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def create_auth_user(email: str, password: str, metadata: dict) -> str:
    """Create a Supabase Auth user via the Admin API.
    Returns the new user's UUID.
    If the user already exists (by email), returns their existing UUID.
    """
    # Check if already exists
    existing = get("/auth/v1/admin/users?per_page=100")
    for u in existing.get("users", []):
        if u.get("email") == email:
            uid = u["id"]
            print(f"    [EXISTS] {email} -> {uid}")
            return uid

    result = post("/auth/v1/admin/users", {
        "email": email,
        "password": password,
        "email_confirm": True,          # skip email verification
        "user_metadata": metadata,
    })
    uid = result["id"]
    print(f"    [CREATED] {email} -> {uid}")
    return uid


def upsert_profile(uid: str, profile: dict) -> None:
    """Insert or update a row in public.users via Supabase REST."""
    body = {"id": uid, **profile}
    data = json.dumps([body]).encode()
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/users",
        data=data,
        headers={
            "apikey": SERVICE_KEY,
            "Authorization": f"Bearer {SERVICE_KEY}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=representation",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            rows = json.loads(resp.read())
            if rows:
                print(f"    [DB ROW]  public.users.id={rows[0]['id'][:8]}...  role={rows[0]['role']}")
    except urllib.error.HTTPError as e:
        body_bytes = e.read()
        try:
            err = json.loads(body_bytes)
        except Exception:
            err = body_bytes.decode(errors="replace")
        raise RuntimeError(f"DB upsert HTTP {e.code}: {err}") from None


# ── Seed data ─────────────────────────────────────────────────────────────────

SEED_USERS = [
    {
        "email": "teacher@smartcampus.local",
        "password": "Teacher@2024!",
        "metadata": {"role": "teacher"},
        "profile": {
            "email": "teacher@smartcampus.local",
            "full_name": "Dr. Arun Kumar",
            "role": "teacher",
            "department": "Computer Science",
            "is_active": True,
        },
    },
    {
        "email": "student@smartcampus.local",
        "password": "Student@2024!",
        "metadata": {"role": "student"},
        "profile": {
            "email": "student@smartcampus.local",
            "full_name": "Priya Sharma",
            "role": "student",
            "department": "Computer Science",
            "student_id_number": "CS2024001",
            "is_active": True,
        },
    },
    {
        "email": "admin@smartcampus.local",
        "password": "Admin@2024!",
        "metadata": {"role": "admin"},
        "profile": {
            "email": "admin@smartcampus.local",
            "full_name": "System Administrator",
            "role": "admin",
            "department": "Administration",
            "is_active": True,
        },
    },
]

# ── Run ───────────────────────────────────────────────────────────────────────

print()
print("=" * 60)
print("Smart Campus — Seed Users")
print("=" * 60)
print(f"Project: {SUPABASE_URL}")
print()

created = []
errors  = []

for user in SEED_USERS:
    print(f"  {user['profile']['role'].upper()}: {user['email']}")
    try:
        uid = create_auth_user(user["email"], user["password"], user["metadata"])
        upsert_profile(uid, user["profile"])
        created.append({**user, "uid": uid})
    except Exception as e:
        print(f"    [ERROR] {e}")
        errors.append(user["email"])
    print()

# ── Summary ───────────────────────────────────────────────────────────────────

print("=" * 60)
print("Summary")
print("=" * 60)
print()
if created:
    print("Login credentials:")
    print()
    for u in created:
        print(f"  Role:     {u['profile']['role']}")
        print(f"  Email:    {u['email']}")
        print(f"  Password: {u['password']}")
        print(f"  UID:      {u['uid']}")
        print()

if errors:
    print(f"  FAILED: {', '.join(errors)}")
    sys.exit(1)
else:
    print("All users seeded successfully.")
    print()
    print("Next step: Run the Flutter app and log in with any of the above credentials.")
