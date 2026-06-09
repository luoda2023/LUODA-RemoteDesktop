#!/usr/bin/env python3
"""Fetch job logs via API, handling redirects."""
import json, urllib.request, sys, os

with open(os.path.expanduser("~/.hermes/github_token")) as f:
    TOKEN = f.read().strip()

job_id = sys.argv[1]
REPO = "luoda2023/LUODA-RemoteDesktop"

# Step 1: Get job details to find check_run_url
job_url = f"https://api.github.com/repos/{REPO}/actions/jobs/{job_id}"
req = urllib.request.Request(job_url)
req.add_header("Authorization", f"Bearer {TOKEN}")
req.add_header("Accept", "application/vnd.github+json")
req.add_header("User-Agent", "Hermes-Agent")

with urllib.request.urlopen(req) as resp:
    job_data = json.loads(resp.read().decode())

run_id = job_data.get("run_id")
print(f"Job: {job_data.get('name')}, Run ID: {run_id}")

# Step 2: Get run details  
run_url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}"
req = urllib.request.Request(run_url)
req.add_header("Authorization", f"Bearer {TOKEN}")
req.add_header("Accept", "application/vnd.github+json")
req.add_header("User-Agent", "Hermes-Agent")

with urllib.request.urlopen(req) as resp:
    run_data = json.loads(resp.read().decode())

print(f"Run: {run_data.get('name')}, Status: {run_data.get('status')}, Conclusion: {run_data.get('conclusion')}")
print(f"Head SHA: {run_data.get('head_sha')}")

# Step 3: Try to get logs
logs_url = f"https://api.github.com/repos/{REPO}/actions/jobs/{job_id}/logs"
req = urllib.request.Request(logs_url)
req.add_header("Authorization", f"Bearer {TOKEN}")
req.add_header("Accept", "application/vnd.github+json")
req.add_header("User-Agent", "Hermes-Agent")

# Don't follow redirects, capture the redirect URL
class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None
    def http_error_302(self, req, fp, code, msg, headers):
        return fp

opener = urllib.request.build_opener(NoRedirectHandler)
try:
    resp = opener.open(req)
    print(f"Logs: got response, status={resp.status}")
    info = resp.info()
    if 'Location' in info:
        print(f"Redirect URL: {info['Location'][:100]}...")
except urllib.error.HTTPError as e:
    print(f"Logs HTTP Error: {e.code} {e.reason}")
    # Try to get response body
    try:
        body = e.read().decode()
        print(f"Body: {body[:500]}")
    except:
        pass
except Exception as e:
    print(f"Logs Error: {e}")
