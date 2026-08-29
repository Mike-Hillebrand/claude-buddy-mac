import Foundation
import CommonCrypto
import SQLite3

/// Reads the claude.ai session cookie out of the Claude Desktop app (same approach as the
/// Idefix claude-usage-widget) and polls the session endpoints the desktop app itself uses.
final class ClaudeAPI {
    struct Credentials {
        var sessionKey: String
        var orgId: String
    }

    private(set) var credentials: Credentials?
    private var credentialsLoadedAt: Date?
    private(set) var lastError: String?
    private let cookiesPath = NSString(string: "~/Library/Application Support/Claude/Cookies").expandingTildeInPath
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.httpCookieAcceptPolicy = .never
        c.httpShouldSetCookies = false
        return URLSession(configuration: c)
    }()
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func date(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        return iso.date(from: s) ?? isoPlain.date(from: s)
    }

    // MARK: Credentials

    /// (Re)loads the cookie if missing or older than 20 minutes. Returns nil when unavailable.
    @discardableResult
    func ensureCredentials(force: Bool = false) -> Credentials? {
        if !force, let c = credentials, let t = credentialsLoadedAt, Date().timeIntervalSince(t) < 20 * 60 {
            return c
        }
        do {
            let c = try loadCredentials()
            credentials = c
            credentialsLoadedAt = Date()
            lastError = nil
            return c
        } catch {
            lastError = "\(error)"
            return nil
        }
    }

    enum APIError: Error, CustomStringConvertible {
        case keychain(String), noCookieDB, decrypt, noSessionKey, http(Int), badJSON
        var description: String {
            switch self {
            case .keychain(let m): return "Keychain: \(m)"
            case .noCookieDB: return "Cookie-Datei der Claude-App nicht gefunden"
            case .decrypt: return "Cookie konnte nicht entschlüsselt werden"
            case .noSessionKey: return "Kein sessionKey-Cookie (in der Claude-App eingeloggt?)"
            case .http(let s): return "HTTP \(s)"
            case .badJSON: return "Unerwartete Antwort"
            }
        }
    }

    private func loadCredentials() throws -> Credentials {
        let password = try keychainPassword()
        let key = pbkdf2(password: password, salt: "saltysalt", rounds: 1003, length: 16)
        guard FileManager.default.fileExists(atPath: cookiesPath) else { throw APIError.noCookieDB }
        let tmp = NSTemporaryDirectory() + "buddy-cookies-\(getpid()).db"
        try? FileManager.default.removeItem(atPath: tmp)
        try FileManager.default.copyItem(atPath: cookiesPath, toPath: tmp)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = db else { throw APIError.decrypt }
        defer { sqlite3_close(db) }
        let sql = "SELECT name, value, encrypted_value FROM cookies WHERE host_key LIKE '%claude.ai' AND name IN ('sessionKey','lastActiveOrg')"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else { throw APIError.decrypt }
        defer { sqlite3_finalize(stmt) }

        var found: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 0))
            var value = ""
            if let v = sqlite3_column_text(stmt, 1) { value = String(cString: v) }
            if value.isEmpty {
                let len = Int(sqlite3_column_bytes(stmt, 2))
                if len > 3, let blob = sqlite3_column_blob(stmt, 2) {
                    let data = Data(bytes: blob, count: len)
                    if let dec = decrypt(data, key: key) { value = dec }
                }
            }
            if !value.isEmpty { found[name] = value }
        }
        guard let sk = found["sessionKey"], sk.hasPrefix("sk-ant") else { throw APIError.noSessionKey }
        var org = found["lastActiveOrg"] ?? ""
        if org.isEmpty { org = (try? fetchFirstOrg(sessionKey: sk)) ?? "" }
        return Credentials(sessionKey: sk, orgId: org)
    }

    private func keychainPassword() throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Safe Storage", "-w"]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        try p.run()
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard p.terminationStatus == 0, let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw APIError.keychain(e.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return s
    }

    private func pbkdf2(password: String, salt: String, rounds: UInt32, length: Int) -> [UInt8] {
        var key = [UInt8](repeating: 0, count: length)
        let pw = Array(password.utf8), sa = Array(salt.utf8)
        _ = pw.withUnsafeBufferPointer { pwp in
            sa.withUnsafeBufferPointer { sap in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     UnsafeRawPointer(pwp.baseAddress!).assumingMemoryBound(to: Int8.self), pw.count,
                                     sap.baseAddress!, sa.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), rounds,
                                     &key, length)
            }
        }
        return key
    }

    private func decrypt(_ data: Data, key: [UInt8]) -> String? {
        guard data.count > 3, data.prefix(3) == Data("v10".utf8) else { return nil }
        let payload = Array(data.dropFirst(3))
        let iv = [UInt8](repeating: 0x20, count: 16)
        var out = [UInt8](repeating: 0, count: payload.count + 16)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
                             key, key.count, iv, payload, payload.count, &out, out.count, &moved)
        guard status == CCCryptorStatus(kCCSuccess) else { return nil }
        var bytes = Array(out[0..<moved])
        // Newer Chromium prefixes the value with SHA256(host_key) (32 bytes, not printable).
        if bytes.count > 32 && bytes[0..<32].contains(where: { $0 < 0x20 || $0 > 0x7e }) {
            bytes = Array(bytes[32...])
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private func fetchFirstOrg(sessionKey: String) throws -> String {
        var req = URLRequest(url: URL(string: "https://claude.ai/api/organizations")!)
        req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let sem = DispatchSemaphore(value: 0)
        var result = ""
        session.dataTask(with: req) { data, _, _ in
            if let d = data, let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
                let chat = arr.first { ($0["capabilities"] as? [String])?.contains("chat") == true } ?? arr.first
                result = chat?["uuid"] as? String ?? ""
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 15)
        return result
    }

    // MARK: Requests

    private func request(_ url: URL, creds: Credentials) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("sessionKey=\(creds.sessionKey)", forHTTPHeaderField: "Cookie")
        req.setValue(creds.orgId, forHTTPHeaderField: "X-Organization-Uuid")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Buddy/1.0 (macOS desktop pet)", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func fetchJSON(_ url: URL, completion: @escaping (Result<Any, Error>) -> Void) {
        guard let creds = ensureCredentials() else {
            completion(.failure(APIError.noSessionKey)); return
        }
        session.dataTask(with: request(url, creds: creds)) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 {
                // Cookie rotated? Force a reload next time.
                self.credentialsLoadedAt = nil
                completion(.failure(APIError.http(code))); return
            }
            guard code == 200, let d = data, let obj = try? JSONSerialization.jsonObject(with: d) else {
                completion(.failure(APIError.http(code))); return
            }
            completion(.success(obj))
        }.resume()
    }

    /// Cowork + bridge sessions (`exclude_tags` with a dummy value lifts the default filter).
    func fetchCodeSessions(completion: @escaping (Result<[SessionStore.APISession], Error>) -> Void) {
        let url = URL(string: "https://api.anthropic.com/v1/code/sessions?limit=60&exclude_tags=buddy-none")!
        fetchJSON(url) { res in
            switch res {
            case .failure(let e): completion(.failure(e))
            case .success(let obj):
                guard let dict = obj as? [String: Any], let list = dict["data"] as? [[String: Any]] else {
                    completion(.failure(APIError.badJSON)); return
                }
                let out: [SessionStore.APISession] = list.compactMap { s in
                    guard let id = s["id"] as? String else { return nil }
                    var action = ""
                    if let det = s["requires_action_details_list"] as? [[String: Any]], let first = det.first {
                        let tool = (first["display_tool_name"] as? String) ?? (first["tool_name"] as? String) ?? ""
                        let desc = (first["action_description"] as? String) ?? ""
                        action = tool.isEmpty ? desc : (desc.isEmpty ? "Erlauben: \(tool)" : "Erlauben: \(tool) · \(desc)")
                    } else if let ext = s["external_metadata"] as? [String: Any], let pa = ext["pending_action"] as? [String: Any] {
                        let tool = (pa["display_tool_name"] as? String) ?? (pa["tool_name"] as? String) ?? ""
                        if !tool.isEmpty { action = "Erlauben: \(tool)" }
                    }
                    return SessionStore.APISession(
                        id: id,
                        title: (s["title"] as? String) ?? "",
                        status: (s["status"] as? String) ?? "",
                        workerStatus: (s["worker_status"] as? String) ?? "idle",
                        bucket: (s["status_bucket"] as? String) ?? "",
                        unread: (s["unread"] as? Bool) ?? false,
                        lastEvent: self.date(s["last_event_at"] as? String) ?? self.date(s["created_at"] as? String) ?? .distantPast,
                        tags: (s["tags"] as? [String]) ?? [],
                        actionDetail: action)
                }
                completion(.success(out))
            }
        }
    }

    struct Usage {
        struct Window { let label: String; let percent: Double; let resetsAt: Date? }
        var windows: [Window]
    }

    /// Subscription usage (same endpoint the claude.ai usage page uses).
    func fetchUsage(completion: @escaping (Result<Usage, Error>) -> Void) {
        guard let creds = ensureCredentials(), !creds.orgId.isEmpty else {
            completion(.failure(APIError.noSessionKey)); return
        }
        let url = URL(string: "https://claude.ai/api/organizations/\(creds.orgId)/usage")!
        fetchJSON(url) { res in
            switch res {
            case .failure(let e): completion(.failure(e))
            case .success(let obj):
                guard let dict = obj as? [String: Any] else { completion(.failure(APIError.badJSON)); return }
                var windows: [Usage.Window] = []
                func add(_ key: String, _ label: String) {
                    guard let w = dict[key] as? [String: Any], let u = (w["utilization"] as? NSNumber)?.doubleValue else { return }
                    windows.append(Usage.Window(label: label, percent: u, resetsAt: self.date(w["resets_at"] as? String)))
                }
                add("five_hour", "5h")
                add("seven_day", "7d")
                add("seven_day_opus", "Opus")
                add("seven_day_sonnet", "Sonnet")
                add("seven_day_cowork", "Cowork")
                completion(.success(Usage(windows: windows)))
            }
        }
    }

    /// claude.ai chats (needs_input / live_status are only set while a chat has something running).
    func fetchChats(completion: @escaping (Result<[SessionStore.ChatConversation], Error>) -> Void) {
        guard let creds = ensureCredentials(), !creds.orgId.isEmpty else {
            completion(.failure(APIError.noSessionKey)); return
        }
        let url = URL(string: "https://claude.ai/api/organizations/\(creds.orgId)/chat_conversations?limit=25")!
        fetchJSON(url) { res in
            switch res {
            case .failure(let e): completion(.failure(e))
            case .success(let obj):
                guard let list = obj as? [[String: Any]] else { completion(.failure(APIError.badJSON)); return }
                let out: [SessionStore.ChatConversation] = list.compactMap { c in
                    guard let id = c["uuid"] as? String else { return nil }
                    return SessionStore.ChatConversation(
                        id: id,
                        title: (c["name"] as? String) ?? "",
                        needsInput: (c["needs_input"] as? Bool) ?? false,
                        liveStatus: c["live_status"] as? String,
                        updated: self.date(c["updated_at"] as? String) ?? .distantPast)
                }
                completion(.success(out))
            }
        }
    }
}
