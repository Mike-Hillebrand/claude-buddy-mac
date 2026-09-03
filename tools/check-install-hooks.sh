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

python3 "$INSTALLER" >/dev/null
[ "$(ours)" = "12" ]                    || { echo "FAIL: not idempotent, got $(ours)"; exit 1; }

python3 "$INSTALLER" --uninstall >/dev/null
[ "$(ours)" = "0" ]                     || { echo "FAIL: uninstall left $(ours)"; exit 1; }
[ "$(other)" = "echo other" ]           || { echo "FAIL: foreign hook lost on uninstall"; exit 1; }
echo "OK $INSTALLER"
