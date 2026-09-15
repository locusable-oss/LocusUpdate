import Foundation

public enum GitHubReleasesProbe {
    /// Maps bundle id / homepage hints to owner/repo when obvious; otherwise nil (no guessing).
    public static func repo(fromBundle bundleURL: URL) -> (owner: String, repo: String)? {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] else { return nil }
        let candidates: [String] = [
            dict["SUFeedURL"] as? String,
            dict["SUFeedUrl"] as? String,
            dict["CFBundleHelpBookName"] as? String,
        ].compactMap { $0 }

        for c in candidates {
            if let pair = parseGitHub(c) { return pair }
        }
        // Also check Info.plist string values for github.com/owner/repo
        for (_, v) in dict {
            if let s = v as? String, let pair = parseGitHub(s) { return pair }
        }
        return nil
    }

    public static func latestRelease(owner: String, repo: String, session: URLSession = .shared) async -> RemoteVersion? {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("LocusUpdate/0.2", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 1_000_000,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let tag = (obj["tag_name"] as? String) ?? (obj["name"] as? String) ?? ""
        let cleaned = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        guard !cleaned.isEmpty else { return nil }
        let html = (obj["html_url"] as? String).flatMap(URL.init(string:))
        return RemoteVersion(version: cleaned, source: .githubReleases, infoURL: html)
    }

    private static func parseGitHub(_ s: String) -> (String, String)? {
        // https://github.com/owner/repo or github.com/owner/repo/...
        guard let re = try? NSRegularExpression(
            pattern: #"github\.com[/:]([^/\s]+)/([^/\s#?]+)"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = re.firstMatch(in: s, options: [], range: range), m.numberOfRanges >= 3,
              let r1 = Range(m.range(at: 1), in: s),
              let r2 = Range(m.range(at: 2), in: s) else { return nil }
        var repo = String(s[r2])
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        return (String(s[r1]), repo)
    }
}
