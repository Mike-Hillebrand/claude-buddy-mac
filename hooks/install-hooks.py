#!/usr/bin/env python3
"""Install / remove the Buddy hooks in ~/.claude/settings.json (idempotent).

  python3 install-hooks.py            # install or refresh
  python3 install-hooks.py --uninstall
"""
import json, os, shutil, stat, sys, time

HOME = os.path.expanduser("~")
SETTINGS = os.path.join(HOME, ".claude", "settings.json")
APP_DIR = os.path.join(HOME, "Library", "Application Support", "Buddy")
HOOK_DST = os.path.join(APP_DIR, "buddy-hook.sh")
HOOK_SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "buddy-hook.sh")
MARK = "buddy-hook.sh"

EVENTS = [
    "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SubagentStart",
    "SubagentStop", "PreCompact",
]


def load():
    if not os.path.exists(SETTINGS):
        return {}
    with open(SETTINGS, "r", encoding="utf-8") as f:
        raw = f.read().strip()
    return json.loads(raw) if raw else {}


def save(data):
    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    backup = SETTINGS + ".buddy-backup"
    if os.path.exists(SETTINGS) and not os.path.exists(backup):
        shutil.copy2(SETTINGS, backup)
    tmp = SETTINGS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, SETTINGS)


def strip_ours(hooks):
    """Remove every hook group that references buddy-hook.sh. Returns cleaned dict."""
    cleaned = {}
    for event, groups in (hooks or {}).items():
        kept = []
        for g in groups or []:
            inner = [h for h in (g.get("hooks") or []) if MARK not in str(h.get("command", ""))]
            if inner:
                g = dict(g)
                g["hooks"] = inner
                kept.append(g)
        if kept:
            cleaned[event] = kept
    return cleaned


def main():
    uninstall = "--uninstall" in sys.argv
    data = load()
    hooks = strip_ours(data.get("hooks", {}))

    if uninstall:
        if hooks:
            data["hooks"] = hooks
        else:
            data.pop("hooks", None)
        save(data)
        print("Buddy hooks removed from", SETTINGS)
        return

    os.makedirs(APP_DIR, exist_ok=True)
    shutil.copyfile(HOOK_SRC, HOOK_DST)
    os.chmod(HOOK_DST, os.stat(HOOK_DST).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    cmd_path = HOOK_DST.replace('"', '\\"')
    for ev in EVENTS:
        entry = {
            "hooks": [{
                "type": "command",
                "command": f'"{cmd_path}" {ev}',
                "timeout": 5,
                "async": True,
            }]
        }
        hooks.setdefault(ev, []).append(entry)

    data["hooks"] = hooks
    save(data)
    print(f"Buddy hooks installed for {len(EVENTS)} events → {SETTINGS}")
    print(f"Hook script: {HOOK_DST}")
    print("Backup of your previous settings:", SETTINGS + ".buddy-backup")


if __name__ == "__main__":
    main()
