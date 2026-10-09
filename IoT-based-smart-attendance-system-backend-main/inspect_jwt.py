"""Inspect the algorithm used by the Supabase JWT."""
import base64
import json
from pathlib import Path

env: dict[str, str] = {}
for line in Path(".env").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, _, v = line.partition("=")
        env[k.strip()] = v.strip()

import urllib.request

SUPABASE_URL = env.get("SUPABASE_URL", "")
ANON_KEY     = env.get("SUPABASE_ANON_KEY", "")

body = json.dumps({"email": "teacher@smartcampus.local", "password": "Teacher@2024!"}).encode()
req = urllib.request.Request(
    f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
    data=body,
    headers={"apikey": ANON_KEY, "Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(req, timeout=15) as resp:
    token = json.loads(resp.read())["access_token"]

# Decode header (base64url, no sig verification)
header_b64 = token.split(".")[0]
# Pad to multiple of 4
header_b64 += "=" * (4 - len(header_b64) % 4)
header = json.loads(base64.urlsafe_b64decode(header_b64))
print("JWT Header:", json.dumps(header, indent=2))

payload_b64 = token.split(".")[1]
payload_b64 += "=" * (4 - len(payload_b64) % 4)
payload = json.loads(base64.urlsafe_b64decode(payload_b64))
print("JWT Payload (trimmed):", json.dumps({k: v for k, v in payload.items() if k != "session_id"}, indent=2))
