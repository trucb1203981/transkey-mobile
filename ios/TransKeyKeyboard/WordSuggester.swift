import Foundation

/// Word suggestions for the Latin keyboard bars (en, de, fr, es, it, pt), in
/// the QuickType layout.
///
/// Each language has a frequency-ranked list, most common first: en reuses
/// en_words.txt (also the Vietnamese corrector's English passthrough), the
/// others are words_<lang>.txt built by tools/keyboard-words. Entries keep
/// their natural case (German nouns are capitalised). Matching ignores case
/// and accents, so a user who types without accents still gets them. For the
/// word being typed it offers, best first:
/// 1. by frequency, the same word with its accents or capital restored
///    ("ecole" -> "école", German "haus" -> "Haus") and completions
///    ("hel" -> "help", "hello");
/// 2. when nothing matches and it is not a word itself, corrections within a
///    small edit distance ("teh" -> "the"), by distance then frequency.
///
/// Swift port of android/.../WordSuggester.kt: keep the two in sync.
final class WordSuggester {
    static let maxToken = 24
    /// Languages that ship a word list.
    static let langs: Set<String> = ["en", "de", "fr", "es", "it", "pt"]

    private var forms: [String] = []        // display form, most common first
    private var keys: [[Character]] = []    // accent-free lowercase, same index
    private var known: Set<String> = []     // lowercase forms

    init(lang: String, bundle: Bundle = .main) {
        let name = lang == "en" ? "en_words" : "words_\(lang)"
        guard let url = bundle.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        load(text.split(separator: "\n").map(String.init))
    }

    init(words: [String]) {
        load(words)
    }

    private func load(_ words: [String]) {
        for line in words {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.count >= 2, s.allSatisfy({ $0.isLetter }),
                  known.insert(s.lowercased()).inserted else { continue }
            forms.append(s)
            keys.append(Array(Self.fold(s)))
        }
    }

    /// Up to `max` suggestions for `typed`, never `typed` itself; empty when
    /// `typed` is not a word.
    func suggest(_ typed: String, max maxCount: Int = 2) -> [String] {
        guard maxCount > 0, Self.isWordToken(typed) else { return [] }
        let lower = typed.lowercased()
        let key = Array(Self.fold(typed))
        var out: [String] = []
        func add(_ i: Int) -> Bool {
            let s = Self.matchCase(typed, forms[i])
            if !out.contains(s) { out.append(s) }
            return out.count >= maxCount
        }
        // One pass in frequency order over two kinds of match: the typed word
        // itself with its accents or capital restored, and completions. Ranking
        // them together keeps a rare exact form ("Hau") behind a common
        // completion ("Haus").
        for i in keys.indices {
            let k = keys[i]
            let match = k.count == key.count
                ? k == key && Self.matchCase(typed, forms[i]) != typed
                : k.count > key.count && k.starts(with: key)
            if match, add(i) { return out }
        }
        if !out.isEmpty || key.count < 2 || known.contains(lower) { return out }
        let cap = key.count <= 4 ? 1 : 2
        var scored: [(index: Int, dist: Int)] = []
        for i in keys.indices where abs(keys[i].count - key.count) <= cap {
            let d = Self.distance(key, keys[i], cap: cap)
            if d <= cap { scored.append((i, d)) }
        }
        // Equal distances keep frequency order, like Kotlin's stable sortedBy.
        scored.sort { $0.dist != $1.dist ? $0.dist < $1.dist : $0.index < $1.index }
        for item in scored where add(item.index) { break }
        return out
    }

    /// Letters only, the only shape these lists can complete.
    static func isWordToken(_ s: String) -> Bool {
        (1...maxToken).contains(s.count) && s.allSatisfy { $0.isLetter }
    }

    /// The trailing word of `before` (the text left of the caret), or "" when
    /// the caret is not right after one.
    static func trailingWord(_ before: String) -> String {
        String(before.reversed().prefix { $0.isLetter }.reversed())
    }

    /// Lowercase with accents stripped ("École" -> "ecole"); ß and other base
    /// letters stay.
    static func fold(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    }

    /// The suggestion in the case the user is typing: ALL CAPS stays all caps,
    /// a capitalised word gets a capital, otherwise the list's own form (so
    /// German nouns keep their capital).
    private static func matchCase(_ typed: String, _ form: String) -> String {
        if typed.count >= 2, typed.allSatisfy({ $0.isUppercase }) { return form.uppercased() }
        if typed.first?.isUppercase == true { return form.prefix(1).uppercased() + form.dropFirst() }
        return form
    }

    /// Optimal-string-alignment distance (adjacent swaps cost 1), early exit
    /// above `cap`.
    private static func distance(_ a: [Character], _ b: [Character], cap: Int) -> Int {
        let n = a.count, m = b.count
        if n == 0 { return m }
        var prev2 = [Int](repeating: 0, count: m + 1)
        var prev = Array(0...m)
        var cur = [Int](repeating: 0, count: m + 1)
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
