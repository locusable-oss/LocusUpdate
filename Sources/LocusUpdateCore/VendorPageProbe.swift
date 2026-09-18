import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum VendorPageProbe {
    /// Explicit homepage-like keys only. Does not walk every plist string (crash reporters, analytics, keys).
    private static let homepageKeys = [
        "Homepage",
        "HomePage",
        "ProductHomepage",
        "VendorURL",
        "ProductURL",
        "CompanyURL",
    ]

    public static func homepage(fromBundle bundleURL: URL) -> URL? {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] else { return nil }

        for key in homepageKeys {
            if let url = httpsPage(dict[key]) { return url }
        }
        for (key, value) in dict {
            let lk = key.lowercased()
            guard lk.contains("home") || lk.contains("website") || lk.contains("vendor") || lk == "producturl" else {
                continue
            }
            if let url = httpsPage(value) { return url }
        }
        return nil
    }

    public static func latestVersion(homepage: URL, session: URLSession = .shared) async -> RemoteVersion? {
        guard isPublicHTTPSPage(homepage) else { return nil }
        var req = URLRequest(url: homepage)
        req.timeoutInterval = 10
        req.setValue("LocusUpdate/0.2", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = await ProbeHTTP.data(for: req, session: session),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let final = http.url, isPublicHTTPSPage(final),
              data.count < 1_500_000 else { return nil }
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        guard let html else { return nil }

        guard let re = try? NSRegularExpression(
            pattern: #"\b[Vv]?(\d+\.\d+(?:\.\d+){0,2})\b"#,
            options: []
        ) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var versions: [String] = []
        var examined = 0
        re.enumerateMatches(in: html, options: [], range: range) { match, _, stop in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: html) else { return }
            examined += 1
            let token = String(html[r])
            if isPlausibleProductVersion(token) {
                versions.append(token)
            }
            if examined >= 200 { stop.pointee = true }
        }
        guard let best = versions.max(by: { SemanticVersion.compare($0, $1) == .orderedAscending }) else {
            return nil
        }
        return RemoteVersion(version: best, source: .vendorPage, infoURL: homepage)
    }

    /// Reject feeds, GitHub (handled elsewhere), loopback, and raw IPs. https only.
    static func isPublicHTTPSPage(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") { return false }
        if host.contains(":") { return false }
        let parts = host.split(separator: ".")
        if parts.count == 4, parts.allSatisfy({ Int($0) != nil }) { return false }
        if host == "github.com" || host.hasSuffix(".github.com") { return false }
        let path = url.path.lowercased()
        if path.hasSuffix(".xml") || path.contains("appcast") { return false }
        return true
    }

    private static func httpsPage(_ value: Any?) -> URL? {
        guard let s = value as? String, let url = URL(string: s), isPublicHTTPSPage(url) else { return nil }
        return url
    }

    /// Skip years and one-component tokens so a copyright line does not beat the product version.
    static func isPlausibleProductVersion(_ raw: String) -> Bool {
        let parts = raw.split(separator: ".")
        guard (2...4).contains(parts.count) else { return false }
        guard let major = Int(parts[0]), (0..<200).contains(major) else { return false }
        return parts.dropFirst().allSatisfy { Int($0) != nil }
    }
}
