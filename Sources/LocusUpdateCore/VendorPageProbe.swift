import Foundation

public enum VendorPageProbe {
    /// Bounded HTML scrape: only https homepage-like URL from Info.plist; extract first plausible version token.
    public static func homepage(fromBundle bundleURL: URL) -> URL? {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] else { return nil }
        let keys = ["SUFeedURL", "ExpandURL", "CFBundleURLTypes"] // weak; prefer explicit strings
        for (_, v) in dict {
            if let s = v as? String, let u = URL(string: s), u.scheme?.lowercased() == "https",
               !(u.host ?? "").contains("github.com") {
                return u
            }
        }
        _ = keys
        return nil
    }

    public static func latestVersion(homepage: URL, session: URLSession = .shared) async -> RemoteVersion? {
        var req = URLRequest(url: homepage)
        req.timeoutInterval = 10
        req.setValue("LocusUpdate/0.2", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 1_500_000,
              let html = String(data: data, encoding: .utf8) else { return nil }

        guard let re = try? NSRegularExpression(
            pattern: #"\b[Vv]?(\d+\.\d+(?:\.\d+){0,2})\b"#,
            options: []
        ) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var versions: [String] = []
        re.enumerateMatches(in: html, options: [], range: range) { match, _, stop in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: html) else { return }
            versions.append(String(html[r]))
            if versions.count >= 20 { stop.pointee = true }
        }
        guard let best = versions.max(by: { SemanticVersion.compare($0, $1) == .orderedAscending }) else {
            return nil
        }
        return RemoteVersion(version: best, source: .vendorPage, infoURL: homepage)
    }
}
