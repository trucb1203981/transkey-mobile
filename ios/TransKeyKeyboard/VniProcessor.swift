import Foundation

/// Vietnamese VNI composer, raw-derived (Unikey-style), sibling of
/// `TelexProcessor`.
/// Swift port of the Android `VniProcessor.kt` - keep the two in sync.
///
/// The buffer of record is the LITERAL keystroke sequence (`raw`); the displayed
/// Vietnamese (`composingText`) is recomputed from scratch on every key, so fast
/// typing, backspace and mid-word edits can never leave a corrupt half-applied
/// state.
///
/// VNI rules (the modifier is a DIGIT typed after the syllable):
///   1 2 3 4 5 = sắc huyền hỏi ngã nặng, placed by Vietnamese orthography,
///   6 = circumflex (a e o -> â ê ô), 7 = horn (o u -> ơ ư, and "uo" horns
///   both), 8 = breve (a -> ă), 9 = đ, 0 = clear the tone.
///
/// Repeating a modifier UNDOES it and emits the literal digit ("a1" -> á,
/// "a11" -> "a1"; "d9" -> đ, "d99" -> "d9"), and from there the REST of the word
/// is literal. That escape is what makes "covid19" and other digit-carrying
/// words typable at all, and it sets `literalIntent`, the signal to skip
/// Vietnamese auto-correction on commit. Same shape as the doubled-key escape
/// in Telex.
final class VniProcessor {

    private var raw: [Character] = []
    private var composed = ""
    private var literal = false

    var hasComposingText: Bool { !raw.isEmpty }
    var composingText: String { composed }
    var literalIntent: Bool { literal }

    /// The literal LETTER keystrokes typed so far, with the VNI digit modifiers
    /// dropped. The keyboard compares this with the composed word to keep an
    /// English word the user actually typed verbatim, so it must survive a
    /// backspace - hence deriving it from `raw` rather than tracking it outside.
    var rawLetters: String { String(raw.filter { $0.isLetter }) }

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
        for key in raw {
            // Once the user escaped VNI by repeating a modifier ("covid19"),
            // the REST of the word is literal: no more tones or shapes.
            if lit {
                out.append(key)
                continue
            }
            guard Self.isDigit(key) else {
                out.append(key)
                relocateTone(&out)
                continue
            }
            let applied: Bool
            switch key {
            case "1": applied = applyTone(&out, tone: 0)
            case "2": applied = applyTone(&out, tone: 1)
            case "3": applied = applyTone(&out, tone: 2)
            case "4": applied = applyTone(&out, tone: 3)
            case "5": applied = applyTone(&out, tone: 4)
            case "6": applied = applyShape(&out, accepted: ["a", "e", "o"],
                                           replacements: ["a": "â", "e": "ê", "o": "ô"])
            case "7": applied = applyHorn(&out)
            case "8": applied = applyShape(&out, accepted: ["a"], replacements: ["a": "ă"])
            case "9": applied = applyDStroke(&out)
            default: applied = clearTone(&out) // "0"
            }
            if applied {
                relocateTone(&out)
            } else {
                // Undone (a repeat) or nothing to modify: the digit is literal,
                // and the helpers above have already reverted their diacritic,
                // so the word reads exactly as it was typed.
                out.append(key)
                lit = true
            }
        }
        composed = String(out)
        literal = lit
    }

    /// Returns true when the tone was applied, false when it was undone or is
    /// not applicable - in both of those cases the caller emits the literal
    /// digit and stops composing the word.
    private func applyTone(_ out: inout [Character], tone: Int) -> Bool {
        let end = lastVowelIndex(out)
        guard end >= 0 else { return false }
        let target = pickToneTarget(out, end: end)
        let current = out[target]
        if Self.toneOf(current) == tone { // repeat: drop the tone, emit the digit
            out[target] = Self.stripTone(current)
            return false
        }
        guard let toned = Self.toneChar(Self.stripTone(current), tone: tone) else { return false }
        out[target] = Self.preserveCase(current, toned)
        return true
    }

    /// Circumflex/breve on the nearest eligible vowel. A vowel that already
    /// carries exactly this shape is reverted instead (the repeat escape).
    private func applyShape(_ out: inout [Character],
                            accepted: Set<Character>,
                            replacements: [Character: Character]) -> Bool {
        for index in out.indices.reversed() {
            let current = out[index]
            let base = Self.plainBase(current)
            guard accepted.contains(base), let shaped = replacements[base] else { continue }
            if Self.lower(Self.stripTone(current)) == shaped {
                out[index] = Self.replaceShapeKeepingTone(current, base)
                return false
            }
            out[index] = Self.replaceShapeKeepingTone(current, shaped)
            return true
        }
        return false
    }

    private func applyHorn(_ out: inout [Character]) -> Bool {
        let end = lastVowelIndex(out)
        guard end >= 0 else { return false }
        var start = end
        while start > 0 && Self.isVowel(out[start - 1]) { start -= 1 }
        if start < end {
            for index in start..<end
            where Self.plainBase(out[index]) == "u" && Self.plainBase(out[index + 1]) == "o" {
                // "uo" horns as a pair (thuong -> thương); a second 7 unhorns both.
                let horned = Self.lower(Self.stripTone(out[index])) == "ư" &&
                    Self.lower(Self.stripTone(out[index + 1])) == "ơ"
                out[index] = Self.replaceShapeKeepingTone(out[index], horned ? "u" : "ư")
                out[index + 1] = Self.replaceShapeKeepingTone(out[index + 1], horned ? "o" : "ơ")
                return !horned
            }
        }
        for index in stride(from: end, through: start, by: -1) {
            let base = Self.plainBase(out[index])
            let shaped: Character
            switch base {
            case "u": shaped = "ư"
            case "o": shaped = "ơ"
            default: continue
            }
            if Self.lower(Self.stripTone(out[index])) == shaped {
                out[index] = Self.replaceShapeKeepingTone(out[index], base)
                return false
            }
            out[index] = Self.replaceShapeKeepingTone(out[index], shaped)
            return true
        }
        return false
    }

    private func applyDStroke(_ out: inout [Character]) -> Bool {
        for index in out.indices.reversed() {
            switch out[index] {
            case "d": out[index] = "đ"; return true
            case "D": out[index] = "Đ"; return true
            // Already stroked: a second 9 restores the plain d and the digit is
            // emitted literally.
            case "đ": out[index] = "d"; return false
            case "Đ": out[index] = "D"; return false
            default: continue
            }
        }
        return false
    }

    private func clearTone(_ out: inout [Character]) -> Bool {
        var changed = false
        for index in out.indices {
            let plain = Self.stripTone(out[index])
            if plain != out[index] {
                out[index] = plain
                changed = true
            }
        }
        return changed
    }

    /// Re-seat the tone after the vowel cluster changed shape, so a tone typed
    /// before the syllable was finished lands where orthography wants it
    /// ("hoa1n" -> "hoán", not "hóan").
    private func relocateTone(_ out: inout [Character]) {
        let end = lastVowelIndex(out)
        guard end >= 0 else { return }
        var start = end
        while start > 0 && Self.isVowel(out[start - 1]) { start -= 1 }
        let toned = (start...end).filter { Self.toneOf(out[$0]) >= 0 }
        guard toned.count == 1, let currentIndex = toned.first else { return }
        let target = pickToneTarget(out, end: end)
        guard currentIndex != target else { return }
        let tone = Self.toneOf(out[currentIndex])
        guard let moved = Self.toneChar(Self.stripTone(out[target]), tone: tone) else { return }
        out[currentIndex] = Self.stripTone(out[currentIndex])
        out[target] = Self.preserveCase(out[target], moved)
    }

    private func pickToneTarget(_ out: [Character], end: Int) -> Int {
        var start = end
        while start > 0 && Self.isVowel(out[start - 1]) { start -= 1 }
        let closed = end + 1 < out.count && !Self.isVowel(out[end + 1])
        if end > start {
            // "gi" and "qu" are digraphs: the tone belongs to the vowel AFTER them.
            let first = Self.lower(Self.stripTone(out[start]))
            let before: Character = start > 0 ? Self.lower(out[start - 1]) : " "
            if (before == "g" && first == "i") || (before == "q" && first == "u") { start += 1 }
        }
        let count = end - start + 1
        var priority = -1
        for index in start...end
        where Self.priority.contains(Self.lower(Self.stripTone(out[index]))) {
            priority = index
        }
        if priority >= 0 { return priority }
        if count == 1 { return start }
        if count >= 3 { return start + 1 }
        if closed { return end }
        return start
    }

    private func lastVowelIndex(_ out: [Character]) -> Int {
        for index in out.indices.reversed() where Self.isVowel(out[index]) { return index }
        return -1
    }

    // MARK: - Character tables

    private static func replaceShapeKeepingTone(_ current: Character, _ shaped: Character) -> Character {
        let tone = toneOf(current)
        let replacement = tone >= 0 ? (toneChar(shaped, tone: tone) ?? shaped) : shaped
        return preserveCase(current, replacement)
    }

    /// Plain base letter ignoring tone AND shape (ư -> u, ấ -> a).
    private static func plainBase(_ ch: Character) -> Character {
        let base = lower(stripTone(ch))
        return shapeToBase[base] ?? base
    }

    private static func isVowel(_ ch: Character) -> Bool { vowels[lower(stripTone(ch))] != nil }

    private static func stripTone(_ ch: Character) -> Character {
        let base = toneTable[lower(ch)]?.0 ?? lower(ch)
        return preserveCase(ch, base)
    }

    private static func toneOf(_ ch: Character) -> Int { toneTable[lower(ch)]?.1 ?? -1 }

    private static func toneChar(_ base: Character, tone: Int) -> Character? {
        vowels[lower(base)]?[tone]
    }

    private static func preserveCase(_ source: Character, _ replacement: Character) -> Character {
        source.isUppercase ? upper(replacement) : replacement
    }

    private static func lower(_ ch: Character) -> Character { ch.lowercased().first ?? ch }
    private static func upper(_ ch: Character) -> Character { ch.uppercased().first ?? ch }
    private static func isDigit(_ ch: Character) -> Bool { ch >= "0" && ch <= "9" }

    private static let priority: Set<Character> = ["â", "ă", "ê", "ô", "ơ", "ư"]
    private static let shapeToBase: [Character: Character] = [
        "â": "a", "ă": "a", "ê": "e", "ô": "o", "ơ": "o", "ư": "u",
    ]

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
    private static let toneTable: [Character: (Character, Int)] = {
        var m: [Character: (Character, Int)] = [:]
        for (b, variants) in vowels {
            for (i, ch) in variants.enumerated() { m[ch] = (b, i) }
        }
        return m
    }()
}
