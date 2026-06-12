import Foundation

/// Vietnamese auto-corrector + English passthrough.
/// Swift port of the Android `VietWordCorrector.kt` - keep the two in sync.
///
/// Vietnamese writes each space-separated token as one syllable from a finite
/// set (~7k). We load a frequency-ranked syllable list (vn_syllables.txt)
/// and, for a possibly mistyped/merged token, return the closest valid
/// syllable(s) by a keyboard-proximity-weighted edit distance (g↔h cheap,
/// tone/diacritic-only cheaper, far letters expensive), tie-broken by frequency.
/// A DP segmentation also splits words merged by a missed space
/// ("bạnnkhoẻ" -> "bạn khoẻ").
///
/// A common English word list (en_words.txt) lets English mixed into
/// Vietnamese pass through untouched ("email", "code", "class").
final class VietWordCorrector {

    private var rank: [String: Int] = [:]          // syllable -> freq rank (0 = top)
    private var byLen: [Int: [String]] = [:]       // length (chars) -> syllables
    private var english: Set<String> = []          // common English words

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "vn_syllables", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            var i = 0
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let s = line.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty && rank[s] == nil {
                    rank[s] = i
                    byLen[s.count, default: []].append(s)
                }
                i += 1
            }
        }
        if let url = bundle.url(forResource: "en_words", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let s = line.trimmingCharacters(in: .whitespaces)
                if s.count >= 2 { english.insert(s) }
            }
        }
    }

    func isValid(_ word: String) -> Bool {
        rank[word.lowercased()] != nil
    }

    /// A known common English word - typed as-is, never Vietnamese-corrected.
    func isEnglish(_ word: String) -> Bool {
        word.count >= 2 && english.contains(word.lowercased())
    }

    /// Best-first suggestions for a (possibly mistyped) syllable.
    func suggest(_ typed: String, max maxCount: Int = 3) -> [String] {
        guard typed.count >= 2 else { return [] }
        let w = typed.lowercased()
        let wc = Array(w)
        var scored: [(String, Double)] = []
        for len in (w.count - 1)...(w.count + 1) {
            guard let pool = byLen[len] else { continue }
            for cand in pool {
                let cost = distance(wc, Array(cand), cap: Self.maxCost)
                if cost <= Self.maxCost {
                    scored.append((cand, cost + Double(rank[cand] ?? 0) * Self.rankWeight))
                }
            }
        }
        scored.sort { $0.1 < $1.1 }
        var res: [String] = []
        for (s, _) in scored {
            if s != w && !res.contains(matchCase(typed, s)) {
                res.append(matchCase(typed, s))
                if res.count >= maxCount { break }
            }
        }
        return res
    }

    /// Auto-fix a committed word: returns a replacement (possibly several
    /// syllables separated by spaces) or nil to keep what was typed. Runs a DP
    /// segmentation; each piece must be (or correct within `segMaxCost` to) a
    /// valid syllable, with a per-syllable `joinPenalty` to avoid over-splitting.
    func fix(_ typed: String) -> String? {
        guard typed.count >= 2 else { return nil }
        let w = typed.lowercased()
        if rank[w] != nil { return nil }
        let wc = Array(w)
        let n = wc.count
        if n > Self.maxToken { return nil }
        var dp = [Double](repeating: .greatestFiniteMagnitude, count: n + 1)
        var back = [(Int, String)?](repeating: nil, count: n + 1)
        dp[0] = 0.0
        for i in 1...n {
            let lo = max(0, i - Self.maxSyl)
            for j in lo..<i {
                if dp[j] == .greatestFiniteMagnitude { continue }
                let segChars = Array(wc[j..<i])
                let seg = String(segChars)
                let word: String
                let c: Double
                if rank[seg] != nil {
                    word = seg
                    c = 0.0
                } else {
                    let (bw, bc) = bestSingle(segChars, cap: Self.segMaxCost)
                    guard let bw else { continue }
                    word = bw
                    c = bc
                }
                let total = dp[j] + c + Self.joinPenalty
                if total < dp[i] {
                    dp[i] = total
                    back[i] = (j, word)
                }
            }
        }
        if dp[n] == .greatestFiniteMagnitude { return nil }
        var parts: [String] = []
        var i = n
        while i > 0 {
            guard let b = back[i] else { return nil }
            parts.append(b.1)
            i = b.0
        }
        parts.reverse()
        let result = parts.joined(separator: " ")
        if result == w { return nil }
        return matchCase(typed, result)
    }

    /// Nearest valid syllable to `w` within `cap`; (nil, MAX) if none.
    private func bestSingle(_ w: [Character], cap: Double) -> (String?, Double) {
        guard w.count >= 2 else { return (nil, .greatestFiniteMagnitude) }
        var best: String?
        var bestCost = cap + 0.001
        for len in (w.count - 1)...(w.count + 1) {
            guard let pool = byLen[len] else { continue }
            for cand in pool {
                let cost = distance(w, Array(cand), cap: cap)
                if cost < bestCost ||
                    (cost == bestCost && best != nil && (rank[cand] ?? 0) < (rank[best!] ?? 0)) {
                    bestCost = cost
                    best = cand
                }
            }
        }
        return (best, best == nil ? .greatestFiniteMagnitude : bestCost)
    }

    private func matchCase(_ src: String, _ out: String) -> String {
        guard let first = src.first, first.isUppercase, let outFirst = out.first else { return out }
        return String(outFirst).uppercased() + out.dropFirst()
    }

    /// Keyboard-proximity-weighted edit distance, with early exit above `cap`.
    private func distance(_ a: [Character], _ b: [Character], cap: Double) -> Double {
        let n = a.count
        let m = b.count
        if abs(n - m) > 1 { return cap + 1 }
        var prev = (0...m).map { Double($0) * Self.indel }
        var cur = [Double](repeating: 0, count: m + 1)
        for i in 1...n {
            cur[0] = Double(i) * Self.indel
            var rowMin = cur[0]
            let ca = a[i - 1]
            for j in 1...m {
                let sub = prev[j - 1] + subCost(ca, b[j - 1])
                let del = prev[j] + Self.indel
                let ins = cur[j - 1] + Self.indel
                var v = sub
                if del < v { v = del }
                if ins < v { v = ins }
                cur[j] = v
                if v < rowMin { rowMin = v }
            }
            if rowMin > cap { return cap + 1 }
            swap(&prev, &cur)
        }
        return prev[m]
    }

    private func subCost(_ a: Character, _ b: Character) -> Double {
        if a == b { return 0.0 }
        let ba = Self.baseChar(a)
        let bb = Self.baseChar(b)
        if ba == bb { return Self.sameBase }
        if Self.adjacent(ba, bb) { return Self.adj }
        return Self.far
    }

    // MARK: - Constants

    private static let indel = 1.0
    private static let sameBase = 0.3
    private static let adj = 0.7
    private static let far = 2.0
    private static let maxCost = 2.2
    private static let rankWeight = 0.00014

    private static let maxToken = 16
    private static let maxSyl = 7
    private static let segMaxCost = 1.3
    private static let joinPenalty = 0.8

    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let pos: [Character: (Int, Int)] = {
        var m: [Character: (Int, Int)] = [:]
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() { m[ch] = (r, c) }
        }
        return m
    }()

    private static func adjacent(_ a: Character, _ b: Character) -> Bool {
        guard let pa = pos[a], let pb = pos[b] else { return false }
        return abs(pa.0 - pb.0) <= 1 && abs(pa.1 - pb.1) <= 1
    }

    private static let baseMap: [Character: Character] = {
        let groups: [Character: String] = [
            "a": "àáảãạăằắẳẵặâầấẩẫậ",
            "e": "èéẻẽẹêềếểễệ",
            "i": "ìíỉĩị",
            "o": "òóỏõọôồốổỗộơờớởỡợ",
            "u": "ùúủũụưừứửữự",
            "y": "ỳýỷỹỵ",
            "d": "đ",
        ]
        var m: [Character: Character] = [:]
        for (b, variants) in groups {
            for ch in variants { m[ch] = b }
        }
        return m
    }()

    private static func baseChar(_ ch: Character) -> Character {
        let c = Character(String(ch).lowercased())
        return baseMap[c] ?? c
    }
}
