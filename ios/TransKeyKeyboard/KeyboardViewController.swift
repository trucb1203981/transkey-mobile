import UIKit

/// TransKey custom keyboard, styled after the native iOS system keyboard
/// (iPhone users keep their muscle memory: same layout, key shapes, dynamic
/// light/dark colors, double-space period, auto-capitalization), with the
/// Vietnamese Telex engine and word suggestions ported from Android.
class KeyboardViewController: UIInputViewController {

    // MARK: - Key model

    fileprivate enum KeyType {
        case char(String)       // letter / digit / symbol
        case shift
        case backspace
        case toNumbers          // "123"
        case toSymbols          // "#+="
        case toLetters          // "ABC"
        case globe
        case space
        case ret
    }

    fileprivate enum Layer {
        case letters, numbers, symbols
    }

    private enum ShiftState {
        case off, oneShot, locked
    }

    fileprivate final class KeyButton: UIButton {
        var keyType: KeyType = .char("")
    }

    /// Feature chip with the TransKey home gradient (#6366F1 → #A855F7),
    /// matching the Android suggestion-strip chips so the actions stand out.
    fileprivate final class GradientPillButton: UIButton {
        private let grad = CAGradientLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            grad.colors = [
                UIColor(red: 0.388, green: 0.400, blue: 0.945, alpha: 1).cgColor,
                UIColor(red: 0.659, green: 0.333, blue: 0.969, alpha: 1).cgColor,
            ]
            grad.startPoint = CGPoint(x: 0, y: 0.5)
            grad.endPoint = CGPoint(x: 1, y: 0.5)
            layer.insertSublayer(grad, at: 0)
            layer.masksToBounds = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            grad.frame = bounds
            layer.cornerRadius = bounds.height / 2
        }
    }

    // MARK: - Layouts (Apple iPhone portrait layouts per input language)

    /// One letters layout per input language. `shiftRows` is an explicit
    /// shifted character layer (Thai second layer, Korean double jamo); nil
    /// means shift uppercases the same rows (Latin, Cyrillic). `hasShift`
    /// false hides the shift key entirely (Arabic has no case), matching the
    /// system keyboards.
    fileprivate struct LangLayout {
        let rows: [[String]]
        let shiftRows: [[String]]?
        let hasShift: Bool
    }

    private static let latinLayout = LangLayout(
        rows: [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
            ["z", "x", "c", "v", "b", "n", "m"],
        ],
        shiftRows: nil,
        hasShift: true
    )

    /// Layouts mirror the system keyboards (ЙЦУКЕН, Arabic, Kedmanee,
    /// Dubeolsik) so users keep their habits; row splits match the Android
    /// TransKey layouts.
    private static let langLayouts: [String: LangLayout] = [
        "ru": LangLayout(
            rows: [
                ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х"],
                ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
                ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"],
            ],
            shiftRows: nil,
            hasShift: true
        ),
        "ar": LangLayout(
            rows: [
                ["ض", "ص", "ث", "ق", "ف", "غ", "ع", "ه", "خ", "ح", "ج", "د"],
                ["ش", "س", "ي", "ب", "ل", "ا", "ت", "ن", "م", "ك", "ط"],
                ["ذ", "ئ", "ء", "ؤ", "ر", "ى", "ة", "و", "ز", "ظ"],
            ],
            shiftRows: nil,
            hasShift: false
        ),
        "th": LangLayout(
            rows: [
                ["ๅ", "/", "_", "ภ", "ถ", "ุ", "ึ", "ค", "ต", "จ", "ข", "ช"],
                ["ๆ", "ไ", "ำ", "พ", "ะ", "ั", "ี", "ร", "น", "ย", "บ", "ล"],
                ["ฟ", "ห", "ก", "ด", "เ", "้", "่", "า", "ส", "ว", "ง", "ฃ"],
                ["ผ", "ป", "แ", "อ", "ิ", "ื", "ท", "ม", "ใ", "ฝ"],
            ],
            shiftRows: [
                ["+", "๑", "๒", "๓", "๔", "ู", "฿", "๕", "๖", "๗", "๘", "๙"],
                ["๐", "\"", "ฎ", "ฑ", "ธ", "ํ", "๊", "ณ", "ฯ", "ญ", "ฐ", ","],
                ["ฤ", "ฆ", "ฏ", "โ", "ฌ", "็", "๋", "ษ", "ศ", "ซ", ".", "ฅ"],
                ["(", ")", "ฉ", "ฮ", "ฺ", "์", "?", "ฒ", "ฬ", "ฦ"],
            ],
            hasShift: true
        ),
        "ko": LangLayout(
            rows: [
                ["ㅂ", "ㅈ", "ㄷ", "ㄱ", "ㅅ", "ㅛ", "ㅕ", "ㅑ", "ㅐ", "ㅔ"],
                ["ㅁ", "ㄴ", "ㅇ", "ㄹ", "ㅎ", "ㅗ", "ㅓ", "ㅏ", "ㅣ"],
                ["ㅋ", "ㅌ", "ㅊ", "ㅍ", "ㅠ", "ㅜ", "ㅡ"],
            ],
            shiftRows: [
                ["ㅃ", "ㅉ", "ㄸ", "ㄲ", "ㅆ", "ㅛ", "ㅕ", "ㅑ", "ㅒ", "ㅖ"],
                ["ㅁ", "ㄴ", "ㅇ", "ㄹ", "ㅎ", "ㅗ", "ㅓ", "ㅏ", "ㅣ"],
                ["ㅋ", "ㅌ", "ㅊ", "ㅍ", "ㅠ", "ㅜ", "ㅡ"],
            ],
            hasShift: true
        ),
    ]

    private var currentLayout: LangLayout {
        Self.langLayouts[inputLang] ?? Self.latinLayout
    }

    /// The character rows currently on screen (letters follow the input
    /// language and the shift layer; numbers/symbols are language-neutral).
    private func activeCharRows() -> [[String]] {
        switch layer {
        case .numbers: return numberRows
        case .symbols: return symbolRows
        case .letters:
            let lay = currentLayout
            if shiftState != .off, let sr = lay.shiftRows { return sr }
            return lay.rows
        }
    }

    private let numberRows = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]
    private let symbolRows = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
        [".", ",", "?", "!", "'"],
    ]

    /// Space-bar label, like the system keyboard naming its language.
    private static let autonyms: [String: String] = [
        "auto": "Auto", "vi": "Tiếng Việt", "en": "English", "ja": "日本語",
        "ja_flick": "日本語", "zh": "中文", "ko": "한국어", "fr": "Français", "es": "Español",
        "de": "Deutsch", "ru": "Русский", "th": "ไทย", "id": "Bahasa Indonesia",
        "pt": "Português", "it": "Italiano", "ar": "العربية", "hi": "हिन्दी",
    ]

    // MARK: - State

    private var layer: Layer = .letters
    private var shiftState: ShiftState = .off
    private var lastShiftTap = Date.distantPast
    private var lastSpaceTap = Date.distantPast

    private let telex = TelexProcessor()
    private let hangul = HangulComposer()
    private lazy var corrector = VietWordCorrector()

    // Japanese romaji->kana composer + kana->kanji converter, and the Chinese
    // pinyin buffer with live hanzi candidates - ports of the Android engines.
    private let romaji = RomajiKanaConverter()
    private lazy var kanjiConv = KanaKanjiConverter()
    private lazy var pinyinConv = PinyinHanziConverter()
    /// Raw pinyin run shown in the field; candidates update on each letter.
    private var pinyin = ""
    private var zhCandidates: [String] = []
    /// Japanese conversion (space on a kana run): the field shows the
    /// highlighted candidate; space cycles, a new key / return finalizes,
    /// backspace cancels back to kana editing.
    private var jaConverting = false
    private var jaCandidates: [String] = []
    private var jaCandIdx = 0
    private var jaReading = ""
    /// The candidates currently on the bar (tap target lookup).
    private var barCandidates: [String] = []
    private var autocorrectEnabled = AppGroupStore.shared.keyboardAutocorrectEnabled

    /// Typing language (layout + composer), independent from the translate
    /// pair, persisted in the App Group. Cycled by the action-bar chip.
    private var inputLang = AppGroupStore.shared.keyboardInputLang

    /// Telex runs only when typing Vietnamese (and the master switch is on).
    private var telexActive: Bool {
        inputLang == "vi" && AppGroupStore.shared.keyboardTelexEnabled
    }

    /// Every language the keyboard can type, offered in the typing picker.
    /// Latin languages (de/es/fr/id/it/pt) share QWERTY + the accent popup,
    /// mirroring the Android typing modes.
    static let typingLangs = ["vi", "en", "ar", "zh", "fr", "de", "id", "it", "ja", "ja_flick", "ko", "pt", "ru", "es", "th"]

    /// Both Japanese modes (romaji qwerty + 12-key flick) drive the SAME kana
    /// buffer + henkan, so every conversion check uses this instead of a bare
    /// `inputLang == "ja"`.
    private var isJa: Bool { inputLang == "ja" || inputLang == "ja_flick" }

    // Set on every edit we make through the proxy; textDidChange uses it to
    // tell our own edits apart from an external caret move / app edit, which
    // must reset the composing word (otherwise stale state corrupts input).
    private var lastInternalEdit = Date.distantPast

    private var isPro = false
    private var resultPanelVisible = false
    // Pre-action field snapshot; non-nil = the red undo chip is armed on the
    // bar. Any manual edit or field switch invalidates it (Android parity).
    private var undoSnapshot: String?
    // True while we replace the field with an action result / undo, so the
    // replacement's own proxy edits don't invalidate the fresh snapshot.
    private var actionReplaceInProgress = false
    // One request at a time, mirroring Android's actionInFlight guard.
    private var actionInFlight = false
    private var backspaceTimer: Timer?

    private let api = APIClient()

    // MARK: - UI elements

    private var heightConstraint: NSLayoutConstraint!
    private var mainStack: UIStackView!
    private var topBar: UIView!
    private var barLogoButton: UIButton!
    private var barContentStack: UIStackView!
    private var keyArea: KeyAreaView!
    private var keyButtons: [KeyButton] = []
    /// The Japanese 12-key flick grid, overlaid on keyArea while inputLang ==
    /// "ja_flick" (hidden otherwise). Created lazily, reuses the same kana
    /// buffer + henkan as the romaji path.
    private var flickView: FlickInputView?
    /// The emoji picker, overlaid above the flick grid when its ☺ key is
    /// tapped (flick mode only for now). nil = not showing.
    private var emojiPanel: EmojiPanelView?
    private let keyPreview = UIView()
    private let keyPreviewLabel = UILabel()
    private var backspaceTicks = 0

    // Central touch tracking: keys are passive visuals and KeyAreaView routes
    // raw touches here, which is how slide-between-keys, multi-touch rollover
    // and long-press variants can match the system keyboard exactly.
    fileprivate final class TouchState {
        enum Mode { case normal, spaceCursor, variants }
        var key: KeyButton?
        var mode: Mode = .normal
        var consumed = false
        var returnLayer: Layer?
        var longPressTimer: Timer?
        var spacePanX: CGFloat = 0
    }
    private var touchStates: [UITouch: TouchState] = [:]

    private var variantPopup: UIView?
    private var variantOptionLabels: [UILabel] = []
    private var variantOptions: [String] = []
    private var variantSelectedIndex = 0
    private var langPicker: LanguagePairPickerView?
    private var clipPanel: UIView?
    // Translated text currently shown in the clipboard panel, so the panel's
    // Copy button can put it back on the pasteboard.
    private var clipPanelText = ""
    // First-run guide overlay (explains the action chips), shown once.
    private var guidePanel: UIView?

    private var resultPanel: UIView!
    private var resultErrorLabel: UILabel!
    private var upgradeBtn: UIButton!

    // MARK: - Metrics (Apple system keyboard; compact values in landscape)

    private let barHeight: CGFloat = 44
    private let resultPanelHeight: CGFloat = 120
    private let keyHGap: CGFloat = 6
    private let sideMargin: CGFloat = 3
    private var rowTopInset: CGFloat = 6
    private var rowVGap: CGFloat = 12
    private var keyHeight: CGFloat = 42
    private var keyAreaHeight: CGFloat = 216
    private var keyAreaHeightConstraint: NSLayoutConstraint!

    /// The system keyboard is shorter in landscape; mirror that. Row count
    /// follows the layout (Thai has 4 character rows like the system Thai
    /// keyboard, so the whole keyboard grows).
    private func applyMetrics() {
        let landscape = view.bounds.width > 480
        keyHeight = landscape ? 33 : 42
        rowVGap = landscape ? 7 : 12
        rowTopInset = landscape ? 4 : 6
        let numRows = CGFloat(activeCharRows().count + 1)
        keyAreaHeight = rowTopInset + keyHeight * numRows + rowVGap * (numRows - 1) + 6
        if keyAreaHeightConstraint.constant != keyAreaHeight {
            keyAreaHeightConstraint.constant = keyAreaHeight
            updateHeight()
        }
    }

    // MARK: - Colors (match the system keyboard in light and dark)

    private let kbBackground = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1.0)
            : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1.0)
    }
    private let keyFill = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.42, blue: 0.43, alpha: 1.0)
            : UIColor.white
    }
    private let specialKeyFill = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.27, green: 0.27, blue: 0.29, alpha: 1.0)
            : UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1.0)
    }
    private let primaryColor = UIColor(red: 0.42, green: 0.39, blue: 1.0, alpha: 1.0)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        isPro = AppGroupStore.shared.plan != "free"
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if heightConstraint == nil {
            heightConstraint = view.heightAnchor.constraint(equalToConstant: totalHeight)
            heightConstraint.priority = UILayoutPriority(999)
            heightConstraint.isActive = true
        }
        // The app (or a previous keyboard session) may have changed languages
        // or settings while we were away; re-read and rebuild.
        autocorrectEnabled = AppGroupStore.shared.keyboardAutocorrectEnabled
        // Strict Telex by default (Android parity): the ie/ye/ue auto-rime is
        // the ONLY no-trigger-key transform and must stay opt-in behind the
        // autocorrect setting — unwired it defaults true and rewrites plain
        // letters ("vien" -> "viên", English "friend" -> "friênd").
        telex.autoRime = autocorrectEnabled
        inputLang = AppGroupStore.shared.keyboardInputLang
        if !Self.typingLangs.contains(inputLang) {
            inputLang = "vi"
        }
        layer = .letters
        shiftState = .off
        rebuildKeys()
        maybeAutoShift()
        updateSuggestionBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // App Store Guideline 4.4.1: the keyboard must type without Full Access.
        // All input (layouts, Telex, candidates) runs on-device, so we never
        // block the keys. Only the network action chips (Translate / Reply /
        // Refine) require Full Access; showActionBar() swaps them for an inline
        // "Enable Full Access" hint when it is off.
        maybeShowGuide()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyMetrics()
        layoutKeys()
    }

    private var totalHeight: CGFloat {
        barHeight + (resultPanelVisible ? resultPanelHeight : 0) + keyAreaHeight
    }

    private func updateHeight() {
        heightConstraint?.constant = totalHeight
    }

    // MARK: - Text change tracking

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Our own proxy edits also land here; only an external change (caret
        // move, app rewrote the field) may reset the composing word.
        if Date().timeIntervalSince(lastInternalEdit) > 0.15 {
            telex.reset()
            hangul.reset()
            romaji.reset()
            endJaConversion()
            pinyin = ""
            zhCandidates = []
            undoSnapshot = nil   // field switch / external edit drops the undo
            maybeAutoShift()
            updateSuggestionBar()
        }
    }

    private func noteInternalEdit() {
        lastInternalEdit = Date()
        guard !actionReplaceInProgress else { return }
        // Any manual edit invalidates the post-action undo snapshot, exactly
        // like Android: the red chip disappears once the user types again.
        if undoSnapshot != nil {
            undoSnapshot = nil
            showActionBar()
        }
        // The error banner also clears on the next keypress (Android parity).
        if resultPanelVisible {
            closeResultTapped()
        }
    }

    /// Instruction shown when a user taps the "Enable Full Access" hint chip
    /// that replaces the network action chips while Full Access is off. Reuses
    /// the reading panel (on-device, no network) so it works without access.
    @objc private func fullAccessHintTapped() {
        commitComposing()
        showClipboardPanel(translated: KB.t("fullAccessInfo"), title: KB.t("enableFullAccess"))
    }

    // MARK: - UI setup

    private func setupUI() {
        view.backgroundColor = kbBackground

        mainStack = UIStackView()
        mainStack.axis = .vertical
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        setupTopBar()
        setupResultPanel()

        keyArea = KeyAreaView()
        keyArea.owner = self
        keyArea.isMultipleTouchEnabled = true
        keyArea.backgroundColor = .clear
        keyArea.translatesAutoresizingMaskIntoConstraints = false
        keyAreaHeightConstraint = keyArea.heightAnchor.constraint(equalToConstant: keyAreaHeight)
        keyAreaHeightConstraint.isActive = true
        mainStack.addArrangedSubview(keyArea)

        setupKeyPreview()
        rebuildKeys()
    }

    /// The magnified-character balloon shown while a key is pressed, like the
    /// system keyboard. One reusable view; extensions cannot draw outside
    /// their own bounds, so for the top key row it overlaps the suggestion bar.
    private func setupKeyPreview() {
        keyPreview.backgroundColor = keyFill
        keyPreview.layer.cornerRadius = 8
        keyPreview.layer.shadowColor = UIColor.black.cgColor
        keyPreview.layer.shadowOpacity = 0.25
        keyPreview.layer.shadowOffset = CGSize(width: 0, height: 1)
        keyPreview.layer.shadowRadius = 4
        keyPreview.isHidden = true
        keyPreview.isUserInteractionEnabled = false
        keyPreviewLabel.font = .systemFont(ofSize: 34)
        keyPreviewLabel.textColor = .label
        keyPreviewLabel.textAlignment = .center
        keyPreviewLabel.adjustsFontSizeToFitWidth = true
        keyPreview.addSubview(keyPreviewLabel)
        view.addSubview(keyPreview)
    }

    private func showKeyPreview(for btn: KeyButton) {
        guard case .char = btn.keyType, let text = btn.title(for: .normal) else { return }
        let f = view.convert(btn.frame, from: keyArea)
        let w = max(f.width * 1.55, 46)
        let h = f.height * 1.45
        var x = f.midX - w / 2
        x = max(2, min(x, view.bounds.width - w - 2))
        keyPreview.frame = CGRect(x: x, y: max(2, f.minY - h + 6), width: w, height: h)
        keyPreviewLabel.frame = keyPreview.bounds
        keyPreviewLabel.text = text
        view.bringSubviewToFront(keyPreview)
        keyPreview.isHidden = false
    }

    private func hideKeyPreview() {
        keyPreview.isHidden = true
    }

    // MARK: - Top bar (QuickType-style suggestions + TransKey actions)

    private func setupTopBar() {
        topBar = UIView()
        topBar.backgroundColor = .clear
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.heightAnchor.constraint(equalToConstant: barHeight).isActive = true

        barLogoButton = UIButton(type: .system)
        barLogoButton.setImage(UIImage(systemName: "sparkles"), for: .normal)
        barLogoButton.tintColor = primaryColor
        barLogoButton.addTarget(self, action: #selector(barLogoTapped), for: .touchUpInside)
        barLogoButton.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(barLogoButton)

        barContentStack = UIStackView()
        barContentStack.axis = .horizontal
        barContentStack.distribution = .fillEqually
        barContentStack.spacing = 1
        barContentStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(barContentStack)

        NSLayoutConstraint.activate([
            barLogoButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 4),
            barLogoButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            barLogoButton.widthAnchor.constraint(equalToConstant: 40),
            barLogoButton.heightAnchor.constraint(equalToConstant: 36),
            barContentStack.leadingAnchor.constraint(equalTo: barLogoButton.trailingAnchor, constant: 2),
            barContentStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -4),
            barContentStack.topAnchor.constraint(equalTo: topBar.topAnchor, constant: 4),
            barContentStack.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -4),
        ])

        mainStack.addArrangedSubview(topBar)
        updateSuggestionBar()
    }

    /// The sparkles brand button opens the host app.
    @objc private func barLogoTapped() {
        openHostApp("transkey://")
    }

    private func clearBarContent() {
        barContentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Suggestion/candidate modes need full-height stretching; action-bar
        // mode overrides to .center so the pills hug their content.
        barContentStack.alignment = .fill
    }

    /// Feature chips shown whenever the bar is idle - gradient pills up
    /// front like the Android suggestion strip, sized to their content so
    /// labels never get squeezed. Order: language pair first, then the
    /// action chips. Entitlement gating mirrors Android actionModes():
    /// Reply REPLACES Translate for entitled users; Refine is paid-only
    /// and hidden (not greyed) for free users.
    private func showActionBar() {
        clearBarContent()
        // .equalSpacing keeps every chip at its intrinsic size (the lang pills stay
        // visibly smaller than the action chips, unlike .fillProportionally which
        // let the wide "Auto→VI" pill eat the row) AND inserts EQUAL gaps between
        // all of them, so the bar stays balanced - including a free account that
        // only has two action chips (Trả lời + Dịch, no paid Trau chuốt). An
        // earlier attempt with manual flexible spacers under .fill failed: equal
        // priority spacers don't split evenly (one ate all the slack, the rest
        // collapsed), leaving the chips bunched left with a void on the right.
        barContentStack.distribution = .equalSpacing
        barContentStack.alignment = .center
        barContentStack.spacing = 5
        let store = AppGroupStore.shared
        let pairTitle = "\(Self.shortLang(store.sourceLang))→\(Self.shortLang(store.targetLang))"
        // App Store Guideline 4.4.1: Translate / Reply / Refine all hit the
        // network (and the clipboard), which a keyboard extension can only do
        // with Full Access. The keys themselves type fine without it, so when
        // Full Access is off we swap the action chips for a single hint chip
        // that explains how to turn them on - the keyboard stays fully usable.
        // .equalSpacing distributes the gaps for us; the first arranged subview
        // pins to the leading edge and the last to the trailing edge, so the lang
        // pills bracket the bar and the action chips spread evenly between them.
        if hasFullAccess {
            barContentStack.addArrangedSubview(langChip(pairTitle, #selector(langPairTapped)))
            // "Trả lời" = COMPOSE: replace the field in place (undo pill arms).
            // Kept on the LEFT - the less time-critical action (compose a reply,
            // then send). Free runs the plain translate flow; entitled accounts
            // run the context-aware reply flow - same button, plan decides the
            // engine (user decision 2026-06-13, intentionally diverges from the
            // Android strip where Reply replaces Translate).
            let replySelector = store.featureReply
                ? #selector(replyTapped)
                : #selector(translateTapped)
            barContentStack.addArrangedSubview(gradientChip(KB.t("reply"), replySelector, enabled: true))
            if store.featureRefine {
                barContentStack.addArrangedSubview(gradientChip(KB.t("refine"), #selector(refineTapped), enabled: true))
            }
            // "Dịch" = READ the conversation: translate whatever the user copied
            // and show it in a panel over the keys. Last action chip, kept on the
            // RIGHT (by the typing-lang pill) so the copy -> Dịch flow is an easy
            // right-thumb reach (user request 2026-06-22). Needs Full Access.
            barContentStack.addArrangedSubview(
                gradientChip(KB.t("translate"), #selector(clipboardTranslateTapped), enabled: true))
        } else {
            barContentStack.addArrangedSubview(
                langChip("🔒 " + KB.t("enableFullAccess"), #selector(fullAccessHintTapped)))
        }
        barContentStack.addArrangedSubview(langChip(inputLangChipLabel, #selector(inputLangPickTapped)))
        if undoSnapshot != nil {
            barContentStack.addArrangedSubview(undoChip())
        }
    }

    /// Solid red undo pill at the far right of the chips, same as the Android
    /// strip: red (not the brand gradient) so it clearly reads "revert", and
    /// only present while a whole-field replace can still be undone.
    private func undoChip() -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle("↶", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = .systemRed
        btn.layer.cornerRadius = 15
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 11, bottom: 4, right: 11)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        btn.accessibilityLabel = KB.t("undo")
        btn.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)
        return btn
    }

    /// While a translate/reply/refine request is in flight the chips give way
    /// to a spinner on the bar (the Android strip shows "Đang xử lý" the same
    /// way); showActionBar() restores the chips when the request settles.
    private func showBarProcessing() {
        clearBarContent()
        barContentStack.distribution = .fill
        barContentStack.spacing = 8
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = primaryColor
        spinner.startAnimating()
        let label = UILabel()
        label.text = KB.t("processing")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        barContentStack.addArrangedSubview(spinner)
        barContentStack.addArrangedSubview(label)
        barContentStack.addArrangedSubview(UIView())
    }

    private static func shortLang(_ code: String) -> String {
        code == "auto" ? "Auto" : code.uppercased()
    }

    private func gradientChip(_ title: String, _ action: Selector, enabled: Bool) -> UIButton {
        let btn = GradientPillButton(type: .custom)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        btn.setTitleColor(.white, for: .normal)
        btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        shrinkTitleToFit(btn)
        btn.isEnabled = enabled
        btn.alpha = enabled ? 1.0 : 0.45
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private func langChip(_ title: String, _ action: Selector) -> UIButton {
        // Quieter than the gradient action chips: smaller font + tighter
        // padding so the pair/typing-lang pills don't crowd the bar.
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        btn.setTitleColor(.label, for: .normal)
        btn.backgroundColor = .tertiarySystemFill
        btn.layer.cornerRadius = 13
        btn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 9, bottom: 5, right: 9)
        shrinkTitleToFit(btn)
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    /// When the undo chip joins the bar the chips get squeezed; shrink the
    /// label instead of ellipsizing it (same as the Android strip's
    /// auto-shrinking chip text).
    private func shrinkTitleToFit(_ btn: UIButton) {
        btn.titleLabel?.adjustsFontSizeToFitWidth = true
        btn.titleLabel?.minimumScaleFactor = 0.65
        btn.titleLabel?.lineBreakMode = .byClipping
        btn.titleLabel?.baselineAdjustment = .alignCenters
    }

    /// The source→target pill: open/close the language pair picker, overlaid
    /// on the key area like a settings panel.
    @objc private func langPairTapped() {
        commitComposing()
        if langPicker != nil {
            dismissLangPicker()
            return
        }
        let picker = LanguagePairPickerView(mode: .pair)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.onDone = { [weak self] in self?.dismissLangPicker() }
        picker.onChanged = { [weak self] in self?.showActionBar() }
        view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        langPicker = picker
    }

    private func dismissLangPicker() {
        langPicker?.removeFromSuperview()
        langPicker = nil
    }

    /// Reading panel over the key area for clipboard translations (same
    /// overlay geometry as the language pickers). The text is selectable so
    /// a fragment can be copied; ✕ returns to the keys.
    private func showClipboardPanel(
        translated: String,
        title customTitle: String? = nil,
        scamTitle: String? = nil,
        scamDetail: String? = nil,
        scamHigh: Bool = false
    ) {
        dismissClipboardPanel()
        dismissLangPicker()

        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = .systemGroupedBackground

        let title = UILabel()
        title.text = customTitle ?? KB.t("translation")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .secondaryLabel
        title.translatesAutoresizingMaskIntoConstraints = false

        let close = UIButton(type: .system)
        close.setTitle("✕", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        close.setTitleColor(.secondaryLabel, for: .normal)
        close.accessibilityLabel = KB.t("close")
        close.addTarget(self, action: #selector(clipboardPanelCloseTapped), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false

        // Copy the translation back onto the pasteboard (the panel reads what the
        // user copied; this puts the RESULT there so they can paste it). Brand
        // accent so it reads as the panel's primary action. Sits left of ✕.
        clipPanelText = translated
        let copy = UIButton(type: .system)
        copy.setTitle(KB.t("copy"), for: .normal)
        copy.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        copy.setTitleColor(primaryColor, for: .normal)
        copy.addTarget(self, action: #selector(clipboardPanelCopyTapped(_:)), for: .touchUpInside)
        copy.translatesAutoresizingMaskIntoConstraints = false

        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.text = translated
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .label
        textView.backgroundColor = .secondarySystemGroupedBackground
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        textView.translatesAutoresizingMaskIntoConstraints = false

        // Optional fraud-warning banner between the title bar and the text.
        let scamBanner: UIView? = scamTitle.map { t in
            let accent: UIColor = scamHigh
                ? UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0)   // #FF6B6B
                : UIColor(red: 0.96, green: 0.62, blue: 0.07, alpha: 1.0)  // #F59E0B
            let box = UIView()
            box.translatesAutoresizingMaskIntoConstraints = false
            box.backgroundColor = accent.withAlphaComponent(0.12)
            box.layer.cornerRadius = 10
            let titleLbl = UILabel()
            titleLbl.text = "🛡 " + t
            titleLbl.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLbl.textColor = accent
            titleLbl.numberOfLines = 0
            titleLbl.translatesAutoresizingMaskIntoConstraints = false
            let stack = UIStackView(arrangedSubviews: [titleLbl])
            stack.axis = .vertical
            stack.spacing = 2
            stack.translatesAutoresizingMaskIntoConstraints = false
            if let detail = scamDetail, !detail.isEmpty {
                let detailLbl = UILabel()
                detailLbl.text = detail
                detailLbl.font = .systemFont(ofSize: 12)
                detailLbl.textColor = .secondaryLabel
                detailLbl.numberOfLines = 0
                stack.addArrangedSubview(detailLbl)
            }
            box.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
                stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
                stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            ])
            return box
        }

        panel.addSubview(title)
        panel.addSubview(close)
        panel.addSubview(copy)
        scamBanner.map { panel.addSubview($0) }
        panel.addSubview(textView)
        view.addSubview(panel)
        // textView starts below the banner when present, else below the title.
        let textTopAnchor = scamBanner?.bottomAnchor ?? title.bottomAnchor
        var constraints: [NSLayoutConstraint] = [
            panel.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),

            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            close.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
            close.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),

            copy.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            copy.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -10),

            textView.topAnchor.constraint(equalTo: textTopAnchor, constant: 6),
            textView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            textView.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            textView.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8),
        ]
        if let banner = scamBanner {
            constraints += [
                banner.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
                banner.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
                banner.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        clipPanel = panel
    }

    @objc private func clipboardPanelCloseTapped() {
        dismissClipboardPanel()
    }

    @objc private func clipboardPanelCopyTapped(_ sender: UIButton) {
        // Full Access is on whenever the Dịch chip (and so this panel) is
        // available, so the pasteboard write is allowed. Briefly flip the label
        // to "Copied" for feedback, then restore it.
        UIPasteboard.general.string = clipPanelText
        let original = sender.title(for: .normal)
        sender.setTitle(KB.t("copied"), for: .normal)
        sender.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak sender] in
            sender?.setTitle(original, for: .normal)
            sender?.isEnabled = true
        }
    }

    private func dismissClipboardPanel() {
        clipPanel?.removeFromSuperview()
        clipPanel = nil
    }

    // MARK: - First-run guide

    /// Show the action-chip guide exactly once, the first time the keyboard
    /// appears. Marks seen on first SHOW (not just on dismiss) so it appears
    /// once even if the user switches field instead of tapping "Got it".
    /// Parity with the Android keyboard's first-run guide overlay.
    private func maybeShowGuide() {
        guard !AppGroupStore.shared.keyboardGuideSeen, guidePanel == nil else { return }
        AppGroupStore.shared.keyboardGuideSeen = true
        showGuidePanel()
    }

    private func showGuidePanel() {
        dismissClipboardPanel()
        dismissLangPicker()

        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = .systemGroupedBackground

        let title = UILabel()
        title.text = KB.t("guideTitle")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = .label
        title.numberOfLines = 0
        title.translatesAutoresizingMaskIntoConstraints = false

        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 12
        rows.translatesAutoresizingMaskIntoConstraints = false

        // Rows mirror the visible chips (KeyboardViewController.showActionBar):
        // "Dịch" reads the clipboard, "Trả lời" composes the field, and
        // "Trau chuốt" only appears for entitled (paid) users - so a free user
        // is never shown a chip they don't have.
        func addRow(_ label: String, _ desc: String) {
            let row = UIStackView()
            row.axis = .vertical
            row.spacing = 2
            let l = UILabel()
            l.text = label
            l.font = .systemFont(ofSize: 15, weight: .semibold)
            l.textColor = primaryColor
            let d = UILabel()
            d.text = desc
            d.font = .systemFont(ofSize: 13)
            d.textColor = .secondaryLabel
            d.numberOfLines = 0
            row.addArrangedSubview(l)
            row.addArrangedSubview(d)
            rows.addArrangedSubview(row)
        }
        addRow(KB.t("translate"), KB.t("guideClipboard"))
        addRow(KB.t("reply"), KB.t("guideReply"))
        if AppGroupStore.shared.featureRefine {
            addRow(KB.t("refine"), KB.t("guideRefine"))
        }

        let gotIt = GradientPillButton(type: .custom)
        gotIt.setTitle(KB.t("gotIt"), for: .normal)
        gotIt.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        gotIt.setTitleColor(.white, for: .normal)
        gotIt.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        gotIt.addTarget(self, action: #selector(guideGotItTapped), for: .touchUpInside)
        gotIt.translatesAutoresizingMaskIntoConstraints = false

        panel.addSubview(title)
        panel.addSubview(rows)
        panel.addSubview(gotIt)
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),

            rows.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            rows.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            rows.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),

            gotIt.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            gotIt.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            gotIt.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12),
            gotIt.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
        ])
        guidePanel = panel
    }

    @objc private func guideGotItTapped() {
        dismissGuidePanel()
    }

    private func dismissGuidePanel() {
        guidePanel?.removeFromSuperview()
        guidePanel = nil
    }

    /// Open the typing-language picker (all native layouts), overlaid on the
    /// key area like the pair picker.
    @objc private func inputLangPickTapped() {
        commitComposing()
        dismissEmojiPanel()
        if langPicker != nil {
            dismissLangPicker()
            return
        }
        let picker = LanguagePairPickerView(mode: .typing(current: inputLang))
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.onDone = { [weak self] in self?.dismissLangPicker() }
        picker.onTypingPicked = { [weak self] code in
            guard let self else { return }
            self.inputLang = code
            AppGroupStore.shared.keyboardInputLang = code
            self.shiftState = .off
            self.layer = .letters
            self.dismissLangPicker()
            self.rebuildKeys()
            self.updateSuggestionBar()
        }
        view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        langPicker = picker
    }

    /// QuickType-style bar while composing (verbatim word + corrections);
    /// CJK candidates while a pinyin/kana run is open; feature chips whenever
    /// idle, like the Android strip.
    private func updateSuggestionBar() {
        if inputLang == "zh", !pinyin.isEmpty {
            zhCandidates = pinyinConv.convert(pinyin)
            showCandidates(zhCandidates.isEmpty ? [pinyin] : zhCandidates)
            return
        }
        if isJa {
            if jaConverting {
                showCandidates(jaCandidates, highlight: jaCandIdx)
                return
            }
            if romaji.hasComposingText {
                // Live candidates for the current kana run (Apple QuickType
                // style); space still drives the classic henkan cycle.
                let reading = romaji.composingText
                let cands = kanjiConv.convert(reading)
                showCandidates(cands.isEmpty ? [reading] : cands)
                return
            }
        }
        let word = telex.composingText
        guard telexActive, !word.isEmpty else {
            showActionBar()
            return
        }
        clearBarContent()
        barContentStack.distribution = .fillEqually
        barContentStack.spacing = 1

        var items: [(String, Bool)] = [("\"\(word)\"", true)]   // (insert text, verbatim)
        if !telex.literalIntent {
            for s in corrector.suggest(word, max: 2) {
                items.append((s, false))
            }
        }
        for (i, item) in items.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(item.0, for: .normal)
            btn.titleLabel?.font = item.1
                ? .systemFont(ofSize: 15)
                : .systemFont(ofSize: 15, weight: .medium)
            btn.setTitleColor(.label, for: .normal)
            btn.tag = i
            btn.addTarget(self, action: #selector(suggestionTapped(_:)), for: .touchUpInside)
            barContentStack.addArrangedSubview(btn)
        }
    }

    @objc private func suggestionTapped(_ sender: UIButton) {
        guard telex.hasComposingText else { return }
        let raw = sender.title(for: .normal) ?? ""
        let replacement = raw.hasPrefix("\"") ? telex.composingText : raw
        replaceComposing(with: replacement + " ")
        playClick()
        maybeAutoShift()
    }

    /// CJK candidate strip: hanzi for the pinyin run, kanji surfaces for the
    /// kana run / active conversion.
    private func showCandidates(_ cands: [String], highlight: Int = -1) {
        barCandidates = cands
        clearBarContent()
        barContentStack.distribution = .fillProportionally
        barContentStack.spacing = 1
        for (i, word) in cands.prefix(6).enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(word, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 17, weight: i == highlight ? .semibold : .regular)
            btn.setTitleColor(i == highlight ? primaryColor : .label, for: .normal)
            btn.tag = i
            btn.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
            barContentStack.addArrangedSubview(btn)
        }
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        guard barCandidates.indices.contains(sender.tag) else { return }
        let word = barCandidates[sender.tag]
        playClick()
        if inputLang == "zh", !pinyin.isEmpty {
            commitZh(word)
            return
        }
        if isJa {
            if jaConverting {
                let shown = jaCandidates.indices.contains(jaCandIdx) ? jaCandidates[jaCandIdx] : ""
                applyComposingDiff(from: shown, to: word)
                endJaConversion()
            } else if romaji.hasComposingText {
                applyComposingDiff(from: romaji.composingText, to: word)
                romaji.reset()
            }
            updateSuggestionBar()
        }
    }

    // MARK: - Key building

    private func rebuildKeys() {
        keyButtons.forEach { $0.removeFromSuperview() }
        keyButtons = []

        // Japanese flick: a self-contained grid replaces the QWERTY keys.
        if inputLang == "ja_flick" {
            showFlickKeyboard()
            keyArea.setNeedsLayout()
            view.setNeedsLayout()
            return
        }
        hideFlickKeyboard()

        for chars in activeCharRows() {
            for ch in chars {
                addKey(.char(ch))
            }
        }

        // Last-row modifier (shift / layer switch) + backspace
        switch layer {
        case .letters:
            if currentLayout.hasShift {
                addKey(.shift)
            }
        case .numbers:
            addKey(.toSymbols)
        case .symbols:
            addKey(.toNumbers)
        }
        addKey(.backspace)

        // Bottom row
        addKey(layer == .letters ? .toNumbers : .toLetters)
        if needsInputModeSwitchKey {
            addKey(.globe)
        }
        addKey(.space)
        addKey(.ret)

        styleAllKeys()
        keyArea.setNeedsLayout()
        view.setNeedsLayout()
    }

    private func addKey(_ type: KeyType) {
        let btn = KeyButton(type: .system)
        btn.keyType = type
        btn.layer.cornerRadius = 5
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.30
        btn.layer.shadowOffset = CGSize(width: 0, height: 1)
        btn.layer.shadowRadius = 0
        if case .globe = type {
            // The system handler does both: tap switches keyboard, long-press
            // shows the keyboard picker (Apple's recommended wiring). The
            // globe stays a live control; KeyAreaView never sees its touches.
            btn.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        } else {
            // All other keys are passive visuals; KeyAreaView routes raw
            // touches to the controller (slide, rollover, long-press).
            btn.isUserInteractionEnabled = false
        }
        keyArea.addSubview(btn)
        keyButtons.append(btn)
    }

    private func styleAllKeys() {
        for btn in keyButtons {
            switch btn.keyType {
            case .char(let ch):
                btn.backgroundColor = keyFill
                btn.setTitleColor(.label, for: .normal)
                btn.setImage(nil, for: .normal)
                let display: String
                if layer == .letters && currentLayout.shiftRows == nil {
                    display = shiftState == .off ? ch : ch.uppercased()
                } else {
                    display = ch
                }
                btn.setTitle(display, for: .normal)
                // Dense layouts (11-13 columns: ru/ar/th) need a smaller face;
                // digits/symbols use the same 23pt as letters, like the system.
                let dense = layer == .letters && (activeCharRows().map(\.count).max() ?? 10) > 10
                btn.titleLabel?.font = .systemFont(ofSize: dense ? 19 : 23)
            case .shift:
                btn.backgroundColor = shiftState == .off ? specialKeyFill : keyFill
                btn.setTitle(nil, for: .normal)
                let name: String
                switch shiftState {
                case .off: name = "shift"
                case .oneShot: name = "shift.fill"
                case .locked: name = "capslock.fill"
                }
                btn.setImage(UIImage(systemName: name), for: .normal)
                btn.tintColor = .label
            case .backspace:
                btn.backgroundColor = specialKeyFill
                btn.setTitle(nil, for: .normal)
                btn.setImage(UIImage(systemName: "delete.left"), for: .normal)
                btn.tintColor = .label
            case .toNumbers:
                styleLabelKey(btn, "123")
            case .toSymbols:
                styleLabelKey(btn, "#+=")
            case .toLetters:
                styleLabelKey(btn, "ABC")
            case .globe:
                btn.backgroundColor = specialKeyFill
                btn.setTitle(nil, for: .normal)
                btn.setImage(UIImage(systemName: "globe"), for: .normal)
                btn.tintColor = .label
            case .space:
                btn.backgroundColor = keyFill
                btn.setImage(nil, for: .normal)
                btn.setTitle(spaceLabel, for: .normal)
                btn.setTitleColor(.secondaryLabel, for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 15)
            case .ret:
                // Action return types (go/search/send/done) get the blue fill
                // like the system keyboard.
                let type = textDocumentProxy.returnKeyType ?? .default
                let prominent: Bool
                switch type {
                case .go, .search, .send, .done: prominent = true
                default: prominent = false
                }
                btn.backgroundColor = prominent ? .systemBlue : specialKeyFill
                btn.setImage(nil, for: .normal)
                btn.setTitle(returnLabel, for: .normal)
                btn.setTitleColor(prominent ? .white : .label, for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 16)
            }
        }
    }

    private func styleLabelKey(_ btn: KeyButton, _ title: String) {
        btn.backgroundColor = specialKeyFill
        btn.setImage(nil, for: .normal)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.label, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16)
    }

    private var spaceLabel: String {
        Self.autonyms[inputLang] ?? inputLang
    }

    /// The action-bar typing-language chip: short language code, except the
    /// flick mode which shows かな so the two Japanese modes are distinct.
    private var inputLangChipLabel: String {
        inputLang == "ja_flick" ? "かな" : inputLang.uppercased()
    }

    private var returnLabel: String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return "go"
        case .search: return "search"
        case .send: return "send"
        case .done: return "done"
        case .next: return "next"
        default: return "return"
        }
    }

    // MARK: - Key layout (manual frames, mirrors the system keyboard)

    private func layoutKeys() {
        // The flick grid lays itself out (FlickInputView.layoutSubviews).
        if inputLang == "ja_flick" { return }
        let w = keyArea.bounds.width
        guard w > 0, !keyButtons.isEmpty else { return }

        let rows = activeCharRows()
        let maxCols = CGFloat(rows.map(\.count).max() ?? 10)
        let keyW = (w - sideMargin * 2 - keyHGap * (maxCols - 1)) / maxCols
        let modW = keyW * 1.4
        let lastRow = rows.count - 1
        // Arabic letters have no shift key; numbers/symbols always have the
        // #+=/123 modifier in that slot.
        let hasLeftModifier = layer != .letters || currentLayout.hasShift

        var i = 0

        func rowY(_ r: Int) -> CGFloat { rowTopInset + CGFloat(r) * (keyHeight + rowVGap) }

        for (r, chars) in rows.enumerated() {
            let count = CGFloat(chars.count)
            var cw = keyW
            var x = (w - (count * cw + (count - 1) * keyHGap)) / 2
            if r == lastRow {
                // The last character row sits between the modifier and
                // backspace. Letters: centered at standard width (z-m on the
                // system keyboard). Numbers/symbols: STRETCHED to fill the
                // span - the system keyboard's wide . , ? ! ' keys.
                let leftEdge = hasLeftModifier ? sideMargin + modW + keyHGap : sideMargin
                let rightEdge = w - sideMargin - modW - keyHGap
                let avail = rightEdge - leftEdge
                let needed = count * cw + (count - 1) * keyHGap
                if layer != .letters || needed > avail {
                    cw = (avail - keyHGap * (count - 1)) / count
                    x = leftEdge
                } else {
                    x = leftEdge + (avail - needed) / 2
                }
            }
            for _ in chars {
                keyButtons[i].frame = CGRect(x: x, y: rowY(r), width: cw, height: keyHeight)
                x += cw + keyHGap
                i += 1
            }
        }

        // Modifier (shift / #+= / 123) and backspace flank the last char row.
        let modY = rowY(lastRow)
        if hasLeftModifier {
            keyButtons[i].frame = CGRect(x: sideMargin, y: modY, width: modW, height: keyHeight)
            i += 1
        }
        keyButtons[i].frame = CGRect(x: w - sideMargin - modW, y: modY, width: modW, height: keyHeight)
        i += 1

        // Bottom row
        let by = rowY(rows.count)
        let ctrlW = keyW * 1.25
        let returnW = keyW * 2.4
        var bx = sideMargin
        keyButtons[i].frame = CGRect(x: bx, y: by, width: ctrlW, height: keyHeight) // 123/ABC
        bx += ctrlW + keyHGap
        i += 1
        if needsInputModeSwitchKey {
            keyButtons[i].frame = CGRect(x: bx, y: by, width: ctrlW, height: keyHeight) // globe
            bx += ctrlW + keyHGap
            i += 1
        }
        let spaceW = w - bx - sideMargin - returnW - keyHGap
        keyButtons[i].frame = CGRect(x: bx, y: by, width: spaceW, height: keyHeight) // space
        bx += spaceW + keyHGap
        i += 1
        keyButtons[i].frame = CGRect(x: bx, y: by, width: returnW, height: keyHeight) // return
    }

    // MARK: - Key handling (central touch routing from KeyAreaView)

    /// Expanded hit test: key rects tile the whole surface so there are no
    /// dead zones between keys; nearest center wins where expansions overlap.
    private func keyAt(_ p: CGPoint) -> KeyButton? {
        var best: KeyButton?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for b in keyButtons {
            let f = b.frame.insetBy(dx: -(keyHGap / 2 + 1), dy: -(rowVGap / 2 + 1))
            guard f.contains(p) else { continue }
            let d = hypot(p.x - b.frame.midX, p.y - b.frame.midY)
            if d < bestDist { bestDist = d; best = b }
        }
        return best
    }

    /// Sliding a finger retargets only among the typing keys; control keys
    /// (shift, delete, layer switches) act on touch-down and never retarget.
    private func isSlideTarget(_ t: KeyType) -> Bool {
        switch t {
        case .char, .space, .ret: return true
        default: return false
        }
    }

    fileprivate func keysTouchesBegan(_ touches: Set<UITouch>) {
        for touch in touches {
            // Multi-touch rollover, like the system keyboard: the moment a
            // second finger lands, the letter still held by the first finger
            // is committed.
            for st in touchStates.values where st.mode == .normal && !st.consumed {
                if let k = st.key, case .char(let ch) = k.keyType {
                    st.longPressTimer?.invalidate()
                    st.consumed = true
                    handleCharacter(ch)
                }
            }

            let p = touch.location(in: keyArea)
            guard let key = keyAt(p) else { continue }
            let st = TouchState()
            st.key = key
            touchStates[touch] = st
            playClick()

            switch key.keyType {
            case .char:
                showKeyPreview(for: key)
                scheduleVariantTimer(touch, key)
            case .backspace:
                // Deletes on touch DOWN (system behavior), then repeats.
                handleBackspace()
                scheduleBackspaceRepeat(touch)
            case .shift:
                handleShift()
            case .toNumbers:
                st.returnLayer = layer
                commitComposing()
                layer = .numbers
                rebuildKeys()
                st.key = nil
            case .toSymbols:
                st.returnLayer = layer
                layer = .symbols
                rebuildKeys()
                st.key = nil
            case .toLetters:
                st.returnLayer = layer
                layer = .letters
                rebuildKeys()
                st.key = nil
            case .space:
                st.spacePanX = p.x
                scheduleSpaceCursorTimer(touch)
            case .globe, .ret:
                break
            }
        }
    }

    fileprivate func keysTouchesMoved(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let st = touchStates[touch], !st.consumed else { continue }
            let p = touch.location(in: keyArea)
            switch st.mode {
            case .spaceCursor:
                let stepWidth: CGFloat = 9
                let dx = p.x - st.spacePanX
                let steps = Int(dx / stepWidth)
                if steps != 0 {
                    noteInternalEdit()
                    textDocumentProxy.adjustTextPosition(byCharacterOffset: steps)
                    st.spacePanX += CGFloat(steps) * stepWidth
                }
            case .variants:
                updateVariantSelection(x: touch.location(in: view).x)
            case .normal:
                let newKey = keyAt(p)
                guard newKey !== st.key else { continue }
                st.longPressTimer?.invalidate()
                if let nk = newKey, isSlideTarget(nk.keyType) {
                    st.key = nk
                    if case .char = nk.keyType {
                        showKeyPreview(for: nk)
                        scheduleVariantTimer(touch, nk)
                    } else {
                        hideKeyPreview()
                    }
                } else {
                    st.key = nil
                    hideKeyPreview()
                }
            }
        }
    }

    fileprivate func keysTouchesEnded(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let st = touchStates.removeValue(forKey: touch) else { continue }
            st.longPressTimer?.invalidate()
            hideKeyPreview()

            if st.mode == .variants {
                insertSelectedVariant()
                dismissVariantPopup()
                continue
            }
            if st.mode == .spaceCursor {
                keyArea.alpha = 1.0
                continue
            }
            if let k = st.key, case .backspace = k.keyType {
                backspaceTimer?.invalidate()
                backspaceTimer = nil
                maybeAutoShift()
                continue
            }
            guard !st.consumed, let key = st.key else { continue }
            switch key.keyType {
            case .char(let ch):
                handleCharacter(ch)
                // Touched 123/#+= then slid to a character: insert it and
                // bounce back to the layer the gesture started from, the
                // system one-symbol gesture.
                if let rl = st.returnLayer, layer != rl {
                    layer = rl
                    rebuildKeys()
                }
            case .space:
                handleSpace()
            case .ret:
                handleReturn()
            case .globe:
                advanceToNextInputMode()
            default:
                break
            }
        }
    }

    fileprivate func keysTouchesCancelled(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let st = touchStates.removeValue(forKey: touch) else { continue }
            st.longPressTimer?.invalidate()
            if st.mode == .variants { dismissVariantPopup() }
            if st.mode == .spaceCursor { keyArea.alpha = 1.0 }
            if let k = st.key, case .backspace = k.keyType {
                backspaceTimer?.invalidate()
                backspaceTimer = nil
            }
            hideKeyPreview()
        }
    }

    // MARK: - Long-press timers

    private func scheduleBackspaceRepeat(_ touch: UITouch) {
        backspaceTicks = 0
        backspaceTimer?.invalidate()
        backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self, self.touchStates[touch] != nil else { return }
            self.backspaceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.telex.reset()
                self.hangul.reset()
                self.noteInternalEdit()
                self.backspaceTicks += 1
                // Characters first; a sustained press accelerates to words.
                if self.backspaceTicks <= 15 {
                    self.textDocumentProxy.deleteBackward()
                } else if self.backspaceTicks % 2 == 0 {
                    self.deleteWordBackward()
                }
                self.updateSuggestionBar()
            }
        }
    }

    private func scheduleSpaceCursorTimer(_ touch: UITouch) {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self, let st = self.touchStates[touch], st.mode == .normal else { return }
            st.mode = .spaceCursor
            st.spacePanX = touch.location(in: self.keyArea).x
            self.commitComposing()
            self.updateSuggestionBar()
            self.hideKeyPreview()
            // The system keyboard blanks the key labels in trackpad mode;
            // dimming is the closest cheap cue.
            self.keyArea.alpha = 0.5
        }
        touchStates[touch]?.longPressTimer = timer
    }

    private func scheduleVariantTimer(_ touch: UITouch, _ key: KeyButton) {
        guard case .char(let ch) = key.keyType, Self.variantMap[ch] != nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self, let st = self.touchStates[touch], st.mode == .normal else { return }
            st.mode = .variants
            self.hideKeyPreview()
            self.showVariantPopup(for: key)
        }
        touchStates[touch]?.longPressTimer = timer
    }

    // MARK: - Accent variant popup (long-press a key, slide, release)

    /// First entry is always the base character, like the system popup.
    /// Letter sets follow the US/Vietnamese system keyboard; ₫ added for VN.
    private static let variantMap: [String: [String]] = [
        "a": ["a", "à", "á", "â", "ä", "æ", "ã", "å", "ā"],
        "c": ["c", "ç", "ć", "č"],
        "d": ["d", "đ"],
        "e": ["e", "è", "é", "ê", "ë", "ē", "ė", "ę"],
        "i": ["i", "ì", "í", "î", "ï", "ī", "į"],
        "l": ["l", "ł"],
        "n": ["n", "ñ", "ń"],
        "o": ["o", "ò", "ó", "ô", "ö", "œ", "ø", "ō", "õ"],
        "s": ["s", "ß", "ś", "š"],
        "u": ["u", "ù", "ú", "û", "ü", "ū"],
        "y": ["y", "ÿ"],
        "z": ["z", "ž", "ź", "ż"],
        "0": ["0", "°"],
        "-": ["-", "–", "—", "•"],
        "/": ["/", "\\"],
        "$": ["$", "₫", "€", "£", "¥", "₩"],
        "&": ["&", "§"],
        "\"": ["\"", "«", "»", "„", "“", "”"],
        ".": [".", "…"],
        "?": ["?", "¿"],
        "!": ["!", "¡"],
        "'": ["'", "‘", "’", "`"],
        "%": ["%", "‰"],
        "=": ["=", "≠", "≈"],
        // Cyrillic (system Russian keyboard): е -> ё, ь -> ъ.
        "е": ["е", "ё"],
        "ь": ["ь", "ъ"],
        // Arabic alef hamza/madda forms, untypeable otherwise (أنا "I").
        "ا": ["ا", "أ", "إ", "آ", "ٱ"],
    ]

    private func showVariantPopup(for key: KeyButton) {
        guard case .char(let ch) = key.keyType, let baseVariants = Self.variantMap[ch] else { return }
        dismissVariantPopup()
        let upper = layer == .letters && shiftState != .off && currentLayout.shiftRows == nil
        variantOptions = upper ? baseVariants.map { $0.uppercased() } : baseVariants
        variantSelectedIndex = 0

        let f = view.convert(key.frame, from: keyArea)
        let ow = max(36, f.width)
        let h = f.height * 1.3
        let w = ow * CGFloat(variantOptions.count) + 8
        var x = f.minX - 4
        x = max(2, min(x, view.bounds.width - w - 2))
        let pop = UIView(frame: CGRect(x: x, y: max(2, f.minY - h - 4), width: w, height: h))
        pop.backgroundColor = keyFill
        pop.layer.cornerRadius = 9
        pop.layer.shadowColor = UIColor.black.cgColor
        pop.layer.shadowOpacity = 0.3
        pop.layer.shadowOffset = CGSize(width: 0, height: 1)
        pop.layer.shadowRadius = 5
        pop.isUserInteractionEnabled = false

        variantOptionLabels = []
        for (i, v) in variantOptions.enumerated() {
            let lb = UILabel(frame: CGRect(x: 4 + CGFloat(i) * ow, y: 4, width: ow, height: h - 8))
            lb.text = v
            lb.font = .systemFont(ofSize: 22)
            lb.textAlignment = .center
            lb.layer.cornerRadius = 6
            lb.layer.masksToBounds = true
            pop.addSubview(lb)
            variantOptionLabels.append(lb)
        }
        view.addSubview(pop)
        variantPopup = pop
        highlightVariant(0)
    }

    private func updateVariantSelection(x: CGFloat) {
        guard let pop = variantPopup, !variantOptionLabels.isEmpty else { return }
        let ow = (pop.bounds.width - 8) / CGFloat(variantOptionLabels.count)
        let idx = Int((x - pop.frame.minX - 4) / ow)
        highlightVariant(max(0, min(idx, variantOptionLabels.count - 1)))
    }

    private func highlightVariant(_ idx: Int) {
        variantSelectedIndex = idx
        for (i, lb) in variantOptionLabels.enumerated() {
            lb.backgroundColor = i == idx ? .systemBlue : .clear
            lb.textColor = i == idx ? .white : .label
        }
    }

    private func insertSelectedVariant() {
        guard variantSelectedIndex < variantOptions.count else { return }
        let v = variantOptions[variantSelectedIndex]
        commitComposing()
        noteInternalEdit()
        textDocumentProxy.insertText(v)
        if shiftState == .oneShot {
            shiftState = .off
            shiftDidChange()
        }
        updateSuggestionBar()
    }

    private func dismissVariantPopup() {
        variantPopup?.removeFromSuperview()
        variantPopup = nil
        variantOptionLabels = []
        variantOptions = []
    }

    // MARK: - Key actions

    private func handleCharacter(_ ch: String) {
        let isLetter = layer == .letters
        var out = ch
        if isLetter && shiftState != .off && currentLayout.shiftRows == nil {
            out = ch.uppercased()
        }

        if isLetter && telexActive, let c = out.first {
            let prev = telex.composingText
            telex.input(c)
            applyComposingDiff(from: prev, to: telex.composingText)
        } else if isLetter && inputLang == "ko", let c = out.first {
            let prev = hangul.composingText
            hangul.input(c)
            applyComposingDiff(from: prev, to: hangul.composingText)
        } else if isLetter && inputLang == "ja", let c = out.first,
                  c.isASCII, c.isLetter, c.isLowercase {
            if jaConverting { finalizeJaConversion() }   // a new key finalizes
            let prev = romaji.composingText
            romaji.input(c)
            applyComposingDiff(from: prev, to: romaji.composingText)
        } else if isLetter && inputLang == "zh", let c = out.first,
                  c.isASCII, c.isLetter, c.isLowercase {
            // Accumulate latin pinyin with live hanzi candidates on the bar.
            let prev = pinyin
            pinyin.append(c)
            applyComposingDiff(from: prev, to: pinyin)
        } else {
            commitComposing()
            noteInternalEdit()
            textDocumentProxy.insertText(out)
        }

        if shiftState == .oneShot {
            shiftState = .off
            shiftDidChange()
        }
        updateSuggestionBar()
    }

    /// Shift changes restyle Latin/Cyrillic keys in place; layouts with an
    /// explicit shift layer (Thai, Korean) swap the rows instead.
    private func shiftDidChange() {
        if layer == .letters && currentLayout.shiftRows != nil {
            rebuildKeys()
        } else {
            styleAllKeys()
        }
    }

    private func handleShift() {
        let now = Date()
        if now.timeIntervalSince(lastShiftTap) < 0.3 {
            shiftState = .locked
        } else {
            switch shiftState {
            case .off: shiftState = .oneShot
            case .oneShot, .locked: shiftState = .off
            }
        }
        lastShiftTap = now
        shiftDidChange()
    }

    private func handleBackspace() {
        if jaConverting {
            // Backspace during conversion: drop back to editing the kana.
            let shown = jaCandidates.indices.contains(jaCandIdx) ? jaCandidates[jaCandIdx] : ""
            cancelJaConversion()
            applyComposingDiff(from: shown, to: romaji.composingText)
        } else if romaji.hasComposingText {
            let prev = romaji.composingText
            romaji.backspace()
            applyComposingDiff(from: prev, to: romaji.composingText)
        } else if !pinyin.isEmpty {
            let prev = pinyin
            pinyin = String(pinyin.dropLast())
            applyComposingDiff(from: prev, to: pinyin)
        } else if telex.hasComposingText {
            let prev = telex.composingText
            telex.backspace()
            applyComposingDiff(from: prev, to: telex.composingText)
        } else if hangul.hasComposingText {
            let prev = hangul.composingText
            hangul.backspace()
            applyComposingDiff(from: prev, to: hangul.composingText)
        } else {
            noteInternalEdit()
            textDocumentProxy.deleteBackward()
        }
        maybeAutoShift()
        updateSuggestionBar()
    }

    /// Delete the word (plus its trailing whitespace) before the caret.
    private func deleteWordBackward() {
        guard let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty else { return }
        var count = 0
        var seenNonSpace = false
        for ch in before.reversed() {
            if ch == " " || ch == "\n" {
                if seenNonSpace { break }
            } else {
                seenNonSpace = true
            }
            count += 1
        }
        noteInternalEdit()
        for _ in 0..<count { textDocumentProxy.deleteBackward() }
    }

    private func handleSpace() {
        // Japanese: space converts kana->kanji (first press) then cycles
        // candidates; only a space with nothing composing types a space.
        if isJa {
            if jaConverting { cycleJaCandidate(); return }
            if startJaConversion() { return }
        }
        // Chinese: space commits the top hanzi candidate (no space typed).
        if inputLang == "zh", !pinyin.isEmpty {
            commitZh(zhCandidates.first ?? pinyin)
            return
        }
        let now = Date()
        // Double-space period, the iOS habit: "word  " -> "word. "
        // (ideographic 。 on the CJK layouts, like the system keyboards).
        if now.timeIntervalSince(lastSpaceTap) < 0.4,
           !telex.hasComposingText, !hangul.hasComposingText,
           let before = textDocumentProxy.documentContextBeforeInput,
           before.hasSuffix(" "),
           before.count >= 2 {
            let prior = before[before.index(before.endIndex, offsetBy: -2)]
            if prior.isLetter || prior.isNumber {
                noteInternalEdit()
                textDocumentProxy.deleteBackward()
                let cjk = inputLang == "zh" || isJa
                textDocumentProxy.insertText(cjk ? "。" : ". ")
                lastSpaceTap = .distantPast
                maybeAutoShift()
                updateSuggestionBar()
                return
            }
        }
        lastSpaceTap = now

        commitWordWithAutocorrect()
        noteInternalEdit()
        textDocumentProxy.insertText(" ")
        maybeAutoShift()
        updateSuggestionBar()
    }

    private func handleReturn() {
        // CJK: the first return only finalizes the run in the field (kanji
        // candidate / kana / raw pinyin); a bare return inserts the newline.
        if jaConverting || romaji.hasComposingText || !pinyin.isEmpty {
            commitComposing()
            updateSuggestionBar()
            return
        }
        commitComposing()
        noteInternalEdit()
        textDocumentProxy.insertText("\n")
        maybeAutoShift()
        updateSuggestionBar()
    }

    // MARK: - Composing helpers

    /// Replace the tail of the on-screen word so it goes from `prev` to `new`
    /// with the fewest proxy operations (delete differing suffix, insert).
    private func applyComposingDiff(from prev: String, to new: String) {
        let p = Array(prev)
        let n = Array(new)
        var common = 0
        while common < p.count && common < n.count && p[common] == n[common] { common += 1 }
        noteInternalEdit()
        for _ in 0..<(p.count - common) {
            textDocumentProxy.deleteBackward()
        }
        if common < n.count {
            textDocumentProxy.insertText(String(n[common...]))
        }
    }

    /// End the current composing word, leaving its text as-is in the field.
    private func commitComposing() {
        _ = telex.commitWord()
        _ = hangul.commit()
        if jaConverting {
            finalizeJaConversion()   // the displayed candidate stays
        } else if romaji.hasComposingText {
            // commit() may finalize a trailing "n" as ん - mirror that edit.
            let prev = romaji.composingText
            let final = romaji.commit()
            if final != prev { applyComposingDiff(from: prev, to: final) }
        }
        if !pinyin.isEmpty {
            pinyin = ""              // the raw pinyin stays in the field
            zhCandidates = []
        }
    }

    // MARK: - Japanese henkan / Chinese pinyin commits

    /// Space on a kana run: start conversion, field shows the top candidate.
    private func startJaConversion() -> Bool {
        guard romaji.hasComposingText else { return false }
        let shown = romaji.composingText
        let reading = romaji.commit()
        guard !reading.isEmpty else { return false }
        jaReading = reading
        var cands = Array(kanjiConv.convert(reading).prefix(12))
        if cands.isEmpty { cands = [reading] }
        jaCandidates = cands
        jaCandIdx = 0
        jaConverting = true
        applyComposingDiff(from: shown, to: cands[0])
        updateSuggestionBar()
        return true
    }

    /// Space again: highlight (and show in the field) the next candidate.
    private func cycleJaCandidate() {
        guard jaConverting, !jaCandidates.isEmpty else { return }
        let prev = jaCandidates[jaCandIdx]
        jaCandIdx = (jaCandIdx + 1) % jaCandidates.count
        applyComposingDiff(from: prev, to: jaCandidates[jaCandIdx])
        updateSuggestionBar()
    }

    /// Finalize the highlighted candidate (return / a new key).
    private func finalizeJaConversion() {
        guard jaConverting else { return }
        endJaConversion()
    }

    /// Backspace during conversion: back to editing the kana reading.
    private func cancelJaConversion() {
        let reading = jaReading
        endJaConversion()
        romaji.load(reading)
    }

    private func endJaConversion() {
        jaConverting = false
        jaCandidates = []
        jaCandIdx = 0
        jaReading = ""
    }

    // MARK: - Japanese flick (12-key) input

    private func showFlickKeyboard() {
        let fv: FlickInputView
        if let existing = flickView {
            fv = existing
        } else {
            fv = FlickInputView()
            fv.translatesAutoresizingMaskIntoConstraints = false
            fv.onKana = { [weak self] in self?.flickInputKana($0) }
            fv.onSymbol = { [weak self] in self?.flickInputSymbol($0) }
            fv.onBackspace = { [weak self] in self?.handleBackspace() }
            fv.onSpace = { [weak self] in self?.handleSpace() }
            fv.onReturn = { [weak self] in self?.handleReturn() }
            fv.onDakuten = { [weak self] in self?.flickDakuten() }
            fv.onSwitchToRomaji = { [weak self] in self?.flickSwitchToRomaji() }
            fv.onEmoji = { [weak self] in self?.flickToggleEmoji() }
            fv.onTapSound = { [weak self] in self?.playClick() }
            keyArea.addSubview(fv)
            NSLayoutConstraint.activate([
                fv.topAnchor.constraint(equalTo: keyArea.topAnchor),
                fv.leadingAnchor.constraint(equalTo: keyArea.leadingAnchor),
                fv.trailingAnchor.constraint(equalTo: keyArea.trailingAnchor),
                fv.bottomAnchor.constraint(equalTo: keyArea.bottomAnchor),
            ])
            // Same system globe behaviour as the QWERTY keyboard's globe key:
            // tap = next keyboard, long-press = the keyboard picker.
            fv.globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            flickView = fv
        }
        fv.showsGlobe = needsInputModeSwitchKey
        fv.isHidden = false
        keyArea.bringSubviewToFront(fv)
    }

    private func hideFlickKeyboard() {
        flickView?.isHidden = true
        dismissEmojiPanel()
    }

    /// Toggle the emoji picker over the flick grid (the ☺ key).
    private func flickToggleEmoji() {
        if emojiPanel != nil { dismissEmojiPanel(); return }
        let panel = EmojiPanelView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.onTapSound = { [weak self] in self?.playClick() }
        panel.onPick = { [weak self] in self?.flickInsertEmoji($0) }
        panel.onBackspace = { [weak self] in self?.handleBackspace() }
        panel.onBack = { [weak self] in self?.dismissEmojiPanel() }
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        emojiPanel = panel
    }

    private func dismissEmojiPanel() {
        emojiPanel?.removeFromSuperview()
        emojiPanel = nil
    }

    /// Insert an emoji: finalize any kana run, type it, remember it as recent.
    private func flickInsertEmoji(_ e: String) {
        commitComposing()
        noteInternalEdit()
        textDocumentProxy.insertText(e)
        AppGroupStore.shared.pushEmojiRecent(e)
        updateSuggestionBar()
    }

    /// A flick produced a kana: append it to the SAME composing buffer the
    /// romaji path uses, so all henkan / candidate logic is shared.
    private func flickInputKana(_ kana: String) {
        if jaConverting { finalizeJaConversion() }
        let prev = romaji.composingText
        romaji.load(prev + kana)
        applyComposingDiff(from: prev, to: romaji.composingText)
        updateSuggestionBar()
    }

    /// A flick produced a punctuation mark (、。？！…): finalize any kana run,
    /// then insert the mark literally (it must not enter the kana buffer or
    /// space would try to convert it).
    private func flickInputSymbol(_ mark: String) {
        commitComposing()
        noteInternalEdit()
        textDocumentProxy.insertText(mark)
        updateSuggestionBar()
    }

    /// The 小゛゜ key: cycle the LAST kana in the buffer through its
    /// dakuten / handakuten / small forms (Android KEYCODE_KANA_MOD parity).
    private func flickDakuten() {
        guard !jaConverting, romaji.hasComposingText else { return }
        let cur = romaji.composingText
        guard let last = cur.last else { return }
        // The cycle map is keyed by hiragana; map katakana down and back so the
        // key works the same in katakana mode.
        let scalar = last.unicodeScalars.first!.value
        let isKata = scalar >= 0x30A1 && scalar <= 0x30F6
        let hira: Character = isKata
            ? Character(UnicodeScalar(scalar - 0x60)!) : last
        guard let nextHira = Self.dakutenCycle[hira] else { return }
        let next: Character = isKata
            ? Character(UnicodeScalar(nextHira.unicodeScalars.first!.value + 0x60)!)
            : nextHira
        let prev = cur
        romaji.load(String(cur.dropLast()) + String(next))
        applyComposingDiff(from: prev, to: romaji.composingText)
        updateSuggestionBar()
    }

    /// The ABC key: switch to the romaji (QWERTY) Japanese mode, where latin
    /// letters, numbers and symbols are reachable.
    private func flickSwitchToRomaji() {
        commitComposing()
        inputLang = "ja"
        AppGroupStore.shared.keyboardInputLang = "ja"
        shiftState = .off
        layer = .letters
        rebuildKeys()
        updateSuggestionBar()
    }

    /// Closed cycle for the 小゛゜ modifier: base -> dakuten -> handakuten ->
    /// small -> base. Only kana that have a variant appear; others are no-ops.
    private static let dakutenCycle: [Character: Character] = [
        "か": "が", "が": "か", "き": "ぎ", "ぎ": "き", "く": "ぐ", "ぐ": "く",
        "け": "げ", "げ": "け", "こ": "ご", "ご": "こ",
        "さ": "ざ", "ざ": "さ", "し": "じ", "じ": "し", "す": "ず", "ず": "す",
        "せ": "ぜ", "ぜ": "せ", "そ": "ぞ", "ぞ": "そ",
        "た": "だ", "だ": "た", "ち": "ぢ", "ぢ": "ち", "て": "で", "で": "て",
        "と": "ど", "ど": "と", "つ": "づ", "づ": "っ", "っ": "つ",
        "は": "ば", "ば": "ぱ", "ぱ": "は", "ひ": "び", "び": "ぴ", "ぴ": "ひ",
        "ふ": "ぶ", "ぶ": "ぷ", "ぷ": "ふ", "へ": "べ", "べ": "ぺ", "ぺ": "へ",
        "ほ": "ぼ", "ぼ": "ぽ", "ぽ": "ほ",
        "う": "ゔ", "ゔ": "う",
        "あ": "ぁ", "ぁ": "あ", "い": "ぃ", "ぃ": "い", "え": "ぇ", "ぇ": "え",
        "お": "ぉ", "ぉ": "お",
        "や": "ゃ", "ゃ": "や", "ゆ": "ゅ", "ゅ": "ゆ", "よ": "ょ", "ょ": "よ",
        "わ": "ゎ", "ゎ": "わ",
    ]

    /// Commit [text] (a chosen hanzi candidate, or the raw pinyin) and reset.
    private func commitZh(_ text: String) {
        applyComposingDiff(from: pinyin, to: text)
        pinyin = ""
        zhCandidates = []
        updateSuggestionBar()
    }

    /// Commit on a word boundary; when autocorrect is ON, replace a typo with
    /// the dictionary fix (never for literal-intent or known English words).
    /// Vietnamese only - Hangul commits as typed.
    private func commitWordWithAutocorrect() {
        if hangul.hasComposingText {
            commitComposing()
            return
        }
        let word = telex.composingText
        let literal = telex.literalIntent
        commitComposing()
        guard autocorrectEnabled, !literal, word.count >= 2 else { return }
        guard !corrector.isValid(word), !corrector.isEnglish(word) else { return }
        if let fixed = corrector.fix(word) {
            noteInternalEdit()
            for _ in 0..<word.count {
                textDocumentProxy.deleteBackward()
            }
            textDocumentProxy.insertText(fixed)
        }
    }

    /// Replace the current composing word with `replacement` (suggestion tap).
    private func replaceComposing(with replacement: String) {
        let word = telex.composingText
        commitComposing()
        noteInternalEdit()
        for _ in 0..<word.count {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(replacement)
        updateSuggestionBar()
    }

    /// One-shot shift at a sentence start, like the system keyboard. Gated on
    /// the field asking for sentence capitalization, and only for layouts
    /// where shift means case (Latin, Cyrillic) - never Thai/Korean/Arabic.
    private func maybeAutoShift() {
        guard layer == .letters, shiftState == .off else { return }
        guard currentLayout.hasShift, currentLayout.shiftRows == nil else { return }
        // ja/zh ride the QWERTY layout but type CJK - no sentence caps.
        guard inputLang != "ja", inputLang != "zh" else { return }
        guard textDocumentProxy.autocapitalizationType == .sentences else { return }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let shouldCap: Bool
        if before.isEmpty || before.hasSuffix("\n") {
            shouldCap = true
        } else if before.hasSuffix(". ") || before.hasSuffix("! ") || before.hasSuffix("? ") {
            shouldCap = true
        } else {
            shouldCap = false
        }
        if shouldCap {
            shiftState = .oneShot
            styleAllKeys()
        }
    }

    private func playClick() {
        UIDevice.current.playInputClick()
    }

    // MARK: - Result panel (translate / reply / refine results)

    private func setupResultPanel() {
        resultPanel = UIView()
        resultPanel.backgroundColor = .systemBackground
        resultPanel.isHidden = true
        resultPanel.translatesAutoresizingMaskIntoConstraints = false
        resultPanel.heightAnchor.constraint(equalToConstant: resultPanelHeight).isActive = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        resultPanel.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: resultPanel.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: resultPanel.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: resultPanel.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: resultPanel.bottomAnchor, constant: -8),
        ])

        resultErrorLabel = UILabel()
        resultErrorLabel.font = .systemFont(ofSize: 13)
        resultErrorLabel.textColor = .systemRed
        resultErrorLabel.numberOfLines = 2
        resultErrorLabel.isHidden = true
        stack.addArrangedSubview(resultErrorLabel)

        upgradeBtn = UIButton(type: .system)
        upgradeBtn.setTitle("Upgrade for unlimited", for: .normal)
        upgradeBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        upgradeBtn.setTitleColor(.white, for: .normal)
        upgradeBtn.backgroundColor = primaryColor
        upgradeBtn.layer.cornerRadius = 8
        upgradeBtn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        upgradeBtn.addTarget(self, action: #selector(upgradeTapped), for: .touchUpInside)
        upgradeBtn.isHidden = true
        stack.addArrangedSubview(upgradeBtn)

        let actionStack = UIStackView()
        actionStack.axis = .horizontal
        actionStack.spacing = 12

        let closeBtn = smallButton(title: "✕", action: #selector(closeResultTapped))
        actionStack.addArrangedSubview(closeBtn)
        actionStack.addArrangedSubview(UIView())
        stack.addArrangedSubview(actionStack)

        mainStack.addArrangedSubview(resultPanel)
    }

    private func smallButton(title: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.setTitleColor(primaryColor, for: .normal)
        btn.backgroundColor = primaryColor.withAlphaComponent(0.1)
        btn.layer.cornerRadius = 6
        btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    // MARK: - TransKey actions

    /// Translate the whole field and replace it in place, arming the red undo
    /// chip - exactly the Android chip behavior (no result popup, the inserted
    /// text IS the result).
    @objc private func translateTapped() {
        guard !actionInFlight else { return }
        commitComposing()
        let fullText = (textDocumentProxy.documentContextBeforeInput ?? "")
            + (textDocumentProxy.documentContextAfterInput ?? "")
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showResultError("No text in input field.")
            return
        }

        actionInFlight = true
        showBarProcessing()

        Task { @MainActor in
            do {
                let store = AppGroupStore.shared
                let json = try await api.translate(
                    text: trimmed,
                    targetLang: store.targetLang,
                    sourceLang: store.sourceLang
                )
                actionInFlight = false
                applyActionResult(original: fullText, replacement: extractTranslation(json))
            } catch {
                actionInFlight = false
                showActionBar()
                handleRequestError(error)
            }
        }
    }

    /// Translate the CLIPBOARD and show it in a reading panel over the keys
    /// (X returns to typing). Covers the "understand the incoming message"
    /// case the in-field actions can't reach: copy their message, tap, read.
    /// UIPasteboard returns nil without Full Access - same requirement every
    /// network chip already has.
    @objc private func clipboardTranslateTapped() {
        guard !actionInFlight else { return }
        commitComposing()
        let raw = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            showResultError("Chưa có chữ nào được sao chép. Hãy copy tin nhắn cần dịch trước.")
            return
        }
        let text = String(raw.prefix(3000))

        actionInFlight = true
        showBarProcessing()

        Task { @MainActor in
            do {
                let store = AppGroupStore.shared
                let json = try await api.translate(
                    text: text,
                    targetLang: store.targetLang,
                    sourceLang: store.sourceLang
                )
                actionInFlight = false
                showActionBar()
                // Scam warning (server drops "none", so present = warn). A
                // received message the user copied is exactly the fraud target.
                var scamTitle: String?
                var scamDetail: String?
                var scamHigh = false
                if let scam = json["scamRisk"] as? [String: Any],
                   let level = scam["level"] as? String, level == "low" || level == "high" {
                    scamHigh = level == "high"
                    scamTitle = KB.t(scamHigh ? "scamHigh" : "scamLow")
                    let reason = (scam["reason"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    scamDetail = (reason?.isEmpty == false) ? reason : KB.t("scamHint")
                }
                showClipboardPanel(
                    translated: extractTranslation(json),
                    scamTitle: scamTitle,
                    scamDetail: scamDetail,
                    scamHigh: scamHigh
                )
            } catch {
                actionInFlight = false
                showActionBar()
                handleRequestError(error)
            }
        }
    }

    @objc private func replyTapped() {
        guard !actionInFlight else { return }
        commitComposing()
        let fullText = (textDocumentProxy.documentContextBeforeInput ?? "")
            + (textDocumentProxy.documentContextAfterInput ?? "")
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showResultError("No text in input field.")
            return
        }

        actionInFlight = true
        showBarProcessing()

        Task { @MainActor in
            do {
                let json = try await api.translate(
                    text: trimmed,
                    targetLang: AppGroupStore.shared.targetLang,
                    sourceLang: nil,
                    isReply: true
                )
                actionInFlight = false
                applyActionResult(original: fullText, replacement: extractTranslation(json))
            } catch {
                actionInFlight = false
                showActionBar()
                handleRequestError(error)
            }
        }
    }

    /// Replace the field's entire content. UITextDocumentProxy has no
    /// select-all; walk the caret to the end, then delete backwards chunk by
    /// chunk (the proxy exposes the document in windows around the caret).
    private func replaceAllText(with text: String) {
        noteInternalEdit()
        while let after = textDocumentProxy.documentContextAfterInput, !after.isEmpty {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: after.count)
        }
        while let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty {
            for _ in 0..<before.count { textDocumentProxy.deleteBackward() }
            noteInternalEdit()
        }
        textDocumentProxy.insertText(text)
    }

    /// Success path shared by translate/reply/refine: swap the field content
    /// for the result and arm the undo chip. The chip stays until the user
    /// edits the field or switches fields (Android parity, no timer).
    private func applyActionResult(original: String, replacement: String) {
        guard !replacement.isEmpty else {
            showActionBar()
            return
        }
        actionReplaceInProgress = true
        replaceAllText(with: replacement)
        actionReplaceInProgress = false
        undoSnapshot = original
        showActionBar()
    }

    /// Restore the field to its pre-action text, then drop the chip.
    @objc private func undoTapped() {
        guard let snapshot = undoSnapshot else { return }
        undoSnapshot = nil
        actionReplaceInProgress = true
        replaceAllText(with: snapshot)
        actionReplaceInProgress = false
        showActionBar()
    }

    @objc private func refineTapped() {
        guard AppGroupStore.shared.featureRefine else { return }
        guard !actionInFlight else { return }
        commitComposing()
        let fullText = (textDocumentProxy.documentContextBeforeInput ?? "")
            + (textDocumentProxy.documentContextAfterInput ?? "")
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showResultError("No text in input field.")
            return
        }

        actionInFlight = true
        showBarProcessing()

        Task { @MainActor in
            do {
                let json = try await api.refine(text: trimmed)
                actionInFlight = false
                applyActionResult(original: fullText, replacement: extractTranslation(json))
            } catch {
                actionInFlight = false
                showActionBar()
                handleRequestError(error)
            }
        }
    }

    // MARK: - Error panel (the panel only ever shows errors now; successful
    // actions replace the field directly and arm the undo chip instead)

    @objc private func closeResultTapped() {
        resultPanel.isHidden = true
        resultPanelVisible = false
        upgradeBtn?.isHidden = true
        updateHeight()
    }

    private func showResultError(_ message: String) {
        if !resultPanelVisible {
            resultPanel.isHidden = false
            resultPanelVisible = true
            updateHeight()
        }
        resultErrorLabel.text = message
        resultErrorLabel.isHidden = false
        // Generic errors never offer the upgrade CTA; only the quota error does.
        upgradeBtn.isHidden = true
    }

    /// Route an API error: a daily-quota hit gets the upgrade CTA so the free
    /// user can act on it; everything else is a plain red message.
    private func handleRequestError(_ error: Error) {
        if case APIError.quotaExceeded = error {
            showResultError(APIError.quotaExceeded.errorDescription ?? "Daily quota exceeded.")
            upgradeBtn.isHidden = false
        } else {
            showResultError(error.localizedDescription)
        }
    }

    @objc private func upgradeTapped() {
        openHostApp("transkey://upgrade")
    }

    /// Open a host-app URL from the keyboard extension. extensionContext.open is
    /// unreliable for keyboards, so walk the responder chain to UIApplication
    /// and call open(_:) there (the standard keyboard-extension pattern).
    private func openHostApp(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
    }

    private func extractTranslation(_ json: [String: Any]) -> String {
        return json["translation"] as? String
            ?? json["result"] as? String
            ?? json["summary"] as? String
            ?? json["explanation"] as? String
            ?? json["refined"] as? String
            ?? ""
    }
}

/// Passive key surface that forwards raw touches to the controller, so every
/// key shares one touch pipeline (slide between keys, multi-touch rollover,
/// long-press) exactly like the system keyboard.
final class KeyAreaView: UIView {
    weak var owner: KeyboardViewController?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        owner?.keysTouchesBegan(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        owner?.keysTouchesMoved(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        owner?.keysTouchesEnded(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        owner?.keysTouchesCancelled(touches)
    }
}

/// Opt in to system key-click sounds; without this conformance
/// UIDevice.playInputClick() is silently ignored for the extension.
extension UIInputView: @retroactive UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}

/// In-app-language localization for the keyboard extension. The keyboard must
/// follow the language the user picked INSIDE the app (mirrored to the App
/// Group as `tk_ui_lang` by AppGroupBridge.saveUiLang), NOT the iOS device
/// language - so the system Bundle/NSLocalizedString (which follows the
/// device) can't be used. This small manual table keyed by the app's UI
/// language does it; English is the fallback for any missing language/key.
enum KB {
    /// The app's current UI language. Prefer the mirrored app choice, then the
    /// device language (if shipped), then English.
    static var lang: String {
        let stored = AppGroupStore.shared.uiLang
        if !stored.isEmpty, table[stored] != nil { return stored }
        let device = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        return table[device] != nil ? device : "en"
    }

    static func t(_ key: String) -> String {
        let l = lang
        return table[l]?[key] ?? table["en"]?[key] ?? key
    }

    private static let table: [String: [String: String]] = [
        "en": ["translate": "Translate", "reply": "Reply", "refine": "Refine", "undo": "Undo", "processing": "Processing…", "translation": "Translation", "close": "Close", "typingLanguage": "Typing language", "translationLanguage": "Translation language", "done": "Done", "swap": "⇄ Swap", "chooseTypingLanguage": "Choose the language you want to type", "sourceLanguage": "Source language", "translateTo": "Translate to", "autoDetect": "Auto detect", "enableFullAccess": "Enable Full Access", "fullAccessInfo": "Translate, Reply and Refine need Full Access. Turn it on:\nSettings → General → Keyboard → Keyboards → TransKey → Allow Full Access", "guideTitle": "Using the translate keyboard", "guideClipboard": "Copy their message, then tap to see what it says.", "guideReply": "Type your reply, then tap to translate it before sending.", "guideRefine": "Polish your text so it reads smoothly.", "gotIt": "Got it", "copy": "Copy", "copied": "Copied", "scamHigh": "Warning: this message shows signs of a scam", "scamLow": "Caution: this message could be a scam", "scamHint": "Be careful before replying, clicking links, or sending money."],
        "vi": ["translate": "Dịch", "reply": "Trả lời", "refine": "Trau chuốt", "undo": "Hoàn tác", "processing": "Đang xử lý…", "translation": "Bản dịch", "close": "Đóng", "typingLanguage": "Ngôn ngữ gõ phím", "translationLanguage": "Ngôn ngữ dịch", "done": "Xong", "swap": "⇄ Đổi chiều", "chooseTypingLanguage": "Chọn ngôn ngữ bạn muốn gõ", "sourceLanguage": "Ngôn ngữ nguồn", "translateTo": "Dịch sang", "autoDetect": "Tự nhận diện", "enableFullAccess": "Bật Toàn quyền truy cập", "fullAccessInfo": "Dịch, Trả lời và Trau chuốt cần Toàn quyền truy cập. Bật tại:\nCài đặt → Cài đặt chung → Bàn phím → Bàn phím → TransKey → Cho phép Toàn quyền truy cập", "guideTitle": "Cách dùng bàn phím dịch", "guideClipboard": "Copy tin nhắn của họ rồi nhấn để xem nội dung bằng ngôn ngữ của bạn.", "guideReply": "Gõ câu trả lời của bạn rồi nhấn để dịch trước khi gửi.", "guideRefine": "Trau chuốt câu chữ cho mượt mà, tự nhiên hơn.", "gotIt": "Đã hiểu", "copy": "Copy", "copied": "Đã copy", "scamHigh": "Cảnh báo: tin nhắn có dấu hiệu lừa đảo", "scamLow": "Thận trọng: tin nhắn này có thể là lừa đảo", "scamHint": "Hãy cẩn thận trước khi trả lời, bấm liên kết hay chuyển tiền."],
        "ar": ["translate": "ترجمة", "reply": "رد", "refine": "تحسين", "undo": "تراجع", "processing": "جارٍ المعالجة…", "translation": "الترجمة", "close": "إغلاق", "typingLanguage": "لغة الكتابة", "translationLanguage": "لغة الترجمة", "done": "تم", "swap": "⇄ تبديل", "chooseTypingLanguage": "اختر اللغة التي تريد الكتابة بها", "sourceLanguage": "اللغة المصدر", "translateTo": "الترجمة إلى", "autoDetect": "اكتشاف تلقائي", "enableFullAccess": "تفعيل الوصول الكامل", "fullAccessInfo": "الترجمة والرد والتحسين تتطلب الوصول الكامل. فعّله من:\nالإعدادات ← عام ← لوحة المفاتيح ← لوحات المفاتيح ← TransKey ← السماح بالوصول الكامل", "guideTitle": "استخدام لوحة الترجمة", "guideClipboard": "انسخ رسالتهم ثم اضغط لرؤية معناها بلغتك.", "guideReply": "اكتب ردك ثم اضغط لترجمته قبل الإرسال.", "guideRefine": "حسّن نصك ليصبح أكثر سلاسة وطبيعية.", "gotIt": "فهمت", "copy": "نسخ", "copied": "تم النسخ", "scamHigh": "تحذير: تظهر على هذه الرسالة علامات احتيال", "scamLow": "تنبيه: قد تكون هذه الرسالة عملية احتيال", "scamHint": "كن حذرًا قبل الرد أو النقر على الروابط أو إرسال الأموال."],
        "de": ["translate": "Übersetzen", "reply": "Antworten", "refine": "Verfeinern", "undo": "Rückgängig", "processing": "Wird verarbeitet…", "translation": "Übersetzung", "close": "Schließen", "typingLanguage": "Tippsprache", "translationLanguage": "Übersetzungssprache", "done": "Fertig", "swap": "⇄ Tauschen", "chooseTypingLanguage": "Wähle die Sprache zum Tippen", "sourceLanguage": "Ausgangssprache", "translateTo": "Übersetzen nach", "autoDetect": "Automatisch erkennen", "enableFullAccess": "Vollzugriff aktivieren", "fullAccessInfo": "Übersetzen, Antworten und Verfeinern benötigen Vollzugriff. So aktivierst du ihn:\nEinstellungen → Allgemein → Tastatur → Tastaturen → TransKey → Vollzugriff erlauben", "guideTitle": "Übersetzungstastatur verwenden", "guideClipboard": "Kopiere ihre Nachricht und tippe, um sie in deiner Sprache zu lesen.", "guideReply": "Tippe deine Antwort und tippe dann, um sie vor dem Senden zu übersetzen.", "guideRefine": "Verfeinere deinen Text, damit er natürlich klingt.", "gotIt": "Verstanden", "copy": "Kopieren", "copied": "Kopiert", "scamHigh": "Warnung: Diese Nachricht zeigt Anzeichen von Betrug", "scamLow": "Vorsicht: Diese Nachricht könnte Betrug sein", "scamHint": "Sei vorsichtig, bevor du antwortest, Links anklickst oder Geld sendest."],
        "es": ["translate": "Traducir", "reply": "Responder", "refine": "Pulir", "undo": "Deshacer", "processing": "Procesando…", "translation": "Traducción", "close": "Cerrar", "typingLanguage": "Idioma de escritura", "translationLanguage": "Idioma de traducción", "done": "Listo", "swap": "⇄ Cambiar", "chooseTypingLanguage": "Elige el idioma que quieres escribir", "sourceLanguage": "Idioma de origen", "translateTo": "Traducir a", "autoDetect": "Detección automática", "enableFullAccess": "Activar Acceso completo", "fullAccessInfo": "Traducir, Responder y Pulir necesitan Acceso completo. Actívalo:\nAjustes → General → Teclado → Teclados → TransKey → Permitir acceso completo", "guideTitle": "Cómo usar el teclado de traducción", "guideClipboard": "Copia su mensaje y toca para verlo en tu idioma.", "guideReply": "Escribe tu respuesta y toca para traducirla antes de enviarla.", "guideRefine": "Pule tu texto para que se lea con naturalidad.", "gotIt": "Entendido", "copy": "Copiar", "copied": "Copiado", "scamHigh": "Advertencia: este mensaje muestra señales de estafa", "scamLow": "Precaución: este mensaje podría ser una estafa", "scamHint": "Ten cuidado antes de responder, hacer clic en enlaces o enviar dinero."],
        "fr": ["translate": "Traduire", "reply": "Répondre", "refine": "Peaufiner", "undo": "Annuler", "processing": "Traitement…", "translation": "Traduction", "close": "Fermer", "typingLanguage": "Langue de saisie", "translationLanguage": "Langue de traduction", "done": "Terminé", "swap": "⇄ Inverser", "chooseTypingLanguage": "Choisissez la langue de saisie", "sourceLanguage": "Langue source", "translateTo": "Traduire vers", "autoDetect": "Détection auto", "enableFullAccess": "Activer l'accès complet", "fullAccessInfo": "Traduire, Répondre et Peaufiner nécessitent l'accès complet. Activez-le :\nRéglages → Général → Clavier → Claviers → TransKey → Autoriser l'accès complet", "guideTitle": "Utiliser le clavier de traduction", "guideClipboard": "Copiez leur message, puis appuyez pour le lire dans votre langue.", "guideReply": "Saisissez votre réponse, puis appuyez pour la traduire avant l'envoi.", "guideRefine": "Peaufinez votre texte pour qu'il soit fluide et naturel.", "gotIt": "Compris", "copy": "Copier", "copied": "Copié", "scamHigh": "Avertissement : ce message présente des signes d'arnaque", "scamLow": "Prudence : ce message pourrait être une arnaque", "scamHint": "Soyez prudent avant de répondre, cliquer sur un lien ou envoyer de l'argent."],
        "id": ["translate": "Terjemahkan", "reply": "Balas", "refine": "Perhalus", "undo": "Urungkan", "processing": "Memproses…", "translation": "Terjemahan", "close": "Tutup", "typingLanguage": "Bahasa ketik", "translationLanguage": "Bahasa terjemahan", "done": "Selesai", "swap": "⇄ Tukar", "chooseTypingLanguage": "Pilih bahasa yang ingin diketik", "sourceLanguage": "Bahasa sumber", "translateTo": "Terjemahkan ke", "autoDetect": "Deteksi otomatis", "enableFullAccess": "Aktifkan Akses Penuh", "fullAccessInfo": "Terjemahkan, Balas, dan Perhalus memerlukan Akses Penuh. Aktifkan di:\nPengaturan → Umum → Keyboard → Keyboard → TransKey → Izinkan Akses Penuh", "guideTitle": "Cara memakai keyboard terjemahan", "guideClipboard": "Salin pesan mereka, lalu ketuk untuk membacanya dalam bahasamu.", "guideReply": "Ketik balasanmu, lalu ketuk untuk menerjemahkannya sebelum dikirim.", "guideRefine": "Perhalus teksmu agar terbaca lebih alami.", "gotIt": "Mengerti", "copy": "Salin", "copied": "Tersalin", "scamHigh": "Peringatan: pesan ini menunjukkan tanda-tanda penipuan", "scamLow": "Hati-hati: pesan ini mungkin penipuan", "scamHint": "Berhati-hatilah sebelum membalas, mengeklik tautan, atau mengirim uang."],
        "it": ["translate": "Traduci", "reply": "Rispondi", "refine": "Rifinisci", "undo": "Annulla", "processing": "Elaborazione…", "translation": "Traduzione", "close": "Chiudi", "typingLanguage": "Lingua di digitazione", "translationLanguage": "Lingua di traduzione", "done": "Fine", "swap": "⇄ Inverti", "chooseTypingLanguage": "Scegli la lingua con cui digitare", "sourceLanguage": "Lingua di origine", "translateTo": "Traduci in", "autoDetect": "Rilevamento automatico", "enableFullAccess": "Abilita Accesso completo", "fullAccessInfo": "Traduci, Rispondi e Rifinisci richiedono l'Accesso completo. Attivalo:\nImpostazioni → Generali → Tastiera → Tastiere → TransKey → Consenti accesso completo", "guideTitle": "Come usare la tastiera di traduzione", "guideClipboard": "Copia il loro messaggio e tocca per leggerlo nella tua lingua.", "guideReply": "Scrivi la tua risposta e tocca per tradurla prima di inviarla.", "guideRefine": "Rifinisci il testo perché scorra in modo naturale.", "gotIt": "Ho capito", "copy": "Copia", "copied": "Copiato", "scamHigh": "Avviso: questo messaggio mostra segni di truffa", "scamLow": "Attenzione: questo messaggio potrebbe essere una truffa", "scamHint": "Fai attenzione prima di rispondere, cliccare link o inviare denaro."],
        "ja": ["translate": "翻訳", "reply": "返信", "refine": "推敲", "undo": "取り消し", "processing": "処理中…", "translation": "翻訳", "close": "閉じる", "typingLanguage": "入力言語", "translationLanguage": "翻訳言語", "done": "完了", "swap": "⇄ 入れ替え", "chooseTypingLanguage": "入力する言語を選択", "sourceLanguage": "元の言語", "translateTo": "翻訳先", "autoDetect": "自動検出", "enableFullAccess": "フルアクセスを許可", "fullAccessInfo": "翻訳・返信・推敲にはフルアクセスが必要です。オンにする:\n設定 → 一般 → キーボード → キーボード → TransKey → フルアクセスを許可", "guideTitle": "翻訳キーボードの使い方", "guideClipboard": "相手のメッセージをコピーして、タップすると自分の言語で読めます。", "guideReply": "返信を入力して、タップすると送信前に翻訳できます。", "guideRefine": "文章を整えて、より自然な表現にします。", "gotIt": "わかりました", "copy": "コピー", "copied": "コピーしました", "scamHigh": "警告：このメッセージには詐欺の兆候があります", "scamLow": "注意：このメッセージは詐欺の可能性があります", "scamHint": "返信・リンクのクリック・送金の前に十分ご注意ください。"],
        "ko": ["translate": "번역", "reply": "답장", "refine": "다듬기", "undo": "실행 취소", "processing": "처리 중…", "translation": "번역", "close": "닫기", "typingLanguage": "입력 언어", "translationLanguage": "번역 언어", "done": "완료", "swap": "⇄ 바꾸기", "chooseTypingLanguage": "입력할 언어를 선택하세요", "sourceLanguage": "원본 언어", "translateTo": "번역 대상", "autoDetect": "자동 감지", "enableFullAccess": "전체 접근 허용", "fullAccessInfo": "번역, 답장, 다듬기에는 전체 접근이 필요합니다. 켜는 방법:\n설정 → 일반 → 키보드 → 키보드 → TransKey → 전체 접근 허용", "guideTitle": "번역 키보드 사용법", "guideClipboard": "상대방 메시지를 복사한 후 누르면 내 언어로 볼 수 있어요.", "guideReply": "답장을 입력한 후 누르면 보내기 전에 번역돼요.", "guideRefine": "문장을 다듬어 더 자연스럽게 만들어요.", "gotIt": "확인", "copy": "복사", "copied": "복사됨", "scamHigh": "경고: 이 메시지는 사기 징후가 있습니다", "scamLow": "주의: 이 메시지는 사기일 수 있습니다", "scamHint": "답장, 링크 클릭, 송금 전에 반드시 주의하세요."],
        "pt": ["translate": "Traduzir", "reply": "Responder", "refine": "Refinar", "undo": "Desfazer", "processing": "Processando…", "translation": "Tradução", "close": "Fechar", "typingLanguage": "Idioma de digitação", "translationLanguage": "Idioma de tradução", "done": "Concluir", "swap": "⇄ Inverter", "chooseTypingLanguage": "Escolha o idioma que deseja digitar", "sourceLanguage": "Idioma de origem", "translateTo": "Traduzir para", "autoDetect": "Detecção automática", "enableFullAccess": "Ativar Acesso total", "fullAccessInfo": "Traduzir, Responder e Refinar precisam de Acesso total. Ative:\nAjustes → Geral → Teclado → Teclados → TransKey → Permitir acesso total", "guideTitle": "Como usar o teclado de tradução", "guideClipboard": "Copie a mensagem deles e toque para ver no seu idioma.", "guideReply": "Digite sua resposta e toque para traduzi-la antes de enviar.", "guideRefine": "Aprimore seu texto para que fique natural.", "gotIt": "Entendi", "copy": "Copiar", "copied": "Copiado", "scamHigh": "Aviso: esta mensagem mostra sinais de golpe", "scamLow": "Cuidado: esta mensagem pode ser um golpe", "scamHint": "Tenha cuidado antes de responder, clicar em links ou enviar dinheiro."],
        "ru": ["translate": "Перевести", "reply": "Ответить", "refine": "Улучшить", "undo": "Отменить", "processing": "Обработка…", "translation": "Перевод", "close": "Закрыть", "typingLanguage": "Язык ввода", "translationLanguage": "Язык перевода", "done": "Готово", "swap": "⇄ Поменять", "chooseTypingLanguage": "Выберите язык для ввода", "sourceLanguage": "Исходный язык", "translateTo": "Перевести на", "autoDetect": "Автоопределение", "enableFullAccess": "Включить полный доступ", "fullAccessInfo": "Перевод, Ответ и Улучшение требуют полного доступа. Включите:\nНастройки → Основные → Клавиатура → Клавиатуры → TransKey → Разрешить полный доступ", "guideTitle": "Как пользоваться клавиатурой перевода", "guideClipboard": "Скопируйте их сообщение и нажмите, чтобы прочитать на своём языке.", "guideReply": "Введите ответ и нажмите, чтобы перевести его перед отправкой.", "guideRefine": "Отшлифуйте текст, чтобы он читался естественно.", "gotIt": "Понятно", "copy": "Копировать", "copied": "Скопировано", "scamHigh": "Предупреждение: это сообщение похоже на мошенничество", "scamLow": "Осторожно: это сообщение может быть мошенничеством", "scamHint": "Будьте осторожны, прежде чем отвечать, переходить по ссылкам или отправлять деньги."],
        "th": ["translate": "แปล", "reply": "ตอบกลับ", "refine": "ขัดเกลา", "undo": "เลิกทำ", "processing": "กำลังประมวลผล…", "translation": "คำแปล", "close": "ปิด", "typingLanguage": "ภาษาที่พิมพ์", "translationLanguage": "ภาษาที่แปล", "done": "เสร็จ", "swap": "⇄ สลับ", "chooseTypingLanguage": "เลือกภาษาที่ต้องการพิมพ์", "sourceLanguage": "ภาษาต้นทาง", "translateTo": "แปลเป็น", "autoDetect": "ตรวจจับอัตโนมัติ", "enableFullAccess": "เปิดการเข้าถึงแบบเต็ม", "fullAccessInfo": "แปล ตอบกลับ และขัดเกลา ต้องใช้การเข้าถึงแบบเต็ม เปิดได้ที่:\nการตั้งค่า → ทั่วไป → แป้นพิมพ์ → แป้นพิมพ์ → TransKey → อนุญาตการเข้าถึงแบบเต็ม", "guideTitle": "วิธีใช้แป้นพิมพ์แปลภาษา", "guideClipboard": "คัดลอกข้อความของอีกฝ่าย แล้วแตะเพื่ออ่านเป็นภาษาของคุณ", "guideReply": "พิมพ์ข้อความตอบกลับ แล้วแตะเพื่อแปลก่อนส่ง", "guideRefine": "ปรับข้อความให้อ่านลื่นและเป็นธรรมชาติ", "gotIt": "เข้าใจแล้ว", "copy": "คัดลอก", "copied": "คัดลอกแล้ว", "scamHigh": "คำเตือน: ข้อความนี้มีสัญญาณของการหลอกลวง", "scamLow": "โปรดระวัง: ข้อความนี้อาจเป็นการหลอกลวง", "scamHint": "โปรดระมัดระวังก่อนตอบกลับ คลิกลิงก์ หรือโอนเงิน"],
        "zh": ["translate": "翻译", "reply": "回复", "refine": "润色", "undo": "撤销", "processing": "处理中…", "translation": "翻译", "close": "关闭", "typingLanguage": "输入语言", "translationLanguage": "翻译语言", "done": "完成", "swap": "⇄ 互换", "chooseTypingLanguage": "选择要输入的语言", "sourceLanguage": "源语言", "translateTo": "翻译为", "autoDetect": "自动检测", "enableFullAccess": "允许完全访问", "fullAccessInfo": "翻译、回复和润色需要完全访问。开启方式:\n设置 → 通用 → 键盘 → 键盘 → TransKey → 允许完全访问", "guideTitle": "翻译键盘使用方法", "guideClipboard": "复制对方的消息，点按即可用你的语言查看。", "guideReply": "输入你的回复，点按即可在发送前翻译。", "guideRefine": "润色你的文字，让它读起来更自然。", "gotIt": "知道了", "copy": "复制", "copied": "已复制", "scamHigh": "警告：这条消息有诈骗迹象", "scamLow": "注意：这条消息可能是诈骗", "scamHint": "在回复、点击链接或转账前请务必小心。"],
    ]
}

// MARK: - Japanese 12-key flick keyboard

/// Shared colors so the flick grid matches the QWERTY keyboard in light/dark.
private enum FlickPalette {
    static let background = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1.0)
            : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1.0)
    }
    static let keyFill = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.42, blue: 0.43, alpha: 1.0)
            : UIColor.white
    }
    static let specialFill = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.27, green: 0.27, blue: 0.29, alpha: 1.0)
            : UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1.0)
    }
    static let primary = UIColor(red: 0.42, green: 0.39, blue: 1.0, alpha: 1.0)
}

/// The self-contained Japanese 12-key flick grid (フリック入力). Mirrors the
/// Android keyboard_japanese_flick layout: a 5x4 grid where the centre three
/// columns are the ten kana flick keys + the dakuten modifier + the punctuation
/// flick key, flanked by function columns. Every kana produced is fed back into
/// the SAME composing buffer the romaji path uses (via the onKana callback), so
/// henkan / candidates / backspace all reuse the existing engine unchanged.
final class FlickInputView: UIView {

    // Callbacks into the controller (all on the main thread).
    var onKana: ((String) -> Void)?
    var onSymbol: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onSpace: (() -> Void)?
    var onReturn: (() -> Void)?
    var onDakuten: (() -> Void)?
    var onSwitchToRomaji: (() -> Void)?
    var onEmoji: (() -> Void)?
    var onTapSound: (() -> Void)?

    /// Show the next-keyboard globe (only when the system offers a switch).
    var showsGlobe = false { didSet { globeButton.isHidden = !showsGlobe; setNeedsLayout() } }

    /// Katakana output mode (the カナ key). Keys keep their hiragana grouping;
    /// only the emitted/displayed character is mapped to katakana.
    private var katakana = false

    let globeButton = UIButton(type: .system)
    private let katakanaButton = UIButton(type: .system)
    private let abcButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    private let dakutenButton = UIButton(type: .system)
    private let backspaceButton = UIButton(type: .system)
    private let spaceButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)

    /// (kana flick key, column 0-4, row 0-3).
    private var kanaKeys: [(view: FlickKeyView, col: Int, row: Int)] = []

    // Flick options in direction order [centre, left, up, right, down].
    private static let kanaRows: [(String, Int, Int, [String], Bool)] = [
        ("あ", 1, 0, ["あ", "い", "う", "え", "お"], false),
        ("か", 2, 0, ["か", "き", "く", "け", "こ"], false),
        ("さ", 3, 0, ["さ", "し", "す", "せ", "そ"], false),
        ("た", 1, 1, ["た", "ち", "つ", "て", "と"], false),
        ("な", 2, 1, ["な", "に", "ぬ", "ね", "の"], false),
        ("は", 3, 1, ["は", "ひ", "ふ", "へ", "ほ"], false),
        ("ま", 1, 2, ["ま", "み", "む", "め", "も"], false),
        ("や", 2, 2, ["や", "「", "ゆ", "」", "よ"], false),
        ("ら", 3, 2, ["ら", "り", "る", "れ", "ろ"], false),
        ("わ", 2, 3, ["わ", "を", "ん", "ー", "〜"], false),
        ("、", 3, 3, ["、", "。", "？", "！", "…"], true),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        buildKeys()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildKeys() {
        for spec in Self.kanaRows {
            let key = FlickKeyView(options: spec.3, isPunct: spec.4)
            key.displayTransform = { [weak self] in self?.display($0) ?? $0 }
            key.onTouchDown = { [weak self] in self?.onTapSound?() }
            key.onEmit = { [weak self] raw, isPunct in
                guard let self else { return }
                if isPunct {
                    self.onSymbol?(raw)
                } else {
                    self.onKana?(self.display(raw))
                }
            }
            addSubview(key)
            kanaKeys.append((key, spec.1, spec.2))
        }

        configureFn(katakanaButton, title: "カナ", action: #selector(katakanaTapped))
        configureFn(abcButton, title: "ABC", action: #selector(abcTapped))
        configureFn(emojiButton, title: "☺", action: #selector(emojiTapped))
        emojiButton.titleLabel?.font = .systemFont(ofSize: 22)
        configureFn(dakutenButton, title: "小゛゜", action: #selector(dakutenTapped))
        configureFn(spaceButton, title: "空白", action: #selector(spaceTapped))
        configureFn(returnButton, title: "改行", action: #selector(returnTapped))

        backspaceButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        backspaceButton.tintColor = .label
        styleFnButton(backspaceButton)
        backspaceButton.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        addSubview(backspaceButton)

        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.tintColor = .label
        styleFnButton(globeButton)
        globeButton.isHidden = true
        addSubview(globeButton)
    }

    private func configureFn(_ btn: UIButton, title: String, action: Selector) {
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.label, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16)
        btn.titleLabel?.adjustsFontSizeToFitWidth = true
        btn.titleLabel?.minimumScaleFactor = 0.7
        styleFnButton(btn)
        btn.addTarget(self, action: action, for: .touchUpInside)
        addSubview(btn)
    }

    private func styleFnButton(_ btn: UIButton) {
        btn.backgroundColor = FlickPalette.specialFill
        btn.layer.cornerRadius = 5
    }

    // MARK: Katakana mapping

    /// Map a hiragana string to katakana when katakana mode is on; punctuation
    /// and the long-vowel mark are left untouched (they share both scripts).
    private func display(_ s: String) -> String {
        guard katakana else { return s }
        var out = ""
        for sc in s.unicodeScalars {
            if sc.value >= 0x3041, sc.value <= 0x3096, let k = UnicodeScalar(sc.value + 0x60) {
                out.unicodeScalars.append(k)
            } else {
                out.unicodeScalars.append(sc)
            }
        }
        return out
    }

    // MARK: Actions

    @objc private func katakanaTapped() {
        onTapSound?()
        katakana.toggle()
        katakanaButton.setTitle(katakana ? "かな" : "カナ", for: .normal)
        // Repaint every key's centre label + any open preview in the new script.
        kanaKeys.forEach { $0.view.refreshLabel() }
    }

    @objc private func abcTapped() { onTapSound?(); onSwitchToRomaji?() }
    @objc private func emojiTapped() { onTapSound?(); onEmoji?() }
    @objc private func dakutenTapped() { onTapSound?(); onDakuten?() }
    @objc private func backspaceTapped() { onTapSound?(); onBackspace?() }
    @objc private func spaceTapped() { onTapSound?(); onSpace?() }
    @objc private func returnTapped() { onTapSound?(); onReturn?() }

    // MARK: Layout (5 columns x 4 rows; return + globe span two rows)

    override func layoutSubviews() {
        super.layoutSubviews()
        let cols: CGFloat = 5, rows: CGFloat = 4
        let gap: CGFloat = 3
        let cw = bounds.width / cols
        let ch = bounds.height / rows

        func cell(_ col: Int, _ row: Int, rowSpan: Int = 1) -> CGRect {
            CGRect(x: CGFloat(col) * cw + gap,
                   y: CGFloat(row) * ch + gap,
                   width: cw - gap * 2,
                   height: ch * CGFloat(rowSpan) - gap * 2)
        }

        for entry in kanaKeys {
            entry.view.frame = cell(entry.col, entry.row)
        }
        dakutenButton.frame = cell(1, 3)

        katakanaButton.frame = cell(0, 0)
        abcButton.frame = cell(0, 1)
        emojiButton.frame = cell(0, 2)
        // The globe (when shown) takes the lower-left cell; otherwise that
        // space is left empty (the ABC key already covers the latin switch).
        globeButton.frame = cell(0, 3)

        backspaceButton.frame = cell(4, 0)
        spaceButton.frame = cell(4, 1)
        returnButton.frame = cell(4, 2, rowSpan: 2)
    }
}

/// One kana flick key: a centre label plus a five-way flick. Touch-down shows a
/// cross preview of the five options; the finger's offset on lift picks one
/// (dead-zone in the middle = the centre kana). Raw options are hiragana; the
/// owning view's displayTransform renders/emits katakana when that mode is on.
final class FlickKeyView: UIView {

    private let options: [String]          // [centre, left, up, right, down]
    private let isPunct: Bool
    var displayTransform: (String) -> String = { $0 }
    var onEmit: ((_ raw: String, _ isPunct: Bool) -> Void)?
    var onTouchDown: (() -> Void)?

    private let label = UILabel()
    private var startPoint: CGPoint = .zero
    private var currentDir = 0
    private var popup: FlickPreviewPopup?

    init(options: [String], isPunct: Bool) {
        self.options = options
        self.isPunct = isPunct
        super.init(frame: .zero)
        backgroundColor = FlickPalette.keyFill
        layer.cornerRadius = 5
        isMultipleTouchEnabled = false
        label.text = options[0]
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 24)
        label.textColor = .label
        label.frame = bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Re-render the centre label (after a katakana toggle).
    func refreshLabel() {
        label.text = displayTransform(options[0])
    }

    // MARK: Flick gesture

    private func direction(for p: CGPoint) -> Int {
        let dx = p.x - startPoint.x
        let dy = p.y - startPoint.y
        if hypot(dx, dy) < 18 { return 0 }          // dead-zone -> centre
        if abs(dx) >= abs(dy) { return dx < 0 ? 1 : 3 }
        return dy < 0 ? 2 : 4
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        startPoint = t.location(in: self)
        currentDir = 0
        backgroundColor = FlickPalette.specialFill
        onTouchDown?()
        showPopup()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let dir = direction(for: t.location(in: self))
        if dir != currentDir {
            currentDir = dir
            popup?.highlight(dir)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let dir = touches.first.map { direction(for: $0.location(in: self)) } ?? currentDir
        finish(emit: options[dir])
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(emit: nil)
    }

    private func finish(emit raw: String?) {
        backgroundColor = FlickPalette.keyFill
        popup?.removeFromSuperview()
        popup = nil
        if let raw { onEmit?(raw, isPunct) }
    }

    private func showPopup() {
        popup?.removeFromSuperview()
        let labels = options.map { displayTransform($0) }
        let pop = FlickPreviewPopup(options: labels)
        // Centre the cross over this key, clamped inside the grid so it never
        // runs off the side. It may extend above the grid (UIView doesn't clip)
        // which is fine - it overlaps the suggestion bar like the key preview.
        guard let host = superview else { return }
        var origin = CGPoint(x: frame.midX - pop.bounds.width / 2,
                             y: frame.midY - pop.bounds.height / 2)
        origin.x = max(2, min(origin.x, host.bounds.width - pop.bounds.width - 2))
        pop.frame = CGRect(origin: origin, size: pop.bounds.size)
        pop.highlight(0)
        host.addSubview(pop)
        host.bringSubviewToFront(pop)
        popup = pop
    }
}

/// The five-cell cross shown while a flick key is held; highlights the cell the
/// finger is currently pointing at.
final class FlickPreviewPopup: UIView {

    private var cells: [UIView] = []       // index 0-4 = centre,left,up,right,down
    private let cellSize: CGFloat = 46

    init(options: [String]) {
        super.init(frame: CGRect(x: 0, y: 0, width: 46 * 3, height: 46 * 3))
        backgroundColor = .clear
        // (col, row) for centre,left,up,right,down in a 3x3 grid.
        let pos: [(CGFloat, CGFloat)] = [(1, 1), (0, 1), (1, 0), (2, 1), (1, 2)]
        for (i, opt) in options.enumerated() {
            let c = UIView(frame: CGRect(x: pos[i].0 * cellSize, y: pos[i].1 * cellSize,
                                         width: cellSize, height: cellSize))
            c.backgroundColor = FlickPalette.specialFill
            c.layer.cornerRadius = 6
            c.layer.shadowColor = UIColor.black.cgColor
            c.layer.shadowOpacity = 0.25
            c.layer.shadowOffset = CGSize(width: 0, height: 1)
            c.layer.shadowRadius = 3
            let l = UILabel(frame: c.bounds)
            l.text = opt
            l.textAlignment = .center
            l.font = .systemFont(ofSize: 24)
            l.textColor = .label
            c.addSubview(l)
            addSubview(c)
            cells.append(c)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func highlight(_ dir: Int) {
        for (i, c) in cells.enumerated() {
            c.backgroundColor = i == dir ? FlickPalette.primary : FlickPalette.specialFill
            (c.subviews.first as? UILabel)?.textColor = i == dir ? .white : .label
        }
    }
}

// MARK: - Emoji picker (flick keyboard)

/// A self-contained emoji grid shown over the flick keyboard (the ☺ key).
/// iOS does not let a third-party keyboard open the system emoji keyboard, so
/// this is our own picker: a scrollable grid plus a bottom bar with the
/// category selector, an あ key (back to kana) and a backspace. "Recently used"
/// is the first category, persisted in the App Group. Curated emoji sets keep
/// every glyph valid (no tofu) on the shipped iOS range.
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    var onPick: ((String) -> Void)?
    var onBack: (() -> Void)?
    var onBackspace: (() -> Void)?
    var onTapSound: (() -> Void)?

    private let collection: UICollectionView
    private let bottomBar = UIView()
    private let backButton = UIButton(type: .system)
    private let backspaceButton = UIButton(type: .system)
    private let catScroll = UIScrollView()
    private let catStack = UIStackView()
    private var catButtons: [UIButton] = []

    /// (tab icon, emoji list). Recents is prepended when non-empty.
    private var sections: [(icon: String, emojis: [String])] = []
    private var currentIndex = 0

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 2
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        backgroundColor = FlickPalette.background
        buildSections()
        setupCollection()
        setupBottomBar()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildSections() {
        var s: [(String, [String])] = []
        let recents = AppGroupStore.shared.emojiRecents
        if !recents.isEmpty { s.append(("🕘", recents)) }
        for c in Self.categories { s.append((c.icon, c.emojis)) }
        sections = s
        if currentIndex >= sections.count { currentIndex = 0 }
    }

    private func setupCollection() {
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "emoji")
        collection.alwaysBounceVertical = true
        collection.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collection)
    }

    private func setupBottomBar() {
        bottomBar.backgroundColor = .clear
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBar)

        backButton.setTitle("あ", for: .normal)
        backButton.setTitleColor(.label, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 17)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(backButton)

        backspaceButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        backspaceButton.tintColor = .label
        backspaceButton.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        backspaceButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(backspaceButton)

        catScroll.showsHorizontalScrollIndicator = false
        catScroll.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(catScroll)

        catStack.axis = .horizontal
        catStack.distribution = .fill
        catStack.translatesAutoresizingMaskIntoConstraints = false
        catScroll.addSubview(catStack)
        for (i, sec) in sections.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(sec.icon, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 18)
            b.widthAnchor.constraint(equalToConstant: 38).isActive = true
            b.tag = i
            b.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
            catStack.addArrangedSubview(b)
            catButtons.append(b)
        }

        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: topAnchor),
            collection.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            collection.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            collection.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 44),

            backButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 46),
            backButton.heightAnchor.constraint(equalTo: bottomBar.heightAnchor),

            backspaceButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            backspaceButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            backspaceButton.widthAnchor.constraint(equalToConstant: 46),
            backspaceButton.heightAnchor.constraint(equalTo: bottomBar.heightAnchor),

            catScroll.leadingAnchor.constraint(equalTo: backButton.trailingAnchor),
            catScroll.trailingAnchor.constraint(equalTo: backspaceButton.leadingAnchor),
            catScroll.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            catScroll.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor),

            catStack.topAnchor.constraint(equalTo: catScroll.topAnchor),
            catStack.bottomAnchor.constraint(equalTo: catScroll.bottomAnchor),
            catStack.leadingAnchor.constraint(equalTo: catScroll.leadingAnchor),
            catStack.trailingAnchor.constraint(equalTo: catScroll.trailingAnchor),
            catStack.heightAnchor.constraint(equalTo: catScroll.heightAnchor),
        ])
        highlightCategory()
    }

    private func highlightCategory() {
        for (i, b) in catButtons.enumerated() {
            b.backgroundColor = i == currentIndex ? FlickPalette.keyFill : .clear
            b.layer.cornerRadius = 6
        }
    }

    // MARK: Actions

    @objc private func backTapped() { onTapSound?(); onBack?() }
    @objc private func backspaceTapped() { onTapSound?(); onBackspace?() }

    @objc private func categoryTapped(_ sender: UIButton) {
        onTapSound?()
        currentIndex = sender.tag
        highlightCategory()
        collection.reloadData()
        if collection.numberOfItems(inSection: 0) > 0 {
            collection.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: false)
        }
    }

    // MARK: Collection

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections.indices.contains(currentIndex) ? sections[currentIndex].emojis.count : 0
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath)
        let tag = 77
        let label: UILabel
        if let l = cell.contentView.viewWithTag(tag) as? UILabel {
            label = l
        } else {
            label = UILabel(frame: cell.contentView.bounds)
            label.tag = tag
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 30)
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            cell.contentView.addSubview(label)
        }
        label.text = sections[currentIndex].emojis[indexPath.item]
        return cell
    }

    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let cols: CGFloat = 8
        let w = floor(cv.bounds.width / cols)
        return CGSize(width: w, height: w)
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onTapSound?()
        onPick?(sections[currentIndex].emojis[indexPath.item])
    }

    // MARK: Curated emoji sets (valid on the shipped iOS range)

    static let categories: [(icon: String, emojis: [String])] = [
        ("😀", ["😀","😃","😄","😁","😆","😅","😂","🤣","🥲","😊","😇","🙂","🙃","😉","😌","😍","🥰","😘","😗","😙","😚","😋","😛","😝","😜","🤪","🤨","🧐","🤓","😎","🥸","🤩","🥳","😏","😒","😞","😔","😟","😕","🙁","☹️","😣","😖","😫","😩","🥺","😢","😭","😤","😠","😡","🤬","🤯","😳","🥵","🥶","😱","😨","😰","😥","😓","🤗","🤔","🤭","🤫","🤥","😶","😐","😑","😬","🙄","😯","😦","😧","😮","😲","🥱","😴","🤤","😪","😵","🤐","🥴","🤢","🤮","🤧","😷","🤒","🤕","🤑","🤠","😈","👿","👹","👺","🤡","💩","👻","💀","👽","👾","🤖","🎃","😺","😸","😹","😻","😼","😽","🙀","😿","😾","👋","🤚","🖐","✋","🖖","👌","🤌","🤏","✌️","🤞","🤟","🤘","🤙","👈","👉","👆","👇","☝️","👍","👎","✊","👊","🤛","🤜","👏","🙌","👐","🤲","🙏","💪","👀","👁️","👅","👄","💋","🧠","🫀","🦷","👶","🧒","👦","👧","🧑","👨","👩","🧓","👴","👵","🙆","🙅","💁","🙋","🙇","🤦","🤷"]),
        ("🐻", ["🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐯","🦁","🐮","🐷","🐽","🐸","🐵","🙈","🙉","🙊","🐔","🐧","🐦","🐤","🐣","🐥","🦆","🦅","🦉","🦇","🐺","🐗","🐴","🦄","🐝","🐛","🦋","🐌","🐞","🐜","🦗","🕷️","🦂","🐢","🐍","🦎","🦖","🦕","🐙","🦑","🦐","🦞","🦀","🐡","🐠","🐟","🐬","🐳","🐋","🦈","🐊","🐅","🐆","🦓","🦍","🦧","🐘","🦛","🦏","🐪","🐫","🦒","🦘","🐃","🐂","🐄","🐎","🐖","🐏","🐑","🦙","🐐","🦌","🐕","🐩","🦮","🐈","🐓","🦃","🦚","🦜","🦢","🦩","🕊️","🐇","🦝","🦨","🦦","🦥","🐁","🐀","🐿️","🦔","🐉","🐲","🌵","🎄","🌲","🌳","🌴","🌱","🌿","☘️","🍀","🎍","🍃","🍂","🍁","🌾","🌺","🌸","🌼","🌻","🌷","🌹","🥀","🌽","🍄","🐚","🌊","💧","🔥","🌈","⭐️","🌟","✨","⚡️","☀️","🌤️","⛅️","☁️","🌧️","⛈️","❄️","☃️","⛄️","💨","🌪️","🌫️","🌙","🌝","🌚","🌕","🌑","🪐","🌎","🌍","🌏"]),
        ("🍎", ["🍏","🍎","🍐","🍊","🍋","🍌","🍉","🍇","🍓","🫐","🍈","🍒","🍑","🥭","🍍","🥥","🥝","🍅","🍆","🥑","🥦","🥬","🥒","🌶️","🫑","🌽","🥕","🧄","🧅","🥔","🍠","🥐","🥯","🍞","🥖","🥨","🧀","🥚","🍳","🧈","🥞","🧇","🥓","🥩","🍗","🍖","🌭","🍔","🍟","🍕","🥪","🥙","🧆","🌮","🌯","🥗","🥘","🍝","🍜","🍲","🍛","🍣","🍱","🥟","🍤","🍙","🍚","🍘","🍥","🥮","🍢","🍡","🍧","🍨","🍦","🥧","🧁","🍰","🎂","🍮","🍭","🍬","🍫","🍿","🍩","🍪","🌰","🥜","🍯","🥛","🍼","☕️","🍵","🧃","🥤","🧋","🍶","🍺","🍻","🥂","🍷","🥃","🍸","🍹","🧉","🍾","🥄","🍴","🍽️","🥣","🥡","🥢","🧂"]),
        ("⚽️", ["⚽️","🏀","🏈","⚾️","🥎","🎾","🏐","🏉","🥏","🎱","🪀","🏓","🏸","🏒","🏑","🥍","🏏","🥅","⛳️","🪁","🏹","🎣","🤿","🥊","🥋","🎽","🛹","🛼","🛷","⛸️","🥌","🎿","⛷️","🏂","🪂","🏋️","🤼","🤸","⛹️","🤺","🤾","🏌️","🏇","🧘","🏄","🏊","🤽","🚣","🧗","🚵","🚴","🏆","🥇","🥈","🥉","🏅","🎖️","🏵️","🎗️","🎫","🎟️","🎪","🤹","🎭","🩰","🎨","🎬","🎤","🎧","🎼","🎹","🥁","🪘","🎷","🎺","🪗","🎸","🪕","🎻","🎲","♟️","🎯","🎳","🎮","🎰","🧩"]),
        ("🚗", ["🚗","🚕","🚙","🚌","🚎","🏎️","🚓","🚑","🚒","🚐","🛻","🚚","🚛","🚜","🦯","🦽","🦼","🛴","🚲","🛵","🏍️","🛺","🚨","🚔","🚍","🚘","🚖","🚡","🚠","🚟","🚃","🚋","🚝","🚄","🚅","🚈","🚂","🚆","🚇","🚊","🚉","✈️","🛫","🛬","🛩️","💺","🛰️","🚀","🛸","🚁","🛶","⛵️","🚤","🛥️","🛳️","⛴️","🚢","⚓️","⛽️","🚧","🚦","🚥","🗺️","🗿","🗽","🗼","🏰","🏯","🏟️","🎡","🎢","🎠","⛲️","⛱️","🏖️","🏝️","🏜️","🌋","⛰️","🏔️","🗻","🏕️","⛺️","🏠","🏡","🏘️","🏚️","🏗️","🏢","🏬","🏣","🏤","🏥","🏦","🏨","🏪","🏫","🏩","💒","🏛️","⛪️","🕌","🕍","🛕","🕋","⛩️","🛤️","🌁","🌃","🏙️","🌄","🌅","🌆","🌇","🌉","🎑","🌌"]),
        ("💡", ["⌚️","📱","📲","💻","⌨️","🖥️","🖨️","🖱️","🕹️","💽","💾","💿","📀","📼","📷","📸","📹","🎥","📞","☎️","📟","📠","📺","📻","🎙️","⏱️","⏲️","⏰","🕰️","⌛️","⏳","📡","🔋","🔌","💡","🔦","🕯️","🧯","🛢️","💸","💵","💴","💶","💷","💰","💳","💎","⚖️","🧰","🔧","🔨","⚒️","🛠️","⛏️","🔩","⚙️","🧱","⛓️","🧲","🔫","💣","🧨","🔪","🗡️","⚔️","🛡️","🚬","⚰️","⚱️","🏺","🔮","📿","🧿","💈","⚗️","🔭","🔬","🕳️","💊","💉","🩸","🧬","🦠","🧫","🧪","🌡️","🧹","🧺","🧻","🚽","🚰","🚿","🛁","🛀","🧼","🪒","🧽","🧴","🛎️","🔑","🗝️","🚪","🛋️","🛏️","🛌","🧸","🖼️","🛍️","🛒","🎁","🎈","🎏","🎀","🎊","🎉","🧧","✉️","📩","📨","📧","💌","📦","📫","📮","📝","✏️","📚","📖","🔖","🔗","📎","📐","📏","📌","📍","✂️","🖊️","🖌️","🔍","🔎","🔒","🔓","🔑"]),
        ("❤️", ["❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔","❣️","💕","💞","💓","💗","💖","💘","💝","💟","☮️","✝️","☪️","🕉️","☸️","✡️","🔯","🕎","☯️","☦️","🛐","⛎","♈️","♉️","♊️","♋️","♌️","♍️","♎️","♏️","♐️","♑️","♒️","♓️","🆔","⚛️","🉑","☢️","☣️","📴","📳","🈶","🈚️","🈸","🈺","🈷️","✴️","🆚","💮","🉐","㊙️","㊗️","🈴","🈵","🈹","🈲","🅰️","🅱️","🆎","🆑","🅾️","🆘","❌","⭕️","🛑","⛔️","📛","🚫","💯","💢","♨️","🚷","🚯","🚳","🚱","🔞","📵","🚭","❗️","❓","❕","❔","‼️","⁉️","🔅","🔆","〽️","⚠️","🚸","🔱","⚜️","🔰","♻️","✅","🈯️","💹","❇️","✳️","❎","🌐","💠","Ⓜ️","🌀","💤","🏧","🚾","♿️","🅿️","🈳","🈂️","🛂","🛃","🛄","🛅","🚹","🚺","🚼","🚻","🚮","🎦","📶","🈁","🔣","ℹ️","🔤","🔡","🔠","🆖","🆗","🆙","🆒","🆕","🆓","🔟","🔢","▶️","⏸️","⏯️","⏹️","⏺️","⏭️","⏮️","⏩️","⏪️","🔼","🔽","➡️","⬅️","⬆️","⬇️","↗️","↘️","↙️","↖️","↕️","↔️","↪️","↩️","🔀","🔁","🔂","🔄","🎵","🎶","➕","➖","➗","✖️","♾️","💲","💱","™️","©️","®️","✔️","☑️","🔘","🔴","🟠","🟡","🟢","🔵","🟣","⚫️","⚪️","🟤","🔺","🔻","🔸","🔹","🔶","🔷","🔳","🔲","⬛️","⬜️","🟥","🟧","🟨","🟩","🟦","🟪","🟫","🔔","🔕"]),
        ("🚩", ["🏳️","🏴","🏁","🚩","🏳️‍🌈","🏴‍☠️","🇯🇵","🇻🇳","🇺🇸","🇬🇧","🇰🇷","🇨🇳","🇫🇷","🇩🇪","🇪🇸","🇮🇹","🇷🇺","🇧🇷","🇮🇩","🇹🇭","🇮🇳","🇨🇦","🇦🇺","🇸🇬","🇲🇾","🇵🇭","🇳🇱","🇸🇪","🇨🇭","🇹🇷","🇸🇦","🇦🇪","🇭🇰","🇹🇼","🇲🇽","🇦🇷","🇵🇹","🇵🇱","🇺🇦","🇳🇿"]),
    ]
}
