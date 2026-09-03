import Foundation

/// Reads the Claude-Usage widget's on-disk snapshot and hands Buddy the plan resets.
///
/// Read-only: Buddy never fetches plan usage itself (that needs the session cookie = the logout
/// bug). It only displays this file, which a separate tool writes. No network, no cookie, no keychain.
final class UsageSnapshotReader {
    /// The widget writes here (see its WidgetShared.swift → SharedStore.snapshotURL).
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.claude.usage-widget/usage-snapshot.json")

    private let url: URL
    private(set) var resets: UsageResets?
    var onChange: ((UsageResets?) -> Void)?

    private var timer: Timer?
    private var lastMod: Date?

    init(url: URL = UsageSnapshotReader.defaultURL) { self.url = url }

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
