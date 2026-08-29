import AppKit
import SwiftUI
import ServiceManagement

final class AppController: NSObject, NSMenuDelegate {
    let store = SessionStore()
    let api = ClaudeAPI()
    let vm = PetViewModel()
    let settings = Settings.shared

    private var panel: PetPanel!
    private var hosting: NSHostingView<PetView>!
    private var statusItem: NSStatusItem!
    private var hooks: HookWatcher!
    private var tickTimer: Timer?
    private var pollTimer: Timer?
    private var tick = 0
    private var look: SpriteLook
    private var pixelSpecies: PixelSpecies
    private var lastMomentId = 0
    private var quipText = ""
    private var quipUntil = Date.distantPast
    private var particleCounter = 0
    private var apiStatus = "noch nicht abgefragt"
    private var apiBackoffUntil = Date.distantPast
    private var lastChatPoll = Date.distantPast
    private var lastUsagePoll = Date.distantPast
    private var usage: ClaudeAPI.Usage?
    private let bg = DispatchQueue(label: "buddy.api", qos: .utility)

    override init() {
        look = settings.currentLook()
        pixelSpecies = settings.currentPixelSpecies()
        super.init()
    }

    // MARK: Lifecycle

    func start() {
        vm.theme = settings.theme
        vm.fontSize = settings.size.fontSize
        vm.cell = settings.size.cell
        vm.style = settings.style
        vm.card = settings.card
        vm.usageMode = settings.usageMode

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
        panel.onRightClick = { [weak self] ev in self?.showContextMenu(ev) }
        panel.onMoved = { [weak self] in
            guard let self = self else { return }
            self.settings.panelOrigin = self.panel.frame.origin
        }
        placePanel()
        panel.orderFrontRegardless()

        setupStatusItem()

        hooks = HookWatcher { [weak self] ev in
            DispatchQueue.main.async { self?.store.apply(hook: ev) }
        }
        hooks.start()

        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.onTick() }
        tickTimer?.tolerance = 0.05
        pollTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in self?.poll() }
        pollTimer?.tolerance = 1
        poll()

        quip("Buddy ist da.", seconds: 4)
        onTick()
    }

    private func panelSize() -> NSSize {
        let fs = settings.size.fontSize
        let usageH: CGFloat = settings.usageMode == .off ? 0 : fs * 0.72 * 1.3 + 4
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
        let screen = NSScreen.main ?? NSScreen.screens.first
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = settings.panelOrigin ?? NSPoint(x: vis.maxX - size.width - 24, y: vis.minY + 24)
        // keep on screen
        origin.x = min(max(origin.x, vis.minX - size.width + 60), vis.maxX - 60)
        origin.y = min(max(origin.y, vis.minY - size.height + 60), vis.maxY - 60)
        panel.setFrameOrigin(origin)
    }

    // MARK: Tick / animation

    private func onTick() {
        tick += 1
        if tick % 40 == 0 { store.prune() }

        let state = store.globalState
        let focus = store.focus
        let now = Date()
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
        else if state == .sleeping { eye = "-" }
        else if tick % 16 == 0 { eye = "-" }   // blink
        if settings.style == .pixel {
            let n = max(1, pixelSpecies.frames.count)
            let frame: Int
            if state == .working || state == .thinking {
                frame = tick % n                                   // busy: continuous wiggle
            } else {
                let phase = (tick / 2) % (n + 5)                   // idle: short wiggle burst, then rest
                frame = phase < n ? phase : 0
            }
            let wink: Int? = (eye == nil && tick % 44 == 22) ? 0 : nil   // occasional wink with the left eye
            let px = PixelRenderer.render(species: pixelSpecies, frame: frame, hat: look.hat, eyes: look.eyes,
                                          eyeOverride: eye, wink: wink, flat: settings.flat)
            if px != vm.pixels { vm.pixels = px }
            let breath = (tick / 2) % 2 == 0
            if breath != vm.breath { vm.breath = breath }
        } else {
            let frame = state == .working ? tick % 3 : (tick / 2) % 3
            let rows = SpriteComposer.render(look: look, frame: frame, eyeOverride: eye)
            if rows != vm.rows { vm.rows = rows }
        }

        // Bubble
        var text = ""
        var accent = false
        if let f = focus, state == .attention {
            text = f.detail.isEmpty ? "\(f.title): braucht dich" : "\(f.title): \(f.detail)"; accent = true
        } else if let m = errM {
            text = "✗ " + m.text; accent = true
        } else if let m = doneM {
            text = "✓ " + m.text
        } else if let m = attM {
            text = m.text; accent = true
        } else if petM != nil {
            text = "♥ " + Quips.pick(["danke", "jaaa", "noch mal", "mhm", "fein"], seed: tick / 10)
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
        case .sleeping: label = hooks.hooksInstalled ? "keine Sessions" : "Hooks nicht installiert"
        default:
            let counts = store.counts
            var parts: [String] = []
            if let n = counts[.attention], n > 0 { parts.append("\(n) braucht dich") }
            if let n = counts[.working], n > 0 { parts.append("\(n) arbeitet") }
            if let n = counts[.thinking], n > 0 { parts.append("\(n) denkt") }
            if let n = counts[.ready], n > 0 { parts.append("\(n) bereit") }
            if let n = counts[.idle], n > 0 { parts.append("\(n) idle") }
            label = parts.joined(separator: " · ")
        }
        if label != vm.label { vm.label = label }

        // Usage strip
        if settings.usageMode != .off, tick % 4 == 0 { updateUsageText(now: now, label: label) }

        // Idle chatter
        if settings.quips, tick % 480 == 0, state == .idle || state == .sleeping || state == .ready {
            quip(Quips.pick(Quips.idle, seed: tick / 480 + Int(now.timeIntervalSince1970) % 7), seconds: 6)
        }
    }

    private func bar(_ percent: Double, width: Int = 10) -> String {
        let filled = max(0, min(width, Int((percent / 100 * Double(width)).rounded())))
        return String(repeating: "▓", count: filled) + String(repeating: "░", count: width - filled)
    }

    private func relative(_ date: Date?, now: Date) -> String {
        guard let d = date else { return "" }
        let s = Int(d.timeIntervalSince(now))
        if s <= 0 { return "jetzt" }
        let h = s / 3600, m = (s % 3600) / 60, days = s / 86400
        if days >= 1 { return "in \(days)d \(h % 24)h" }
        if h >= 1 { return "in \(h)h \(m)m" }
        return "in \(m)m"
    }

    private func updateUsageText(now: Date, label: String) {
        guard let u = usage, !u.windows.isEmpty else {
            let placeholder = api.lastError == nil ? "Usage lädt…" : "Usage: nicht verfügbar"
            if vm.usageLine != placeholder { vm.usageLine = placeholder }
            if vm.tickerText != placeholder { vm.tickerText = placeholder }
            return
        }
        // Bar: the two main windows.
        let main = u.windows.prefix(2).map { w in "\(w.label) \(bar(w.percent)) \(Int(w.percent.rounded()))%" }
        let line = main.joined(separator: "  ")
        if vm.usageLine != line { vm.usageLine = line }
        // Ticker: everything, with resets and the session summary.
        var parts: [String] = u.windows.map { w in
            var s = "\(w.label): \(Int(w.percent.rounded()))%"
            let r = relative(w.resetsAt, now: now)
            if !r.isEmpty { s += " (Reset \(r))" }
            return s
        }
        if !label.isEmpty { parts.append(label) }
        let ticker = parts.joined(separator: "   ·   ")
        if vm.tickerText != ticker { vm.tickerText = ticker }
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

    // MARK: Polling

    private func poll() {
        guard Date() >= apiBackoffUntil else { return }
        guard settings.pollCowork || settings.pollChats || settings.usageMode != .off else { return }
        let wantChats = settings.pollChats && Date().timeIntervalSince(lastChatPoll) > 20
        let wantUsage = settings.usageMode != .off && Date().timeIntervalSince(lastUsagePoll) > 60
        bg.async { [weak self] in
            guard let self = self else { return }
            guard self.api.ensureCredentials() != nil else {
                DispatchQueue.main.async {
                    self.apiStatus = "Cookie: \(self.api.lastError ?? "unbekannt")"
                    self.apiBackoffUntil = Date().addingTimeInterval(60)
                }
                return
            }
            if self.settings.pollCowork {
                self.api.fetchCodeSessions { res in
                    DispatchQueue.main.async {
                        switch res {
                        case .success(let list):
                            self.store.apply(api: list)
                            self.apiStatus = "verbunden · \(list.count) Sessions"
                        case .failure(let e):
                            self.apiStatus = "Fehler: \(e)"
                            self.apiBackoffUntil = Date().addingTimeInterval(30)
                        }
                    }
                }
            }
            if wantChats {
                self.lastChatPoll = Date()
                self.api.fetchChats { res in
                    DispatchQueue.main.async {
                        if case .success(let list) = res { self.store.apply(chats: list) }
                    }
                }
            }
            if wantUsage {
                self.lastUsagePoll = Date()
                self.api.fetchUsage { res in
                    DispatchQueue.main.async {
                        if case .success(let u) = res { self.usage = u }
                    }
                }
            }
        }
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
        let header = NSMenuItem(title: "Buddy \(state.label) · Cowork/Chat: \(apiStatus)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let sessions = store.visibleSessions
        if sessions.isEmpty {
            let it = NSMenuItem(title: "Keine aktiven Sessions", action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        } else {
            for s in sessions.prefix(15) {
                let title = "\(dot(for: s.state)) \(s.source.glyph) \(s.title) — \(s.state.label)\(s.detail.isEmpty ? "" : " · \(s.detail)")"
                let it = NSMenuItem(title: title, action: #selector(openSession(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = s.id
                menu.addItem(it)
            }
        }
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
        addSub(look, "Stil", styleMenu)
        let speciesMenu = NSMenu()
        if settings.style == .pixel {
            for sp in PixelBank.all {
                let it = NSMenuItem(title: sp.name, action: #selector(pickSpecies(_:)), keyEquivalent: "")
                it.target = self; it.representedObject = sp.id
                it.state = sp.id == pixelSpecies.id ? .on : .off
                speciesMenu.addItem(it)
            }
        } else {
            for sp in SpriteBank.all {
                let it = NSMenuItem(title: sp.name, action: #selector(pickSpecies(_:)), keyEquivalent: "")
                it.target = self; it.representedObject = sp.id
                it.state = sp.id == self.look.species.id ? .on : .off
                speciesMenu.addItem(it)
            }
        }
        addSub(look, "Spezies", speciesMenu)
        let hatMenu = NSMenu()
        for h in Hat.allCases {
            let it = NSMenuItem(title: h.label, action: #selector(pickHat(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = h.rawValue
            it.state = h == self.look.hat ? .on : .off
            hatMenu.addItem(it)
        }
        addSub(look, "Hut", hatMenu)
        let eyeMenu = NSMenu()
        for e in EyeStyle.allCases {
            let it = NSMenuItem(title: e.label, action: #selector(pickEyes(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = e.rawValue
            it.state = e == self.look.eyes ? .on : .off
            eyeMenu.addItem(it)
        }
        addSub(look, "Augen", eyeMenu)
        let themeMenu = NSMenu()
        for t in Theme.allCases {
            let it = NSMenuItem(title: t.label, action: #selector(pickTheme(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = t.rawValue
            it.state = t == settings.theme ? .on : .off
            themeMenu.addItem(it)
        }
        addSub(look, "Farbe", themeMenu)
        let sizeMenu = NSMenu()
        for s in PetSize.allCases {
            let it = NSMenuItem(title: s.label, action: #selector(pickSize(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = s.rawValue
            it.state = s == settings.size ? .on : .off
            sizeMenu.addItem(it)
        }
        addSub(look, "Größe", sizeMenu)
        let usageMenu = NSMenu()
        for m in UsageMode.allCases {
            let it = NSMenuItem(title: m.label, action: #selector(pickUsage(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = m.rawValue
            it.state = m == settings.usageMode ? .on : .off
            usageMenu.addItem(it)
        }
        addSub(look, "Usage-Anzeige", usageMenu)
        look.addItem(toggle("Outline & Schattierung", !settings.flat, #selector(toggleFlat)))
        look.addItem(toggle("Karte hinter dem Buddy", settings.card, #selector(toggleCard)))
        let shuffle = NSMenuItem(title: "Neu auswürfeln", action: #selector(shuffleLook), keyEquivalent: "")
        shuffle.target = self
        look.addItem(shuffle)
        addSub(menu, "Aussehen", look)

        // Verhalten
        let beh = NSMenu()
        beh.addItem(toggle("Sprüche", settings.quips, #selector(toggleQuips)))
        beh.addItem(toggle("Töne", settings.sounds, #selector(toggleSounds)))
        beh.addItem(toggle("Cowork-Sessions abfragen", settings.pollCowork, #selector(togglePollCowork)))
        beh.addItem(toggle("Chats abfragen", settings.pollChats, #selector(togglePollChats)))
        beh.addItem(.separator())
        let inst = NSMenuItem(title: hooks.hooksInstalled ? "Claude-Code-Hooks neu installieren…" : "Claude-Code-Hooks installieren…", action: #selector(installHooks), keyEquivalent: "")
        inst.target = self
        beh.addItem(inst)
        let uninst = NSMenuItem(title: "Claude-Code-Hooks entfernen…", action: #selector(uninstallHooks), keyEquivalent: "")
        uninst.target = self
        beh.addItem(uninst)
        addSub(menu, "Verhalten", beh)

        menu.addItem(toggle("Beim Login starten", launchAtLogin, #selector(toggleLaunchAtLogin)))
        let reset = NSMenuItem(title: "Position zurücksetzen", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        let openClaude = NSMenuItem(title: "Claude öffnen", action: #selector(openClaudeApp), keyEquivalent: "")
        openClaude.target = self
        menu.addItem(openClaude)
        let log = NSMenuItem(title: "Event-Log anzeigen", action: #selector(showLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Buddy beenden", action: #selector(quit), keyEquivalent: "q")
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
        guard let id = sender.representedObject as? String else { return }
        if id.hasPrefix("api:") || id.hasPrefix("chat:") { openClaudeApp() }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Utilities/Terminal.app")) }
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
        quip("Hallo, ich bin \(settings.style == .pixel ? pixelSpecies.name : look.species.name).", seconds: 4)
    }
    @objc private func pickUsage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = UsageMode(rawValue: raw) else { return }
        settings.usageMode = m
        vm.usageMode = m
        lastUsagePoll = .distantPast
        placePanel()
        poll()
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
        quip("Neu: \(settings.style == .pixel ? pixelSpecies.name : look.species.name).", seconds: 4)
    }
    @objc private func toggleCard() { settings.card.toggle(); vm.card = settings.card }
    @objc private func toggleFlat() { settings.flat.toggle() }
    @objc private func toggleQuips() { settings.quips.toggle() }
    @objc private func toggleSounds() { settings.sounds.toggle() }
    @objc private func togglePollCowork() { settings.pollCowork.toggle(); if settings.pollCowork { poll() } else { store.apply(api: []) } }
    @objc private func togglePollChats() { settings.pollChats.toggle(); if !settings.pollChats { store.apply(chats: []) } }
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
            alert("Login-Start konnte nicht geändert werden", "\(error)")
        }
    }

    @objc private func installHooks() { runHookInstaller(uninstall: false) }
    @objc private func uninstallHooks() { runHookInstaller(uninstall: true) }

    private func runHookInstaller(uninstall: Bool) {
        guard let script = Bundle.main.path(forResource: "install-hooks", ofType: "py") else {
            alert("Installer fehlt", "install-hooks.py liegt nicht im App-Bundle."); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", script] + (uninstall ? ["--uninstall"] : [])
        let out = Pipe()
        p.standardOutput = out; p.standardError = out
        do {
            try p.run(); p.waitUntilExit()
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            alert(uninstall ? "Hooks entfernt" : "Hooks installiert",
                  text + (uninstall ? "" : "\n\nLaufende Claude-Code-Sessions laden Hooks erst nach einem Neustart."))
        } catch {
            alert("Installer-Fehler", "\(error)")
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
