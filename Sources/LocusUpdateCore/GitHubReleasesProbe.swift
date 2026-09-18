import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
        for (_, v) in dict {
            if let s = v as? String, let pair = parseGitHub(s) { return pair }
        }
        return nil
    }

    public static func latestRelease(owner: String, repo: String, session: URLSession = .shared) async -> RemoteVersion? {
        guard let ownerSeg = sanitizePathSegment(owner),
              let repoSeg = sanitizePathSegment(repo),
              let url = URL(string: "https://api.github.com/repos/\(ownerSeg)/\(repoSeg)/releases/latest") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("LocusUpdate/0.2", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = await ProbeHTTP.data(for: req, session: session),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 1_000_000,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let tag = (obj["tag_name"] as? String) ?? (obj["name"] as? String) ?? ""
        let cleaned = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        guard !cleaned.isEmpty else { return nil }
        let html = githubPageURL(obj["html_url"] as? String)
        return RemoteVersion(version: cleaned, source: .githubReleases, infoURL: html)
    }

    /// Owner/repo path segments only. Rejects traversal, slashes, and characters that would change the API URL.
    static func sanitizePathSegment(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        guard !s.isEmpty, s != ".", s != ".." else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    private static func githubPageURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), let page = RemoteVersion.httpURL(url) else { return nil }
        let host = page.host?.lowercased() ?? ""
        guard host == "github.com" || host.hasSuffix(".github.com") else { return nil }
        return page
    }

    private static func parseGitHub(_ s: String) -> (String, String)? {
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
        let owner = String(s[r1])
        guard sanitizePathSegment(owner) != nil, sanitizePathSegment(repo) != nil else { return nil }
        return (owner, repo)
    }
}
