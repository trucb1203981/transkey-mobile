import Foundation

/// Offline pinyin -> hanzi conversion backed by a compact SQLite dictionary
/// (pinyin -> hanzi, freq). Pinyin + hanzi come from CC-CEDICT (CC-BY-SA - keep
/// attribution); ranking frequency from jieba (MIT). Keys are toneless joined
/// pinyin (你好 -> "nihao"), so a full word reading is a direct lookup.
///
/// Candidates = exact-pinyin matches, then predictive prefix completions, then
/// a greedy longest-prefix segmentation - all ranked by frequency. Port of the
/// Android PinyinHanziConverter (keep the two in sync).
final class PinyinHanziConverter {

    private static let maxSylLen = 6   // longest pinyin syllable (e.g. zhuang)
    private static let maxWord = 6     // longest word (syllables) to group

    private var dict: CJKDictionary?
    private var syllables: Set<String> = []
    var isReady: Bool { dict?.isReady == true }

    func ensureLoaded() {
        guard dict == nil else { return }
        let d = CJKDictionary(resource: "zhdict")
        syllables = Set(d.strings("SELECT s FROM syllables", []))
        dict = d
    }

    private func exact(_ pinyin: String, _ limit: Int) -> [String] {
        dict?.strings(
            "SELECT hanzi FROM zhdict WHERE pinyin=? ORDER BY freq DESC LIMIT \(limit)",
            [pinyin]) ?? []
    }

    /// Words whose pinyin starts with [pinyin] (predictive), excluding exact.
    private func prefix(_ pinyin: String, _ limit: Int) -> [String] {
        dict?.strings(
            "SELECT hanzi FROM zhdict WHERE pinyin>? AND pinyin<? ORDER BY freq DESC LIMIT \(limit)",
            [pinyin, pinyin + "{"]) ?? []   // '{' = 'z'+1
    }

    /// Split pinyin into valid syllables (greedy longest), or nil if some
    /// tail can't be covered - e.g. an incomplete syllable while still typing.
    private func splitSyllables(_ pinyin: String) -> [String]? {
        let chars = Array(pinyin)
        var out: [String] = []
        var i = 0
        while i < chars.count {
            var matched = false
            var j = min(i + Self.maxSylLen, chars.count)
            while j > i {
                let sub = String(chars[i..<j])
                if syllables.contains(sub) {
                    out.append(sub); i = j; matched = true; break
                }
                j -= 1
            }
            if !matched { return nil }
        }
        return out
    }

    /// Convert a full multi-syllable reading: split into syllables, then
    /// greedily group the longest run of syllables that is a dictionary word,
    /// else take the best single character per syllable (你很好 -> 你/很/好).
    /// Nil if the input isn't cleanly splittable (still mid-typing).
    private func segment(_ pinyin: String) -> String? {
        guard let syl = splitSyllables(pinyin), syl.count >= 2 else { return nil }
        var sb = ""
        var i = 0
        while i < syl.count {
            var matched = false
            var j = min(i + Self.maxWord, syl.count)
            while j > i {
                let key = syl[i..<j].joined()
                let s = exact(key, 1)
                if !s.isEmpty { sb += s[0]; i = j; matched = true; break }
                j -= 1
            }
            if !matched {
                let s = exact(syl[i], 1)
                sb += s.isEmpty ? syl[i] : s[0]
                i += 1
            }
        }
        return sb
    }

    /// Candidates for [pinyin] (lowercase a-z). Exact, prefix, then segmented.
    func convert(_ pinyin: String) -> [String] {
        guard !pinyin.isEmpty else { return [] }
        if dict == nil { ensureLoaded() }
        var seen = Set<String>()
        var res: [String] = []
        func add(_ s: String) {
            if seen.insert(s).inserted { res.append(s) }
        }
        for s in exact(pinyin, 9) { add(s) }
        for s in prefix(pinyin, 18) { add(s) }
        if let seg = segment(pinyin), !seg.isEmpty, seg != pinyin { add(seg) }
        return res
    }
}
