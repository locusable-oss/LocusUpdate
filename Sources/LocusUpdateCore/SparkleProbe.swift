import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SparkleProbe {
    /// Looks for Sparkle feed URL inside Info.plist (SUFeedURL / SUFeedUrl).
    public static func feedURL(fromBundle bundleURL: URL) -> URL? {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] else { return nil }
        let raw = (dict["SUFeedURL"] as? String) ?? (dict["SUFeedUrl"] as? String)
        guard let raw, let url = URL(string: raw) else { return nil }
        return RemoteVersion.httpURL(url)
    }

    /// Fetches appcast XML and returns the newest shortVersionString, paired with that item's notes or download URL.
    public static func latestVersion(feedURL: URL, session: URLSession = .shared) async -> RemoteVersion? {
        guard RemoteVersion.httpURL(feedURL) != nil else { return nil }
        var req = URLRequest(url: feedURL)
        req.timeoutInterval = 12
        req.setValue("LocusUpdate/0.2", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = await ProbeHTTP.data(for: req, session: session),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 2_000_000,
              let xml = String(data: data, encoding: .utf8) else { return nil }
        if let final = http.url, RemoteVersion.httpURL(final) == nil { return nil }

        guard let best = bestItem(in: xml) else { return nil }
        let page = best.infoURL ?? RemoteVersion.httpURL(feedURL)
        return RemoteVersion(version: best.version, source: .sparkle, infoURL: page)
    }

    /// Test hook: newest item version plus its notes/download URL, without fetching.
    static func parsedRelease(in xml: String) -> (version: String, infoURL: URL?)? {
        guard let best = bestItem(in: xml) else { return nil }
        return (best.version, best.infoURL)
    }

    private struct Item {
        var version: String
        var infoURL: URL?
    }

    private static func bestItem(in xml: String) -> Item? {
        let blocks = itemBlocks(in: xml)
        var best: Item?
        for block in blocks {
            guard let version = firstVersion(in: block) else { continue }
            let item = Item(version: version, infoURL: infoURL(in: block))
            if let current = best {
                if SemanticVersion.compare(current.version, item.version) == .orderedAscending {
                    best = item
                }
            } else {
                best = item
            }
        }
        return best
    }

    private static func itemBlocks(in xml: String) -> [String] {
        guard let re = try? NSRegularExpression(
            pattern: #"<item\b[^>]*>[\s\S]*?</item>"#,
            options: [.caseInsensitive]
        ) else { return [xml] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        var blocks: [String] = []
        re.enumerateMatches(in: xml, options: [], range: range) { match, _, _ in
            guard let match, let r = Range(match.range, in: xml) else { return }
            blocks.append(String(xml[r]))
        }
        return blocks.isEmpty ? [xml] : blocks
    }

    private static func firstVersion(in xml: String) -> String? {
        let patterns = [
            #"sparkle:shortVersionString\s*=\s*"([^"]+)""#,
            #"sparkle:version\s*=\s*"([^"]+)""#,
            #"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>"#,
            #"<sparkle:version>([^<]+)</sparkle:version>"#,
        ]
        for pattern in patterns {
            if let value = firstCapture(in: xml, pattern: pattern) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    /// Prefer the release-notes page for this item, then a non-binary link, then the enclosure URL.
    private static func infoURL(in item: String) -> URL? {
        let notes = [
            #"sparkle:releaseNotesLink\s*=\s*"([^"]+)""#,
            #"<sparkle:releaseNotesLink>([^<]+)</sparkle:releaseNotesLink>"#,
        ]
        for pattern in notes {
            if let url = httpCapture(in: item, pattern: pattern), !isBinaryDownload(url) {
                return url
            }
        }
        if let link = httpCapture(in: item, pattern: #"<link[^>]*>\s*([^<\s]+)\s*</link>"#), !isBinaryDownload(link) {
            return link
        }
        if let enclosure = httpCapture(in: item, pattern: #"\burl\s*=\s*"(https?://[^"]+)""#) {
            return enclosure
        }
        return nil
    }

    private static func isBinaryDownload(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["dmg", "zip", "pkg", "gz", "bz2", "xz", "tbz", "tgz"].contains(ext)
    }

    private static func httpCapture(in text: String, pattern: String) -> URL? {
        guard let raw = firstCapture(in: text, pattern: pattern),
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return RemoteVersion.httpURL(url)
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
