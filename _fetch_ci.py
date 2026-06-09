import json, os, urllib.request, sys

with open(os.path.expanduser("~/.hermes/github_token")) as f:
    TOKEN = f.read().strip()

REPO = "luoda2023/LUODA-RemoteDesktop"
endpoint = f"https://api.github.com/repos/{REPO}/actions/runs?per_page=5"

req = urllib.request.Request(endpoint)
req.add_header("Authorization", f"Bearer {TOKEN}")
req.add_header("Accept", "application/vnd.github+json")
req.add_header("User-Agent", "Hermes-Agent")
req.add_header("X-GitHub-Api-Version", "2022-11-28")

try:
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode())
    runs = data.get("workflow_runs", [])
    print(f"=== RUNS: {len(runs)} ===")
    for r in runs:
        print(f"ID:{r['id']} | STATUS:{r['status']} | CONCLUSION:{r['conclusion']} | NAME:{r['name']} | BRANCH:{r['head_branch']} | {r['created_at']}")
    with open("/tmp/ci_runs.json", "w") as f:
        json.dump(data, f)
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
