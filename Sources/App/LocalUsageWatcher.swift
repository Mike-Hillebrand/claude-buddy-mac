import Foundation

/// Tails ~/.claude/projects/**/*.jsonl and sums *today's* Claude Code usage.
///
/// Fully local: it only reads files already on disk (the same logs Claude Code writes for
/// itself). No network, no cookies, no keychain, no Anthropic endpoints. This is the safe
/// replacement for the removed cloud usage polling.
final class LocalUsageWatcher {
    struct Snapshot: Equatable {
        var totals = UsageTotals()
        var costUSD: Double = 0
        var lastActivity: Date? = nil     // newest log mtime seen today
        var day = ""                      // UTC yyyy-MM-dd this snapshot covers
    }

    private(set) var snapshot = Snapshot()
    var onChange: ((Snapshot) -> Void)?

    private let root: URL
    private var offsets: [String: UInt64] = [:]   // file path → bytes already consumed
    private var timer: Timer?

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    func start() {
        snapshot.day = Self.todayUTC()
        rescan()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.rescan() }
        timer?.tolerance = 5
    }

    func stop() { timer?.invalidate(); timer = nil }

    // MARK: - Scan

    private func rescan() {
        let day = Self.todayUTC()
        if day != snapshot.day {                       // midnight rollover → start fresh
            snapshot = Snapshot(); snapshot.day = day; offsets.removeAll()
        }
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root,
                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                     options: [.skipsHiddenFiles]) else { return }
        var changed = false
        var newest = snapshot.lastActivity
        let dayStart = Self.startOfTodayUTC()

        for case let url as URL in en where url.pathExtension == "jsonl" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let touchedToday = (mtime ?? .distantPast) >= dayStart
            // Only files touched today can hold today's lines — unless we're already tailing them.
            guard touchedToday || offsets[url.path] != nil else { continue }

            let from = offsets[url.path] ?? 0
            guard let (chunk, consumed) = readNew(url, from: from) else { continue }
            offsets[url.path] = consumed
            if chunk.isEmpty { continue }

            for raw in chunk.split(separator: "\n") {
                guard let (d, model, t) = LocalUsage.parse(line: String(raw)), d == day else { continue }
                snapshot.totals += t
                snapshot.costUSD += LocalUsage.costUSD(model: model, tokens: t)
                changed = true
            }
            if touchedToday, let m = mtime, m > (newest ?? .distantPast) { newest = m }
        }

        if newest != snapshot.lastActivity { snapshot.lastActivity = newest; changed = true }
        if changed { onChange?(snapshot) }
    }

    /// Read appended bytes from `from` up to the last complete line. Returns the text plus the
    /// new consumed offset (advanced only past the last newline, so a half-written trailing line
    /// is re-read next time instead of being lost).
    private func readNew(_ url: URL, from: UInt64) -> (String, UInt64)? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let end = (try? fh.seekToEnd()) ?? 0
        var start = from
        if end < start { start = 0 }                   // file shrank/rotated → re-read
        guard end > start else { return ("", end) }
        try? fh.seek(toOffset: start)
        let data = (try? fh.readToEnd()) ?? Data()
        guard let nl = data.lastIndex(of: 0x0A) else { return ("", start) }   // no full line yet
        let upTo = data.index(after: nl)               // include the newline
        let complete = data.subdata(in: data.startIndex..<upTo)
        let consumed = start + UInt64(upTo - data.startIndex)
        return (String(decoding: complete, as: UTF8.self), consumed)
    }

    // MARK: - Day helpers (UTC, to match the logs' own timestamps)

    private static func utcFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
    static func todayUTC() -> String { utcFormatter().string(from: Date()) }
    static func startOfTodayUTC() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.startOfDay(for: Date())
    }
}
