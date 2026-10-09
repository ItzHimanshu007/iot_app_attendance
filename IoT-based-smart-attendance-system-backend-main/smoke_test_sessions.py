import json
import sys
import urllib.error
import urllib.request

BASE = "http://localhost:8000"

# ── 1. Teacher login ──────────────────────────────────────────────────────────
login_data = json.dumps({
    "email": "teacher@smartcampus.local",
    "password": "Teacher@2024!",
}).encode()
req = urllib.request.Request(
    f"{BASE}/api/v1/auth/login",
    data=login_data,
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        token = json.loads(r.read())["access_token"]
    print("[OK] Teacher login")
except urllib.error.HTTPError as e:
    print(f"[FAIL] Login: HTTP {e.code} — {e.read()}")
    sys.exit(1)

auth = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json",
}

# ── 2. GET /subjects/ ─────────────────────────────────────────────────────────
req = urllib.request.Request(f"{BASE}/api/v1/subjects/", headers=auth)
with urllib.request.urlopen(req, timeout=10) as r:
    subjects = json.loads(r.read())
print(f"[OK] Subjects: {len(subjects)} loaded")
cs501 = next((s for s in subjects if s["code"] == "CS501"), None)
cs401 = next((s for s in subjects if s["code"] == "CS401"), None)
assert cs501, "CS501 missing from subjects!"
assert cs401, "CS401 missing from subjects!"

# ── 3. GET /classrooms/ ───────────────────────────────────────────────────────
req = urllib.request.Request(f"{BASE}/api/v1/classrooms/", headers=auth)
with urllib.request.urlopen(req, timeout=10) as r:
    classrooms = json.loads(r.read())
print(f"[OK] Classrooms: {len(classrooms)} loaded")
room302 = next((c for c in classrooms if c["name"] == "Room 302"), None)
halla   = next((c for c in classrooms if c["name"] == "Lecture Hall A"), None)
assert room302, "Room 302 missing!"
assert halla, "Lecture Hall A missing!"

errors = []

# ── 4. POST /sessions/ — CS501 + Room 302 ────────────────────────────────────
payload = json.dumps({
    "subject_id": cs501["id"],
    "classroom_id": room302["id"],
    "duration_minutes": 60,
}).encode()
req = urllib.request.Request(
    f"{BASE}/api/v1/sessions/",
    data=payload,
    headers=auth,
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        session = json.loads(r.read())
    print(f"[OK] CS501 + Room 302 created: {session['id']}  status={session['status']}")
except urllib.error.HTTPError as e:
    body = json.loads(e.read())
    msg = f"[FAIL] CS501+Room302: HTTP {e.code} — {body.get('error', {}).get('message', body)}"
    print(msg)
    errors.append(msg)

# ── 5. POST /sessions/ — CS401 + Lecture Hall A ───────────────────────────────
payload = json.dumps({
    "subject_id": cs401["id"],
    "classroom_id": halla["id"],
    "duration_minutes": 60,
}).encode()
req = urllib.request.Request(
    f"{BASE}/api/v1/sessions/",
    data=payload,
    headers=auth,
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        session2 = json.loads(r.read())
    print(f"[OK] CS401 + Lecture Hall A created: {session2['id']}  status={session2['status']}")
except urllib.error.HTTPError as e:
    body = json.loads(e.read())
    msg = f"[FAIL] CS401+HallA: HTTP {e.code} — {body.get('error', {}).get('message', body)}"
    print(msg)
    errors.append(msg)

# ── Result ────────────────────────────────────────────────────────────────────
print()
if errors:
    print("FAILURES:")
    for e in errors:
        print(f"  {e}")
    sys.exit(1)
else:
    print("Live validation PASSED — session creation works on empty attendance_sessions table.")
