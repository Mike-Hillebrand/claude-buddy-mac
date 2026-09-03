#!/bin/sh
# Buddy status line. Claude Code pipes its status JSON to stdin on every update. Two jobs:
#  1. write the plan limits (rate_limits.five_hour / seven_day) to Buddy's snapshot file, so the
#     buddy shows "⏳ 5h 42% → 15:12 · Woche 61% → Do 22:19" — official data from the CLI's own
#     rate-limit headers; no cookie, no keychain, no network of our own
#  2. print one line for the terminal
DIR="$HOME/Library/Application Support/Buddy"
mkdir -p "$DIR" 2>/dev/null
PROG=$(cat <<'PY'
import json, sys, os, datetime as dt
out = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
rl = d.get("rate_limits") or {}

def iso(v):
    if v is None:
        return None
    if isinstance(v, (int, float)):   # unix seconds
        return dt.datetime.fromtimestamp(v, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return str(v)                     # already ISO 8601

def pct(x):
    p = (x or {}).get("used_percentage", (x or {}).get("utilization"))
    return round(p) if isinstance(p, (int, float)) else None

def bar(x):
    return {"pct": pct(x) or 0, "resetsAt": iso((x or {}).get("resets_at"))}

if rl.get("five_hour") or rl.get("seven_day"):
    snap = {"session": bar(rl.get("five_hour")), "weeklyAll": bar(rl.get("seven_day")),
            "updatedAt": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "error": None}
    tmp = out + ".tmp"
    with open(tmp, "w") as f:
        json.dump(snap, f)
    os.replace(tmp, out)

parts = []
name = (d.get("model") or {}).get("display_name")
if name:
    parts.append(name)
cw = (d.get("context_window") or {}).get("used_percentage")
if isinstance(cw, (int, float)):
    parts.append("ctx %d%%" % round(cw))
for label, key in (("5h", "five_hour"), ("7d", "seven_day")):
    p = pct(rl.get(key))
    if p is not None:
        parts.append("%s %d%%" % (label, p))
print(" · ".join(parts))
PY
)
exec python3 -c "$PROG" "$DIR/usage-snapshot.json"
