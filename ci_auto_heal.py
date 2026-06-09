#!/usr/bin/env python3
"""LUODA CI Auto-Heal Engine - auto-fix builds"""
import os,sys,json,time,re,hashlib,subprocess,urllib.request,urllib.error
import argparse,logging,traceback
from pathlib import Path
from datetime import datetime
REPO="luoda2023/LUODA-RemoteDesktop"
BRANCH="v2.0.0"
WORKDIR=Path.cwd()
TOKEN=os.environ.get("GH_TOKEN") or ""
BUILD_TARGETS=["Build LUODA Windows EXE","Build LUODA Windows MSI","Build LUODA Android APK","Build LUODA Linux DEB","Build LUODA macOS DMG","Build LUODA Web"]
IGNORE=["warning: unused import","warning: unused variable","warning: field is never read","warning: function is never used"]
FIXES=[]
def reg(pattern,targets,fn,desc):FIXES.append({"p":re.compile(pattern,re.I|re.M),"t":targets,"f":fn,"d":desc})
def fix_cargo(log,info):subprocess.run(["cargo","generate-lockfile"],cwd=WORKDIR,capture_output=True,timeout=120);return "fix: update Cargo.lock"
def fix_dart(log,info):
 for f in Path("flutter").rglob("*.dart"):
  c=f.read_bytes();x=c
  for a,b in[(b"\xe2\x80\x93",b"-"),(b"\xe2\x80\x94",b"--"),(b"\xe2\x80\x99",b"'"),(b"\xe2\x80\x98",b"'"),(b"\xe2\x80\x9c",b'"'),(b"\xe2\x80\x9d",b'"'),(b"\xc2\xa0",b" ")]:x=x.replace(a,b)
  if x!=c:f.write_bytes(x);print(f"  Fixed {f}")
 return "fix: Dart encoding"
def fix_rust(log,info):
 lines=log.split("\n")
 errs=[l for l in lines if "error[" in l]
 print(f"Rust errors: {len(errs)}")
 for e in errs[:15]:print(f"  {e.strip()}")
 r=subprocess.run(["cargo","check","--features","flutter"],cwd=WORKDIR,capture_output=True,text=True,timeout=300)
 for l in (r.stdout+r.stderr).split("\n")[-30:]:
  if l.strip():print(f"  {l.strip()}")
 return None
def fix_apk(log,info):
 env=os.environ.copy();env["AOM_INCLUDE_PATH"]=str(WORKDIR/"libs"/"aom");env["BINDGEN_EXTRA_CLANG_ARGS"]=""
 subprocess.run(["cargo","build","--target","aarch64-linux-android","--features","flutter","-p","scrap"],cwd=WORKDIR,env=env,capture_output=True,timeout=300)
 return "fix: APK bindings"
def fix_pubspec(log,info):
 p=WORKDIR/"flutter"/"pubspec.yaml"
 if p.exists():c=p.read_text();p.write_text(c.replace("luoda2023","rustdesk-org"))
 return "fix: pubspec dependencies"
def fix_web(log,info):
 if "getSettingsTabConfig" in log:return "fix: Web - missing getSettingsTabConfig"
 if "chr()" in log:return "fix: Web - chr() error"
 return None
reg(r"error: failed to select.*Cargo\.lock",["*"],fix_cargo,"Cargo.lock update")
reg(r"Error: Invalid argument|encoding.*error|Invalid UTF-8",["*"],fix_dart,"Dart encoding")
reg(r"error\[E\d{4}\]",["*"],fix_rust,"Rust compilation")
reg(r"aom.*bindgen|AOM_INCLUDE_PATH",["Build LUODA Android APK"],fix_apk,"APK bindings")
reg(r"flutter pub get.*failed|pub get.*error",["*"],fix_pubspec,"Flutter deps")
reg(r"getSettingsTabConfig|chr\(\)",["Build LUODA Web"],fix_web,"Web errors")
LD=WORKDIR/".ci_auto_heal";LD.mkdir(exist_ok=True)
lf=LD/f"heal_{datetime.now():%Y%m%d_%H%M%S}.log"
logging.basicConfig(level=logging.INFO,format="[%(asctime)s] %(message)s",datefmt="%H:%M:%S",handlers=[logging.FileHandler(lf,encoding="utf-8"),logging.StreamHandler()])
log=logging.getLogger("h")

def api(path,method="GET",data=None):
 url=f"https://api.github.com/repos/{REPO}{path}"
 h={"Authorization":f"Bearer {TOKEN}","Accept":"application/vnd.github+json","User-Agent":"L/1.0"}
 req=urllib.request.Request(url,headers=h,method=method)
 if data:req.data=json.dumps(data).encode()
 try:
  with urllib.request.urlopen(req,timeout=30) as r:
   b=r.read().decode();return json.loads(b) if b else {}
 except urllib.error.HTTPError as e:
  b=e.fp.read().decode()[:200] if e.fp else "";log.error(f"HTTP{e.code}:{b}");return{"error":str(e)}
 except urllib.error.URLError as e:
  log.error(f"URL:{e}");return{"error":str(e)}

def runs(status=None,pp=10):
 p=f"/actions/runs?branch={BRANCH}&per_page={pp}"
 if status:p+=f"&status={status}"
 d=api(p);return d.get("workflow_runs",[]) if "error" not in d else []

def jobs(rid):d=api(f"/actions/runs/{rid}/jobs");return d.get("jobs",[]) if "error" not in d else []
def jlogs(jid):
 """Get job logs - handles redirect/zip response"""
 url=f"https://api.github.com/repos/{REPO}/actions/jobs/{jid}/logs"
 h={"Authorization":f"Bearer {TOKEN}","Accept":"application/vnd.github+json","User-Agent":"L/1.0"}
 req=urllib.request.Request(url,headers=h)
 try:
  with urllib.request.urlopen(req,timeout=60) as r:
   ct=r.headers.get("Content-Type","")
   loc=r.headers.get("Location","")
   if loc:
    req2=urllib.request.Request(loc,headers={"User-Agent":"L/1.0"})
    with urllib.request.urlopen(req2,timeout=60) as r2:
     b=r2.read()
   else:
    b=r.read()
   # Try to decode - zip files will fail, so return raw
   try:return b.decode("utf-8",errors="replace")
   except:return b.decode("latin-1",errors="replace")
 except urllib.error.HTTPError as e:
  log.error(f"jlogs HTTP{e.code}")
  try:return e.fp.read().decode("utf-8",errors="replace")[:5000]
  except:return ""
 except Exception as e:
  log.error(f"jlogs err:{e}");return ""
def dispatch(wf):r=api(f"/actions/workflows/{wf}/dispatches",method="POST",data={"ref":BRANCH});return not (isinstance(r,dict)and r.get("error"))
def latest(target):
 for r in runs(status="completed",pp=30):
  if r.get("name")==target:return r
 return None

def fire_all():
 wfs=["build-exe.yml","build-msi.yml","build-apk.yml","build-deb.yml","build-dmg.yml","build-web.yml"]
 log.info("Trigger all builds...")
 for w in wfs:ok=dispatch(w);log.info(f"  {w}:{'OK' if ok else 'FAIL'}");time.sleep(1)

def analyze(text,target):
 errs=[];lines=text.split("\n")
 for i,l in enumerate(lines):
  if any(re.search(p,l,re.I) for p in IGNORE):continue
  m=re.search(r"(error\[E\d{4}\])",l)
  if m:errs.append({"t":"rust","m":m.group(1),"l":i+1});continue
  m=re.search(r"(Error|ERROR|FAIL|fatal)[:\s]+(.+)",l)
  if m and not any(k in l for k in["warning:","note:","help:"]):errs.append({"t":"gen","m":l.strip()[:200],"l":i+1})
 s=set();u=[]
 for e in errs:
  k=e["m"][:80]
  if k not in s:s.add(k);u.append(e)
 return u[:20]

def find_fix(errors,target):
 t="\n".join(e["m"] for e in errors)
 best=None;bp=0
 for e in FIXES:
  if target not in e["t"] and "*" not in e["t"]:continue
  if e["p"].search(t):
   prio=len(e["p"].pattern)
   if prio>bp:bp=prio;best=e
 return best

def gclean():
 r=subprocess.run(["git","status","--porcelain"],capture_output=True,text=True,cwd=WORKDIR,timeout=30)
 return r.returncode==0 and r.stdout.strip()==""

def gpush(msg):
 subprocess.run(["git","add","-A"],cwd=WORKDIR,capture_output=True,timeout=30)
 r=subprocess.run(["git","diff","--cached","--quiet"],cwd=WORKDIR,capture_output=True,timeout=30)
 if r.returncode==0:log.info("  No changes");return True
 r=subprocess.run(["git","commit","-m",msg],cwd=WORKDIR,capture_output=True,text=True,timeout=30)
 log.info(f"  Commit:{r.stdout.strip()}")
 r=subprocess.run(["git","push","origin",BRANCH],cwd=WORKDIR,capture_output=True,text=True,timeout=120)
 if r.returncode!=0:log.error(f"  Push fail:{r.stderr.strip()[:300]}");return False
 log.info("  Push OK");return True

def heal(interval=60,maxl=100):
 log.info("="*60)
 log.info(f"LUODA Auto-Heal Started  Repo:{REPO}  Branch:{BRANCH}")
 log.info(f"Log:{lf}")
 log.info("="*60)
 fixed=set()
 for loop in range(1,maxl+1):
  log.info(f"LOOP {loop}/{maxl}")
  passing=True
  for target in BUILD_TARGETS:
   run=latest(target)
   if run is None:log.warning(f"  {target}:no runs");passing=False;continue
   conc=run.get("conclusion");rid=run.get("id");sha=run.get("head_sha","")[:12]
   log.info(f"  {target}:{rid} conc={conc}")
   if conc=="success":continue
   if conc=="failure":
    passing=False
    if sha in fixed:log.info(f"    skip {sha}");continue
    log.info("    fetch logs...")
    js=jobs(rid);txt=""
    for j in js:
     if j.get("conclusion")=="success":continue
     jl=jlogs(j.get("id"))
     if isinstance(jl,str):txt+=f"\n---{j.get('name')}---\n{jl}\n"
    if not txt:log.warning("    no logs");fixed.add(sha);continue
    errs=analyze(txt,target)
    if not errs:log.info("    no actionable");fixed.add(sha);continue
    log.info(f"    {len(errs)} errors")
    for e in errs[:5]:log.info(f"      {e['m'][:100]}")
    match=find_fix(errs,target)
    if not match:log.warning("    no fix");fixed.add(sha);continue
    log.info(f"    fix:{match['d']}")
    try:msg=match["f"](txt,{"target":target,"run_id":rid})
    except Exception as ex:log.error(f"    ex:{ex}");fixed.add(sha);continue
    if not msg:log.info("    no changes");fixed.add(sha);continue
    if gclean():log.info("    clean");fixed.add(sha);continue
    if gpush(msg):fixed.add(sha);log.info("    pushed!")
    time.sleep(5)
  if passing:
   ip=runs(status="in_progress",pp=10)
   rn=[r["name"] for r in ip if r.get("name") in BUILD_TARGETS]
   if rn:log.info(f"running:{rn}")
   else:log.info("ALL PASS! verification...");fire_all();return True
  log.info(f"wait {interval}s...");time.sleep(interval)
 log.warning("max loops");return False

if __name__=="__main__":
 ap=argparse.ArgumentParser()
 ap.add_argument("--interval",type=int,default=60)
 ap.add_argument("--max-loops",type=int,default=100)
 ap.add_argument("--trigger-now",action="store_true")
 ap.add_argument("--once",action="store_true")
 a=ap.parse_args()
 if not TOKEN:log.error("No GH_TOKEN");sys.exit(1)
 if a.trigger_now:fire_all()
 heal(a.interval,1 if a.once else a.max_loops)
