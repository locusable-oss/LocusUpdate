import Foundation

public enum SparkleProbe {
    /// Looks for Sparkle feed URL inside Info.plist (SUFeedURL / SUFeedUrl).
    public static func feedURL(fromBundle bundleURL: URL) -> URL? {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] else { return nil }
        let raw = (dict["SUFeedURL"] as? String) ?? (dict["SUFeedUrl"] as? String)
        guard let raw, let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    /// Fetches appcast XML and returns the newest enclosure/shortVersionString found (bounded size).
    public static func latestVersion(feedURL: URL, session: URLSession = .shared) async -> RemoteVersion? {
        var req = URLRequest(url: feedURL)
        req.timeoutInterval = 12
        req.setValue("LocusUpdate/0.2", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 2_000_000,
              let xml = String(data: data, encoding: .utf8) else { return nil }

        // Prefer sparkle:shortVersionString, then sparkle:version, then title-looking semver
        let patterns = [
            #"sparkle:shortVersionString\s*=\s*"([^"]+)""#,
            #"sparkle:version\s*=\s*"([^"]+)""#,
            #"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>"#,
            #"<sparkle:version>([^<]+)</sparkle:version>"#,
        ]
        var found: [String] = []
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
            re.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let r = Range(match.range(at: 1), in: xml) else { return }
                found.append(String(xml[r]))
            }
            if !found.isEmpty { break }
        }
        guard let best = found.max(by: { SemanticVersion.compare($0, $1) == .orderedAscending }) else {
            return nil
        }
        return RemoteVersion(version: best, source: .sparkle, infoURL: feedURL)
    }
}
