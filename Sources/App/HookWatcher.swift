import Foundation

/// Tails `~/Library/Application Support/Buddy/events.jsonl` (written by buddy-hook.sh).
final class HookWatcher {
    static let appSupportDir = NSString(string: "~/Library/Application Support/Buddy").expandingTildeInPath
    static let eventsPath = appSupportDir + "/events.jsonl"
    static let hookScriptPath = appSupportDir + "/buddy-hook.sh"

    private var offset: UInt64 = 0
    private var remainder = ""
    private var timer: Timer?
    private let onEvent: (SessionStore.HookEvent) -> Void

    init(onEvent: @escaping (SessionStore.HookEvent) -> Void) {
        self.onEvent = onEvent
        try? FileManager.default.createDirectory(atPath: Self.appSupportDir, withIntermediateDirectories: true)
        rotateIfHuge()
        // Replay the tail so a restart of Buddy picks up sessions that are still alive.
        replayTail(maxBytes: 64 * 1024)
    }

    func start(interval: TimeInterval = 0.5) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        timer?.tolerance = 0.2
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// True only when the script exists AND ~/.claude/settings.json still references it.
    /// Other tools rewrite that file and silently drop our entries (happened 2026-08-31 and went
    /// unnoticed for three days because this used to check the script file only).
    var hooksInstalled: Bool {
        guard FileManager.default.isExecutableFile(atPath: Self.hookScriptPath) else { return false }
        return registeredInSettings
    }

    private static let settingsPath = NSString(string: "~/.claude/settings.json").expandingTildeInPath
    private var registrationCache: (mod: Date?, value: Bool)?
    /// Re-read only when the file's modification date changes — this is polled every tick while sleeping.
    private var registeredInSettings: Bool {
        let mod = (try? FileManager.default.attributesOfItem(atPath: Self.settingsPath))?[.modificationDate] as? Date
        if let c = registrationCache, c.mod == mod { return c.value }
        let value = (try? String(contentsOfFile: Self.settingsPath, encoding: .utf8))?.contains("buddy-hook.sh") ?? false
        registrationCache = (mod, value)
        return value
    }

    private func rotateIfHuge() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.eventsPath)
        if let size = attrs?[.size] as? UInt64, size > 5 * 1024 * 1024 {
            try? FileManager.default.removeItem(atPath: Self.eventsPath)
        }
    }

    private func replayTail(maxBytes: Int) {
        guard let fh = FileHandle(forReadingAtPath: Self.eventsPath) else { return }
        defer { fh.closeFile() }
        let size = fh.seekToEndOfFile()
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        fh.seek(toFileOffset: start)
        let data = fh.readDataToEndOfFile()
        offset = size
        guard var text = String(data: data, encoding: .utf8) else { return }
        if start > 0, let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }
        let cutoff = Date().addingTimeInterval(-30 * 60)
        for line in text.split(separator: "\n") {
            if let ev = SessionStore.HookEvent(jsonLine: String(line)), ev.ts >= cutoff { onEvent(ev) }
        }
    }

    private func poll() {
        guard let fh = FileHandle(forReadingAtPath: Self.eventsPath) else { return }
        defer { fh.closeFile() }
        let size = fh.seekToEndOfFile()
        if size < offset { offset = 0; remainder = "" }   // file was rotated / truncated
        guard size > offset else { return }
        fh.seek(toFileOffset: offset)
        let data = fh.readDataToEndOfFile()
        offset = size
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        var text = remainder + chunk
        remainder = ""
        if !text.hasSuffix("\n"), let nl = text.lastIndex(of: "\n") {
            remainder = String(text[text.index(after: nl)...])
            text = String(text[...nl])
        } else if !text.hasSuffix("\n") {
            remainder = text; return
        }
        for line in text.split(separator: "\n") {
            if let ev = SessionStore.HookEvent(jsonLine: String(line)) { onEvent(ev) }
        }
    }
}
