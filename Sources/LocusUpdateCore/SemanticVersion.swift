import Foundation

/// Lightweight SemVer-ish compare.
/// Numeric components are unbounded digit strings so a huge build number does not collapse to 0 via Int overflow.
/// A letter suffix on the same numbers is a prerelease and sorts older (`1.2.3` > `1.2.3-beta`).
public enum SemanticVersion {
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = parts(a)
        let pb = parts(b)
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : Token.num("0")
            let y = i < pb.count ? pb[i] : Token.num("0")
            switch (x, y) {
            case let (.num(l), .num(r)):
                let c = compareNumbers(l, r)
                if c != .orderedSame { return c }
            case let (.str(l), .str(r)):
                let c = l.localizedCaseInsensitiveCompare(r)
                if c != .orderedSame { return c }
            case (.num, .str):
                return .orderedDescending
            case (.str, .num):
                return .orderedAscending
            }
        }
        return .orderedSame
    }

    public static func isOutdated(local: String, remote: String) -> Bool {
        let l = normalize(local)
        let r = normalize(remote)
        guard !l.isEmpty, !r.isEmpty, l != "—", r != "—" else { return false }
        return compare(l, r) == .orderedAscending
    }

    private enum Token { case num(String), str(String) }

    /// Drop one leading v before a digit so `v1.2` and `1.2` compare equal. Interior letters stay.
    private static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 1, let first = t.first, first == "v" || first == "V" else { return t }
        let second = t[t.index(after: t.startIndex)]
        if second.isNumber {
            t.removeFirst()
        }
        return t
    }

    private static func compareNumbers(_ l: String, _ r: String) -> ComparisonResult {
        let a = stripLeadingZeros(l)
        let b = stripLeadingZeros(r)
        if a.count != b.count {
            return a.count < b.count ? .orderedAscending : .orderedDescending
        }
        if a == b { return .orderedSame }
        return a < b ? .orderedAscending : .orderedDescending
    }

    private static func stripLeadingZeros(_ s: String) -> String {
        let trimmed = s.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    private static func parts(_ raw: String) -> [Token] {
        let s = normalize(raw)
        guard !s.isEmpty else { return [] }
        var tokens: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            if s[i].isNumber {
                var j = i
                while j < s.endIndex, s[j].isNumber { j = s.index(after: j) }
                tokens.append(.num(String(s[i..<j])))
                i = j
            } else if s[i].isLetter {
                var j = i
                while j < s.endIndex, s[j].isLetter { j = s.index(after: j) }
                tokens.append(.str(String(s[i..<j])))
                i = j
            } else {
                i = s.index(after: i)
            }
        }
        return tokens
    }
}
