#!/bin/sh
# Plan limits (5h / 7d) for the buddy from the OAuth usage endpoint, using Claude Code's own token.
# Decision 03.09.2026 (Mike): accepted the credential-reuse risk for this endpoint after the 1.3.0
# cookie incident. Guard rails — keep them:
#   GET only · never refreshes or rewrites the token · skips when the token is expired ·
#   token travels stdin → python, never argv or logs · only while Claude Code is active
#   (called from buddy-hook.sh) · silent on any error.
#
# Throttle: the endpoint's own limit is far tighter than it looks — a burst of manual testing
# on 03.09.2026 drew a 429 with Retry-After: 3572s (~1h), not the few-minutes-scale rate limiting
# most endpoints use. 20 min between requests leaves 3x headroom under that. On a 429 the marker
# is pushed out by the server's own Retry-After instead of retrying every 20 min into the same wall.
DIR="$HOME/Library/Application Support/Buddy"
OUT="$DIR/usage-snapshot.json"; MARK="$DIR/.usage-fetch-at"; THROTTLE=1200
mkdir -p "$DIR" 2>/dev/null
if [ -f "$MARK" ] && [ $(( $(date +%s) - $(stat -f %m "$MARK") )) -lt "$THROTTLE" ]; then exit 0; fi
touch "$MARK"
PROG=$(cat <<'PY'
import json, os, sys, time, datetime as dt, urllib.request, urllib.error
out, mark, throttle = sys.argv[1], sys.argv[2], int(sys.argv[3])

def iso(s):   # "2026-09-03T10:00:00.621024+00:00" → "2026-09-03T10:00:00Z" (what Buddy parses)
    if not s:
        return None
    try:
        return dt.datetime.fromisoformat(str(s).replace("Z", "+00:00")).astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        return str(s)

def bar(x):
    x = x or {}
    u = x.get("utilization")   # 0-100
    return {"pct": round(u) if isinstance(u, (int, float)) else 0, "resetsAt": iso(x.get("resets_at"))}

def defer(seconds):
    # Push the throttle marker's mtime forward so the shell-level check skips until then,
    # instead of re-hitting a still-active server rate limit every `throttle` seconds.
    future = time.time() + max(0, seconds - throttle)
    try:
        os.utime(mark, (future, future))
    except Exception:
        pass

fake = os.environ.get("BUDDY_USAGE_FAKE")   # tests: response JSON, no keychain, no network
if fake:
    d = json.loads(fake)
else:
    try:
        o = (json.load(sys.stdin) or {}).get("claudeAiOauth") or {}
    except Exception:
        sys.exit(0)
    tok, exp = o.get("accessToken"), o.get("expiresAt")
    if not tok or (isinstance(exp, (int, float)) and exp / 1000 < time.time()):
        sys.exit(0)   # expired: the CLI refreshes its token, never us
    req = urllib.request.Request("https://api.anthropic.com/api/oauth/usage", headers={
        "Authorization": "Bearer " + tok, "anthropic-beta": "oauth-2025-04-20",
        "Content-Type": "application/json",
        "User-Agent": "Buddy/1.6 (+https://github.com/Mike-Hillebrand/claude-buddy-mac)"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            d = json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 429:
            defer(int(e.headers.get("Retry-After", "3600")))
        sys.exit(0)   # the buddy simply keeps the last snapshot
    except Exception:
        sys.exit(0)

snap = {"session": bar(d.get("five_hour")), "weeklyAll": bar(d.get("seven_day")),
        "updatedAt": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "error": None}
def write(path):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(snap, f)
    os.replace(tmp, path)

write(out)
# ponytail: Buddy <= 1.6.0 still reads the old Claude-Usage widget path (a symlink won't do:
# NSURL reports the link's own mtime). Drop this once every install is on the rebuilt Buddy.
legacy = os.path.expanduser("~/Library/Group Containers/group.com.claude.usage-widget/usage-snapshot.json")
if os.path.isdir(os.path.dirname(legacy)) and not os.path.islink(legacy):
    write(legacy)
PY
)
if [ -n "$BUDDY_USAGE_FAKE" ]; then exec python3 -c "$PROG" "$OUT" "$MARK" "$THROTTLE" </dev/null; fi
security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | python3 -c "$PROG" "$OUT" "$MARK" "$THROTTLE"
