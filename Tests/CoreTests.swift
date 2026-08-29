import Foundation

// Minimal self-checking harness for the platform-independent core (runs on Linux too).
var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if !cond { failures += 1; print("FAIL: \(msg)") }
}

// 1. Every species: 3 frames × 5 rows × 12 cols, at least one eye slot.
for sp in SpriteBank.all {
    check(sp.frames.count == 3, "\(sp.id): frame count \(sp.frames.count)")
    for (fi, f) in sp.frames.enumerated() {
        check(f.count == 5, "\(sp.id) f\(fi): row count \(f.count)")
        for (ri, r) in f.enumerated() {
            check(r.count == 12, "\(sp.id) f\(fi) r\(ri): width \(r.count) → '\(r)'")
        }
        check(f.joined().contains("@"), "\(sp.id) f\(fi): no eye slot")
    }
}

// 2. Render with hats/eyes keeps geometry.
for sp in SpriteBank.all {
    for hat in Hat.allCases {
        for eyes in EyeStyle.allCases {
            let rows = SpriteComposer.render(look: SpriteLook(species: sp, hat: hat, eyes: eyes), frame: 1)
            check(rows.count == 5 && rows.allSatisfy { $0.count == 12 }, "\(sp.id)/\(hat)/\(eyes): geometry")
            check(!rows.joined().contains("@"), "\(sp.id): eye slot not replaced")
        }
    }
}
let blink = SpriteComposer.render(look: SpriteLook(species: SpriteBank.species(id: "cat"), hat: .crown, eyes: .dot), frame: 0, eyeOverride: "-")
check(blink[2].contains("-"), "blink override")

// 3. Bubble wrapping/box.
let box = Bubble.box("Steppenwolf Charakterisierung: Erlauben: Bash · rm -rf build")
check(box.count <= 5, "bubble max 5 lines, got \(box.count)")
check(box.allSatisfy { $0.count == box[0].count }, "bubble rows equal width")
check(box[box.count - 1].contains("┬"), "bubble tail")
check(Bubble.box("").isEmpty, "empty bubble")
let long = Bubble.wrap("EinSehrLangesWortOhneLeerzeichenDasNichtPasst")
check(long.count == 1 && long[0].count <= Bubble.maxWidth, "long word truncated: \(long)")

// 4. Store: hook lifecycle.
let store = SessionStore()
var clock = Date(timeIntervalSince1970: 1_800_000_000)
store.now = { clock }
func ev(_ json: String) -> SessionStore.HookEvent { SessionStore.HookEvent(jsonLine: json)! }
let sid = "abc-123"
let base = "\"session\":\"\(sid)\",\"cwd\":\"/Users/mike/Projects/website\""
store.apply(hook: ev("{\"ts\":1800000000,\"event\":\"SessionStart\",\(base),\"tool\":\"\",\"type\":\"\",\"agent\":\"\",\"msg\":\"\"}"))
check(store.globalState == .idle, "after SessionStart idle, got \(store.globalState)")
check(store.focus?.title == "website", "title from cwd")
store.apply(hook: ev("{\"ts\":1800000001,\"event\":\"UserPromptSubmit\",\(base),\"tool\":\"\",\"type\":\"\",\"agent\":\"\",\"msg\":\"\"}"))
check(store.globalState == .thinking, "thinking after prompt")
store.apply(hook: ev("{\"ts\":1800000002,\"event\":\"PreToolUse\",\(base),\"tool\":\"Bash\",\"type\":\"\",\"agent\":\"\",\"msg\":\"\"}"))
check(store.globalState == .working && store.focus?.detail == "Bash", "working with tool")
store.apply(hook: ev("{\"ts\":1800000003,\"event\":\"Notification\",\(base),\"tool\":\"\",\"type\":\"permission_prompt\",\"agent\":\"\",\"msg\":\"Claude needs your permission to use Bash\"}"))
check(store.globalState == .attention, "attention on permission prompt")
check(store.focus?.detail == "Erlauben: Bash", "permission detail → \(store.focus?.detail ?? "nil")")
check(store.moments.last?.kind == .attention, "attention moment")
store.apply(hook: ev("{\"ts\":1800000004,\"event\":\"PreToolUse\",\(base),\"tool\":\"Bash\",\"type\":\"\",\"agent\":\"\",\"msg\":\"\"}"))
store.apply(hook: ev("{\"ts\":1800000005,\"event\":\"Stop\",\(base),\"tool\":\"\",\"type\":\"\",\"agent\":\"\",\"msg\":\"\"}"))
check(store.globalState == .ready, "ready after Stop, got \(store.globalState)")
check(store.moments.last?.kind == .done, "done moment after Stop")
store.apply(hook: ev("{\"ts\":1800000006,\"event\":\"SessionEnd\",\(base),\"tool\":\"\",\"type\":\"\",\"agent\":\"\",\"msg\":\"\"}"))
check(store.globalState == .sleeping, "sleeping after SessionEnd")

// 5. Store: API sessions.
func apiSession(_ id: String, worker: String, bucket: String, unread: Bool = true, age: TimeInterval = 10, tags: [String] = ["product:cowork-remote"], status: String = "active") -> SessionStore.APISession {
    SessionStore.APISession(id: id, title: "Session \(id)", status: status, workerStatus: worker, bucket: bucket, unread: unread, lastEvent: clock.addingTimeInterval(-age), tags: tags, actionDetail: "")
}
store.apply(api: [
    apiSession("a", worker: "running", bucket: "working"),
    apiSession("b", worker: "idle", bucket: "blocked", age: 3 * 3600),      // stale → ignored
    apiSession("c", worker: "idle", bucket: "review_ready", age: 60),
    apiSession("d", worker: "idle", bucket: "completed", status: "archived"),
])
check(store.sessions.count == 2, "api: 2 tracked, got \(store.sessions.count) → \(store.sessions.keys.sorted())")
check(store.globalState == .working, "api: running wins")
store.apply(api: [apiSession("a", worker: "idle", bucket: "review_ready"), apiSession("c", worker: "idle", bucket: "review_ready", age: 60)])
check(store.globalState == .ready && store.moments.last?.kind == .done, "api: running → review_ready celebrates")
store.apply(api: [apiSession("a", worker: "requires_action", bucket: "working")])
check(store.globalState == .attention && store.focus?.detail == "Freigabe nötig", "api: requires_action → attention")
check(store.sessions.count == 1, "api: vanished sessions dropped")

// 6. Dedup: bridge code sessions hidden while hooks are active.
store.removeAll()
store.apply(hook: ev("{\"ts\":1800000000,\"event\":\"PreToolUse\",\(base),\"tool\":\"Edit\",\"type\":\"\",\"agent\":\"\",\"msg\":\"\"}"))
store.apply(api: [apiSession("x", worker: "running", bucket: "working", tags: ["remote-control-sdk"])])
check(store.sessions.count == 1, "bridge duplicate hidden while hooks active")
clock = clock.addingTimeInterval(31 * 60)
store.prune()
check(store.sessions.isEmpty, "stale hook session pruned")
store.apply(api: [apiSession("x", worker: "running", bucket: "working", tags: ["remote-control-sdk"])])
check(store.sessions.count == 1 && store.focus?.source == .code, "bridge session used when hooks silent")

// 7. Chats.
store.removeAll()
store.apply(chats: [SessionStore.ChatConversation(id: "c1", title: "Research", needsInput: true, liveStatus: nil, updated: clock.addingTimeInterval(-60)),
                    SessionStore.ChatConversation(id: "c2", title: "Old", needsInput: true, liveStatus: nil, updated: clock.addingTimeInterval(-5 * 3600))])
check(store.sessions.count == 1 && store.globalState == .attention, "chat needs_input → attention")

// 8. Deterministic look.
let l1 = LookGenerator.look(for: "5f4f7b9d"), l2 = LookGenerator.look(for: "5f4f7b9d")
check(l1.species.id == l2.species.id && l1.hat == l2.hat && l1.eyes == l2.eyes, "deterministic look")

// 8b. Pixel species geometry + renderer.
for sp in PixelBank.all {
    check(sp.frames.count >= 2, "pixel \(sp.id): frame count")
    for (fi, f) in sp.frames.enumerated() {
        check(f.count == PixelBank.rows, "pixel \(sp.id) f\(fi): rows \(f.count)")
        for (ri, r) in f.enumerated() { check(r.count == PixelBank.cols, "pixel \(sp.id) f\(fi) r\(ri): width \(r.count) '\(r)'") }
        let eyes = f.joined().filter { $0 == "e" }.count
        check(eyes == 8 || eyes == 4 || eyes == 12, "pixel \(sp.id) f\(fi): expected 2×2 eye slots, got \(eyes) cells")
    }
    for (fi, f) in sp.walk.enumerated() {
        check(f.count == PixelBank.rows && f.allSatisfy { $0.count == PixelBank.cols }, "pixel \(sp.id) walk f\(fi): geometry")
    }
    if !sp.walk.isEmpty {
        let w0 = PixelRenderer.render(species: sp, frame: 0, hat: .none, eyes: .dot, walking: true)
        let w1 = PixelRenderer.render(species: sp, frame: 1, hat: .none, eyes: .dot, walking: true)
        check(w0 != w1, "pixel \(sp.id): walk frames differ")
    }
    for hat in Hat.allCases {
        for ov: Character? in [nil, "-", "O", "^", "x"] {
            let px = PixelRenderer.render(species: sp, frame: 0, hat: hat, eyes: .dot, eyeOverride: ov)
            check(!px.isEmpty, "pixel render empty")
            check(px.allSatisfy { $0.x >= -1 && $0.x <= PixelBank.cols && $0.y >= -PixelBank.hatRows - 1 && $0.y <= PixelBank.rows }, "pixel \(sp.id)/\(hat): out of bounds")
            let keys = px.map { $0.y * 100 + $0.x }
            check(Set(keys).count == keys.count, "pixel \(sp.id)/\(hat)/\(String(describing: ov)): duplicate pixels")
            check(px.contains { $0.kind == .dark }, "pixel \(sp.id): no dark eye pixels")
            check(px.contains { $0.kind == .outline } && px.contains { $0.kind == .shade } && px.contains { $0.kind == .light }, "pixel \(sp.id): outline/bevel missing")
        }
    }
}
let winked = PixelRenderer.render(species: PixelBank.species(id: "clawd"), frame: 0, hat: .none, eyes: .dot, wink: 0)
let open = PixelRenderer.render(species: PixelBank.species(id: "clawd"), frame: 0, hat: .none, eyes: .dot)
check(winked.filter { $0.kind == .dark }.count < open.filter { $0.kind == .dark }.count, "wink closes one eye")
let flat = PixelRenderer.render(species: PixelBank.species(id: "clawd"), frame: 1, hat: .none, eyes: .dot, flat: true)
check(!flat.contains { $0.kind == .outline || $0.kind == .light }, "flat has no outline/bevel")
print("\n=== Pixel gallery (frame 0, hat: tophat) ===")
for sp in PixelBank.all {
    let px = PixelRenderer.render(species: sp, frame: 0, hat: .tophat, eyes: .dot)
    var canvas = Array(repeating: Array(repeating: " ", count: PixelBank.cols + 2), count: PixelBank.rows + PixelBank.hatRows + 2)
    for p in px {
        let ch: String
        switch p.kind { case .body: ch = "█"; case .shade: ch = "▓"; case .light: ch = "░"; case .white: ch = "◻"; case .dark: ch = "▪"; case .accent: ch = "◆"; case .outline: ch = "·" }
        canvas[p.y + PixelBank.hatRows + 1][p.x + 1] = ch
    }
    print("[\(sp.id)]")
    for row in canvas { print("|" + row.joined() + "|") }
}

// 8c. Tic-tac-toe: perfect play never loses against random play; imperfect play stays legal.
var rngState: UInt64 = 42
func rnd() -> Double { rngState = rngState &* 6364136223846793005 &+ 1442695040888963407; return Double(rngState >> 11) / Double(1 << 53) }
var buddyLosses = 0, buddyWins = 0, ttdraws = 0
for g in 0..<300 {
    var t = TicTacToe(); t.reset(starter: g % 2 == 0 ? .x : .o)
    while !t.isOver {
        if t.turn == .o { t.play(t.bestMove()!) }
        else { let f = t.freeCells; t.play(f[Int(rnd() * Double(f.count)) % f.count]) }
    }
    switch t.outcome { case .win(.o): buddyWins += 1; case .win(.x): buddyLosses += 1; case .draw: ttdraws += 1; default: break }
}
check(buddyLosses == 0, "perfect play lost \(buddyLosses) games")
check(buddyWins > 0 && ttdraws > 0, "sanity: wins \(buddyWins) draws \(ttdraws)")
var t2 = TicTacToe(); t2.play(0); t2.play(4)
check(t2.turn == .x && t2.freeCells.count == 7, "turn order")
check(!t2.play(0), "illegal move rejected")
for _ in 0..<50 { let m = t2.move(skill: 0.0, random: rnd); check(m != nil && t2.cells[m!] == nil, "random move legal") }
var t3 = TicTacToe(); t3.play(0); t3.play(3); t3.play(1); t3.play(4)   // X: 0,1 → X must block/win at 2
check(t3.bestMove() == 2, "wins when possible, got \(String(describing: t3.bestMove()))")
var t4 = TicTacToe(); t4.play(0); t4.play(4); t4.play(1)               // O to move, must block 2
check(t4.bestMove() == 2, "blocks the threat, got \(String(describing: t4.bestMove()))")

// 9. Print a gallery for eyeballing.
print("\n=== Gallery (frame 0, own eyes, hat as generated) ===")
for sp in SpriteBank.all {
    let rows = SpriteComposer.render(look: SpriteLook(species: sp, hat: .none, eyes: .dot), frame: 0)
    print("[\(sp.id)]")
    for r in rows { print("|" + r + "|") }
}
print("\n=== Sample bubble ===")
for r in Bubble.box("website: Erlauben: Bash") { print(r) }
for r in SpriteComposer.render(look: SpriteLook(species: SpriteBank.species(id: "duck"), hat: .tophat, eyes: .dot), frame: 0, eyeOverride: "O") { print(r) }

print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
