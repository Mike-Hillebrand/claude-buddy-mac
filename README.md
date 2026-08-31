# Buddy — a Claude desktop pet for macOS

A little pixel buddy that floats on your desktop (no window, no card) and shows what **Claude Code**
is doing right now — thinking, working, waiting for you, done — from the hooks it fires locally.

<p align="center"><img src="docs/buddy.gif" width="250" alt="Buddy cycling through sleeping, idle, thinking, working, needs-you and done"></p>

Built with plain `swiftc` — no Xcode, no developer account, no 7-day signing expiry.

## What it shows

| State      | Source (Claude Code hooks)                          |
|------------|-----------------------------------------------------|
| working    | `PreToolUse` — a tool is running                    |
| thinking   | between your prompt and the next tool call          |
| needs you  | permission prompt / idle prompt                     |
| ready      | `Stop` — the turn finished                          |
| sleeping   | no active session                                   |

Reactions: confetti + sound when something finishes, jumping `!` when Claude needs you, `x` eyes on
errors, hearts when you click it, breathing / blinking / the occasional wink while idle, arms that
wiggle while working. Drag it anywhere (position is remembered). Right-click or the paw icon in the
menu bar opens the menu; a menu entry reveals the active session's project folder in Finder.

Extras: **wander mode** (Behavior menu) lets the buddy stroll along the edges of the screen — never
across it — with a proper walk cycle, pausing when Claude needs you or your cursor comes close.
And it plays **tic-tac-toe** (menu → 🎮): you are X, it thinks for a moment, gloats when it wins and
sulks when it loses. It plays well but not perfectly, so you can beat it.

**Local usage line** (Behavior → *Show usage*, on by default): a small line under the buddy with
today's Claude Code tokens and turn count — e.g. `⚡ 108M heute · 313×` — read straight from Claude
Code's own logs in `~/.claude/projects`. No network, no cookies (see *Privacy & security*). It also
keeps the buddy **awake** while there's recent local activity or the Claude app is open: it dozes with
its eyes open instead of dropping to sleep the moment a turn ends.

**Voice button:** the round microphone under the buddy opens Claude's *Quick Entry* (the panel you
normally get by double-tapping ⌥) — press Caps Lock there to dictate (enable dictation once in Claude's
Quick Entry settings). Buddy simulates the ⌥⌥ shortcut, so macOS asks once for Accessibility access;
without it the click falls back to opening a new chat. ⌥-click always opens a new chat. Hide it via
Behavior → *Show voice button*.

## Look

- **Style:** pixel (filled, automatic outline + bevel — default) or ASCII (terminal look, 5×12 chars).
- **Species:** pixel: Clawd, Blob, Cat, Duck, Ghost, Robot, Penguin, Octopus, Rabbit · ASCII: 18 species.
- **Hat, eyes, color, size** (S/M/L/XL), card behind the buddy on/off, outline & shading on/off.
- **Language:** German or English (menu → Language); defaults to German on German systems, English elsewhere.
- Default species / hat / eyes are rolled deterministically from your account id ("Shuffle" in the menu).

## How it reads Claude's state

**Claude Code hooks** (real-time, fully local): `hooks/buddy-hook.sh` appends every hook event as one
JSON line to `~/Library/Application Support/Buddy/events.jsonl`; Buddy tails that file. Works for the
terminal, IDE extensions and the Claude Code tab of the desktop app. No network, no credentials — the
file never leaves your machine.

## Privacy & security

Buddy makes **exactly one network request**: an unauthenticated `GET` to the public GitHub Releases
API to check whether a newer version exists (menu → Behavior → *Check for updates*, on by default,
toggleable). That request carries no cookies and nothing about your account.

The **usage line** reads Claude Code's own local log files under `~/.claude/projects` (the same JSONL
Claude Code writes for itself) and sums today's tokens on your machine. It is a plain local file read —
no network request, no cookie, no keychain, no Anthropic API. Turn it off with Behavior → *Show usage*.

Buddy does **not** read your Claude session cookie, keychain, or any Anthropic API. Earlier versions
(≤ 1.2.0) polled internal Anthropic endpoints by reusing the desktop app's `sessionKey` cookie from a
third process — that looks like session-token replay to anti-abuse systems and could get your whole
account signed out across devices. **1.3.0 removed that entirely** (verify with
`strings Buddy.app/Contents/MacOS/Buddy | grep -i sessionkey` → no matches). If you ran an older
version and saw repeated logouts, update.

## Requirements

- macOS 14+ (release zips are Apple Silicon; Intel builds from source)
- Xcode Command Line Tools (`xcode-select --install`) — that's all, no Xcode
- Claude Code (for the hooks)

## Install

**Download:** grab `Buddy-<version>-arm64.zip` from [Releases](https://github.com/Mike-Hillebrand/claude-buddy-mac/releases),
unzip, move `Buddy.app` to `/Applications`. The build is ad-hoc signed (no Apple developer account),
so Gatekeeper will refuse it once. Clear the quarantine flag and it runs:

```sh
xattr -dr com.apple.quarantine /Applications/Buddy.app
open /Applications/Buddy.app
```

**Or build it yourself** (Command Line Tools are enough):

```sh
./build.sh            # → build/Buddy.app
./build.sh install    # build, copy to /Applications, (re)launch
./build.sh release    # build + zip for a release
```

"Launch at login" is in the menu (SMAppService).

## Hooks

Menu → **Behavior → Install Claude Code hooks…**, or manually:

```sh
python3 hooks/install-hooks.py             # merges into ~/.claude/settings.json (backup: settings.json.buddy-backup)
python3 hooks/install-hooks.py --uninstall
```

The hooks are `async` and add no latency to Claude Code. Running sessions pick them up after a restart.

## Project layout

```
Sources/Core/   sprites (ASCII + pixel, hats, eyes, speech bubble), localization + state model — Foundation only, tested
Sources/App/    AppKit/SwiftUI: panel, view, menu, hook watcher, API client, settings
Resources/      app icon (rendered from the Clawd sprite; .icns is generated at build time)
hooks/          buddy-hook.sh, install-hooks.py
tools/          demo.sh (records the feature demo via `Buddy --demo`), uiclick.swift (synthetic clicks), screens.swift
Tests/          CoreTests.swift (also runs on Linux Swift)
```

Core tests: copy `Tests/CoreTests.swift` to `main.swift`, then
`swiftc -swift-version 5 Sources/Core/*.swift main.swift -o /tmp/t && /tmp/t`.

## Demo mode

`Buddy --demo` reads commands from `~/Library/Application Support/Buddy/cmd.txt` (one per line:
`state working Edit`, `species cat`, `hat crown`, `theme lime`, `wander 1 -1`,
`walk-now 14`, `game`, `move 4`, `menu`, `pet`, `quip <text>`, …) and ignores real hook events, so a
script can walk it through every feature for a recording — see `tools/demo.sh`. Other flags:
`--no-greeting`, `--game`, `--walk-now`, `--wander-dir=-1`.

## Drawing your own pixel species

`Sources/Core/PixelSprites.swift`: 16×14 grid, 2–3 frames. Legend: `.` empty, `#` body, `s` shade,
`l` light, `w` white, `d` dark, `a` accent (yellow), `e` eye slot (2×2 or 2×3). Outline and bevel
are added automatically.

## Authors

[Mike Hillebrand](https://github.com/Mike-Hillebrand) · [Mike Hillebrand Media](https://github.com/MikeHillebrandMedia) — built together with Claude.

## Notes

Not affiliated with Anthropic; the sprites are original pixel art.

## License

MIT — see [LICENSE](LICENSE).
