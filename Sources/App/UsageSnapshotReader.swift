import Foundation

/// Reads the on-disk plan-reset snapshot and hands Buddy the resets.
///
/// Read-only: Buddy never fetches plan usage itself (that needs the session cookie = the logout
/// bug). The file is written by buddy-statusline.sh from the `rate_limits` block Claude Code pipes
/// to its status line — official data, no network, no cookie, no keychain.
final class UsageSnapshotReader {
    /// Written by buddy-statusline.sh (installed next to buddy-hook.sh).
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Buddy/usage-snapshot.json")
    /// Legacy source: the Claude-Usage widget's snapshot, used only while Buddy's own file doesn't exist.
    static let legacyWidgetURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.claude.usage-widget/usage-snapshot.json")

    private let fixedURL: URL?
    private var url: URL {
        fixedURL ?? (FileManager.default.fileExists(atPath: Self.defaultURL.path) ? Self.defaultURL : Self.legacyWidgetURL)
    }
    private(set) var resets: UsageResets?
    var onChange: ((UsageResets?) -> Void)?

    private var timer: Timer?
    private var lastMod: Date?

    init(url: URL? = nil) { self.fixedURL = url }

    func start() {
        read()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.read() }
        timer?.tolerance = 5
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func read() {
        let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if mod == lastMod { return }          // nothing new on disk
        lastMod = mod
        guard let data = try? Data(contentsOf: url), let r = UsageSnapshotParser.parse(data) else {
            if resets != nil { resets = nil; onChange?(nil) }
            return
        }
        resets = r
        onChange?(r)
    }
}
