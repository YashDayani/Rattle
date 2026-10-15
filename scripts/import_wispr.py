#!/usr/bin/env python3
"""Import Wispr Flow data (history, dictionary, snippets, notes, meetings) into Rattle.
Non-destructive: merges by id, backs up Rattle's JSON first. Quit Rattle before --apply.
Usage: import_wispr.py [--apply]"""
import json, os, shutil, sqlite3, sys, tempfile, time, uuid
from datetime import datetime, timezone

HOME = os.path.expanduser("~/Library/Application Support")
WF = os.path.join(HOME, "Wispr Flow")
RT = os.path.join(HOME, "Rattle")
apply = "--apply" in sys.argv

def iso(s):
    if not s: return "1970-01-01T00:00:00Z"
    s = s.replace(" +00:00", "+00:00").replace(" ", "T")
    d = datetime.fromisoformat(s).astimezone(timezone.utc)
    return d.strftime("%Y-%m-%dT%H:%M:%SZ")

def uid(s):
    try: return str(uuid.UUID(s)).upper()
    except Exception: return str(uuid.uuid5(uuid.NAMESPACE_OID, s)).upper()

def load(name):
    p = os.path.join(RT, name + ".json")
    return json.load(open(p)) if os.path.exists(p) else []

def secs(ts):
    n = 0
    for part in ts.split(":"): n = n * 60 + int(part)
    return float(n)

# Copy DB + WAL so a running Wispr Flow is not disturbed
tmp = tempfile.mkdtemp()
for f in ("flow.sqlite", "flow.sqlite-wal", "flow.sqlite-shm"):
    if os.path.exists(os.path.join(WF, f)): shutil.copy(os.path.join(WF, f), tmp)
db = sqlite3.connect(os.path.join(tmp, "flow.sqlite")); db.row_factory = sqlite3.Row

out = {}
# History
hist = load("history"); have = {h["id"] for h in hist}; new = []
for r in db.execute("select * from History where coalesce(formattedText,asrText,'')!='' order by timestamp"):
    i = uid(r["transcriptEntityId"])
    if i in have: continue
    text = (r["editedText"] or r["formattedText"] or r["asrText"] or "").strip()
    new.append({"id": i, "date": iso(r["timestamp"]), "raw": r["asrText"] or text, "text": text,
                "duration": r["duration"] or 0, "appName": (r["app"] or "").split(".")[-1] or "Unknown",
                "bundleID": r["app"]})
out["history"] = (hist, new)
# Dictionary (words) and snippets
d = load("dictionary"); dw = {e["word"].lower() for e in d}; nd = []
sn = load("snippets"); st = {e["trigger"].lower() for e in sn}; ns = []
for r in db.execute("select * from Dictionary where isDeleted=0"):
    if r["isSnippet"]:
        if r["phrase"].lower() not in st and r["replacement"]:
            ns.append({"id": uid(r["id"]), "trigger": r["phrase"], "expansion": r["replacement"]}); st.add(r["phrase"].lower())
    elif r["phrase"].lower() not in dw:
        e = {"id": uid(r["id"]), "word": r["phrase"]}
        if r["replacement"]: e["replacement"] = r["replacement"]
        nd.append(e); dw.add(r["phrase"].lower())
out["dictionary"] = (d, nd); out["snippets"] = (sn, ns)
# Notes
notes = load("notes"); have = {n["id"] for n in notes}; nn = []
for r in db.execute("select * from Notes where isDeleted=0"):
    i = uid(r["id"])
    if i in have: continue
    nn.append({"id": i, "text": r["content"] or r["title"], "created": iso(r["createdAt"]),
               "updated": iso(r["modifiedAt"]), "pinned": bool(r["pinned"])})
out["notes"] = (notes, nn)
# Meetings
meet = load("meetings"); have = {m["id"] for m in meet}; nm = []
for r in db.execute("select * from Meetings where isDeleted=0 and isTourDemo=0"):
    i = uid(r["id"])
    if i in have: continue
    base = os.path.join(WF, "meetings", r["id"])
    lines = []
    for fn in ("refined.ndjson", "live.ndjson"):
        p = os.path.join(base, fn)
        if not os.path.exists(p): continue
        for ln in open(p, encoding="utf-8"):
            try: o = json.loads(ln)
            except Exception: continue
            if "text" not in o: continue
            sp = o.get("speaker") or {}
            who = "You" if sp.get("source") == "mic" else (sp.get("name") or "Others")
            lines.append({"id": str(uuid.uuid4()).upper(), "time": secs(o.get("timestamp", "0")),
                          "speaker": who, "text": o["text"].strip()})
        if lines: break
    dur = (r["recordedMs"] or 0) / 1000 or (lines[-1]["time"] if lines else 0)
    nm.append({"id": i, "title": r["title"], "date": iso(r["createdAt"]), "duration": dur, "lines": lines,
               "summary": r["summary"] or "", "capturedSystemAudio": False})
out["meetings"] = (meet, nm)

for k, (old, new) in out.items(): print(f"{k:11s} existing {len(old):4d}  +{len(new)} new")
if not apply: print("\nDry run. Quit Rattle, then re-run with --apply."); sys.exit()
bk = os.path.join(RT, "backup-before-wispr-import-" + time.strftime("%Y%m%d-%H%M%S")); os.makedirs(bk)
for k, (old, new) in out.items():
    p = os.path.join(RT, k + ".json")
    if os.path.exists(p): shutil.copy(p, bk)
    if new: json.dump(sorted(old + new, key=lambda x: x.get("date", x.get("created", "")), reverse=k in ("history", "meetings")) if k in ("history", "meetings") else old + new, open(p, "w"), indent=2, ensure_ascii=False)
print("Done. Backup in", bk)
