import Foundation

// MARK: - States

/// Ordered by priority (higher raw value wins when several sessions are active).
enum PetState: Int, Comparable, CaseIterable {
    case sleeping = 0   // nothing tracked at all
    case idle           // sessions exist, nothing happening
    case ready          // a session finished and waits for review (unread)
    case thinking       // Claude is generating (no tool running)
    case working        // a tool is running
    case attention      // needs input / permission / blocked

    static func < (a: PetState, b: PetState) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .sleeping: return S.t("state.sleeping")
        case .idle: return S.t("state.idle")
        case .ready: return S.t("state.ready")
        case .thinking: return S.t("state.thinking")
        case .working: return S.t("state.working")
        case .attention: return S.t("state.attention")
        }
    }
}

enum SessionSource: String {
    case code = "Code"        // Claude Code (hooks or bridge)
    case cowork = "Cowork"    // Cowork cloud / remote session
    case dispatch = "Dispatch"
    case chat = "Chat"

    var glyph: String {
        switch self {
        case .code: return ">_"
        case .cowork: return "◇"
        case .dispatch: return "◈"
        case .chat: return "○"
        }
    }
}

struct TrackedSession: Identifiable, Equatable {
    let id: String
    var source: SessionSource
    var title: String
    var state: PetState
    var detail: String        // tool name, action description, …
    var updated: Date
    var unread: Bool = false
}

/// A transient thing the pet should react to (celebrate, complain, …).
struct Moment: Equatable {
    enum Kind: Equatable { case done, error, attention, info, pet }
    let kind: Kind
    let text: String
    let at: Date
    let id: Int
}

// MARK: - Store (pure logic, no UI)

final class SessionStore {
    private(set) var sessions: [String: TrackedSession] = [:]
    private(set) var moments: [Moment] = []
    private var momentCounter = 0
    var now: () -> Date = { Date() }

    /// Hook sessions older than this are dropped (Claude Code killed without SessionEnd).
    var hookStaleAfter: TimeInterval = 30 * 60
    /// How long a finished (ready) session stays visible.
    var readyVisibleFor: TimeInterval = 60 * 60
    /// How long a blocked/needs-input API session counts as attention.
    var attentionVisibleFor: TimeInterval = 2 * 60 * 60
    /// Chats: only consider conversations updated within this window.
    var chatWindow: TimeInterval = 3 * 60 * 60

    // MARK: Derived

    var visibleSessions: [TrackedSession] {
        sessions.values.sorted { a, b in
            if a.state != b.state { return a.state > b.state }
            return a.updated > b.updated
        }
    }

    var globalState: PetState {
        visibleSessions.first?.state ?? .sleeping
    }

    /// The session that currently defines the pet's mood.
    var focus: TrackedSession? { visibleSessions.first }

    var counts: [PetState: Int] {
        var c: [PetState: Int] = [:]
        for s in sessions.values { c[s.state, default: 0] += 1 }
        return c
    }

    func recentMoments(within seconds: TimeInterval) -> [Moment] {
        let t = now()
        return moments.filter { t.timeIntervalSince($0.at) <= seconds }
    }

    func addMoment(_ kind: Moment.Kind, _ text: String) {
        momentCounter += 1
        moments.append(Moment(kind: kind, text: text, at: now(), id: momentCounter))
        if moments.count > 20 { moments.removeFirst(moments.count - 20) }
    }

    /// True when Claude Code hooks have delivered anything recently → bridge sessions are duplicates.
    var hooksActive: Bool {
        let t = now()
        return sessions.values.contains { $0.id.hasPrefix("hook:") && t.timeIntervalSince($0.updated) < 5 * 60 }
    }

    // MARK: Hook events

    struct HookEvent {
        var ts: Date
        var event: String
        var session: String
        var cwd: String
        var tool: String
        var type: String
        var agent: String
        var msg: String

        init?(jsonLine: String) {
            guard let data = jsonLine.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let tsNum = (obj["ts"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
            ts = Date(timeIntervalSince1970: tsNum)
            event = obj["event"] as? String ?? ""
            session = obj["session"] as? String ?? ""
            cwd = obj["cwd"] as? String ?? ""
            tool = obj["tool"] as? String ?? ""
            type = obj["type"] as? String ?? ""
            agent = obj["agent"] as? String ?? ""
            msg = obj["msg"] as? String ?? ""
        }
    }

    func apply(hook e: HookEvent) {
        guard !e.session.isEmpty else { return }
        let id = "hook:" + e.session
        let title = e.cwd.isEmpty ? "Claude Code" : (e.cwd as NSString).lastPathComponent
        var s = sessions[id] ?? TrackedSession(id: id, source: .code, title: title, state: .idle, detail: "", updated: e.ts)
        s.updated = e.ts
        if !e.cwd.isEmpty { s.title = title }

        switch e.event {
        case "SessionStart":
            s.state = .idle; s.detail = ""
        case "UserPromptSubmit":
            s.state = .thinking; s.detail = ""; s.unread = false
        case "PreToolUse":
            s.state = .working; s.detail = e.tool
        case "PostToolUse":
            s.state = .thinking; s.detail = e.tool
        case "PostToolUseFailure":
            s.state = .thinking
            addMoment(.error, "\(e.tool.isEmpty ? S.t("tool") : e.tool) \(S.t("tool.failed")) · \(title)")
        case "Notification":
            switch e.type {
            case "permission_prompt":
                s.state = .attention; s.detail = shortPermission(e.msg)
                addMoment(.attention, "\(title): \(s.detail)")
            case "idle_prompt", "agent_needs_input", "elicitation_dialog", "elicitation_url_dialog":
                s.state = .attention; s.detail = S.t("waiting.input")
                addMoment(.attention, "\(title) \(S.t("waiting.you"))")
            case "agent_completed":
                s.state = .ready; s.unread = true
                addMoment(.done, "\(title) \(S.t("done"))")
            default:
                break
            }
        case "Stop":
            let wasBusy = s.state == .working || s.state == .thinking
            s.state = .ready; s.unread = true; s.detail = ""
            if wasBusy { addMoment(.done, "\(title) \(S.t("done"))") }
        case "StopFailure":
            s.state = .idle
            addMoment(.error, "\(S.t("api.error")) · \(title)")
        case "SubagentStart":
            if s.state == .thinking || s.state == .idle { s.state = .working }
            s.detail = e.agent.isEmpty ? S.t("subagent") : e.agent
        case "SubagentStop":
            break
        case "PreCompact":
            s.detail = "compact"
        case "SessionEnd":
            sessions.removeValue(forKey: id)
            return
        default:
            break
        }
        sessions[id] = s
    }

    private func shortPermission(_ msg: String) -> String {
        // "Claude needs your permission to use Bash" → "Erlauben: Bash"
        if let r = msg.range(of: "to use ") {
            return S.t("permit") + ": " + msg[r.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        return msg.isEmpty ? S.t("permit.q") : msg
    }

    // MARK: API sessions (Cowork / bridge)

    struct APISession {
        var id: String
        var title: String
        var status: String        // active | archived
        var workerStatus: String  // idle | running | requires_action
        var bucket: String        // working | review_ready | blocked | failed | completed
        var unread: Bool
        var lastEvent: Date
        var tags: [String]
        var actionDetail: String
    }

    func apply(api list: [APISession]) {
        let t = now()
        let hooks = hooksActive
        var seen = Set<String>()
        for a in list {
            let id = "api:" + a.id
            guard a.status == "active" else { continue }
            let isBridgeCode = a.tags.contains("remote-control-sdk")
            if isBridgeCode && hooks { continue }   // hooks already cover local Claude Code
            let source: SessionSource = a.tags.contains("product:cowork-remote") ? .cowork
                : a.tags.contains("product:cowork") ? .dispatch
                : isBridgeCode ? .code : .cowork
            let age = t.timeIntervalSince(a.lastEvent)
            var state: PetState? = nil
            var detail = ""
            if a.workerStatus == "running" {
                state = .working
            } else if a.workerStatus == "requires_action" {
                state = .attention; detail = a.actionDetail.isEmpty ? S.t("approval.needed") : a.actionDetail
            } else if a.bucket == "blocked" && a.unread && age < attentionVisibleFor {
                state = .attention; detail = S.t("waiting.input")
            } else if (a.bucket == "review_ready" || a.bucket == "completed") && a.unread && age < readyVisibleFor {
                state = .ready
            } else if a.bucket == "failed" && a.unread && age < readyVisibleFor {
                state = .ready; detail = S.t("failed")
            }
            guard let newState = state else { continue }
            seen.insert(id)
            let title = a.title.isEmpty || a.title == "__warming__" ? source.rawValue : a.title
            if var s = sessions[id] {
                let old = s.state
                s.state = newState; s.detail = detail; s.updated = max(a.lastEvent, s.updated); s.unread = a.unread; s.title = title
                sessions[id] = s
                if old == .working && newState == .ready {
                    addMoment(detail == S.t("failed") ? .error : .done, "\(title) \(detail == S.t("failed") ? S.t("failed") : S.t("done"))")
                } else if old != .attention && newState == .attention {
                    addMoment(.attention, "\(title): \(detail)")
                }
            } else {
                sessions[id] = TrackedSession(id: id, source: source, title: title, state: newState, detail: detail, updated: a.lastEvent, unread: a.unread)
                // Fresh attention that appeared while we were not watching (< 2 min) still deserves a nudge.
                if newState == .attention && age < 120 { addMoment(.attention, "\(title): \(detail)") }
            }
        }
        // Drop API sessions that vanished from the list or no longer qualify.
        for key in sessions.keys where key.hasPrefix("api:") && !seen.contains(key) {
            sessions.removeValue(forKey: key)
        }
    }

    // MARK: Chats

    struct ChatConversation {
        var id: String
        var title: String
        var needsInput: Bool
        var liveStatus: String?
        var updated: Date
    }

    func apply(chats list: [ChatConversation]) {
        let t = now()
        var seen = Set<String>()
        for c in list {
            let id = "chat:" + c.id
            guard t.timeIntervalSince(c.updated) < chatWindow else { continue }
            var state: PetState? = nil
            var detail = ""
            if c.needsInput { state = .attention; detail = S.t("waiting.input") }
            else if let ls = c.liveStatus, !ls.isEmpty { state = .working; detail = ls }
            guard let newState = state else { continue }
            seen.insert(id)
            let title = c.title.isEmpty ? S.t("chat") : c.title
            if var s = sessions[id] {
                let old = s.state
                s.state = newState; s.detail = detail; s.updated = c.updated; s.title = title
                sessions[id] = s
                if old == .working && newState == .attention { addMoment(.attention, "\(title): \(detail)") }
            } else {
                sessions[id] = TrackedSession(id: id, source: .chat, title: title, state: newState, detail: detail, updated: c.updated)
            }
        }
        for key in sessions.keys where key.hasPrefix("chat:") && !seen.contains(key) {
            sessions.removeValue(forKey: key)
        }
    }

    // MARK: Housekeeping

    func prune() {
        let t = now()
        for (key, s) in sessions {
            let age = t.timeIntervalSince(s.updated)
            if key.hasPrefix("hook:") {
                if age > hookStaleAfter { sessions.removeValue(forKey: key); continue }
                if s.state == .ready && age > readyVisibleFor {
                    var u = s; u.state = .idle; u.unread = false; sessions[key] = u
                }
            }
        }
    }

    func removeAll() { sessions.removeAll() }
}

// MARK: - Deterministic default look (FNV-1a + mulberry32 style mixing)

enum LookGenerator {
    static func fnv1a(_ s: String) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for b in s.utf8 { h ^= UInt32(b); h = h &* 0x01000193 }
        return h
    }
    static func mulberry32(_ seed: UInt32) -> () -> UInt32 {
        var a = seed
        return {
            a = a &+ 0x6D2B79F5
            var t = a
            t = (t ^ (t >> 15)) &* (t | 1)
            t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
            return t ^ (t >> 14)
        }
    }
    static func look(for accountId: String) -> SpriteLook {
        let rnd = mulberry32(fnv1a("buddy-desk-" + accountId))
        let species = SpriteBank.all[Int(rnd() % UInt32(SpriteBank.all.count))]
        let hatRoll = rnd() % 100
        let hats = Hat.allCases.filter { $0 != .none }
        let hat: Hat = hatRoll < 40 ? .none : hats[Int(rnd() % UInt32(hats.count))]
        let eyes = EyeStyle.allCases[Int(rnd() % UInt32(EyeStyle.allCases.count))]
        return SpriteLook(species: species, hat: hat, eyes: eyes)
    }
}
