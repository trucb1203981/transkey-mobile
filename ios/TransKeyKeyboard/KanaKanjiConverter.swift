import Foundation

/// Offline kana -> kanji conversion backed by a compact SQLite dictionary
/// (reading -> surface, built from EDICT2 / EDRDG). Conversion is
/// whole-reading lookup plus greedy longest-prefix segmentation (no full
/// morphological analysis - the compact tier). Port of the Android
/// KanaKanjiConverter (keep in sync). Lookups are indexed and
/// sub-millisecond, so running them on the key-press path is fine.
final class KanaKanjiConverter {

    private static let maxSeg = 8   // longest reading chunk to try
    private static let particles: Set<Character> = ["は", "を", "が", "に", "へ", "で", "と", "も", "の"]

    private var dict: CJKDictionary?
    var isReady: Bool { dict?.isReady == true }

    func ensureLoaded() {
        guard dict == nil else { return }
        dict = CJKDictionary(resource: "jadict")
    }

    private func surfaces(_ reading: String, _ limit: Int) -> [String] {
        dict?.strings(
            "SELECT surface FROM dict WHERE reading=? ORDER BY common DESC LIMIT \(limit)",
            [reading]) ?? []
    }

    /// Greedy longest-prefix conversion; common 1-kana particles stay kana.
    private func segment(_ reading: String) -> String {
        let chars = Array(reading)
        var sb = ""
        var i = 0
        while i < chars.count {
            var matched = false
            let end = min(i + Self.maxSeg, chars.count)
            var j = end
            while j > i + 1 {
                let s = surfaces(String(chars[i..<j]), 1)
                if !s.isEmpty { sb += s[0]; i = j; matched = true; break }
                j -= 1
            }
            if !matched {
                // single char: convert only if it is not a bare particle
                let ch = chars[i]
                if !Self.particles.contains(ch) {
                    let s = surfaces(String(ch), 1)
                    if !s.isEmpty { sb += s[0]; i += 1; continue }
                }
                sb += String(ch)
                i += 1
            }
        }
        return sb
    }

    /// Candidates for [reading]: exact matches, then segmented, then kana forms.
    func convert(_ reading: String) -> [String] {
        guard !reading.isEmpty else { return [] }
        if dict == nil { ensureLoaded() }
        var seen = Set<String>()
        var res: [String] = []
        func add(_ s: String) {
            if seen.insert(s).inserted { res.append(s) }
        }
        for s in surfaces(reading, 8) { add(s) }
        let seg = segment(reading)
        if seg != reading { add(seg) }
        add(reading)                       // plain hiragana
        add(Self.toKatakana(reading))      // katakana
        return res
    }

    static func toKatakana(_ s: String) -> String {
        String(s.map { c in
            // Hiragana block ぁ..ゖ (0x3041..0x3096) -> Katakana (+0x60).
            guard let v = c.unicodeScalars.first?.value, (0x3041...0x3096).contains(v),
                  let scalar = Unicode.Scalar(v + 0x60) else { return c }
            return Character(scalar)
        })
    }
}
