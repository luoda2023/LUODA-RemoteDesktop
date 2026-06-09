import json, urllib.request

with open("/home/luoda/.hermes/github_token") as f:
    TOKEN = f.read().strip()

# Test token validity first
req = urllib.request.Request("https://api.github.com/user")
req.add_header("Authorization", f"Bearer {TOKEN}")
req.add_header("Accept", "application/vnd.github+json")
req.add_header("User-Agent", "Hermes-Agent")

try:
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode())
    print(f"Token valid. User: {data.get('login')}, name: {data.get('name')}")
except Exception as e:
    print(f"Token check failed: {e}")
