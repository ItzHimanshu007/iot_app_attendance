"""Quick test: verifies Supabase Auth is connected and lists existing users."""
import json
import urllib.request

env = {}
with open(".env", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            env[k.strip()] = v.strip()

url = env.get("SUPABASE_URL", "")
service_key = env.get("SUPABASE_SERVICE_KEY", "")

req = urllib.request.Request(
    f"{url}/auth/v1/admin/users?per_page=10",
    headers={
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
    },
)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read())
        users = data.get("users", [])
        print(f"Supabase Auth connected. Users: {len(users)}")
        for u in users:
            email = u.get("email", "?")
            meta = u.get("user_metadata", {})
            role = meta.get("role", "not set")
            print(f"  - {email}  (metadata role: {role})")
        if not users:
            print("  No auth users yet.")
            print("  Create one: Supabase Dashboard > Authentication > Users > Invite user")
except Exception as e:
    print(f"Auth API error: {e}")
