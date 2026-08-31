import Foundation

// MARK: - Local Claude Code usage (no network)
//
// Claude Code writes every session as JSON lines under ~/.claude/projects/**/*.jsonl.
// Assistant lines carry `message.usage` with token counts and a UTC `timestamp`.
// This file is pure parsing + math so it stays Foundation-only and unit-testable —
// the actual file tailing lives in the App layer (LocalUsageWatcher). No cookies,
// no keychain, no Anthropic endpoints: it only reads files that are already on disk.

struct UsageTotals: Equatable {
    var input = 0          // fresh input tokens
    var output = 0         // generated tokens
    var cacheCreate = 0    // cache-write tokens
    var cacheRead = 0      // cache-read tokens
    var turns = 0          // assistant messages counted

    /// Everything processed, cache included — the "how busy was today" number.
    var total: Int { input + output + cacheCreate + cacheRead }

    static func += (lhs: inout UsageTotals, rhs: UsageTotals) {
        lhs.input += rhs.input
        lhs.output += rhs.output
        lhs.cacheCreate += rhs.cacheCreate
        lhs.cacheRead += rhs.cacheRead
        lhs.turns += rhs.turns
    }
}

enum LocalUsage {
    /// Parse one JSONL line. Returns the UTC day (yyyy-MM-dd), the model, and the token
    /// deltas — or nil if the line has no assistant usage.
    static func parse(line: String) -> (day: String, model: String, tokens: UsageTotals)? {
        guard line.contains("\"usage\"") else { return nil }               // cheap pre-filter
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any] else { return nil }
        let ts = (obj["timestamp"] as? String) ?? ""
        let day = ts.count >= 10 ? String(ts.prefix(10)) : ""
        let model = (msg["model"] as? String) ?? ""
        func n(_ k: String) -> Int {
            if let v = usage[k] as? Int { return v }
            if let v = usage[k] as? Double { return Int(v) }
            return 0
        }
        var t = UsageTotals()
        t.input = n("input_tokens")
        t.output = n("output_tokens")
        t.cacheCreate = n("cache_creation_input_tokens")
        t.cacheRead = n("cache_read_input_tokens")
        t.turns = 1
        return (day, model, t)
    }

    /// Rough cost estimate in USD. Prices are editable constants and only an estimate;
    /// on a subscription plan this is a "what it would cost on the API" reference, not a bill.
    /// Per-million-token prices: (input, output, cacheWrite, cacheRead).
    static func pricePerMTok(model: String) -> (Double, Double, Double, Double) {
        let m = model.lowercased()
        if m.contains("opus")  { return (15.0, 75.0, 18.75, 1.50) }
        if m.contains("haiku") { return (0.80,  4.0,  1.00, 0.08) }
        return (3.0, 15.0, 3.75, 0.30)                       // sonnet / default
    }

    static func costUSD(model: String, tokens: UsageTotals) -> Double {
        let p = pricePerMTok(model: model)
        return (Double(tokens.input)       * p.0
              + Double(tokens.output)      * p.1
              + Double(tokens.cacheCreate) * p.2
              + Double(tokens.cacheRead)   * p.3) / 1_000_000.0
    }

    /// 107228445 → "107M", 245369 → "245k", 940 → "940".
    static func human(_ n: Int) -> String {
        if n >= 1_000_000 {
            let m = Double(n) / 1_000_000.0
            return m >= 100 ? "\(Int(m.rounded()))M" : String(format: "%.1fM", m)
        }
        if n >= 1_000 {
            let k = Double(n) / 1_000.0
            return k >= 100 ? "\(Int(k.rounded()))k" : String(format: "%.1fk", k)
        }
        return "\(n)"
    }
}
