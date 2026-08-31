import Foundation

enum Lang: String, CaseIterable {
    case de, en
    var label: String { self == .de ? "Deutsch" : "English" }
}

/// Tiny string table. `S.t("key")` returns the string for the active language.
enum S {
    static var lang: Lang = .de

    static func t(_ key: String) -> String {
        guard let entry = table[key] else { return key }
        return lang == .de ? entry.0 : entry.1
    }

    /// Species / hat / eye display names by id.
    static func name(_ id: String) -> String { t("name." + id) }

    // key: (de, en)
    private static let table: [String: (String, String)] = [
        // states
        "state.sleeping": ("schläft", "sleeping"),
        "state.idle": ("idle", "idle"),
        "state.ready": ("bereit", "ready"),
        "state.thinking": ("denkt", "thinking"),
        "state.working": ("arbeitet", "working"),
        "state.attention": ("braucht dich", "needs you"),
        // store texts
        "permit": ("Erlauben", "Allow"),
        "permit.q": ("Erlauben?", "Allow?"),
        "waiting.input": ("wartet auf Input", "waiting for input"),
        "waiting.you": ("wartet auf dich", "is waiting for you"),
        "done": ("fertig", "done"),
        "failed": ("fehlgeschlagen", "failed"),
        "tool.failed": ("fehlgeschlagen", "failed"),
        "tool": ("Tool", "Tool"),
        "api.error": ("API-Fehler", "API error"),
        "needs.you": ("braucht dich", "needs you"),
        "approval.needed": ("Freigabe nötig", "approval needed"),
        "subagent": ("Subagent", "subagent"),
        "chat": ("Chat", "Chat"),
        // labels
        "no.sessions": ("keine Sessions", "no sessions"),
        "hooks.missing": ("Hooks nicht installiert", "hooks not installed"),
        "n.attention": ("braucht dich", "need you"),
        "n.attention.1": ("braucht dich", "needs you"),
        "n.working": ("arbeitet", "working"),
        "n.thinking": ("denkt", "thinking"),
        "n.ready": ("bereit", "ready"),
        "n.idle": ("idle", "idle"),
        "usage.loading": ("Usage lädt…", "loading usage…"),
        "usage.unavailable": ("Usage: nicht verfügbar", "usage: unavailable"),
        "reset": ("Reset", "resets"),
        "now": ("jetzt", "now"),
        "in": ("in", "in"),
        // bubbles
        "hello": ("Buddy ist da.", "Buddy is here."),
        "iam": ("Hallo, ich bin", "Hi, I'm"),
        "new": ("Neu", "New"),
        "thanks.0": ("danke", "thanks"),
        "thanks.1": ("jaaa", "yesss"),
        "thanks.2": ("noch mal", "again"),
        "thanks.3": ("mhm", "mhm"),
        "thanks.4": ("fein", "nice"),
        // menu
        "menu.header": ("Buddy", "Buddy"),
        "menu.cowork": ("Cowork/Chat", "Cowork/chat"),
        "menu.no.sessions": ("Keine aktiven Sessions", "No active sessions"),
        "menu.look": ("Aussehen", "Look"),
        "menu.style": ("Stil", "Style"),
        "menu.species": ("Spezies", "Species"),
        "menu.hat": ("Hut", "Hat"),
        "menu.eyes": ("Augen", "Eyes"),
        "menu.color": ("Farbe", "Color"),
        "menu.size": ("Größe", "Size"),
        "menu.usage": ("Usage-Anzeige", "Usage display"),
        "menu.outline": ("Outline & Schattierung", "Outline & shading"),
        "menu.card": ("Karte hinter dem Buddy", "Card behind the buddy"),
        "menu.shuffle": ("Neu auswürfeln", "Shuffle look"),
        "menu.behavior": ("Verhalten", "Behavior"),
        "menu.quips": ("Sprüche", "Quips"),
        "menu.wander": ("Am Bildschirmrand herumlaufen", "Wander along the screen edges"),
        "menu.mic": ("Sprach-Button anzeigen", "Show voice button"),
        "menu.update.check": ("Auf Updates prüfen", "Check for updates"),
        "update.available": ("Update %@ verfügbar", "Update %@ available"),
        "mic.opening": ("Quick Entry…", "Quick Entry…"),
        "mic.newchat": ("Neuer Chat…", "New chat…"),
        "mic.needs.ax": ("Für Quick Entry: Bedienungshilfen-Zugriff erlauben", "Allow accessibility access for Quick Entry"),
        "menu.ttt": ("Tic-Tac-Toe spielen", "Play tic-tac-toe"),
        "ttt.you": ("Du", "You"),
        "ttt.buddy": ("Buddy", "Buddy"),
        "ttt.draw": ("Remis", "Draw"),
        "ttt.new": ("Neu", "New"),
        "ttt.yourturn": ("Du bist dran (X).", "Your move (X)."),
        "ttt.mystart": ("Ich fang an.", "I'll start."),
        "ttt.thinking": ("hmm…", "hmm…"),
        "ttt.win": ("Gewonnen!", "I win!"),
        "ttt.lose": ("Na gut. Revanche?", "Fine. Rematch?"),
        "ttt.drawq": ("Remis. Nochmal?", "Draw. Again?"),
        "ttt.bubble.win": ("haha, meins!", "haha, mine!"),
        "ttt.bubble.lose": ("okay okay…", "okay okay…"),
        "ttt.bubble.draw": ("Remis. Fair.", "Draw. Fair."),
        "ttt.bubble.start": ("Los geht's!", "Let's go!"),
        "menu.sounds": ("Töne", "Sounds"),
        "menu.poll.cowork": ("Cowork-Sessions abfragen", "Poll Cowork sessions"),
        "menu.poll.chats": ("Chats abfragen", "Poll chats"),
        "menu.hooks.install": ("Claude-Code-Hooks installieren…", "Install Claude Code hooks…"),
        "menu.hooks.reinstall": ("Claude-Code-Hooks neu installieren…", "Reinstall Claude Code hooks…"),
        "menu.hooks.remove": ("Claude-Code-Hooks entfernen…", "Remove Claude Code hooks…"),
        "menu.language": ("Sprache / Language", "Language / Sprache"),
        "menu.login": ("Beim Login starten", "Launch at login"),
        "menu.reset.pos": ("Position zurücksetzen", "Reset position"),
        "menu.open.claude": ("Claude öffnen", "Open Claude"),
        "menu.open.in": ("Sessions öffnen in", "Open sessions in"),
        "open.app": ("Claude-App", "Claude app"),
        "open.browser": ("Browser", "Browser"),
        "menu.open.alt.browser": ("im Browser öffnen", "open in browser"),
        "menu.open.alt.app": ("in der Claude-App öffnen", "open in the Claude app"),
        "menu.reveal": ("Ordner im Finder zeigen", "Show folder in Finder"),
        "menu.log": ("Event-Log anzeigen", "Show event log"),
        "menu.quit": ("Buddy beenden", "Quit Buddy"),
        "api.status.none": ("noch nicht abgefragt", "not polled yet"),
        "api.status.ok": ("verbunden", "connected"),
        "api.status.sessions": ("Sessions", "sessions"),
        "api.status.error": ("Fehler", "error"),
        "api.status.cookie": ("Cookie", "cookie"),
        // alerts
        "alert.login": ("Login-Start konnte nicht geändert werden", "Could not change launch at login"),
        "alert.installer.missing": ("Installer fehlt", "Installer missing"),
        "alert.installer.missing.text": ("install-hooks.py liegt nicht im App-Bundle.", "install-hooks.py is not in the app bundle."),
        "alert.hooks.removed": ("Hooks entfernt", "Hooks removed"),
        "alert.hooks.installed": ("Hooks installiert", "Hooks installed"),
        "alert.hooks.restart": ("Laufende Claude-Code-Sessions laden Hooks erst nach einem Neustart.", "Running Claude Code sessions pick up hooks after a restart."),
        "alert.installer.error": ("Installer-Fehler", "Installer error"),
        // styles / sizes / usage modes / themes
        "style.pixel": ("Pixel (gefüllt)", "Pixel (filled)"),
        "style.ascii": ("ASCII (Terminal)", "ASCII (terminal)"),
        "size.s": ("Klein", "Small"),
        "size.m": ("Mittel", "Medium"),
        "size.l": ("Groß", "Large"),
        "size.xl": ("Riesig", "Huge"),
        "usage.off": ("Aus", "Off"),
        "usage.bar": ("Balken", "Bar"),
        "usage.ticker": ("Laufschrift", "Ticker"),
        "theme.terracotta": ("Claude Terracotta", "Claude terracotta"),
        "theme.red": ("Blocky Red", "Blocky red"),
        "theme.lime": ("Lime", "Lime"),
        "theme.azurio": ("Azurio Blau", "Azurio blue"),
        "theme.ink": ("Tinte", "Ink"),
        "theme.snow": ("Weiß", "White"),
        // hats
        "name.none": ("Kein Hut", "No hat"),
        "name.tophat": ("Zylinder", "Top hat"),
        "name.cap": ("Cap", "Cap"),
        "name.crown": ("Krone", "Crown"),
        "name.beanie": ("Beanie", "Beanie"),
        "name.party": ("Partyhut", "Party hat"),
        "name.halo": ("Heiligenschein", "Halo"),
        "name.wizard": ("Zauberhut", "Wizard hat"),
        "name.bow": ("Schleife", "Bow"),
        // eyes
        "name.dot": ("Punkt", "Dot"),
        "name.wide": ("Groß", "Wide"),
        "name.sleepy": ("Müde", "Sleepy"),
        "name.sparkle": ("Funkeln", "Sparkle"),
        "name.happy": ("Happy", "Happy"),
        // species
        "name.clawd": ("Clawd", "Clawd"),
        "name.blob": ("Blob", "Blob"),
        "name.cat": ("Katze", "Cat"),
        "name.duck": ("Ente", "Duck"),
        "name.ghost": ("Geist", "Ghost"),
        "name.robot": ("Roboter", "Robot"),
        "name.penguin": ("Pinguin", "Penguin"),
        "name.octopus": ("Oktopus", "Octopus"),
        "name.rabbit": ("Hase", "Rabbit"),
        "name.dragon": ("Drache", "Dragon"),
        "name.owl": ("Eule", "Owl"),
        "name.axolotl": ("Axolotl", "Axolotl"),
        "name.capybara": ("Capybara", "Capybara"),
        "name.mushroom": ("Pilz", "Mushroom"),
        "name.cactus": ("Kaktus", "Cactus"),
        "name.snail": ("Schnecke", "Snail"),
        "name.turtle": ("Schildkröte", "Turtle"),
        "name.goose": ("Gans", "Goose"),
        "name.chonk": ("Chonk", "Chonk"),
    ]
}

// MARK: - Quips (idle chatter)

enum Quips {
    static var idle: [String] {
        S.lang == .de ? [
            "Alles ruhig. Zu ruhig.",
            "Ich warte. Geduldig. Meistens.",
            "Kaffee wäre jetzt gut.",
            "Keine Session, kein Stress.",
            "Soll ich was kaputt machen? Nein? Ok.",
            "Pixel sind auch nur Zeichen.",
            "Ich hab da eine Idee. Später.",
            "Tab hier, Tab da. Ich zähl mit.",
            "Deployen wir heute noch?",
            "Ich bin 16 Pixel breit. Reicht.",
            "Du starrst mich an. Ich dich auch.",
            "Fokus. Du schaffst das.",
            "Wenn's brennt, hüpf ich.",
        ] : [
            "All quiet. Too quiet.",
            "I'm waiting. Patiently. Mostly.",
            "Coffee would be nice.",
            "No session, no stress.",
            "Want me to break something? No? Ok.",
            "Pixels are just characters with ambition.",
            "I have an idea. Later.",
            "Tab here, tab there. I'm counting.",
            "Are we shipping today?",
            "I'm 16 pixels wide. That's enough.",
            "You're staring at me. Same.",
            "Focus. You've got this.",
            "If something's on fire, I'll jump.",
        ]
    }
    static var working: [String] {
        S.lang == .de ? ["läuft…", "am Werkeln", "gleich", "tippt…", "gräbt…"]
                      : ["running…", "on it", "almost", "typing…", "digging…"]
    }
    static var thanks: [String] {
        (0..<5).map { S.t("thanks.\($0)") }
    }

    static func pick(_ list: [String], seed: Int) -> String {
        guard !list.isEmpty else { return "" }
        return list[abs(seed) % list.count]
    }
}
