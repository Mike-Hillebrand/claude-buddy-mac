import AppKit
import SwiftUI
import ServiceManagement

final class AppController: NSObject, NSMenuDelegate {
    let store = SessionStore()
    let vm = PetViewModel()
    let settings = Settings.shared

    private var panel: PetPanel!
    private var hosting: NSHostingView<PetView>!
    private var statusItem: NSStatusItem!
    private var hooks: HookWatcher!
    private var tickTimer: Timer?
    private var mouseTimer: Timer?
    private var tick = 0
    private var look: SpriteLook
    private var pixelSpecies: PixelSpecies
    private var lastMomentId = 0
    private var quipText = ""
    private var quipUntil = Date.distantPast
    private var particleCounter = 0
    // Update notifier (public GitHub Releases check — the only network call Buddy makes)
    private let updater = UpdateChecker()
    private var updateTimer: Timer?
    private var updateAvailable: String?

    // Local usage (today's Claude Code tokens, read from ~/.claude/projects — no network)
    private var usageWatcher: LocalUsageWatcher?
    private var usage = LocalUsageWatcher.Snapshot()
    private var claudeRunning = false                 // Claude desktop app open? (presence signal)
    private var lastPresenceCheck = Date.distantPast

    // Tic-tac-toe
    private var gamePanel: GamePanel?
    private let gameVM = GameViewModel()
    private var gameTimer: Timer?

    // Wandering along the screen edges
    private var wanderTimer: Timer?
    private var wanderDir: CGFloat = 1            // +1: bottom→right→top→left (counter-clockwise), -1: reverse
    private var wanderT: CGFloat = 0              // position along the perimeter
    private var wanderResting = true
    private var wanderPhaseUntil = Date.distantPast
    private var wanderNeedsProject = true
    private var wanderRectCache = NSRect.zero
    private var wanderLastTick = Date()

    override init() {
        look = settings.currentLook()
        pixelSpecies = settings.currentPixelSpecies()
        super.init()
    }

    // MARK: Lifecycle

    func start() {
        S.lang = settings.lang
        vm.theme = settings.theme
        vm.fontSize = settings.size.fontSize
        vm.cell = settings.size.cell
        vm.style = settings.style
        vm.card = settings.card
        vm.mic = settings.mic

        panel = PetPanel(contentRect: NSRect(origin: .zero, size: panelSize()))
        let catcher = DragCatcherView(frame: panel.contentView!.bounds)
        catcher.autoresizingMask = [.width, .height]
        catcher.panel = panel
        panel.contentView = catcher
        hosting = NSHostingView(rootView: PetView(vm: vm))
        hosting.frame = catcher.bounds
        hosting.autoresizingMask = [.width, .height]
        catcher.addSubview(hosting)

        panel.onClick = { [weak self] in self?.petTheBuddy() }
        panel.onDoubleClick = { [weak self] in self?.openCurrentSession() }
        panel.buttonHitTest = { [weak self] p in self?.micRect().contains(p) ?? false }
        panel.onButton = { [weak self] in self?.startVoice(alternate: NSEvent.modifierFlags.contains(.option)) }
        panel.onRightClick = { [weak self] ev in self?.showContextMenu(ev) }
        panel.onMoved = { [weak self] in
            guard let self = self else { return }
            self.settings.panelOrigin = self.panel.frame.origin
            self.wanderNeedsProject = true
        }
        placePanel()
        panel.orderFrontRegardless()

        setupStatusItem()

        hooks = HookWatcher { [weak self] ev in
            guard let self = self, !self.demoMode else { return }   // demo mode: states come from the command channel
            DispatchQueue.main.async { self.store.apply(hook: ev) }
        }
        hooks.start()

        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.onTick() }
        tickTimer?.tolerance = 0.05
        // Only the drawn parts of the (mostly transparent) panel should catch the mouse, so windows
        // underneath — e.g. another desktop pet — stay clickable. Cheap: one mouse-location read per tick.
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in self?.updateMousePassThrough() }
        mouseTimer?.tolerance = 0.02
        if settings.updateCheck { startUpdateChecks() }
        if settings.usage { startUsageWatch() }

        let args = CommandLine.arguments
        if !args.contains("--no-greeting") { quip(S.t("hello"), seconds: 4) }
        onTick()
        if settings.wander { startWander() }
        // Demo/test flags: deterministic wandering and an open game board.
        if let a = args.first(where: { $0.hasPrefix("--wander-dir=") }), let d = Double(a.dropFirst(13)) { wanderDir = d < 0 ? -1 : 1 }
        if args.contains("--walk-now") {
            settings.wander = true
            if wanderTimer == nil { startWander() }
            wanderResting = false
            wanderPhaseUntil = Date().addingTimeInterval(40)
        }
        if args.contains("--game") { openGame() }
    }

    // MARK: Update notifier

    private func startUpdateChecks() {
        updateTimer?.invalidate()
        checkForUpdate()
        // Re-check every 6 hours while running.
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.checkForUpdate() }
        updateTimer?.tolerance = 600
    }

    private func checkForUpdate() {
        updater.check { [weak self] newer in
            DispatchQueue.main.async {
                guard let self = self, let v = newer, v != self.updateAvailable else { return }
                self.updateAvailable = v
                self.quip(String(format: S.t("update.available"), v), seconds: 8)
            }
        }
    }

    // MARK: Local usage (today's Claude Code tokens — read from ~/.claude/projects, no network)

    private func startUsageWatch() {
        let w = LocalUsageWatcher()
        w.onChange = { [weak self] snap in
            DispatchQueue.main.async { self?.usage = snap; self?.refreshUsageLine() }
        }
        usageWatcher = w
        w.start()
    }

    private func stopUsageWatch() {
        usageWatcher?.stop(); usageWatcher = nil
        usage = LocalUsageWatcher.Snapshot()
        vm.usageLine = ""
    }

    /// Compact "today" line shown under the buddy, e.g. "⚡ 107M heute · 41×".
    private func refreshUsageLine() {
        guard settings.usage, usage.totals.turns > 0 else {
            if !vm.usageLine.isEmpty { vm.usageLine = "" }
            return
        }
        let line = "⚡ \(LocalUsage.human(usage.totals.total)) \(S.t("usage.today")) · \(usage.totals.turns)×"
        if line != vm.usageLine { vm.usageLine = line }
    }

    /// True while Claude Code activity is recent or the Claude desktop app is open — used so the
    /// buddy dozes (awake) instead of dropping to "sleeping" the moment a turn ends.
    private func recentlyActive(_ now: Date) -> Bool {
        if now.timeIntervalSince(lastPresenceCheck) > 5 {
            lastPresenceCheck = now
            let apps = NSWorkspace.shared.runningApplications
            claudeRunning = apps.contains { app in
                let bid = app.bundleIdentifier?.lowercased() ?? ""
                return bid == "com.anthropic.claudefordesktop" || (bid.contains("anthropic") && bid.contains("claude"))
            }
        }
        if claudeRunning { return true }
        if let last = usage.lastActivity { return now.timeIntervalSince(last) < 240 }
        return false
    }

    // MARK: Wandering (edges only, never across the screen)

    private func startWander() {
        wanderTimer?.invalidate()
        wanderNeedsProject = true
        wanderResting = true
        wanderPhaseUntil = Date().addingTimeInterval(2)
        wanderLastTick = Date()
        wanderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.wanderStep() }
    }

    private func stopWander() {
        wanderTimer?.invalidate(); wanderTimer = nil
        vm.walking = false
        vm.facingLeft = false
        settings.panelOrigin = panel.frame.origin
    }

    /// Rectangle of allowed panel origins: the panel hugs the visible frame of the screen it is on.
    private func wanderRect() -> NSRect {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vis = screen.visibleFrame
        let m: CGFloat = 6
        let size = panel.frame.size
        let visibleW = size.width - 60          // panel has 60 px of transparent slack on the right
        return NSRect(x: vis.minX + m, y: vis.minY + m,
                      width: max(1, vis.width - visibleW - 2 * m), height: max(1, vis.height - size.height - 2 * m))
    }

    private func perimeterPoint(_ t: CGFloat, in r: NSRect) -> NSPoint {
        let W = r.width, H = r.height, P = 2 * (W + H)
        var u = t.truncatingRemainder(dividingBy: P); if u < 0 { u += P }
        if u < W { return NSPoint(x: r.minX + u, y: r.minY) }                       // bottom edge →
        u -= W
        if u < H { return NSPoint(x: r.maxX, y: r.minY + u) }                       // right edge ↑
        u -= H
        if u < W { return NSPoint(x: r.maxX - u, y: r.maxY) }                       // top edge ←
        u -= W
        return NSPoint(x: r.minX, y: r.maxY - u)                                    // left edge ↓
    }

    /// Nearest perimeter parameter for a point (projects onto the four edges).
    private func project(_ p: NSPoint, onto r: NSRect) -> CGFloat {
        let W = r.width, H = r.height
        let x = min(max(p.x, r.minX), r.maxX), y = min(max(p.y, r.minY), r.maxY)
        let candidates: [(CGFloat, CGFloat)] = [
            (abs(p.y - r.minY), x - r.minX),                    // bottom
            (abs(p.x - r.maxX), W + (y - r.minY)),              // right
            (abs(p.y - r.maxY), W + H + (r.maxX - x)),          // top
            (abs(p.x - r.minX), 2 * W + H + (r.maxY - y)),      // left
        ]
        return candidates.min { $0.0 < $1.0 }!.1
    }

    private func wanderStep() {
        guard settings.wander, let panel = panel, let catcher = panel.contentView as? DragCatcherView else { return }
        let now = Date()
        let dt = CGFloat(min(0.1, now.timeIntervalSince(wanderLastTick)))
        wanderLastTick = now
        if catcher.isDragging { wanderNeedsProject = true; setWalking(false); return }

        // Stay put when Claude needs you, right after a reaction, or when the cursor is close.
        let busy = store.globalState == .attention || !store.recentMoments(within: 3).isEmpty || gamePanel?.isVisible == true
        let near = panel.frame.insetBy(dx: -30, dy: -30).contains(NSEvent.mouseLocation)
        if busy || near { setWalking(false); return }

        if now >= wanderPhaseUntil {
            if wanderResting {
                wanderResting = false
                wanderPhaseUntil = now.addingTimeInterval(Double.random(in: 5...14))
                if Double.random(in: 0..<1) < 0.3 { wanderDir *= -1 }
            } else {
                wanderResting = true
                wanderPhaseUntil = now.addingTimeInterval(Double.random(in: 6...20))
                settings.panelOrigin = panel.frame.origin
            }
        }
        if wanderResting { setWalking(false); return }

        let rect = wanderRect()
        if rect != wanderRectCache { wanderRectCache = rect; wanderNeedsProject = true }
        let speed = max(24, vm.cell * 4.5) * dt
        let origin = panel.frame.origin

        if wanderNeedsProject {
            // Walk to the nearest point of the perimeter first (e.g. after a drag), then follow it.
            wanderT = project(origin, onto: rect)
            let target = perimeterPoint(wanderT, in: rect)
            let dx = target.x - origin.x, dy = target.y - origin.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist <= speed {
                panel.setFrameOrigin(target)
                wanderNeedsProject = false
            } else {
                panel.setFrameOrigin(NSPoint(x: origin.x + dx / dist * speed, y: origin.y + dy / dist * speed))
                if abs(dx) > 0.5 { vm.facingLeft = dx < 0 }
            }
            setWalking(true)
            return
        }

        wanderT += wanderDir * speed
        let next = perimeterPoint(wanderT, in: rect)
        let dx = next.x - origin.x
        if abs(dx) > 0.2 { vm.facingLeft = dx < 0 }
        panel.setFrameOrigin(next)
        setWalking(true)
    }

    private func setWalking(_ on: Bool) {
        if vm.walking != on { vm.walking = on }
    }

    private func panelSize() -> NSSize {
        let fs = settings.size.fontSize
        let usageH: CGFloat = 0
        if settings.style == .pixel {
            let cell = settings.size.cell
            let spriteW = cell * CGFloat(PixelBank.cols + 2)
            let bubbleW = fs * 0.602 * 26 + 20
            let spriteH = cell * CGFloat(PixelBank.rows + PixelBank.hatRows + 2)
            let bubbleH = fs * 1.2 * 3 + 32
            return NSSize(width: ceil(max(spriteW, bubbleW) + 60), height: ceil(spriteH + bubbleH + usageH + 46))
        }
        return NSSize(width: ceil(fs * 0.602 * 30 + 28), height: ceil(fs * 1.2 * 11 + usageH + 44))
    }

    private func placePanel() {
        let size = panelSize()
        panel.setContentSize(size)
        let screens = NSScreen.screens
        let main = NSScreen.main ?? screens.first
        let vis = main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let saved = settings.panelOrigin {
            // Keep the saved spot as long as the sprite area is still on *some* screen (multi-display safe).
            let core = NSRect(x: saved.x + 10, y: saved.y + 10, width: min(size.width, 120), height: min(size.height, 120))
            if screens.contains(where: { $0.frame.intersects(core) }) {
                panel.setFrameOrigin(saved)
                return
            }
        }
        panel.setFrameOrigin(NSPoint(x: vis.maxX - size.width - 24, y: vis.minY + 24))
    }

    /// Rects (panel coordinates, origin bottom-left) that should react to the mouse.
    private func hitRects() -> [NSRect] {
        let fs = vm.fontSize
        let pad: CGFloat = 10, bottom: CGFloat = 8
        let small = max(9, fs * 0.72)
        let labelH = small * 1.3 + 6
        let usageH: CGFloat = 0
        let spriteW: CGFloat = settings.style == .pixel ? vm.cell * CGFloat(PixelBank.cols + 2) : fs * 0.602 * 12 + 4
        let spriteH: CGFloat = settings.style == .pixel ? vm.cell * CGFloat(PixelBank.rows + PixelBank.hatRows + 2) : fs * 1.2 * 5
        var rects: [NSRect] = []
        let stripW = max(spriteW, fs * 0.602 * 22)
        rects.append(NSRect(x: pad, y: bottom, width: stripW + 8, height: labelH + usageH))
        let spriteY = bottom + labelH + usageH
        rects.append(NSRect(x: pad, y: spriteY, width: spriteW + 4, height: spriteH + 4))
        let bubbleLines = settings.style == .pixel ? vm.bubbleText.split(separator: "\n").map(String.init) : vm.bubble
        if !bubbleLines.isEmpty {
            let longest = bubbleLines.map { $0.count }.max() ?? 0
            let w = CGFloat(longest) * fs * 0.602 + 24
            let h = CGFloat(bubbleLines.count) * fs * 1.2 + 24
            rects.append(NSRect(x: pad, y: spriteY + spriteH, width: w, height: h))
        }
        return rects
    }

    /// The voice button (panel coordinates): first item of the label row under the sprite.
    func micRect() -> NSRect {
        guard settings.mic else { return .zero }
        let size = PetView.micSize
        return NSRect(x: 10, y: 9, width: size, height: size)
    }

    private func updateMousePassThrough() {
        guard let panel = panel, let catcher = panel.contentView as? DragCatcherView else { return }
        if catcher.isDragging { panel.ignoresMouseEvents = false; return }
        let loc = NSEvent.mouseLocation
        guard panel.frame.contains(loc) else {
            if panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }   // idle default: catch, so a fresh entry works
            if vm.micHover { vm.micHover = false }
            return
        }
        let local = NSPoint(x: loc.x - panel.frame.minX, y: loc.y - panel.frame.minY)
        let hit = hitRects().contains { $0.contains(local) }
        if panel.ignoresMouseEvents == hit { panel.ignoresMouseEvents = !hit }
        let hover = micRect().contains(local)
        if hover != vm.micHover { vm.micHover = hover }
    }

    // MARK: Voice button → Claude Quick Entry (double-tap ⌥), fallback: new chat

    private var axHintShown = false

    private func startVoice(alternate: Bool) {
        if alternate { openNewChat(); return }
        // Silent check — never triggers the "control your Mac" prompt. Quick Entry needs Accessibility
        // (which doesn't stick with ad-hoc signing), so if it isn't granted we just open a new chat.
        if AXIsProcessTrusted() {
            quip(S.t("mic.opening"), seconds: 2)
            let src = CGEventSource(stateID: .hidSystemState)
            let optionKey: CGKeyCode = 58   // Quick Entry's default shortcut is a double tap on Option.
            for i in 0..<2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) {
                    // Modifier keys are reported as flagsChanged events, not keyDown/keyUp.
                    let down = CGEvent(keyboardEventSource: src, virtualKey: optionKey, keyDown: true)
                    down?.type = .flagsChanged; down?.flags = .maskAlternate; down?.post(tap: .cghidEventTap)
                    let up = CGEvent(keyboardEventSource: src, virtualKey: optionKey, keyDown: false)
                    up?.type = .flagsChanged; up?.flags = []; up?.post(tap: .cghidEventTap)
                }
            }
        } else {
            openNewChat()
            if !axHintShown { axHintShown = true; quip(S.t("mic.needs.ax"), seconds: 6) }
        }
    }

    /// Double-click: open the current Claude Code session. Local hook sessions have no per-session URL,
    /// so this continues the last Claude Code session in the desktop app (and brings it to the front).
    private func openCurrentSession() {
        guard let url = URL(string: "claude://code/continue?session=last") else { openClaudeApp(); return }
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func openNewChat() {
        quip(S.t("mic.newchat"), seconds: 2)
        if let url = URL(string: "claude://claude.ai/new?surface=chat&source=desktop_action") {
            NSWorkspace.shared.open(url)
        } else {
            openClaudeApp()
        }
    }

    // MARK: Demo command channel (`--demo`): lines in ~/Library/Application Support/Buddy/cmd.txt

    private let demoMode = CommandLine.arguments.contains("--demo")
    private var demoCmdPath: String {
        NSString(string: "~/Library/Application Support/Buddy/cmd.txt").expandingTildeInPath
    }

    private func pollDemoCommands() {
        guard demoMode, let data = FileManager.default.contents(atPath: demoCmdPath),
              let text = String(data: data, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(atPath: demoCmdPath)
        for raw in text.split(separator: "\n") {
            let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
            guard let cmd = parts.first else { continue }
            let arg = parts.count > 1 ? parts[1] : ""
            runDemoCommand(cmd, arg)
        }
    }

    private func runDemoCommand(_ cmd: String, _ arg: String) {
        switch cmd {
        case "pet": petTheBuddy()
        case "clear": store.removeAll()
        case "mic": startVoice(alternate: arg == "chat")
        case "quip": quip(arg, seconds: 4)
        case "menu":
            // Pop the context menu up next to the sprite (as if right-clicked).
            let m = NSMenu(); m.delegate = self; buildMenu(into: m)
            let fs = settings.size.fontSize
            let spriteW: CGFloat = settings.style == .pixel ? vm.cell * CGFloat(PixelBank.cols + 2) : fs * 0.602 * 12 + 4
            let spriteH: CGFloat = settings.style == .pixel ? vm.cell * CGFloat(PixelBank.rows + PixelBank.hatRows + 2) : fs * 1.2 * 5
            let at = NSPoint(x: 10 + spriteW, y: 8 + fs + spriteH)
            DispatchQueue.main.async { m.popUp(positioning: nil, at: at, in: self.panel.contentView) }
        case "species":
            settings.speciesId = arg; settings.lookInitialized = true
            look = settings.currentLook(); pixelSpecies = settings.currentPixelSpecies()
            quip("\(S.t("iam")) \(settings.style == .pixel ? pixelSpecies.displayName : look.species.displayName).", seconds: 3)
        case "hat": if let h = Hat(rawValue: arg) { settings.hat = h; look = settings.currentLook() }
        case "eyes": if let e = EyeStyle(rawValue: arg) { settings.eyes = e; look = settings.currentLook() }
        case "theme": if let t = Theme(rawValue: arg) { settings.theme = t; vm.theme = t; gameVM.theme = t }
        case "size": if let sz = PetSize(rawValue: arg) { settings.size = sz; vm.fontSize = sz.fontSize; vm.cell = sz.cell; placePanel() }
        case "style": if let st = SpriteStyle(rawValue: arg) { settings.style = st; vm.style = st; placePanel() }
        case "lang": if let l = Lang(rawValue: arg) { settings.lang = l; S.lang = l }
        case "flat": settings.flat = arg == "1"
        case "card": settings.card = arg == "1"; vm.card = settings.card
        case "wander":
            let on = arg.hasPrefix("1")
            settings.wander = on
            if on { startWander() } else { stopWander() }
            if arg.contains("-1") { wanderDir = -1 } else if arg.contains("+1") { wanderDir = 1 }
        case "walk-now":
            settings.wander = true
            if wanderTimer == nil { startWander() }
            wanderResting = false
            wanderPhaseUntil = Date().addingTimeInterval(Double(arg) ?? 30)
        case "rest": wanderResting = true; wanderPhaseUntil = Date().addingTimeInterval(Double(arg) ?? 30)
        case "game": openGame()
        case "game-close": closeGame()
        case "move": if let i = Int(arg) { humanMove(i) }
        case "state":
            // e.g. `state working Edit` → fakes a focus session for screenshots
            let p = arg.split(separator: " ", maxSplits: 1).map(String.init)
            let st: PetState = [
                "sleeping": .sleeping, "idle": .idle, "ready": .ready, "thinking": .thinking, "working": .working, "attention": .attention,
            ][p.first ?? ""] ?? .idle
            store.setDemoSession(state: st, detail: p.count > 1 ? p[1] : "")
        default: break
        }
    }

    // MARK: Tick / animation

    private func onTick() {
        tick += 1
        if tick % 40 == 0 { store.prune() }
        if demoMode { pollDemoCommands() }

        let now = Date()
        var state = store.globalState
        // Recent local activity (or the Claude app being open) keeps the buddy awake — it dozes
        // with the chosen eyes instead of flatlining to "sleeping" the moment a turn ends.
        if state == .sleeping && recentlyActive(now) { state = .idle }
        let focus = store.focus
        let recent = store.recentMoments(within: 4)
        let doneM = recent.last { $0.kind == .done }
        let errM = store.recentMoments(within: 3).last { $0.kind == .error }
        let petM = store.recentMoments(within: 2.5).last { $0.kind == .pet }
        let attM = store.recentMoments(within: 2).last { $0.kind == .attention }

        // New moments → sounds + particles
        if let newest = store.moments.last, newest.id != lastMomentId {
            lastMomentId = newest.id
            switch newest.kind {
            case .done: sound("Glass"); spawnParticles(kind: .done)
            case .error: sound("Basso")
            case .attention: sound("Pop"); spawnParticles(kind: .attention)
            case .pet: spawnParticles(kind: .pet)
            case .info: break
            }
        }
        if !vm.particles.isEmpty {
            vm.particles.removeAll { now.timeIntervalSince($0.born) > $0.life }
        }

        // Frame + eyes
        var eye: Character? = nil
        if errM != nil { eye = "x" }
        else if doneM != nil || petM != nil { eye = "^" }
        else if state == .attention { eye = "O" }
        else if tick % 16 == 0 { eye = "-" }   // blink — otherwise the chosen eye style shows, even at rest
        if settings.style == .pixel {
            let walking = vm.walking
            let n = max(1, walking && !pixelSpecies.walk.isEmpty ? pixelSpecies.walk.count : pixelSpecies.frames.count)
            let frame: Int
            if walking || state == .working || state == .thinking {
                frame = tick % n                                   // busy/walking: continuous cycle
            } else {
                let phase = (tick / 2) % (n + 5)                   // idle: short wiggle burst, then rest
                frame = phase < n ? phase : 0
            }
            let wink: Int? = (eye == nil && tick % 44 == 22) ? 0 : nil   // occasional wink with the left eye
            let px = PixelRenderer.render(species: pixelSpecies, frame: frame, hat: look.hat, eyes: look.eyes,
                                          eyeOverride: eye, wink: wink, flat: settings.flat, walking: walking)
            if px != vm.pixels { vm.pixels = px }
            let breath = (tick / 2) % 2 == 0
            if breath != vm.breath { vm.breath = breath }
        } else {
            let frame = (state == .working || vm.walking) ? tick % 3 : (tick / 2) % 3
            let rows = SpriteComposer.render(look: look, frame: frame, eyeOverride: eye)
            if rows != vm.rows { vm.rows = rows }
        }

        // Bubble
        var text = ""
        var accent = false
        if let f = focus, state == .attention {
            text = f.detail.isEmpty ? "\(f.title): \(S.t("needs.you"))" : "\(f.title): \(f.detail)"; accent = true
        } else if let m = errM {
            text = "✗ " + m.text; accent = true
        } else if let m = doneM {
            text = "✓ " + m.text
        } else if let m = attM {
            text = m.text; accent = true
        } else if petM != nil {
            text = "♥ " + Quips.pick(Quips.thanks, seed: tick / 10)
        } else if state == .thinking {
            text = ["·", "··", "···"][(tick / 2) % 3]
        } else if state == .working, let f = focus {
            text = f.detail.isEmpty ? Quips.pick(Quips.working, seed: tick / 40) : f.detail
        } else if now < quipUntil {
            text = quipText
        }
        if settings.style == .pixel {
            let t = text.isEmpty ? "" : Bubble.wrap(text).joined(separator: "\n")
            if t != vm.bubbleText { vm.bubbleText = t }
        } else {
            let bubble = text.isEmpty ? [] : Bubble.box(text)
            if bubble != vm.bubble { vm.bubble = bubble }
        }
        if accent != vm.bubbleAccent { vm.bubbleAccent = accent }

        // Float text / jump / wobble
        var float = ""
        if state == .attention { float = "!" }
        else if state == .sleeping { float = ["z", "zZ", "zZz"][(tick / 4) % 3] }
        if float != vm.floatText { vm.floatText = float }
        let up = (tick / 2) % 2 == 0
        if up != vm.floatUp { vm.floatUp = up }
        let jump = state == .attention && tick % 4 < 2
        if jump != vm.jump { vm.jump = jump }
        let wobble: CGFloat = errM != nil ? (tick % 2 == 0 ? 2 : -2) : 0
        if wobble != vm.wobble { vm.wobble = wobble }

        // Sessions + label
        let sessions = store.visibleSessions
        if sessions != vm.sessions { vm.sessions = sessions }
        if state != vm.state { vm.state = state }
        let label: String
        switch state {
        case .sleeping: label = hooks.hooksInstalled ? S.t("no.sessions") : S.t("hooks.missing")
        default:
            let counts = store.counts
            var parts: [String] = []
            if let n = counts[.attention], n > 0 { parts.append("\(n) \(S.t(n == 1 ? "n.attention.1" : "n.attention"))") }
            if let n = counts[.working], n > 0 { parts.append("\(n) \(S.t("n.working"))") }
            if let n = counts[.thinking], n > 0 { parts.append("\(n) \(S.t("n.thinking"))") }
            if let n = counts[.ready], n > 0 { parts.append("\(n) \(S.t("n.ready"))") }
            if let n = counts[.idle], n > 0 { parts.append("\(n) \(S.t("n.idle"))") }
            label = parts.joined(separator: " · ")
        }
        if label != vm.label { vm.label = label }

        // Idle chatter
        if settings.quips, tick % 480 == 0, state == .idle || state == .sleeping || state == .ready {
            quip(Quips.pick(Quips.idle, seed: tick / 480 + Int(now.timeIntervalSince1970) % 7), seconds: 6)
        }
    }

    private func quip(_ text: String, seconds: TimeInterval) {
        quipText = text
        quipUntil = Date().addingTimeInterval(seconds)
    }

    private func sound(_ name: String) {
        guard settings.sounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private enum ParticleKind { case done, attention, pet }

    private func spawnParticles(kind: ParticleKind) {
        let fs = vm.fontSize
        let cx = settings.style == .pixel ? vm.cell * 9 : fs * 0.602 * 6
        let cy = settings.style == .pixel ? vm.cell * CGFloat(PixelBank.hatRows + 8) : fs * 1.2 * 2.5
        let now = Date()
        var out: [Particle] = []
        let n = kind == .done ? 16 : (kind == .pet ? 7 : 4)
        for i in 0..<n {
            particleCounter += 1
            let angle = Double.random(in: 0...(2 * Double.pi))
            let speed = CGFloat.random(in: 40...110)
            switch kind {
            case .done:
                let chars = ["*", "+", "·", "✦", "°"]
                let colors: [Color] = [.yellow, .orange, .pink, .mint, .cyan, Color(nsColor: settings.theme.color)]
                out.append(Particle(id: particleCounter, x0: cx, y0: cy, vx: CGFloat(cos(angle)) * speed, vy: CGFloat(sin(angle)) * speed - 60,
                                    gravity: 90, char: chars[i % chars.count], color: colors[i % colors.count], born: now, life: 1.5))
            case .pet:
                out.append(Particle(id: particleCounter, x0: cx + CGFloat.random(in: -20...20), y0: cy, vx: CGFloat.random(in: -12...12), vy: -CGFloat.random(in: 25...45),
                                    gravity: 0, char: "♥", color: Color(red: 1, green: 0.35, blue: 0.5), born: now, life: 2.2))
            case .attention:
                out.append(Particle(id: particleCounter, x0: cx + CGFloat(i - 2) * 14, y0: cy - 10, vx: 0, vy: -30,
                                    gravity: 0, char: "!", color: Color(red: 1.0, green: 0.42, blue: 0.2), born: now, life: 1.0))
            }
        }
        vm.particles.append(contentsOf: out)
    }

    private func petTheBuddy() {
        store.addMoment(.pet, "♥")
    }

    // MARK: Status item & menus

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Buddy")
            b.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        buildMenu(into: menu)
    }

    private func showContextMenu(_ event: NSEvent) {
        let menu = NSMenu()
        buildMenu(into: menu)
        NSMenu.popUpContextMenu(menu, with: event, for: panel.contentView!)
    }

    private func buildMenu(into menu: NSMenu) {
        let state = store.globalState
        let header = NSMenuItem(title: "Buddy \(state.label)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if let v = updateAvailable {
            let up = NSMenuItem(title: "⬆︎ " + String(format: S.t("update.available"), v), action: #selector(openReleases), keyEquivalent: "")
            up.target = self
            menu.addItem(up)
        }
        if settings.usage, usage.totals.turns > 0 {
            let t = usage.totals
            var line = "⚡ \(LocalUsage.human(t.total)) \(S.t("usage.today")) · \(t.turns)× · out \(LocalUsage.human(t.output))"
            if usage.costUSD >= 0.01 { line += String(format: " · ≈ $%.2f", usage.costUSD) }
            let u = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            u.isEnabled = false
            menu.addItem(u)
        }

        let sessions = store.visibleSessions
        if sessions.isEmpty {
            let it = NSMenuItem(title: S.t("menu.no.sessions"), action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        } else {
            for s in sessions.prefix(15) {
                let title = "\(dot(for: s.state)) \(s.source.glyph) \(s.title) — \(s.state.label)\(s.detail.isEmpty ? "" : " · \(s.detail)")"
                let it = NSMenuItem(title: title, action: #selector(openSession(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = s.id
                menu.addItem(it)
                // ⌥ shows the other target (browser ↔ app); local Claude Code sessions reveal their folder.
                let altTitle: String
                if s.id.hasPrefix("hook:") { altTitle = "    ↳ " + S.t("menu.reveal") }
                else { altTitle = "    ↳ " + S.t(settings.openTarget == .app ? "menu.open.alt.browser" : "menu.open.alt.app") }
                let alt = NSMenuItem(title: altTitle, action: #selector(openSessionAlt(_:)), keyEquivalent: "")
                alt.target = self
                alt.representedObject = s.id
                alt.isAlternate = true
                alt.keyEquivalentModifierMask = .option
                menu.addItem(alt)
            }
        }
        menu.addItem(.separator())
        let ttt = NSMenuItem(title: "🎮 " + S.t("menu.ttt"), action: #selector(openGame), keyEquivalent: "")
        ttt.target = self
        menu.addItem(ttt)
        menu.addItem(.separator())

        // Aussehen
        let look = NSMenu()
        let styleMenu = NSMenu()
        for st in SpriteStyle.allCases {
            let it = NSMenuItem(title: st.label, action: #selector(pickStyle(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = st.rawValue
            it.state = st == settings.style ? .on : .off
            styleMenu.addItem(it)
        }
        addSub(look, S.t("menu.style"), styleMenu)
        let speciesMenu = NSMenu()
        if settings.style == .pixel {
            for sp in PixelBank.all {
                let it = NSMenuItem(title: sp.displayName, action: #selector(pickSpecies(_:)), keyEquivalent: "")
                it.target = self; it.representedObject = sp.id
                it.state = sp.id == pixelSpecies.id ? .on : .off
                speciesMenu.addItem(it)
            }
        } else {
            for sp in SpriteBank.all {
                let it = NSMenuItem(title: sp.displayName, action: #selector(pickSpecies(_:)), keyEquivalent: "")
                it.target = self; it.representedObject = sp.id
                it.state = sp.id == self.look.species.id ? .on : .off
                speciesMenu.addItem(it)
            }
        }
        addSub(look, S.t("menu.species"), speciesMenu)
        let hatMenu = NSMenu()
        for h in Hat.allCases {
            let it = NSMenuItem(title: h.label, action: #selector(pickHat(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = h.rawValue
            it.state = h == self.look.hat ? .on : .off
            hatMenu.addItem(it)
        }
        addSub(look, S.t("menu.hat"), hatMenu)
        let eyeMenu = NSMenu()
        for e in EyeStyle.allCases {
            let it = NSMenuItem(title: e.label, action: #selector(pickEyes(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = e.rawValue
            it.state = e == self.look.eyes ? .on : .off
            eyeMenu.addItem(it)
        }
        addSub(look, S.t("menu.eyes"), eyeMenu)
        let themeMenu = NSMenu()
        for t in Theme.allCases {
            let it = NSMenuItem(title: t.label, action: #selector(pickTheme(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = t.rawValue
            it.state = t == settings.theme ? .on : .off
            themeMenu.addItem(it)
        }
        addSub(look, S.t("menu.color"), themeMenu)
        let sizeMenu = NSMenu()
        for s in PetSize.allCases {
            let it = NSMenuItem(title: s.label, action: #selector(pickSize(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = s.rawValue
            it.state = s == settings.size ? .on : .off
            sizeMenu.addItem(it)
        }
        addSub(look, S.t("menu.size"), sizeMenu)
        look.addItem(toggle(S.t("menu.outline"), !settings.flat, #selector(toggleFlat)))
        look.addItem(toggle(S.t("menu.card"), settings.card, #selector(toggleCard)))
        let shuffle = NSMenuItem(title: S.t("menu.shuffle"), action: #selector(shuffleLook), keyEquivalent: "")
        shuffle.target = self
        look.addItem(shuffle)
        addSub(menu, S.t("menu.look"), look)

        // Verhalten
        let beh = NSMenu()
        beh.addItem(toggle(S.t("menu.wander"), settings.wander, #selector(toggleWander)))
        beh.addItem(toggle(S.t("menu.mic"), settings.mic, #selector(toggleMic)))
        beh.addItem(toggle(S.t("menu.usage"), settings.usage, #selector(toggleUsage)))
        beh.addItem(toggle(S.t("menu.quips"), settings.quips, #selector(toggleQuips)))
        beh.addItem(toggle(S.t("menu.sounds"), settings.sounds, #selector(toggleSounds)))
        beh.addItem(toggle(S.t("menu.update.check"), settings.updateCheck, #selector(toggleUpdateCheck)))
        beh.addItem(.separator())
        let inst = NSMenuItem(title: hooks.hooksInstalled ? S.t("menu.hooks.reinstall") : S.t("menu.hooks.install"), action: #selector(installHooks), keyEquivalent: "")
        inst.target = self
        beh.addItem(inst)
        let uninst = NSMenuItem(title: S.t("menu.hooks.remove"), action: #selector(uninstallHooks), keyEquivalent: "")
        uninst.target = self
        beh.addItem(uninst)
        addSub(menu, S.t("menu.behavior"), beh)

        let openMenu = NSMenu()
        for t in OpenTarget.allCases {
            let it = NSMenuItem(title: t.label, action: #selector(pickOpenTarget(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = t.rawValue
            it.state = t == settings.openTarget ? .on : .off
            openMenu.addItem(it)
        }
        addSub(menu, S.t("menu.open.in"), openMenu)
        let langMenu = NSMenu()
        for l in Lang.allCases {
            let it = NSMenuItem(title: l.label, action: #selector(pickLang(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = l.rawValue
            it.state = l == settings.lang ? .on : .off
            langMenu.addItem(it)
        }
        addSub(menu, S.t("menu.language"), langMenu)
        menu.addItem(toggle(S.t("menu.login"), launchAtLogin, #selector(toggleLaunchAtLogin)))
        let reset = NSMenuItem(title: S.t("menu.reset.pos"), action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        let openClaude = NSMenuItem(title: S.t("menu.open.claude"), action: #selector(openClaudeApp), keyEquivalent: "")
        openClaude.target = self
        menu.addItem(openClaude)
        let log = NSMenuItem(title: S.t("menu.log"), action: #selector(showLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: S.t("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func addSub(_ parent: NSMenu, _ title: String, _ sub: NSMenu) {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.submenu = sub
        parent.addItem(it)
    }

    private func toggle(_ title: String, _ on: Bool, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        it.state = on ? .on : .off
        return it
    }

    private func dot(for state: PetState) -> String {
        switch state {
        case .attention: return "🔴"
        case .working: return "🔵"
        case .thinking: return "🟣"
        case .ready: return "🟢"
        case .idle, .sleeping: return "⚪️"
        }
    }

    // MARK: Actions

    @objc private func openSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let s = store.sessions[id] else { return }
        open(session: s, target: settings.openTarget)
    }
    @objc private func openSessionAlt(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let s = store.sessions[id] else { return }
        open(session: s, target: settings.openTarget == .app ? .browser : .app)
    }

    /// Deep link for a tracked session. Cowork/bridge ids are `cse_<suffix>`; the web/app path uses `session_<suffix>`.
    func link(for s: TrackedSession, target: OpenTarget) -> URL? {
        let base = target == .app ? "claude://claude.ai" : "https://claude.ai"
        if s.id.hasPrefix("api:") {
            var raw = String(s.id.dropFirst(4))
            if raw.hasPrefix("cse_") { raw = "session_" + raw.dropFirst(4) }
            return URL(string: "\(base)/code/\(raw)")
        }
        if s.id.hasPrefix("chat:") {
            return URL(string: "\(base)/chat/\(s.id.dropFirst(5))")
        }
        return nil
    }

    private func open(session s: TrackedSession, target: OpenTarget) {
        if s.id.hasPrefix("hook:") {
            // Local Claude Code session: no URL to open — reveal its project folder instead.
            if !s.path.isEmpty, FileManager.default.fileExists(atPath: s.path) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: s.path)
            } else {
                openClaudeApp()
            }
            return
        }
        if let url = link(for: s, target: target) {
            NSWorkspace.shared.open(url)
        } else {
            openClaudeApp()
        }
    }

    @objc private func openClaudeApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc private func pickSpecies(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.speciesId = id; settings.lookInitialized = true
        look = settings.currentLook()
        pixelSpecies = settings.currentPixelSpecies()
        quip("\(S.t("iam")) \(settings.style == .pixel ? pixelSpecies.displayName : look.species.displayName).", seconds: 4)
    }
    @objc private func pickOpenTarget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let t = OpenTarget(rawValue: raw) else { return }
        settings.openTarget = t
    }
    @objc private func pickLang(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let l = Lang(rawValue: raw) else { return }
        settings.lang = l
        S.lang = l
        quip(S.t("hello"), seconds: 3)
    }
    @objc private func pickStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let st = SpriteStyle(rawValue: raw) else { return }
        settings.style = st
        vm.style = st
        pixelSpecies = settings.currentPixelSpecies()
        placePanel()
    }
    @objc private func pickHat(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let h = Hat(rawValue: raw) else { return }
        settings.hat = h; look = settings.currentLook()
    }
    @objc private func pickEyes(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let e = EyeStyle(rawValue: raw) else { return }
        settings.eyes = e; look = settings.currentLook()
    }
    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let t = Theme(rawValue: raw) else { return }
        settings.theme = t; vm.theme = t
    }
    @objc private func pickSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let s = PetSize(rawValue: raw) else { return }
        settings.size = s; vm.fontSize = s.fontSize; vm.cell = s.cell
        placePanel()
    }
    @objc private func shuffleLook() {
        let l = LookGenerator.look(for: UUID().uuidString)
        settings.hat = l.hat; settings.eyes = l.eyes; settings.lookInitialized = true
        if settings.style == .pixel {
            let sp = PixelBank.all[Int.random(in: 0..<PixelBank.all.count)]
            settings.speciesId = sp.id
        } else {
            settings.speciesId = l.species.id
        }
        look = settings.currentLook()
        pixelSpecies = settings.currentPixelSpecies()
        quip("\(S.t("new")): \(settings.style == .pixel ? pixelSpecies.displayName : look.species.displayName).", seconds: 4)
    }
    @objc private func toggleCard() { settings.card.toggle(); vm.card = settings.card }
    // MARK: Tic-tac-toe

    @objc private func openGame() {
        if gamePanel == nil {
            let gp = GamePanel(contentRect: NSRect(x: 0, y: 0, width: 270, height: 330))
            let hosting = NSHostingView(rootView: GameView(vm: gameVM))
            hosting.frame = gp.contentView!.bounds
            hosting.autoresizingMask = [.width, .height]
            gp.contentView = hosting
            gp.setContentSize(hosting.fittingSize)
            gameVM.onCell = { [weak self] i in self?.humanMove(i) }
            gameVM.onNew = { [weak self] in self?.newGame(starter: .x) }
            gameVM.onClose = { [weak self] in self?.closeGame() }
            gamePanel = gp
        }
        gameVM.theme = settings.theme
        guard let gp = gamePanel else { return }
        // Next to the buddy: right side if there is room, otherwise left; bottom-aligned with the sprite.
        let pf = panel.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(pf) } ?? NSScreen.main
        let vis = screen?.visibleFrame ?? pf
        var x = pf.minX + (pf.width - 60) + 8
        if x + gp.frame.width > vis.maxX { x = pf.minX - gp.frame.width - 8 }
        x = max(vis.minX + 4, x)
        let y = min(max(pf.minY, vis.minY + 4), vis.maxY - gp.frame.height - 4)
        gp.setFrameOrigin(NSPoint(x: x, y: y))
        gp.orderFrontRegardless()
        newGame(starter: .x)
        if demoMode {
            let path = NSString(string: "~/Library/Application Support/Buddy/game-frame.txt").expandingTildeInPath
            try? NSStringFromRect(gp.frame).write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Demo mode: mirrors the board to a file so a script can play against the buddy.
    private func writeGameState() {
        guard demoMode else { return }
        let cells = gameVM.game.cells.map { $0 == .x ? "X" : ($0 == .o ? "O" : ".") }.joined()
        let line = "\(cells) turn=\(gameVM.game.turn == .x ? "X" : "O") over=\(gameVM.game.isOver ? 1 : 0) thinking=\(gameVM.buddyThinking ? 1 : 0)"
        let path = NSString(string: "~/Library/Application Support/Buddy/game-state.txt").expandingTildeInPath
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func closeGame() {
        gameTimer?.invalidate(); gameTimer = nil
        gamePanel?.orderOut(nil)
    }

    private func newGame(starter: TicTacToe.Player) {
        gameTimer?.invalidate(); gameTimer = nil
        gameVM.game.reset(starter: starter)
        gameVM.buddyThinking = false
        if starter == .o {
            gameVM.message = S.t("ttt.mystart")
            quip(S.t("ttt.bubble.start"), seconds: 2)
            scheduleBuddyMove()
        } else {
            gameVM.message = S.t("ttt.yourturn")
            quip(S.t("ttt.bubble.start"), seconds: 2)
        }
        writeGameState()
    }

    private func humanMove(_ i: Int) {
        guard gameVM.game.turn == .x, !gameVM.buddyThinking, gameVM.game.play(i) else { return }
        writeGameState()
        if finishIfOver() { return }
        scheduleBuddyMove()
    }

    private func scheduleBuddyMove() {
        gameVM.buddyThinking = true
        gameVM.message = S.t("ttt.thinking")
        quip(S.t("ttt.thinking"), seconds: 2)
        gameTimer?.invalidate()
        gameTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 0.5...1.1), repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // Mostly perfect, occasionally sloppy — otherwise nobody ever wins against it.
            if let m = self.gameVM.game.move(skill: 0.8) { self.gameVM.game.play(m) }
            self.gameVM.buddyThinking = false
            if !self.finishIfOver() { self.gameVM.message = S.t("ttt.yourturn") }
            self.writeGameState()
        }
    }

    /// Handles the end of a game: score, message, buddy reaction. Returns true when the game is over.
    private func finishIfOver() -> Bool {
        switch gameVM.game.outcome {
        case .ongoing:
            return false
        case .win(let p):
            if p == .o {
                gameVM.losses += 1
                gameVM.message = S.t("ttt.win")
                store.addMoment(.done, S.t("ttt.bubble.win"))
            } else {
                gameVM.wins += 1
                gameVM.message = S.t("ttt.lose")
                store.addMoment(.error, S.t("ttt.bubble.lose"))
            }
        case .draw:
            gameVM.draws += 1
            gameVM.message = S.t("ttt.drawq")
            quip(S.t("ttt.bubble.draw"), seconds: 4)
        }
        // Loser starts the next round; after a draw the human starts.
        let nextStarter: TicTacToe.Player = {
            if case .win(let p) = gameVM.game.outcome { return p.other }
            return .x
        }()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self = self, self.gamePanel?.isVisible == true else { return }
            self.newGame(starter: nextStarter)
        }
        return true
    }

    @objc private func toggleMic() { settings.mic.toggle(); vm.mic = settings.mic }
    @objc private func toggleUsage() {
        settings.usage.toggle()
        if settings.usage { startUsageWatch() } else { stopUsageWatch() }
    }
    @objc private func toggleWander() {
        settings.wander.toggle()
        if settings.wander { startWander() } else { stopWander() }
    }
    @objc private func toggleFlat() { settings.flat.toggle() }
    @objc private func toggleQuips() { settings.quips.toggle() }
    @objc private func toggleSounds() { settings.sounds.toggle() }
    @objc private func toggleUpdateCheck() {
        settings.updateCheck.toggle()
        if settings.updateCheck { startUpdateChecks() } else { updateTimer?.invalidate(); updateTimer = nil }
    }
    @objc private func openReleases() {
        if let url = URL(string: UpdateChecker.releasesURL) { NSWorkspace.shared.open(url) }
    }
    @objc private func resetPosition() { settings.panelOrigin = nil; placePanel() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: HookWatcher.eventsPath))
    }

    private var launchAtLogin: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if launchAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            alert(S.t("alert.login"), "\(error)")
        }
    }

    @objc private func installHooks() { runHookInstaller(uninstall: false) }
    @objc private func uninstallHooks() { runHookInstaller(uninstall: true) }

    private func runHookInstaller(uninstall: Bool) {
        guard let script = Bundle.main.path(forResource: "install-hooks", ofType: "py") else {
            alert(S.t("alert.installer.missing"), S.t("alert.installer.missing.text")); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", script] + (uninstall ? ["--uninstall"] : [])
        let out = Pipe()
        p.standardOutput = out; p.standardError = out
        do {
            try p.run(); p.waitUntilExit()
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            alert(uninstall ? S.t("alert.hooks.removed") : S.t("alert.hooks.installed"),
                  text + (uninstall ? "" : "\n\n" + S.t("alert.hooks.restart")))
        } catch {
            alert(S.t("alert.installer.error"), "\(error)")
        }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
