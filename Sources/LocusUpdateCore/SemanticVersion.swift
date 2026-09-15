import Foundation

/// Lightweight SemVer-ish compare: splits on non-digits, compares numeric parts then leftover strings.
public enum SemanticVersion {
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = parts(a)
        let pb = parts(b)
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : Token.num(0)
            let y = i < pb.count ? pb[i] : Token.num(0)
            switch (x, y) {
            case let (.num(l), .num(r)):
                if l != r { return l < r ? .orderedAscending : .orderedDescending }
            case let (.str(l), .str(r)):
                let c = l.localizedCaseInsensitiveCompare(r)
                if c != .orderedSame { return c }
            case (.num, .str):
                return .orderedAscending
            case (.str, .num):
                return .orderedDescending
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

    private enum Token { case num(Int), str(String) }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
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
                tokens.append(.num(Int(s[i..<j]) ?? 0))
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
