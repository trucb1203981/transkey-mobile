import Foundation

/// Romaji -> Hiragana converter for Japanese input on the Latin qwerty layout.
/// Pure table + small automaton: handles the gojuon, yoon (きゃ), sokuon
/// (double consonant -> っ), and syllabic ん. Output is kana only; kana->kanji
/// conversion (henkan) is a separate step done by KanaKanjiConverter. The
/// pending romaji is shown as latin until it forms a kana, so the user sees
/// the in-progress reading. Port of the Android RomajiKanaConverter (keep in
/// sync).
final class RomajiKanaConverter {

    private var committed = ""
    private var pending = ""

    var hasComposingText: Bool { !committed.isEmpty || !pending.isEmpty }
    var composingText: String { committed + pending }

    func reset() {
        committed = ""
        pending = ""
    }

    /// Replace the kana with [s] (resume editing after cancelling conversion).
    func load(_ s: String) {
        committed = s
        pending = ""
    }

    @discardableResult
    func commit() -> String {
        // A trailing "n"/"nn" finalizes as ん; any other leftover stays literal.
        if pending == "n" || pending == "nn" {
            committed += "ん"
            pending = ""
        }
        let s = composingText
        reset()
        return s
    }

    private func isVowel(_ c: Character) -> Bool { "aiueo".contains(c) }
    private func isConsonant(_ c: Character) -> Bool {
        c.isLetter && c.isASCII && !isVowel(c)
    }

    func input(_ c: Character) {
        pending += String(c).lowercased()
        resolve()
    }

    private func resolve() {
        while !pending.isEmpty {
            let p = Array(pending)
            // Sokuon: a doubled consonant (kk, tt, ...) -> っ + keep one.
            if p.count >= 2, p[0] == p[1], isConsonant(p[0]), p[0] != "n" {
                committed += "っ"
                pending = String(p.dropFirst())
                continue
            }
            // Syllabic ん.
            if p.count >= 2, p[0] == "n" {
                let second = p[1]
                if second == "n" {
                    // "nn" is ambiguous: alone it is ん, but "nn" + vowel/y is
                    // ん + a な-row syllable (こんにちは = ko-n-nichi-ha), so wait
                    // for the next char before deciding how many n's to consume.
                    if p.count == 2 { return }
                    let third = p[2]
                    committed += "ん"
                    // vowel/y after "nn" -> drop one n so "n"+rest forms な-row;
                    // otherwise the doubled n is a lone ん (consume both).
                    pending = isVowel(third) || third == "y"
                        ? String(p.dropFirst())
                        : String(p.dropFirst(2))
                    continue
                }
                if isConsonant(second), second != "y" {
                    // n + consonant (not y) -> ん + that consonant.
                    committed += "ん"
                    pending = String(p.dropFirst())
                    continue
                }
            }
            // Exact kana match.
            if let kana = Self.table[pending] {
                committed += kana
                pending = ""
                return
            }
            // Still a prefix of some kana -> wait for more input.
            if Self.prefixes.contains(pending) { return }
            // Dead end: emit the first char as literal latin, retry the rest.
            committed += String(p[0])
            pending = String(p.dropFirst())
        }
    }

    /// Remove one unit (pending romaji char, else last kana). True if changed.
    @discardableResult
    func backspace() -> Bool {
        if !pending.isEmpty {
            pending = String(pending.dropLast())
            return true
        }
        if !committed.isEmpty {
            committed = String(committed.dropLast())
            return true
        }
        return false
    }

    private static let table: [String: String] = [
        "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
        "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
        "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
        "sa": "さ", "shi": "し", "si": "し", "su": "す", "se": "せ", "so": "そ",
        "za": "ざ", "ji": "じ", "zi": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
        "ta": "た", "chi": "ち", "ti": "ち", "tsu": "つ", "tu": "つ", "te": "て", "to": "と",
        "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",
        "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
        "ha": "は", "hi": "ひ", "fu": "ふ", "hu": "ふ", "he": "へ", "ho": "ほ",
        "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
        "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
        "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
        "ya": "や", "yu": "ゆ", "yo": "よ",
        "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
        "wa": "わ", "wo": "を", "nn": "ん",
        // yoon (contracted)
        "kya": "きゃ", "kyu": "きゅ", "kyo": "きょ",
        "gya": "ぎゃ", "gyu": "ぎゅ", "gyo": "ぎょ",
        "sha": "しゃ", "shu": "しゅ", "sho": "しょ",
        "sya": "しゃ", "syu": "しゅ", "syo": "しょ",
        "ja": "じゃ", "ju": "じゅ", "jo": "じょ",
        "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ",
        "nya": "にゃ", "nyu": "にゅ", "nyo": "にょ",
        "hya": "ひゃ", "hyu": "ひゅ", "hyo": "ひょ",
        "bya": "びゃ", "byu": "びゅ", "byo": "びょ",
        "pya": "ぴゃ", "pyu": "ぴゅ", "pyo": "ぴょ",
        "mya": "みゃ", "myu": "みゅ", "myo": "みょ",
        "rya": "りゃ", "ryu": "りゅ", "ryo": "りょ",
        // Extended / loanword kana (katakana rendering happens at conversion,
        // e.g. fashion -> ファッション). Hiragana forms here.
        "fa": "ふぁ", "fi": "ふぃ", "fe": "ふぇ", "fo": "ふぉ", "fyu": "ふゅ",
        "va": "ゔぁ", "vi": "ゔぃ", "vu": "ゔ", "ve": "ゔぇ", "vo": "ゔぉ",
        "wi": "うぃ", "we": "うぇ", "who": "うぉ",
        "she": "しぇ", "je": "じぇ", "che": "ちぇ",
        "tsa": "つぁ", "tsi": "つぃ", "tse": "つぇ", "tso": "つぉ",
        "thi": "てぃ", "dhi": "でぃ", "thu": "てゅ", "dhu": "でゅ",
        "twu": "とぅ", "dwu": "どぅ",
        // Small (sutegana) kana, typed with an x/l prefix; xtu/ltu = っ.
        "xa": "ぁ", "xi": "ぃ", "xu": "ぅ", "xe": "ぇ", "xo": "ぉ",
        "la": "ぁ", "li": "ぃ", "lu": "ぅ", "le": "ぇ", "lo": "ぉ",
        "xya": "ゃ", "xyu": "ゅ", "xyo": "ょ",
        "xtu": "っ", "ltu": "っ", "xtsu": "っ",
        "-": "ー",
    ]

    // Every proper prefix of a table key, so we know when to keep waiting.
    private static let prefixes: Set<String> = {
        var out = Set<String>()
        for k in table.keys {
            var i = k.index(after: k.startIndex)
            while i < k.endIndex {
                out.insert(String(k[..<i]))
                i = k.index(after: i)
            }
        }
        out.insert("n")   // 'n' alone may still become な-row, ん, or にゃ
        return out
    }()
}
