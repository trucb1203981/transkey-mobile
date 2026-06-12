import Foundation

/// Hangul (Korean) syllable composer for the Dubeolsik (2-set) layout. Keys
/// emit compatibility jamo (ㄱ, ㅏ, ...); this combines leading consonant
/// (초성) + vowel (중성) + optional trailing consonant (종성) into a
/// precomposed syllable block (U+AC00 range), handling compound vowels
/// (ㅗ+ㅏ=ㅘ), compound finals (ㄱ+ㅅ=ㄳ), and the "trailing steals to next
/// syllable" rule when a vowel follows a final. Pure automaton - no
/// dictionary. Swift port of the Android `HangulComposer.kt` - keep in sync.
///
/// The whole in-progress run (already-formed syllables + the current one) is
/// kept as composing text; the keyboard finalizes it on space / word boundary
/// / mode switch.
final class HangulComposer {

    private static let lead = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let vowel = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    // jongseong (trailing): index 0 = none.
    private static let tail: [String] = [
        "", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ",
        "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    private var committed = ""
    private var cho = -1   // leading index, or -1
    private var jung = -1  // vowel index, or -1
    private var jong = 0   // trailing index, 0 = none

    var hasComposingText: Bool { !committed.isEmpty || cho >= 0 || jung >= 0 || jong > 0 }
    var composingText: String { committed + current() }

    func reset() {
        committed = ""; cho = -1; jung = -1; jong = 0
    }

    /// Finalize everything and return the full text.
    func commit() -> String {
        let s = composingText
        reset()
        return s
    }

    private func leadOf(_ c: Character) -> Int { Self.lead.firstIndex(of: c) ?? -1 }
    private func vowelOf(_ c: Character) -> Int { Self.vowel.firstIndex(of: c) ?? -1 }
    private func tailOf(_ c: Character) -> Int {
        let i = Self.tail.firstIndex(of: String(c)) ?? 0
        return i > 0 ? i : 0
    }

    private func current() -> String {
        if cho >= 0 && jung >= 0 {
            let scalar = 0xAC00 + (cho * 21 + jung) * 28 + jong
            return String(UnicodeScalar(scalar)!)
        }
        if cho >= 0 { return String(Self.lead[cho]) }
        if jung >= 0 { return String(Self.vowel[jung]) }
        if jong > 0 { return Self.tail[jong] }
        return ""
    }

    private func flush() {
        committed += current()
        cho = -1; jung = -1; jong = 0
    }

    /// Feed one compatibility jamo.
    func input(_ c: Character) {
        if vowelOf(c) >= 0 { inputVowel(c) } else { inputConsonant(c) }
    }

    private func inputConsonant(_ c: Character) {
        let l = leadOf(c)
        if jung < 0 {
            // current has no vowel: empty, or a lone leading consonant.
            if cho >= 0 { flush() }
            if l >= 0 { cho = l } else { committed.append(c) }
            return
        }
        if cho < 0 {
            // standalone vowel in progress -> consonant starts a new syllable.
            flush()
            if l >= 0 { cho = l } else { committed.append(c) }
            return
        }
        // cho + jung present (LV or LVT): try as trailing consonant.
        if jong == 0 {
            let t = tailOf(c)
            if t > 0 {
                jong = t
            } else {
                flush()
                if l >= 0 { cho = l } else { committed.append(c) }
            }
        } else {
            let comb = combineTail(jong, c)
            if comb > 0 {
                jong = comb
            } else {
                flush()
                if l >= 0 { cho = l } else { committed.append(c) }
            }
        }
    }

    private func inputVowel(_ c: Character) {
        let v = vowelOf(c)
        if jung < 0 {
            // empty, or a lone leading consonant -> attach as the vowel.
            jung = v
            return
        }
        if jong == 0 {
            // LV + vowel: try to form a compound vowel, else a new syllable.
            let comb = combineVowel(jung, c)
            if comb >= 0 { jung = comb } else { flush(); jung = v }
            return
        }
        // LVT + vowel: the trailing consonant detaches to lead the new syllable.
        let (remain, stolen) = splitTail(jong)
        jong = remain
        flush()
        cho = stolen; jung = v; jong = 0
    }

    /// Remove one jamo. Returns true if the composing text changed.
    @discardableResult
    func backspace() -> Bool {
        if cho >= 0 || jung >= 0 || jong > 0 {
            if jong > 0 {
                jong = splitTail(jong).0
            } else if jung >= 0 {
                jung = decomposeVowel(jung)
            } else if cho >= 0 {
                cho = -1
            }
            return true
        }
        if !committed.isEmpty {
            let last = committed.removeLast()
            if let scalar = last.unicodeScalars.first?.value,
               (0xAC00...0xD7A3).contains(scalar) {
                let idx = Int(scalar) - 0xAC00
                cho = idx / (21 * 28)
                jung = (idx % (21 * 28)) / 28
                jong = idx % 28
                return backspace() // drop the restored syllable's last jamo
            }
            return true // a standalone jamo was committed; just removed it
        }
        return false
    }

    // ㅗ+ㅏ=ㅘ etc. Returns combined vowel index, or -1.
    private func combineVowel(_ base: Int, _ add: Character) -> Int {
        switch "\(Self.vowel[base])\(add)" {
        case "ㅗㅏ": return vowelOf("ㅘ")
        case "ㅗㅐ": return vowelOf("ㅙ")
        case "ㅗㅣ": return vowelOf("ㅚ")
        case "ㅜㅓ": return vowelOf("ㅝ")
        case "ㅜㅔ": return vowelOf("ㅞ")
        case "ㅜㅣ": return vowelOf("ㅟ")
        case "ㅡㅣ": return vowelOf("ㅢ")
        default: return -1
        }
    }

    // ㄱ+ㅅ=ㄳ etc. Returns combined tail index, or 0.
    private func combineTail(_ base: Int, _ add: Character) -> Int {
        switch "\(Self.tail[base])\(add)" {
        case "ㄱㅅ": return 3
        case "ㄴㅈ": return 5
        case "ㄴㅎ": return 6
        case "ㄹㄱ": return 9
        case "ㄹㅁ": return 10
        case "ㄹㅂ": return 11
        case "ㄹㅅ": return 12
        case "ㄹㅌ": return 13
        case "ㄹㅍ": return 14
        case "ㄹㅎ": return 15
        case "ㅂㅅ": return 18
        default: return 0
        }
    }

    // Split a trailing consonant for the "steal" rule: returns (remaining tail
    // index, leading index of the detached jamo). A single tail -> (0, its lead).
    private func splitTail(_ t: Int) -> (Int, Int) {
        switch t {
        case 3: return (1, leadOf("ㅅ"))
        case 5: return (4, leadOf("ㅈ"))
        case 6: return (4, leadOf("ㅎ"))
        case 9: return (8, leadOf("ㄱ"))
        case 10: return (8, leadOf("ㅁ"))
        case 11: return (8, leadOf("ㅂ"))
        case 12: return (8, leadOf("ㅅ"))
        case 13: return (8, leadOf("ㅌ"))
        case 14: return (8, leadOf("ㅍ"))
        case 15: return (8, leadOf("ㅎ"))
        case 18: return (17, leadOf("ㅅ"))
        default: return (0, leadOf(Self.tail[t].first ?? " "))
        }
    }

    // Compound vowel -> its base (one backspace step); else -1 (remove vowel).
    private func decomposeVowel(_ v: Int) -> Int {
        switch Self.vowel[v] {
        case "ㅘ", "ㅙ", "ㅚ": return vowelOf("ㅗ")
        case "ㅝ", "ㅞ", "ㅟ": return vowelOf("ㅜ")
        case "ㅢ": return vowelOf("ㅡ")
        default: return -1
        }
    }
}
