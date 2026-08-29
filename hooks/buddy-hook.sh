#!/bin/sh
# Buddy hook — called by Claude Code hooks with the event name as $1.
# Reads the hook JSON from stdin, extracts a few fields and appends one
# compact JSON line to the Buddy events file. Never blocks, never fails.
EV="${1:-unknown}"
DIR="$HOME/Library/Application Support/Buddy"
mkdir -p "$DIR" 2>/dev/null
IN=$(head -c 8000 2>/dev/null)

# Extract "key":"value" (first match). Values are kept JSON-escaped as-is.
get() {
  printf '%s' "$IN" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1 | cut -c1-300
}

SID=$(get session_id)
CWD=$(get cwd)
TOOL=$(get tool_name)
MSG=$(get message)
NT=$(get notification_type)
AT=$(get agent_type)
TS=$(date +%s)

# Strip a dangling backslash that could break JSON after truncation.
MSG=$(printf '%s' "$MSG" | sed 's/\\$//')
CWD=$(printf '%s' "$CWD" | sed 's/\\$//')

printf '{"ts":%s,"event":"%s","session":"%s","cwd":"%s","tool":"%s","type":"%s","agent":"%s","msg":"%s"}\n' \
  "$TS" "$EV" "$SID" "$CWD" "$TOOL" "$NT" "$AT" "$MSG" >> "$DIR/events.jsonl" 2>/dev/null

exit 0
