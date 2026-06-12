import Foundation

/// Vietnamese Telex composer, raw-derived (Unikey/OpenKey-style).
/// Swift port of the Android `TelexProcessor.kt` - keep the two in sync.
///
/// The buffer of record is the LITERAL keystroke sequence (`raw`); the displayed
/// Vietnamese (`composingText`) is recomputed from scratch on every key. This is
/// far more robust than mutating the display in place: fast typing, backspace and
/// mid-word edits can never leave a corrupt half-applied state.
///
/// Telex rules:
///   aa ee oo -> â ê ô,  dd -> đ,  aw ow uw -> ă ơ ư
///   tones on the right vowel cluster: s f r x j = sắc huyền hỏi ngã nặng,
///   placed by Vietnamese orthography (chào not chaò; giá not gía).
///   Repeating a modifier UNDOES it and emits the literal key
///   ("as"->á, "ass"->as; "oo"->ô, but "telexx"->telex). A repeat also sets
///   `literalIntent`, the signal to skip Vietnamese auto-correction so English
///   words typed in VI mode ("telexx", "ass") survive verbatim.
final class TelexProcessor {

    private var raw: [Character] = []
    private var composed = ""
    private var literal = false

    /// Strict-Telex switch for the ONLY rule that adds a diacritic without an
    /// explicit Telex keystroke: the "ie/ye + consonant -> iê/yê" rime fill (see
    /// `normalizeIeYeUe`). Every other transform (tones s/f/r/x/j, doubled
    /// aa/ee/oo, dd, the w horn) is triggered by a key the user actually pressed.
    ///
    /// When false, "viet" stays "viet" and ê must be typed explicitly as "ee"
    /// ("vieet"). The keyboard wires this to the autocorrect setting, so with
    /// autocorrect OFF (the default) typing plain letters yields plain text -
    /// what someone typing Vietnamese WITHOUT diacritics expects. Default true
    /// keeps the convenience for callers/tests that don't set it.
    var autoRime: Bool = true

    var hasComposingText: Bool { !raw.isEmpty }
    var composingText: String { composed }
    var literalIntent: Bool { literal }

    func reset() {
        raw.removeAll(keepingCapacity: true)
        composed = ""
        literal = false
    }

    @discardableResult
    func input(_ ch: Character) -> Bool {
        raw.append(ch)
        recompute()
        return true
    }

    @discardableResult
    func backspace() -> Bool {
        guard !raw.isEmpty else { return false }
        raw.removeLast()
        recompute()
        return true
    }

    func commitWord() -> String {
        let out = composed
        reset()
        return out
    }

    private func recompute() {
        var out: [Character] = []
        var lit = false
        for c in raw {
            let lc = Self.lower(c)
            var handled = false

            // Once the user escaped Telex by doubling a modifier (e.g. "currsor",
            // "telexx"), the REST of the word is literal English: no more tone /
            // circumflex / horn. This makes typing English words in VI mode easy
            // ("currsor" -> "cursor") instead of fighting diacritics mid-word.
            if lit {
                out.append(c)
                continue
            }

            // ---- tone keys s f r x j ----
            if let tone = Self.toneKey[lc], !out.isEmpty {
                var vi = out.count - 1
                while vi >= 0 && !Self.isVowel(out[vi]) { vi -= 1 }
                if vi >= 0 {
                    let ti = pickToneTarget(out, end: vi)
                    let cur = out[ti]
                    if Self.toneOf(cur) == tone {
                        out[ti] = Self.stripTone(cur)
                        out.append(c); lit = true; handled = true
                    } else if let res = Self.applyTone(Self.stripTone(cur), tone: tone) {
                        out[ti] = cur.isUppercase ? Self.upper(res) : res
                        handled = true
                    }
                }
                if !handled { out.append(c); handled = true }
            } else if "aeo".contains(lc), let last = out.last,
                      Self.lower(Self.stripTone(last)) == lc,
                      !Self.circumflex.values.contains(Self.stripTone(last)) {
                // circumflex: aa ee oo (preserve any tone already on the vowel)
                let t = Self.toneOf(last)
                let nb = Self.circumflex[lc]!
                let ch = t >= 0 ? Self.applyTone(nb, tone: t)! : nb
                out[out.count - 1] = last.isUppercase ? Self.upper(ch) : ch
                handled = true
            } else if "aeo".contains(lc), let last = out.last,
                      Self.stripTone(last) == Self.circumflex[lc] {
                // undo circumflex: â + a -> aa (literal)
                out[out.count - 1] = last.isUppercase ? Self.upper(lc) : lc
                out.append(c); lit = true; handled = true
            } else if lc == "d", let last = out.last, Self.lower(last) == "d" {
                out[out.count - 1] = last.isUppercase ? "Đ" : "đ"
                handled = true
            } else if lc == "d", let last = out.last, last == "đ" || last == "Đ" {
                out[out.count - 1] = last == "Đ" ? "D" : "d"
                out.append(c); lit = true; handled = true
            } else if lc == "w", !out.isEmpty {
                switch applyHorn(&out) {
                case 1: handled = true
                case 2: out.append(c); lit = true; handled = true // undo -> literal
                default: break
                }
            }

            if !handled { out.append(c) }
            if autoRime { normalizeIeYeUe(&out) }
        }
        composed = String(out)
        literal = lit
    }

    /// i/y + e + (at least one more letter) -> iê/yê. The trailing letter
    /// marks the rime "iê" (always ê: tiên, biết), and "yê" (yên, and the y in
    /// chuyên/truyền). A word-final "e" (keo, beo, theo) is left plain and an
    /// explicit "ee" is handled by the circumflex branch. Tone-preserving, so a
    /// tone typed after the cluster lands on the ê. Runs after every key.
    ///
    /// NOT 'u': every "u + e + consonant" in Vietnamese is the "qu" digraph
    /// (qu = /kw/), where the e is the nucleus and is lexically plain e OR ê -
    /// "quen"/"quét" (plain e) vs "quên"/"quết" (ê) are distinct words. Forcing
    /// uê here would make "quen" unreachable. Genuine "uê" rimes (thuê, tuệ,
    /// Huế) are all open, so they never hit this branch anyway. Mirrors the
    /// qu/gi exception already in `pickToneTarget`.
    ///
    /// "gi" exception: "gi" is also a digraph (onset /z/). "gi + e + vowel" is
    /// the "eo" rime, so "gieo" (sow) keeps plain e. But "gi + e + consonant"
    /// IS "giê" (giết, giếng), so we only skip when a vowel follows the e -
    /// a positional rule that needs no word list and can't regress giết/giếng.
    private func normalizeIeYeUe(_ out: inout [Character]) {
        guard out.count >= 3 else { return }
        for i in 0...(out.count - 3) {
            let a = Self.lower(Self.stripTone(out[i]))
            let b = out[i + 1]
            if !"iy".contains(a) || Self.lower(Self.stripTone(b)) != "e" { continue }
            // "gi" digraph + e + vowel = the "eo" rime (gieo) -> leave plain e.
            let isGiEo = a == "i" && i > 0 &&
                Self.lower(Self.stripTone(out[i - 1])) == "g" &&
                Self.isVowel(out[i + 2])
            if isGiEo { continue }
            let t = Self.toneOf(b)
            let ch = t >= 0 ? Self.applyTone("ê", tone: t)! : "ê"
            out[i + 1] = b.isUppercase ? Self.upper(ch) : ch
        }
    }

    /// Apply the Telex horn/breve key 'w' to the current word, cluster-aware so
    /// "uo" becomes "ươ" in one keystroke ("thuong"+w -> "thương", the way most
    /// Vietnamese type). Returns 0 = not applicable, 1 = horn applied,
    /// 2 = horn undone (caller appends the literal 'w' + sets literal-intent).
    ///
    ///  - Special: a "uo" pair in the cluster horns BOTH -> "ươ" (or undoes
    ///    both if already "ươ").
    ///  - Else horns the rightmost a/o/u in the cluster (or undoes if already
    ///    horned). The cluster is the trailing run of vowels, skipping any
    ///    trailing consonants ("thuong" -> horn the "uo", not the "ng").
    private func applyHorn(_ out: inout [Character]) -> Int {
        var ce = out.count - 1
        while ce >= 0 && !Self.isVowel(out[ce]) { ce -= 1 }
        if ce < 0 { return 0 }
        var cs = ce
        while cs - 1 >= 0 && Self.isVowel(out[cs - 1]) { cs -= 1 }

        // "uo" pair -> horn both (ươ), or undo both if already ươ.
        if cs < ce {
            for i in cs..<ce {
                if hornBase(out[i]) == "u" && hornBase(out[i + 1]) == "o" {
                    if Self.stripTone(out[i]) == "ư" && Self.stripTone(out[i + 1]) == "ơ" {
                        unhorn(&out, i); unhorn(&out, i + 1)
                        return 2
                    }
                    horn(&out, i); horn(&out, i + 1)
                    return 1
                }
            }
        }
        // Single vowel: rightmost hornable in the cluster.
        var target = -1
        for i in cs...ce where "aou".contains(hornBase(out[i])) { target = i }
        if target < 0 { return 0 }
        if "ăơư".contains(Self.stripTone(out[target])) {
            unhorn(&out, target); return 2
        }
        horn(&out, target); return 1
    }

    /// Plain base letter ignoring tone AND horn/circumflex (ư->u, ấ->a).
    private func hornBase(_ ch: Character) -> Character {
        let b = Self.lower(Self.stripTone(ch))
        return Self.hornRev[b] ?? Self.circRev[b] ?? b
    }

    private func horn(_ out: inout [Character], _ i: Int) {
        let p = out[i]
        let t = Self.toneOf(p)
        guard let nb = Self.hornMap[Self.lower(Self.stripTone(p))] else { return }
        let ch = t >= 0 ? Self.applyTone(nb, tone: t)! : nb
        out[i] = p.isUppercase ? Self.upper(ch) : ch
    }

    private func unhorn(_ out: inout [Character], _ i: Int) {
        let p = out[i]
        let t = Self.toneOf(p)
        guard let orig = Self.hornRev[Self.lower(Self.stripTone(p))] else { return }
        let ch = t >= 0 ? Self.applyTone(orig, tone: t)! : orig
        out[i] = p.isUppercase ? Self.upper(ch) : ch
    }

    private func pickToneTarget(_ out: [Character], end: Int) -> Int {
        var start = end
        while start - 1 >= 0 && Self.isVowel(out[start - 1]) { start -= 1 }
        let closed = end + 1 < out.count && !Self.isVowel(out[end + 1])
        if end > start {
            let first = Self.lower(Self.stripTone(out[start]))
            let before: Character = start > 0 ? Self.lower(out[start - 1]) : " "
            if (before == "g" && first == "i") || (before == "q" && first == "u") {
                start += 1
            }
        }
        let n = end - start + 1
        var pr = -1
        for i in start...end where Self.priority.contains(Self.lower(Self.stripTone(out[i]))) { pr = i }
        if pr >= 0 { return pr }
        if n == 1 { return start }
        if n >= 3 { return start + 1 }
        if closed { return end }
        let pair = String([Self.lower(Self.stripTone(out[start])), Self.lower(Self.stripTone(out[end]))])
        return (pair == "oa" || pair == "oe" || pair == "uy") ? end : start
    }

    // MARK: - Character tables

    private static func isVowel(_ ch: Character) -> Bool {
        let c = lower(ch)
        return base.contains(c) || toneTable[c] != nil
    }

    private static func stripTone(_ ch: Character) -> Character {
        let c = lower(ch)
        let b = toneTable[c]?.0 ?? c
        return ch.isUppercase ? upper(b) : b
    }

    private static func toneOf(_ ch: Character) -> Int {
        toneTable[lower(ch)]?.1 ?? -1
    }

    private static func applyTone(_ base: Character, tone: Int) -> Character? {
        guard let variants = vowels[lower(base)] else { return nil }
        return variants[tone]
    }

    private static func lower(_ ch: Character) -> Character {
        ch.lowercased().first ?? ch
    }

    private static func upper(_ ch: Character) -> Character {
        ch.uppercased().first ?? ch
    }

    private static let toneKey: [Character: Int] = ["s": 0, "f": 1, "r": 2, "x": 3, "j": 4]
    private static let priority: Set<Character> = ["â", "ă", "ê", "ô", "ơ", "ư"]
    private static let circumflex: [Character: Character] = ["a": "â", "e": "ê", "o": "ô"]
    private static let hornMap: [Character: Character] = ["a": "ă", "o": "ơ", "u": "ư"]
    private static let hornRev: [Character: Character] = ["ă": "a", "ơ": "o", "ư": "u"]
    private static let circRev: [Character: Character] = ["â": "a", "ê": "e", "ô": "o"]

    // base vowel -> [sắc, huyền, hỏi, ngã, nặng]
    private static let vowels: [Character: [Character]] = [
        "a": ["á", "à", "ả", "ã", "ạ"],
        "â": ["ấ", "ầ", "ẩ", "ẫ", "ậ"],
        "ă": ["ắ", "ằ", "ẳ", "ẵ", "ặ"],
        "e": ["é", "è", "ẻ", "ẽ", "ẹ"],
        "ê": ["ế", "ề", "ể", "ễ", "ệ"],
        "i": ["í", "ì", "ỉ", "ĩ", "ị"],
        "o": ["ó", "ò", "ỏ", "õ", "ọ"],
        "ô": ["ố", "ồ", "ổ", "ỗ", "ộ"],
        "ơ": ["ớ", "ờ", "ở", "ỡ", "ợ"],
        "u": ["ú", "ù", "ủ", "ũ", "ụ"],
        "ư": ["ứ", "ừ", "ử", "ữ", "ự"],
        "y": ["ý", "ỳ", "ỷ", "ỹ", "ỵ"],
    ]
    private static let base: Set<Character> = Set(vowels.keys)
    private static let toneTable: [Character: (Character, Int)] = {
        var m: [Character: (Character, Int)] = [:]
        for (b, variants) in vowels {
            for (i, ch) in variants.enumerated() { m[ch] = (b, i) }
        }
        return m
    }()
}
