#!/usr/bin/env python3
"""Fetch logs via the redirect URL (Azure blob SAS)."""
import json, urllib.request, sys, os, gzip

with open(os.path.expanduser("~/.hermes/github_token")) as f:
    TOKEN = f.read().strip()

job_id = sys.argv[1]
REPO = "luoda2023/LUODA-RemoteDesktop"

# Get the redirect URL
logs_url = f"https://api.github.com/repos/{REPO}/actions/jobs/{job_id}/logs"
req = urllib.request.Request(logs_url)
req.add_header("Authorization", f"Bearer {TOKEN}")
req.add_header("Accept", "application/vnd.github+json")
req.add_header("User-Agent", "Hermes-Agent")

# Capture redirect
class RedirectCatcher(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        self.redirect_url = newurl
        return None

handler = RedirectCatcher()
opener = urllib.request.build_opener(handler)
try:
    opener.open(req)
except:
    pass

redirect_url = getattr(handler, 'redirect_url', None)
if not redirect_url:
    print("No redirect URL found")
    sys.exit(1)

# Fetch from redirect URL (SAS URL, no auth needed)
print(f"Fetching logs from SAS URL...")
req2 = urllib.request.Request(redirect_url)
req2.add_header("User-Agent", "Hermes-Agent")
with urllib.request.urlopen(req2) as resp:
    raw = resp.read()

try:
    text = gzip.decompress(raw).decode('utf-8', errors='replace')
except:
    text = raw.decode('utf-8', errors='replace')

lines = text.split('\n')
print(f"=== LOG {len(lines)} lines ===")

# Show last 150 lines, focusing on errors
error_lines = []
for line in lines:
    if any(kw in line.lower() for kw in ['error', 'fail', 'exception', 'cannot', 'could not', 'missing', 'not found', 'warning']):
        error_lines.append(line)

print("\n=== ERROR/WARNING LINES ===")
for line in error_lines[-30:]:
    print(line)

print("\n=== LAST 50 LINES ===")
for line in lines[-50:]:
    print(line)

with open(f"/tmp/ci_log_{job_id}.txt", "w") as f:
    f.write(text)
