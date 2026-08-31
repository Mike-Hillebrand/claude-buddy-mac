import Foundation

/// Checks GitHub Releases for a newer version. This is the ONLY network call Buddy makes:
/// an unauthenticated GET to the public GitHub API. No cookies, no credentials, nothing about
/// your Claude account is ever read or sent.
final class UpdateChecker {
    static let repo = "Mike-Hillebrand/claude-buddy-mac"
    static let releasesURL = "https://github.com/\(repo)/releases/latest"

    private let endpoint = URL(string: "https://api.github.com/repos/\(UpdateChecker.repo)/releases/latest")!
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    /// Current app version from Info.plist (CFBundleShortVersionString).
    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Returns the newer version string (without leading "v") if the latest release is ahead of
    /// `current`, otherwise nil. Never throws; network/parse failures just yield nil.
    func check(current: String = UpdateChecker.currentVersion, completion: @escaping (String?) -> Void) {
        var req = URLRequest(url: endpoint)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("claude-buddy-mac update check", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: req) { data, resp, _ in
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else { completion(nil); return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            completion(UpdateChecker.isNewer(latest, than: current) ? latest : nil)
        }.resume()
    }

    /// Numeric semver comparison ("1.10.0" > "1.9.0"). Non-numeric parts are ignored.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let xi = i < x.count ? x[i] : 0, yi = i < y.count ? y[i] : 0
            if xi != yi { return xi > yi }
        }
        return false
    }
}
