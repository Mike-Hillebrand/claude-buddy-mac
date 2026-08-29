#!/bin/zsh
# Records a full feature demo of Buddy into /tmp/demo/buddy-demo.mov (9:16 region; REGION assumes a
# second display to the right of a 2560-pt main display — adjust REGION and the click coordinates for your setup).
# Drives the app through its --demo command channel + synthetic clicks (uiclick) for the game.
set -e
zmodload zsh/datetime
B="$HOME/Library/Application Support/Buddy"
CMD="$B/cmd.txt"
UI="$(dirname "$0")/../build/uiclick"       # build once: swiftc -O -o build/uiclick tools/uiclick.swift
APP="$(dirname "$0")/../build/Buddy.app/Contents/MacOS/Buddy"
OUT=/tmp/demo/buddy-demo.mov
REGION="2560,24,797,1416"     # below the menu bar, 9:16
DUR=${DUR:-124}

c() { print -r -- "$1" >> "$CMD"; }          # queue a demo command
say() { c "quip $1"; }

mkdir -p /tmp/demo
pkill -x Buddy 2>/dev/null || true; sleep 1
rm -f "$CMD" "$B/game-frame.txt" "$B/game-state.txt"
defaults write com.mikehillebrand.buddy panelX -int 2566
defaults write com.mikehillebrand.buddy panelY -int 6
defaults write com.mikehillebrand.buddy wander -bool false
defaults write com.mikehillebrand.buddy pollCowork -bool false
defaults write com.mikehillebrand.buddy pollChats -bool false
defaults write com.mikehillebrand.buddy size l
defaults write com.mikehillebrand.buddy usage bar
defaults write com.mikehillebrand.buddy species clawd
defaults write com.mikehillebrand.buddy hat none
defaults write com.mikehillebrand.buddy theme red
("$APP" --demo --no-greeting >/dev/null 2>&1 &)
sleep 3
"$UI" move 3700 300          # cursor out of the recorded region

rm -f "$OUT"
(screencapture -v -k -x -R "$REGION" -V "$DUR" "$OUT" &)
sleep 2.5
T0=$EPOCHREALTIME
at() { local d=$(( T0 + $1 - EPOCHREALTIME )); (( d > 0 )) && sleep $d; return 0; }

c "clear"
at 1;  say "Hi, ich bin Buddy."
at 5;  c "state idle"
at 7;  c "state thinking"
at 10; c "state working Edit"
at 16; c "state attention Erlauben: Bash"
at 21; c "state ready"
at 26; c "pet"
at 29; c "state idle"
at 30; c "menu"
at 31.5; "$UI" key 125; sleep 0.4; "$UI" key 125; sleep 0.4; "$UI" key 125; sleep 0.4; "$UI" key 125
at 34; "$UI" key 53; sleep 0.5; "$UI" click 3600 400; sleep 0.3; "$UI" move 3700 300     # Escape, plus a click outside as fallback
at 35; c "species cat"
at 38; c "species ghost"
at 41; c "species robot"
at 44; c "species clawd"
at 46; c "hat crown"
at 48; c "theme terracotta"
at 50; c "theme lime"
at 52; c "theme red"
at 53; c "hat none"
at 54; c "usage ticker"
at 61; c "usage bar"
at 62; c "wander 1 -1"; c "walk-now 14"
at 77; c "wander 0"
at 79; c "game"
sleep 2
# --- play: read frame, compute cell centres (CG coords), click while it's our turn
FR=$(cat "$B/game-frame.txt")                       # {{x, y}, {w, h}}
FX=$(echo "$FR" | sed -E 's/\{\{([0-9.-]+), ([0-9.-]+)\}, \{([0-9.-]+), ([0-9.-]+)\}\}/\1/')
FY=$(echo "$FR" | sed -E 's/\{\{([0-9.-]+), ([0-9.-]+)\}, \{([0-9.-]+), ([0-9.-]+)\}\}/\2/')
FH=$(echo "$FR" | sed -E 's/\{\{([0-9.-]+), ([0-9.-]+)\}, \{([0-9.-]+), ([0-9.-]+)\}\}/\4/')
CGTOP=$(( 1440 - (${FY%.*} + ${FH%.*}) ))
cellxy() { local i=$1; local r=$((i / 3)); local col=$((i % 3)); echo "$(( ${FX%.*} + 81 + col * 58 )) $(( CGTOP + 73 + r * 58 ))"; }
prefs=(4 0 8 2 6 1 3 5 7)
for round in 1 2 3 4 5; do
  for w in $(seq 1 40); do
    ST=$(cat "$B/game-state.txt" 2>/dev/null || echo "......... turn=O over=0 thinking=1")
    CELLS=${ST%% *}
    [[ "$ST" == *"over=1"* ]] && break 2
    [[ "$ST" == *"turn=X"* && "$ST" == *"thinking=0"* ]] && break
    sleep 0.25
  done
  [[ "$ST" == *"over=1"* ]] && break
  for i in $prefs; do
    if [[ "${CELLS:$i:1}" == "." ]]; then
      read x y <<< "$(cellxy $i)"
      "$UI" move $x $y; sleep 0.35; "$UI" click $x $y
      break
    fi
  done
  sleep 1.2
done
sleep 4
"$UI" move 3700 600
c "game-close"
sleep 2; say "Bis später!"
sleep 4; c "state sleeping"
at $((DUR + 4))
sleep 2
ls -la "$OUT"
# restore polling (size/wander: set them back to your own preference)
defaults write com.mikehillebrand.buddy pollCowork -bool true
defaults write com.mikehillebrand.buddy pollChats -bool true
