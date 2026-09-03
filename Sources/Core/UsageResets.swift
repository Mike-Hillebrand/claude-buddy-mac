import Foundation

// MARK: - Plan reset display (read-only)
//
// Buddy does NOT fetch plan usage — reusing the desktop app's session cookie against internal
// endpoints is exactly what logged the account out (removed in 1.3.0, never coming back).
//
// Instead Buddy *reads* a snapshot file (~/Library/Application Support/Buddy/usage-snapshot.json)
// that buddy-statusline.sh writes from the `rate_limits` block Claude Code pipes to its status
// line. Same JSON shape the old Claude-Usage widget used, so that file still works as a fallback.
// No network, no cookie, no keychain. This file is pure parsing + formatting, Foundation-only.

struct ResetBar: Equatable {
    var pct: Double
    var resetsAt: Date?
}

struct UsageResets: Equatable {
    var session: ResetBar        // the ~5h window
    var weekly: ResetBar         // the weekly ("all models") limit
    var updatedAt: Date?
    var error: String?
}

enum UsageSnapshotParser {
    /// Parse the widget's `UsageSnapshot` JSON: { session:{pct,resetsAt}, weeklyAll:{…}, updatedAt, error }.
    static func parse(_ data: Data) -> UsageResets? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func date(_ v: Any?) -> Date? {
            guard let s = v as? String else { return nil }
            return isoFrac.date(from: s) ?? iso.date(from: s)
        }
        func bar(_ v: Any?) -> ResetBar {
            let m = v as? [String: Any] ?? [:]
            let pct = (m["pct"] as? Double) ?? (m["pct"] as? NSNumber)?.doubleValue ?? 0
            return ResetBar(pct: pct, resetsAt: date(m["resetsAt"]))
        }
        return UsageResets(session: bar(obj["session"]), weekly: bar(obj["weeklyAll"]),
                           updatedAt: date(obj["updatedAt"]), error: obj["error"] as? String)
    }

    /// Compact one-liner: "⏳ 5h 42% → 15:12 · Woche 55% → Mi 14:00". nil if there's nothing usable.
    static func line(_ r: UsageResets, now: Date = Date()) -> String? {
        if let e = r.error, !e.isEmpty { return nil }
        var parts: [String] = []
        func seg(_ label: String, _ bar: ResetBar, weekly: Bool) {
            let pctStr = bar.pct > 0 ? " \(Int(bar.pct.rounded()))%" : ""
            if let reset = bar.resetsAt {
                parts.append("\(label)\(pctStr) → \(whenStr(reset, now: now, weekly: weekly))")
            } else if bar.pct > 0 {
                parts.append("\(label)\(pctStr)")
            }
        }
        seg("5h", r.session, weekly: false)
        seg(S.t("usage.week"), r.weekly, weekly: true)
        return parts.isEmpty ? nil : "⏳ " + parts.joined(separator: " · ")
    }

    /// True if the snapshot is fresh enough to show (its writer ran recently).
    static func isFresh(_ r: UsageResets, now: Date = Date(), within: TimeInterval = 2 * 3600) -> Bool {
        guard let u = r.updatedAt else { return false }
        return now.timeIntervalSince(u) <= within && now.timeIntervalSince(u) >= -300
    }

    // MARK: formatting

    /// Session (≤24h away) → "15:12"; otherwise / weekly → "Mi 14:00" (localized weekday).
    private static func whenStr(_ date: Date, now: Date, weekly: Bool) -> String {
        let soon = date.timeIntervalSince(now) < 24 * 3600 && date.timeIntervalSince(now) > -3600
        let f = DateFormatter()
        f.locale = Locale(identifier: S.lang == .de ? "de_DE" : "en_US")
        f.timeZone = .current
        f.dateFormat = (!weekly && soon) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: date)
    }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
}
