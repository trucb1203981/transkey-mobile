import Foundation

/// English word suggestions for the EN keyboard bar (QuickType layout).
///
/// Built on the same frequency-ranked list the Vietnamese corrector uses for
/// English passthrough (en_words.txt, most common first), so it adds no
/// resource. For the word being typed it offers, best first:
/// 1. completions: words that start with it, by frequency ("hel" -> "help", "hello");
/// 2. when nothing completes and it is not a word itself, corrections within a
///    small edit distance ("teh" -> "the"), by distance then frequency.
///
/// Swift port of android/.../EnglishWordSuggester.kt: keep the two in sync.
final class EnglishWordSuggester {
    static let maxToken = 24

    private var ranked: [[Character]] = []   // most common first
    private var known: Set<String> = []

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "en_words", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        load(text.split(separator: "\n").map(String.init))
    }

    init(words: [String]) {
        load(words)
    }

    private func load(_ words: [String]) {
        for line in words {
            let s = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard s.count >= 2, s.allSatisfy({ ("a"..."z").contains($0) }),
                  known.insert(s).inserted else { continue }
            ranked.append(Array(s))
        }
    }

    /// Up to `max` suggestions for `typed`, never `typed` itself; empty when
    /// `typed` is not a word.
    func suggest(_ typed: String, max maxCount: Int = 2) -> [String] {
        guard maxCount > 0, Self.isWordToken(typed) else { return [] }
        let w = Array(typed.lowercased())
        var out: [String] = []
        for cand in ranked where cand.count > w.count && cand.starts(with: w) {
            out.append(Self.matchCase(typed, String(cand)))
            if out.count >= maxCount { return out }
        }
        if !out.isEmpty || w.count < 2 || known.contains(String(w)) { return out }
        let cap = w.count <= 4 ? 1 : 2
        var scored: [(word: [Character], dist: Int, order: Int)] = []
        for (i, cand) in ranked.enumerated() where abs(cand.count - w.count) <= cap {
            let d = Self.distance(w, cand, cap: cap)
            if d <= cap { scored.append((cand, d, i)) }
        }
        // Equal distances keep frequency order, like Kotlin's stable sortedBy.
        scored.sort { $0.dist != $1.dist ? $0.dist < $1.dist : $0.order < $1.order }
        for item in scored.prefix(maxCount) {
            out.append(Self.matchCase(typed, String(item.word)))
        }
        return out
    }

    /// ASCII letters only, the only shape this list can complete.
    static func isWordToken(_ s: String) -> Bool {
        (1...maxToken).contains(s.count) && s.allSatisfy { $0.isASCII && $0.isLetter }
    }

    /// The trailing word of `before` (the text left of the caret), or "" when
    /// the caret is not right after one.
    static func trailingWord(_ before: String) -> String {
        String(before.reversed().prefix { $0.isLetter }.reversed())
    }

    private static func matchCase(_ typed: String, _ word: String) -> String {
        if typed.count >= 2, typed.allSatisfy({ $0.isUppercase }) { return word.uppercased() }
        if typed.first?.isUppercase == true { return word.prefix(1).uppercased() + word.dropFirst() }
        return word
    }

    /// Optimal-string-alignment distance (adjacent swaps cost 1), early exit
    /// above `cap`.
    private static func distance(_ a: [Character], _ b: [Character], cap: Int) -> Int {
        let n = a.count, m = b.count
        var prev2 = [Int](repeating: 0, count: m + 1)
        var prev = Array(0...m)
        var cur = [Int](repeating: 0, count: m + 1)
        if n == 0 { return m }
        for i in 1...n {
            cur[0] = i
            var rowMin = cur[0]
            if m > 0 {
                for j in 1...m {
                    let cost = a[i - 1] == b[j - 1] ? 0 : 1
                    var v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                    if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                        v = min(v, prev2[j - 2] + 1)
                    }
                    cur[j] = v
                    rowMin = min(rowMin, v)
                }
            }
            if rowMin > cap { return cap + 1 }
            (prev2, prev, cur) = (prev, cur, prev2)
        }
        return prev[m]
    }
}
