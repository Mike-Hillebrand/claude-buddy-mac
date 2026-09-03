#!/bin/sh
# Runs hooks/install-hooks.py against a throwaway HOME and checks: 12 events registered, foreign
# hooks and settings kept, file mode kept (600), idempotent, --uninstall removes only ours.
set -e
cd "$(dirname "$0")/.."
INSTALLER="${INSTALLER:-hooks/install-hooks.py}"   # point at another copy to compare versions
export HOME="$PWD/build/check-home.$$"   # under the repo, not TMPDIR (sandboxes block /var/folders)
trap 'rm -rf "$HOME"' EXIT
S="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
printf '%s\n' '{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo other"}]}]}}' > "$S"
chmod 600 "$S"
ours() { jq '[.hooks[][].hooks[] | select(.command | test("buddy-hook.sh"))] | length' "$S"; }
other() { jq -r '.hooks.Stop[] | .hooks[] | select(.command == "echo other") | .command' "$S"; }

python3 "$INSTALLER" >/dev/null
[ "$(stat -f %Lp "$S")" = "600" ]      || { echo "FAIL: mode became $(stat -f %Lp "$S")"; exit 1; }
[ "$(ours)" = "12" ]                    || { echo "FAIL: expected 12 buddy entries, got $(ours)"; exit 1; }
[ "$(other)" = "echo other" ]           || { echo "FAIL: foreign hook lost"; exit 1; }
[ "$(jq -r .model "$S")" = "opus" ]     || { echo "FAIL: foreign setting lost"; exit 1; }
[ -x "$HOME/Library/Application Support/Buddy/buddy-hook.sh" ] || { echo "FAIL: hook script not installed"; exit 1; }
case "$(jq -r '.statusLine.command' "$S")" in *buddy-statusline.sh*) ;; *) echo "FAIL: statusLine not set"; exit 1;; esac

# statusline script: writes the snapshot from rate_limits and prints one line
SNAP="$HOME/Library/Application Support/Buddy/usage-snapshot.json"
LINE=$(printf '%s' '{"model":{"display_name":"Fable 5.1"},"context_window":{"used_percentage":35.2},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1788440000},"seven_day":{"used_percentage":61,"resets_at":"2026-09-03T20:19:08Z"}}}' | "$HOME/Library/Application Support/Buddy/buddy-statusline.sh")
[ "$LINE" = "Fable 5.1 · ctx 35% · 5h 42% · 7d 61%" ] || { echo "FAIL: status line was '$LINE'"; exit 1; }
[ "$(jq -r '.session.pct' "$SNAP")" = "42" ]                          || { echo "FAIL: snapshot session.pct"; exit 1; }
[ "$(jq -r '.session.resetsAt' "$SNAP")" = "2026-09-03T12:53:20Z" ]   || { echo "FAIL: unix resets_at not converted: $(jq -r .session.resetsAt "$SNAP")"; exit 1; }
[ "$(jq -r '.weeklyAll.resetsAt' "$SNAP")" = "2026-09-03T20:19:08Z" ] || { echo "FAIL: ISO resets_at not kept"; exit 1; }
printf '%s' '{"model":{"display_name":"x"}}' | "$HOME/Library/Application Support/Buddy/buddy-statusline.sh" >/dev/null
[ "$(jq -r '.session.pct' "$SNAP")" = "42" ]                          || { echo "FAIL: snapshot clobbered when rate_limits missing"; exit 1; }

python3 "$INSTALLER" >/dev/null
[ "$(ours)" = "12" ]                    || { echo "FAIL: not idempotent, got $(ours)"; exit 1; }

python3 "$INSTALLER" --uninstall >/dev/null
[ "$(ours)" = "0" ]                     || { echo "FAIL: uninstall left $(ours)"; exit 1; }
[ "$(other)" = "echo other" ]           || { echo "FAIL: foreign hook lost on uninstall"; exit 1; }
[ "$(jq -r '.statusLine' "$S")" = "null" ] || { echo "FAIL: statusLine not removed on uninstall"; exit 1; }
echo "OK $INSTALLER"
