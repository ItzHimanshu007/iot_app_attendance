"""test_login.py — End-to-end login test.
Signs in as each seeded user and hits GET /api/v1/users/me.
"""
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

env: dict[str, str] = {}
for line in Path(".env").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, _, v = line.partition("=")
        env[k.strip()] = v.strip()

SUPABASE_URL = env.get("SUPABASE_URL", "")
ANON_KEY     = env.get("SUPABASE_ANON_KEY", "")
API          = "http://localhost:8000"

USERS = [
    ("teacher@smartcampus.local", "Teacher@2024!"),
    ("student@smartcampus.local", "Student@2024!"),
]


def supabase_login(email: str, password: str) -> str:
    """Sign in via Supabase Auth and return the access_token."""
    body = json.dumps({"email": email, "password": password}).encode()
    req = urllib.request.Request(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        data=body,
        headers={
            "apikey": ANON_KEY,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())["access_token"]


def get_profile(token: str) -> dict:
    """Hit FastAPI GET /api/v1/users/me with a JWT."""
    req = urllib.request.Request(
        f"{API}/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


print()
print("=" * 60)
print("End-to-End Login Test")
print("=" * 60)
print()

all_ok = True
for email, password in USERS:
    print(f"  Testing: {email}")
    try:
        token = supabase_login(email, password)
        print(f"    Supabase Auth  -> JWT obtained (len={len(token)})")

        profile = get_profile(token)
        print(f"    FastAPI /users/me -> role={profile.get('role')} name={profile.get('full_name')}")
        print("    [PASS]")
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        print(f"    [FAIL] HTTP {e.code}: {body[:200]}")
        all_ok = False
    except Exception as e:
        print(f"    [FAIL] {e}")
        all_ok = False
    print()

print("=" * 60)
if all_ok:
    print("ALL LOGINS PASSED -- Backend + Supabase Auth fully connected")
else:
    print("SOME LOGINS FAILED -- check errors above")
print("=" * 60)
sys.exit(0 if all_ok else 1)
