package app.transkey.mobile

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.inputmethodservice.InputMethodService
import android.inputmethodservice.Keyboard
import android.inputmethodservice.KeyboardView
import android.text.InputType
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Toast

/**
 * TransKey system Input Method Editor. Phase 1+2 MVP:
 * - Single QWERTY layout (loaded from xml/keyboard_qwerty.xml)
 * - English mode: chars are committed directly to the InputConnection
 * - Vietnamese Telex mode: chars route through [TelexProcessor] which
 *   maintains a composing region the user sees update in-place
 * - Language is toggled by the dedicated language key (keycode -101)
 *
 * Not yet implemented (deferred to next phases):
 * - Symbols/numbers layer
 * - Suggestion bar
 * - Translation integration (a "translate" key that sends the buffer to
 *   the backend and replaces it with the translation)
 * - Settings to choose default subtype, haptic feedback, theme
 *
 * Why the deprecated KeyboardView API: it gets the MVP shipping in one
 * file with zero custom view code. The Jetpack Compose / custom-view
 * rewrite is the right long-term direction but blocks the MVP on a
 * design + testing cycle that isn't on the critical path.
 */
class TransKeyIME : InputMethodService(), KeyboardView.OnKeyboardActionListener {

    private var keyboardView: KeyboardView? = null
    private var qwertyKeyboard: Keyboard? = null
    private var symbolsKeyboard: Keyboard? = null
    private var symbols2Keyboard: Keyboard? = null
    private val telex = TelexProcessor()
    private val hangul = HangulComposer()
    private val romaji = RomajiKanaConverter()
    private val chunjiin = ChunjiinComposer()
    private val kana = KanaComposer()
    private val kanjiConv by lazy { KanaKanjiConverter(this) }
    private val pinyinConv by lazy { PinyinHanziConverter(this) }
    // Japanese kana->kanji conversion (henkan) session: space starts/cycles
    // candidates, enter/tap/next-key commits the highlighted one.
    private var jaConverting = false
    private var jaCandidates: List<String> = emptyList()
    private var jaCandIdx = 0
    private var jaReading = ""
    // Chinese pinyin input: latin pinyin buffer with LIVE hanzi candidates;
    // space/tap commits a candidate, enter commits the raw pinyin.
    private val pinyin = StringBuilder()
    private var zhCandidates: List<String> = emptyList()
    private enum class Layer { LETTERS, SYMBOLS, SYMBOLS2 }
    private var layer: Layer = Layer.LETTERS

    // Input languages; switch via the globe key (short tap cycles the enabled
    // set, long-press opens the picker). Each maps to a letters layout and an
    // input behavior (Latin direct, VI Telex, Cyrillic direct; CJK/RTL added in
    // later phases). The explicit choice persists in prefs ("typing_mode").
    private enum class Mode { EN, VI, RU, RU_PHON, AR, TH, KO, KO_CHUN, JA, JA_FLICK, ZH }
    private var mode: Mode = Mode.EN
    // Letters keyboard per language, built lazily + centered like qwerty. EN/VI
    // share the Latin qwerty; the others have their own layouts.
    private val letterKeyboards = HashMap<Mode, Keyboard>()
    // Thai Kedmanee has two layers (base + shift) instead of upper/lowercase;
    // the Shift key swaps between them. Cached by the shift flag.
    private val thaiKeyboards = HashMap<Boolean, Keyboard>()
    private var thaiShift = false

    // Voice input. Reuses the bubble's VoiceRecognitionHelper so dictation
    // behaves identically (live partials, generous silence thresholds, glossary
    // biasing, online preference). Partials stream into the field as composing
    // text; the final result is committed. Null until the first tap.
    private var voiceHelper: VoiceRecognitionHelper? = null
    private var isListening: Boolean = false

    // Shift, Gboard-style 3-state: NONE (lowercase) -> ONESHOT (next letter
    // capitalised, then auto-revert) -> LOCK (caps lock) -> NONE.
    private enum class Shift { NONE, ONESHOT, LOCK }
    private var shift: Shift = Shift.NONE
    private val isShifted: Boolean get() = shift != Shift.NONE

    // Vietnamese auto-correction + suggestions (loaded once; VI mode only).
    private val corrector by lazy { VietWordCorrector(this) }
    private var suggestionStrip: SuggestionStripView? = null

    // Auto-correct (dictionary spelling-fix + split merged words) is OFF by
    // default - like Gboard, we don't silently change what the user wrote.
    // Stored as a pref so a settings switch can turn it on; English passthrough
    // and the suggestion chip work regardless.
    private val prefs by lazy { getSharedPreferences("transkey_ime", MODE_PRIVATE) }
    private val autocorrectEnabled: Boolean get() = prefs.getBoolean("autocorrect", false)

    // Literal keystrokes of the current word (before Telex transforms). Offered
    // as a suggestion so English words can be typed in VI mode ("telex").
    private val rawWord = StringBuilder()

    // Suggestions are computed off the UI thread (scanning ~7k syllables per
    // keystroke would jank typing). A sequence number drops stale results.
    private val suggestExecutor by lazy { java.util.concurrent.Executors.newSingleThreadExecutor() }
    private val suggestSeq = java.util.concurrent.atomic.AtomicInteger(0)

    private var rootView: View? = null
    private var emojiPanel: EmojiPanelView? = null
    private var candidateGrid: CandidateGridView? = null

    // ── Feature buttons (Dịch / Trau chuốt) ──
    // When the strip is idle it shows these chips; tapping one sends the whole
    // field through the pre-warmed Flutter engine (same bridge the bubble uses)
    // and replaces the field with the result. Labels follow the app UI language.
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var localizedCtx: android.content.Context? = null
    private var lastUiLocale: String? = null
    // One request at a time; the in-flight id lets a field switch cancel it.
    private var actionInFlight = false
    private var currentActionReq = -1L
    // Undo: the field text captured just before a translate/refine/reply replace.
    // `pending` holds it while the request is in flight; on success it becomes
    // the active `undoSnapshot` (the strip shows the undo chip). Null = nothing
    // to undo (hidden). One-shot: undoing or editing the field clears it.
    private var pendingUndoText: String? = null
    private var undoSnapshot: String? = null
    // Language picker panel (source/target), shown in place of the keyboard.
    private var langPickerView: LanguagePickerView? = null
    // Keyboard settings panel, opened from the strip's grid icon.
    private var settingsView: KeyboardSettingsView? = null
    // Inline translation-history panel (opened from the settings shortcuts).
    private var historyPanelView: HistoryPanelView? = null
    // Voice-language picker (long-press the mic, or auto-prompted when source=Auto).
    private var voicePickerView: VoicePickerView? = null
    // Input-language picker (globe long-press). Reuses VoicePickerView's list UI.
    private var inputLangPickerView: VoicePickerView? = null
    private val hapticEnabled: Boolean get() = prefs.getBoolean("haptic", true)
    // Auto-capitalize the first letter of a field / sentence (Gboard default ON).
    private val autocapEnabled: Boolean get() = prefs.getBoolean("autocap", true)
    // Double-tap space -> ". " (period + space), Gboard default ON.
    private val dotDoubleSpaceEnabled: Boolean get() = prefs.getBoolean("dot_double_space", true)

    override fun onCreateInputView(): View {
        val root = layoutInflater.inflate(R.layout.transkey_ime_view, null)
        rootView = root
        val kv = root.findViewById<KeyboardView>(R.id.keyboard_view)

        // Initialize keyboards with Material You styling
        qwertyKeyboard = Keyboard(this, R.xml.keyboard_qwerty)
        symbolsKeyboard = Keyboard(this, R.xml.keyboard_symbols)
        symbols2Keyboard = Keyboard(this, R.xml.keyboard_symbols2)
        centerRows(qwertyKeyboard)
        centerRows(symbolsKeyboard)
        centerRows(symbols2Keyboard)

        // Apply language mode to keyboard
        val letterH = letterKeyboardFor(mode)?.height ?: 0
        val gkv = kv as? GboardKeyboardView
        kv.keyboard = when (layer) {
            Layer.SYMBOLS -> symbolsKeyboard.also { matchHeight(it, letterH); gkv?.refreshLayout(it) }
            Layer.SYMBOLS2 -> symbols2Keyboard.also { matchHeight(it, letterH); gkv?.refreshLayout(it) }
            else -> letterKeyboardFor(mode) ?: qwertyKeyboard
        }
        kv.setOnKeyboardActionListener(this)
        // Key-press preview popup is disabled: GboardKeyboardView owns drawing
        // and the AOSP preview shows an empty box on icon-only function keys.

        keyboardView = kv

        // Long-press hooks (Gboard-style): space toggles VI/EN, and the comma
        // key opens the emoji panel (its short tap still types a comma).
        (kv as? GboardKeyboardView)?.onLongPress = { code ->
            when (code) {
                KEYCODE_SPACE -> { cycleLanguage(); true }
                KEYCODE_LANG_GLOBE -> { openInputLangPicker(); true }
                ','.code -> { openEmoji(); true }
                else -> {
                    val n = numberForLongPress(code)
                    when {
                        // Chinese: while composing pinyin, the top row picks the
                        // matching numbered candidate (q=1..o=9, p=10) instead of
                        // typing the digit. The strip shows the same 1-based index.
                        isZh() && pinyin.isNotEmpty() && n != null -> {
                            val idx = (if (n == "0") 10 else n.toInt()) - 1
                            if (idx in zhCandidates.indices) {
                                commitTappedZh(zhCandidates[idx]); true
                            } else false
                        }
                        // Otherwise long-press the top letter row (q..p) types its
                        // corner number 1..0 (Gboard), committed directly - the
                        // hint is already drawn so no popup is needed.
                        n != null -> {
                            currentInputConnection?.let { ic ->
                                commitComposed(ic)
                                ic.commitText(n, 1)
                            }
                            true
                        }
                        else -> false
                    }
                }
            }
        }
        // Swipe left/right on the space bar to move the caret (Gboard gesture).
        (kv as? GboardKeyboardView)?.onCursorMove = { dir -> moveCursor(dir) }

        // Japanese flick: report which keys flick (for the preview) + the chosen
        // direction on lift. Only active in JA_FLICK mode (flickLabelsFor gates).
        (kv as? GboardKeyboardView)?.flickProvider = { code -> flickLabelsFor(code) }
        (kv as? GboardKeyboardView)?.onFlick = { code, dir -> handleFlick(code, dir) }

        // Suggestion strip: mic reuses voice input; tapping a suggestion
        // replaces the in-progress Vietnamese word with the chosen syllable.
        suggestionStrip = root.findViewById<SuggestionStripView>(R.id.suggestion_strip)?.apply {
            onMicTap = { startOrStopVoiceInput() }
            onMicLongPress = { openVoicePicker() }
            onSuggestionTap = { word ->
                when {
                    jaConverting -> commitTappedCandidate(word)
                    isZh() && pinyin.isNotEmpty() -> commitTappedZh(word)
                    else -> applySuggestion(word)
                }
            }
            onActionTap = { idx -> onActionButton(idx) }
            onLangTap = { openLangPicker() }
            onGridTap = { openSettings() }
            onUndoTap = { performUndo() }
            onExpandTap = { openCandidateGrid() }
        }
        refreshActionLabels()
        refreshLangPill()
        applyPremiumChrome() // set here too: onStartInput's first call runs before this view exists

        updateShiftIcon()
        updateSpaceBarLabel()
        updateLanguageKeyStyle()
        return root
    }

    /**
     * Center each row horizontally to match Gboard.
     *
     * The deprecated AOSP [Keyboard] left-aligns every row and dumps the
     * leftover width on the right edge, giving a ragged right margin (e.g.
     * left=11px / right=20px on row 1, 54/83 on the a-l row). Gboard centers
     * every row (left margin == right margin). Our per-row key spans already
     * match Gboard; only the alignment differs, so we shift each row's keys by
     * half its leftover width to center it.
     *
     * Touch detection stays correct: the proximity grid threshold is ~one key
     * width (~95px), far larger than the small per-row shift (<=15px), so the
     * shifted key remains in the nearest-key candidates for its new position.
     */
    private fun centerRows(keyboard: Keyboard?) {
        keyboard ?: return
        val screenW = resources.displayMetrics.widthPixels
        keyboard.keys
            .groupBy { it.y }
            .forEach { (_, rowKeys) ->
                val left = rowKeys.minOf { it.x }
                val right = rowKeys.maxOf { it.x + it.width }
                val shift = (screenW - (right - left)) / 2 - left
                if (shift != 0) rowKeys.forEach { it.x += shift }
            }
    }

    /**
     * Rescale [keyboard] vertically so its total height equals [targetH] px,
     * sharing the height evenly across its rows.
     *
     * Gboard keeps the keyboard the SAME height for every layer: a 4-row
     * symbols layer gets taller keys to fill a 5-row Thai letter layer's
     * height instead of shrinking. The deprecated AOSP [Keyboard] sizes itself
     * as rows*keyHeight, so without this the symbols layer would tower under
     * (be shorter than) the Thai letters and look cramped/pushed down. We
     * reposition every key's y/height and patch mTotalHeight so KeyboardView
     * measures to [targetH].
     */
    private fun matchHeight(keyboard: Keyboard?, targetH: Int) {
        keyboard ?: return
        if (targetH <= 0) return
        val rowsByY = keyboard.keys.groupBy { it.y }.toSortedMap()
        val n = rowsByY.size
        if (n == 0) return
        val vGap = (10 * resources.displayMetrics.density).toInt() // verticalGap 10dp
        val keyH = (targetH - vGap * (n - 1)) / n
        if (keyH <= 0) return
        var y = 0
        for ((_, rowKeys) in rowsByY) {
            for (k in rowKeys) { k.y = y; k.height = keyH }
            y += keyH + vGap
        }
        runCatching {
            val f = Keyboard::class.java.getDeclaredField("mTotalHeight")
            f.isAccessible = true
            f.setInt(keyboard, y - vGap)
        }
    }

    /**
     * Preferred typing mode: the user's last explicit globe-key choice
     * (persisted), or - before they ever toggle - the DEVICE language, so a
     * Vietnamese phone starts in VI Telex instead of always defaulting to EN.
     */
    private fun preferredMode(): Mode {
        prefs.getString("typing_mode", null)?.let { id -> modeFromId(id)?.let { return it } }
        return if (resources.configuration.locales.get(0).language == "vi") Mode.VI else Mode.EN
    }

    private fun modeId(m: Mode) = m.name.lowercase()
    private fun modeFromId(id: String): Mode? =
        Mode.values().firstOrNull { it.name.equals(id.trim(), ignoreCase = true) }

    /** Native space-bar / toast label for each input language. */
    private fun modeLabel(m: Mode): String = when (m) {
        Mode.VI -> "Tiếng Việt"
        Mode.RU, Mode.RU_PHON -> "Русский"
        Mode.AR -> "العربية"
        Mode.KO, Mode.KO_CHUN -> "한국어"
        Mode.JA, Mode.JA_FLICK -> "日本語"
        Mode.ZH -> "中文"
        Mode.TH -> "ไทย"
        else -> "English"
    }

    /** The letters keyboard for [m] (Latin qwerty for EN/VI, own layout else). */
    private fun letterKeyboardFor(m: Mode): Keyboard? = when (m) {
        Mode.RU -> letterKeyboards.getOrPut(m) {
            Keyboard(this, R.xml.keyboard_russian).also { centerRows(it) }
        }
        Mode.RU_PHON -> letterKeyboards.getOrPut(m) {
            Keyboard(this, R.xml.keyboard_russian_phonetic).also { centerRows(it) }
        }
        Mode.AR -> letterKeyboards.getOrPut(m) {
            Keyboard(this, R.xml.keyboard_arabic).also { centerRows(it) }
        }
        Mode.KO -> letterKeyboards.getOrPut(m) {
            Keyboard(this, R.xml.keyboard_korean).also { centerRows(it) }
        }
        Mode.KO_CHUN -> letterKeyboards.getOrPut(m) {
            Keyboard(this, R.xml.keyboard_korean_chunjiin).also { centerRows(it) }
        }
        Mode.JA_FLICK -> letterKeyboards.getOrPut(m) {
            Keyboard(this, R.xml.keyboard_japanese_flick).also { centerRows(it) }
        }
        Mode.TH -> thaiKeyboards.getOrPut(thaiShift) {
            Keyboard(this, if (thaiShift) R.xml.keyboard_thai_shift else R.xml.keyboard_thai)
                .also { centerRows(it) }
        }
        else -> qwertyKeyboard // EN, VI (Latin), JA (romaji)
    }

    /** Languages the globe cycles through; the picker grows this set. */
    private fun enabledModes(): List<Mode> {
        val list = prefs.getString("enabled_langs", null)
            ?.split(",")?.mapNotNull { modeFromId(it) }?.distinct()
        return if (list.isNullOrEmpty()) listOf(Mode.EN, Mode.VI) else list
    }
    private fun enableMode(m: Mode) {
        val cur = enabledModes()
        if (m !in cur) prefs.edit()
            .putString("enabled_langs", (cur + m).joinToString(",") { modeId(it) }).apply()
    }

    /** Globe short tap: switch to the next enabled language (or open the picker
     *  when there's nothing to cycle to). */
    private fun cycleLanguage() {
        val enabled = enabledModes()
        if (enabled.size <= 1) { openInputLangPicker(); return }
        val i = enabled.indexOf(mode).let { if (it < 0) 0 else it }
        setMode(enabled[(i + 1) % enabled.size], persist = true)
        Toast.makeText(this, modeLabel(mode), Toast.LENGTH_SHORT).show()
    }

    /** Apply [m] as the active language: swap the letters layout, refresh the
     *  space label + shift, and (optionally) persist the explicit choice. */
    private fun setMode(m: Mode, persist: Boolean) {
        currentInputConnection?.let { commitComposed(it) }
        // Reset katakana toggle when leaving JA_FLICK so it doesn't leak into
        // the next JA_FLICK session with stale labels.
        if (m != Mode.JA_FLICK) flickKatakana = false
        thaiShift = false // always re-enter Thai on the base Kedmanee layer
        mode = m
        if (persist) prefs.edit().putString("typing_mode", modeId(m)).apply()
        if (layer == Layer.LETTERS) applyLayer()
        // Refresh flick key labels when entering JA_FLICK (labels may be stale
        // after switching away and back).
        if (m == Mode.JA_FLICK) updateFlickKeyLabels()
        updateSpaceBarLabel()
        updateLanguageKeyStyle()
        applyShiftState()
        prewarmJa()
    }

    /**
     * Space bar shows the active language name, Gboard-style. Set on every built
     * keyboard so a layout swap always shows the right label.
     */
    private fun updateSpaceBarLabel() {
        val label = modeLabel(mode)
        val kbs = listOf(qwertyKeyboard, symbolsKeyboard, symbols2Keyboard) +
            letterKeyboards.values + thaiKeyboards.values
        for (kb in kbs) {
            kb?.keys?.firstOrNull { it.codes.firstOrNull() == KEYCODE_SPACE }?.label = label
        }
        keyboardView?.invalidateAllKeys()
    }

    private fun startOrStopVoiceInput() {
        if (isListening) {
            voiceHelper?.stop() // commits whatever's been recognized so far
            return
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Toast.makeText(
                this,
                "Cấp quyền Microphone trong Cài đặt → TransKey rồi thử lại",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        // The recognizer needs a concrete language. If the translate source is a
        // specific language, dictate in it. If it's Auto we can't infer the
        // spoken language, so ALWAYS prompt with the picker (never silently
        // reuse a past pick - the user might be speaking a different language
        // this time). The picker pre-highlights the last pick for one-tap reuse.
        val lang = sourceVoiceLang()
        if (lang == null) {
            openVoicePicker()
            return
        }
        beginVoice(lang)
    }

    /** Open the mic in [voiceLang] (an ISO code from VOICE_LANGS). */
    private fun beginVoice(voiceLang: String) {
        val ic = currentInputConnection ?: return
        // Flush any in-progress Telex word so dictation starts on a clean
        // composing region (partials are streamed AS composing text).
        commitComposed(ic)
        telex.reset()
        val langTag = VoiceRecognitionHelper.resolveLanguageTag(voiceLang) ?: "en-US"
        voiceHelper?.destroy()
        voiceHelper = VoiceRecognitionHelper(this, langTag, VoiceCallbacks())
        voiceHelper?.start()
        isListening = true
        suggestionStrip?.setMicListening(true) // mic turns red while listening
    }

    // ── Voice recognition language (shared with the bubble: tk_voice_lang) ──

    /**
     * The language to recognise: an explicit pick (tk_voice_lang) wins, else the
     * translate SOURCE when it's a concrete supported language. Returns null when
     * undetermined (source = Auto, nothing picked) so the caller prompts.
     */
    private fun sourceVoiceLang(): String? {
        val src = readSourceLang()
        return if (src != "auto" && src in BubbleService.VOICE_LANGS) src else null
    }

    /** Last picked voice language (only for pre-highlighting the picker). */
    private fun lastVoicePick(): String =
        flutterPrefs().getString("tk_voice_lang", null)
            ?.takeIf { it in BubbleService.VOICE_LANGS } ?: ""

    private fun writeVoiceLang(code: String) =
        flutterPrefs().edit().putString("tk_voice_lang", code).apply()

    private fun voiceLangOptions(): List<Pair<String, String>> {
        val labels = BubbleService.LANG_LABELS
        return BubbleService.VOICE_LANGS.map { code -> code to (labels[code] ?: code) }
    }

    /**
     * Show the voice-language picker in the keyboard slot. Picking a language
     * starts dictation in it immediately (the user opened this to dictate, via a
     * mic tap on Auto or a mic long-press). The current source language - or the
     * last pick when source is Auto - is pre-highlighted for one-tap reuse.
     */
    private fun openVoicePicker() {
        val root = rootView as? android.view.ViewGroup ?: return
        val kv = keyboardView ?: return
        currentInputConnection?.let { commitComposed(it) }
        val h = kv.height + (suggestionStrip?.height ?: 0)

        voicePickerView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        val view = VoicePickerView(this)
        voicePickerView = view
        view.onPick = { code ->
            writeVoiceLang(code)
            closeVoicePicker()
            beginVoice(code)
        }
        view.onClose = { closeVoicePicker() }
        view.backLabel = localized(R.string.ime_back_keyboard)
        view.configure(localized(R.string.ime_voice_lang), voiceLangOptions(), sourceVoiceLang() ?: lastVoicePick())
        root.addView(view)
        view.setPanelHeight(if (h > 0) h else kv.height)
        view.visibility = View.VISIBLE
        emojiPanel?.visibility = View.GONE
        suggestionStrip?.visibility = View.GONE
        kv.visibility = View.GONE
    }

    private fun closeVoicePicker() {
        voicePickerView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        voicePickerView = null
        suggestionStrip?.visibility = View.VISIBLE
        keyboardView?.visibility = View.VISIBLE
    }

    /**
     * Catalog of selectable input languages (id, display label). EN + VI lead
     * (the app's core markets), then the rest alphabetically by English name
     * (Gboard-style), with each language's variants grouped together.
     */
    private fun inputLangOptions(): List<Pair<String, String>> = listOf(
        modeId(Mode.EN) to "English",
        modeId(Mode.VI) to "Tiếng Việt",
        modeId(Mode.AR) to "العربية",
        modeId(Mode.ZH) to "中文 · 拼音",
        modeId(Mode.JA) to "日本語 (Romaji)",
        modeId(Mode.JA_FLICK) to "日本語 · フリック",
        modeId(Mode.KO) to "한국어 · 두벌식",
        modeId(Mode.KO_CHUN) to "한국어 · 천지인",
        modeId(Mode.RU) to "Русский · ЙЦУКЕН",
        modeId(Mode.RU_PHON) to "Русский · фонетический",
        modeId(Mode.TH) to "ไทย",
    )

    /**
     * Globe long-press: pick any input language. The pick becomes the active
     * language AND is added to the globe's cycle set (enabledModes).
     */
    private fun openInputLangPicker() {
        val root = rootView as? android.view.ViewGroup ?: return
        val kv = keyboardView ?: return
        currentInputConnection?.let { commitComposed(it) }
        closeEmoji(); closeLangPicker(); closeSettings(); closeHistory(); closeVoicePicker()
        val h = kv.height + (suggestionStrip?.height ?: 0)
        inputLangPickerView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        val view = VoicePickerView(this)
        inputLangPickerView = view
        view.onClose = { closeInputLangPicker() }
        view.backLabel = localized(R.string.ime_back_keyboard)
        view.onPick = { id ->
            modeFromId(id)?.let { m ->
                enableMode(m)
                closeInputLangPicker()
                setMode(m, persist = true)
                Toast.makeText(this, modeLabel(m), Toast.LENGTH_SHORT).show()
            }
        }
        view.configure(localized(R.string.ime_input_lang), inputLangOptions(), modeId(mode))
        root.addView(view)
        view.setPanelHeight(if (h > 0) h else kv.height)
        view.visibility = View.VISIBLE
        emojiPanel?.visibility = View.GONE
        suggestionStrip?.visibility = View.GONE
        kv.visibility = View.GONE
    }

    private fun closeInputLangPicker() {
        inputLangPickerView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        inputLangPickerView = null
        suggestionStrip?.visibility = View.VISIBLE
        keyboardView?.visibility = View.VISIBLE
    }

    /**
     * Live dictation, Gboard/bubble-style: each partial hypothesis replaces the
     * composing region so words appear in the field as the user speaks; the
     * final result is committed (+ a trailing space for the next word).
     */
    private inner class VoiceCallbacks : VoiceRecognitionHelper.Callbacks {
        override fun onReady() {
            Toast.makeText(this@TransKeyIME, localized(R.string.bubble_voice_listening), Toast.LENGTH_SHORT).show()
        }

        override fun onPartialResult(text: String) {
            currentInputConnection?.setComposingText(text, 1)
        }

        override fun onFinalResult(text: String) {
            isListening = false
            suggestionStrip?.setMicListening(false)
            currentInputConnection?.apply {
                setComposingText(text, 1)
                finishComposingText()
                commitText(" ", 1)
            }
        }

        override fun onError(message: String) {
            isListening = false
            suggestionStrip?.setMicListening(false)
            // Keep any partial already shown, just close the composing region.
            currentInputConnection?.finishComposingText()
            Toast.makeText(this@TransKeyIME, message, Toast.LENGTH_SHORT).show()
        }
    }

    override fun onDestroy() {
        voiceHelper?.destroy()
        voiceHelper = null
        runCatching { suggestExecutor.shutdownNow() }
        super.onDestroy()
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        // Cursor jumped to a new field — flush any leftover Telex buffer
        // so the next keypress starts a clean word in the new context.
        telex.reset()
        hangul.reset()
        romaji.reset()
        chunjiin.reset()
        kana.reset()
        jaConverting = false; jaCandidates = emptyList(); jaCandIdx = 0; jaReading = ""
        pinyin.setLength(0); zhCandidates = emptyList()
        clearSuggestions()
        abortAction()          // drop any feature request tied to the old field
        // Only a GENUINELY new field has nothing to undo. Many apps call
        // restartInput (restarting=true) on the SAME field right after our
        // whole-field replace - clearing undo there would hide the chip the
        // instant it appears.
        if (!restarting) clearUndo()
        refreshActionLabels()  // pick up a UI-language change since last shown
        refreshLangPill()      // reflect any source/target change since last shown
        applyPremiumChrome()   // gradient border for paid, flat panel for free
        closeEmoji() // never reopen a field stuck in the emoji panel
        closeLangPicker() // never reopen a field stuck in the language picker
        closeSettings() // never reopen a field stuck in the settings panel
        closeHistory() // never reopen a field stuck in the history panel
        closeVoicePicker() // never reopen a field stuck in the voice-lang picker
        closeInputLangPicker() // nor the input-language picker
        // Typing mode for this field: numeric fields force EN (Telex is
        // irrelevant); everything else uses the user's preferred mode, which
        // defaults to the DEVICE language (Vietnamese device -> VI Telex) until
        // the user toggles it via the globe key.
        mode = if (attribute != null && isNumericClass(attribute)) Mode.EN else preferredMode()
        if (layer == Layer.LETTERS) applyLayer() // swap to this language's layout
        updateSpaceBarLabel()
        updateLanguageKeyStyle()
        prewarmJa() // load the kana->kanji dict in the background for JA fields
        // Fresh field: clear any leftover shift, then auto-capitalize if the
        // field/caret position calls for it (start of a text field).
        shift = Shift.NONE
        applyShiftState()
        maybeAutoCap()
    }

    override fun onFinishInput() {
        super.onFinishInput()
        currentInputConnection?.finishComposingText()
        telex.reset()
        hangul.reset()
        romaji.reset()
        chunjiin.reset()
        kana.reset()
        jaConverting = false; jaCandidates = emptyList(); jaCandIdx = 0; jaReading = ""
        pinyin.setLength(0); zhCandidates = emptyList()
        clearSuggestions()
        abortAction()
        // Stop any live dictation so a late callback can't fire into a gone field.
        if (isListening) {
            voiceHelper?.cancel(); isListening = false
            suggestionStrip?.setMicListening(false)
        }
    }

    /**
     * The cursor moved inside the SAME field (a tap elsewhere, an arrow key, a
     * selection, autocomplete). onStartInput does NOT fire for this, so without
     * handling it the stale Telex buffer + composing region stay anchored to the
     * old spot: the next keystroke's setComposingText replaces THAT region and
     * the text snaps back to where it was last edited.
     *
     * If we have an active composition but the caret is no longer sitting at the
     * end of our composing region, finalize the old word where it is and start a
     * clean word at the new cursor.
     */
    override fun onUpdateSelection(
        oldSelStart: Int,
        oldSelEnd: Int,
        newSelStart: Int,
        newSelEnd: Int,
        candidatesStart: Int,
        candidatesEnd: Int,
    ) {
        super.onUpdateSelection(
            oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd,
        )
        if (!telex.hasComposingText) return
        // Our own setComposingText leaves the caret at the end of the composing
        // region (newSelEnd == candidatesEnd, nothing range-selected). Anything
        // else means the user navigated away from the word being composed.
        val movedAway = newSelStart != newSelEnd || // a range is selected
            candidatesStart < 0 ||                  // composing region is gone
            newSelEnd != candidatesEnd              // caret left the region
        if (movedAway) {
            telex.reset()
            currentInputConnection?.finishComposingText()
            clearSuggestions()
            maybeAutoCap() // re-evaluate caps at the new caret position
        }
    }

    // ── KeyboardView.OnKeyboardActionListener ──

    override fun onKey(primaryCode: Int, keyCodes: IntArray?) {
        val ic = currentInputConnection ?: return
        when (primaryCode) {
            KEYCODE_SHIFT -> {
                if (mode == Mode.TH) {
                    // Thai has no upper/lowercase: Shift swaps between the two
                    // Kedmanee layers (base <-> rare consonants / digits / tones).
                    thaiShift = !thaiShift
                    keyboardView?.keyboard = letterKeyboardFor(Mode.TH)
                    updateSpaceBarLabel()
                    keyboardView?.invalidateAllKeys()
                    return
                }
                shift = when (shift) {
                    Shift.NONE -> Shift.ONESHOT
                    Shift.ONESHOT -> Shift.LOCK
                    Shift.LOCK -> Shift.NONE
                }
                applyShiftState()
            }
            KEYCODE_DELETE -> handleBackspace(ic)
            KEYCODE_ENTER -> handleEnter(ic)
            KEYCODE_KANA_MOD -> {
                // JA flick 小゛゜: cycle the last kana (dakuten/handakuten/small).
                if (jaConverting) {
                    commitCandidate(ic)
                } else if (kana.hasComposingText) {
                    kana.modifyLast()
                    val display = if (flickKatakana) toKatakana(kana.composingText) else kana.composingText
                    ic.setComposingText(display, 1)
                }
            }
            KEYCODE_LANG_SWITCH -> {
                // Legacy code from the early "EN/VI" key layout. Kept for
                // safety in case the layout is reverted.
                cycleLanguage()
                updateLangKeyLabel()
            }
            KEYCODE_LANG_GLOBE -> {
                // 🌐 in Row 4 (Gboard pattern). Short tap cycles the enabled
                // input languages; long-press opens the full picker (handled in
                // GboardKeyboardView.onLongPress). Voice input + system-IME-picker
                // live elsewhere (mic on the bubble, system IME switcher).
                cycleLanguage()
            }
            KEYCODE_KANA_TOGGLE -> {
                // カナ/かな toggle on the flick keyboard: switch between
                // hiragana and katakana output. Composing text is converted live.
                flickKatakana = !flickKatakana
                updateFlickKeyLabels()
                if (kana.hasComposingText) {
                    val display = if (flickKatakana) toKatakana(kana.composingText) else kana.composingText
                    ic.setComposingText(display, 1)
                }
            }
            KEYCODE_SYMBOLS -> {
                // ?123 / ABC: letters <-> symbols (from either symbol page).
                commitComposed(ic)
                layer = if (layer == Layer.LETTERS) Layer.SYMBOLS else Layer.LETTERS
                applyLayer()
            }
            KEYCODE_SYMBOLS2 -> {
                // #+= / 123: toggle the two symbol pages.
                layer = if (layer == Layer.SYMBOLS2) Layer.SYMBOLS else Layer.SYMBOLS2
                applyLayer()
            }
            KEYCODE_EMOJI -> openEmoji()
            KEYCODE_SPACE -> {
                // Japanese: space converts kana->kanji (first press) then cycles
                // candidates; only a space with nothing composing types a space.
                if (isJa()) {
                    if (jaConverting) { cycleCandidate(ic); return }
                    if (startConversion(ic)) return
                }
                // Chinese: space commits the top hanzi candidate (no space typed).
                if (isZh() && pinyin.isNotEmpty()) {
                    commitZh(ic, zhCandidates.firstOrNull() ?: pinyin.toString())
                    return
                }
                // Commit (auto-correcting) the current word, then a space.
                commitComposed(ic)
                // Double-tap space -> ". ": if the char right before the existing
                // single space is a word char, replace that space with ". ".
                if (dotDoubleSpaceEnabled) {
                    val two = ic.getTextBeforeCursor(2, 0)
                    if (two != null && two.length == 2 && two[1] == ' ' &&
                        (two[0].isLetterOrDigit())
                    ) {
                        ic.deleteSurroundingText(1, 0)
                        ic.commitText(". ", 1)
                        maybeAutoCap()
                        return
                    }
                }
                ic.commitText(" ", 1)
                maybeAutoCap()
            }
            else -> {
                if (primaryCode <= 0) return
                val ch = primaryCode.toChar().let {
                    if (isShifted) it.uppercaseChar() else it.lowercaseChar()
                }
                handleChar(ic, ch)
                // One-shot shift falls back to lowercase after a single letter.
                if (shift == Shift.ONESHOT) {
                    shift = Shift.NONE
                    applyShiftState()
                }
            }
        }
    }

    /**
     * Show the self-drawn emoji panel in place of the keyboard. The strip +
     * keyboard are hidden and the panel is sized to their combined height so the
     * IME window doesn't jump. ABC returns to letters.
     */
    private fun openEmoji() {
        val root = rootView as? android.view.ViewGroup ?: return
        val kv = keyboardView ?: return
        currentInputConnection?.let { commitComposed(it) }
        val h = kv.height + (suggestionStrip?.height ?: 0)
        val panel = emojiPanel ?: EmojiPanelView(this).also {
            emojiPanel = it
            it.onEmoji = { e -> currentInputConnection?.commitText(e, 1) }
            it.onBackspace = { currentInputConnection?.let { ic -> handleBackspace(ic) } }
            it.onAbc = { closeEmoji() }
        }
        // Attach to the current root (the input view is re-inflated each show,
        // so the panel may still be parented to a stale root). Detach first.
        (panel.parent as? android.view.ViewGroup)?.removeView(panel)
        root.addView(panel)
        panel.setPanelHeight(if (h > 0) h else kv.height)
        panel.visibility = View.VISIBLE
        suggestionStrip?.visibility = View.GONE
        kv.visibility = View.GONE
    }

    private fun closeEmoji() {
        emojiPanel?.visibility = View.GONE
        suggestionStrip?.visibility = View.VISIBLE
        keyboardView?.visibility = View.VISIBLE
    }

    /**
     * Show the full candidate grid (tapped via the ▼ on the strip) in place of
     * the keyboard: every CJK candidate, tap to commit, ▲ to collapse. Mirrors
     * [openEmoji]'s panel handling (re-parent to the current root, size to the
     * keyboard + strip so the IME window doesn't jump).
     */
    private fun openCandidateGrid() {
        val list = when {
            jaConverting -> jaCandidates
            isZh() && pinyin.isNotEmpty() -> zhCandidates
            else -> return
        }
        if (list.isEmpty()) return
        val root = rootView as? android.view.ViewGroup ?: return
        val kv = keyboardView ?: return
        val h = kv.height + (suggestionStrip?.height ?: 0)
        val grid = candidateGrid ?: CandidateGridView(this).also {
            candidateGrid = it
            it.onCollapse = { closeCandidateGrid() }
            it.onPick = { word ->
                if (jaConverting) commitTappedCandidate(word) else commitTappedZh(word)
                closeCandidateGrid()
            }
        }
        grid.setNumbered(isZh())
        grid.setCandidates(list)
        (grid.parent as? android.view.ViewGroup)?.removeView(grid)
        root.addView(grid)
        grid.setPanelHeight(if (h > 0) h else kv.height)
        grid.visibility = View.VISIBLE
        suggestionStrip?.visibility = View.GONE
        kv.visibility = View.GONE
    }

    private fun closeCandidateGrid() {
        candidateGrid?.visibility = View.GONE
        suggestionStrip?.visibility = View.VISIBLE
        keyboardView?.visibility = View.VISIBLE
    }

    /** Swap the visible keyboard to match the current [layer]. */
    private fun applyLayer() {
        val letterH = letterKeyboardFor(mode)?.height ?: 0
        val gkv = keyboardView as? GboardKeyboardView
        val kb = when (layer) {
            Layer.SYMBOLS -> symbolsKeyboard.also { matchHeight(it, letterH); gkv?.refreshLayout(it) }
            Layer.SYMBOLS2 -> symbols2Keyboard.also { matchHeight(it, letterH); gkv?.refreshLayout(it) }
            else -> letterKeyboardFor(mode)
        }
        keyboardView?.keyboard = kb
        keyboardView?.invalidateAllKeys()
    }

    /** Korean Shift map: base jamo -> its tense / extra form (Dubeolsik). */
    private fun tenseJamo(c: Char): Char = when (c) {
        'ㅂ' -> 'ㅃ'; 'ㅈ' -> 'ㅉ'; 'ㄷ' -> 'ㄸ'; 'ㄱ' -> 'ㄲ'; 'ㅅ' -> 'ㅆ'
        'ㅐ' -> 'ㅒ'; 'ㅔ' -> 'ㅖ'; else -> c
    }

    /** Chunjiin consonant group index from the key's first-jamo code, or -1. */
    private fun chunGroup(code: Int): Int = when (code) {
        12593 -> 0; 12596 -> 1; 12599 -> 2; 12610 -> 3; 12613 -> 4; 12616 -> 5; 12615 -> 6
        else -> -1
    }

    // JA flick: center-kana code -> [center, left, up, right, down]. The view
    // detects the flick direction and we map it here. Matches keyboard_japanese_flick.
    private val flickTable: Map<Int, Array<String>> = mapOf(
        12354 to arrayOf("あ", "い", "う", "え", "お"),
        12363 to arrayOf("か", "き", "く", "け", "こ"),
        12373 to arrayOf("さ", "し", "す", "せ", "そ"),
        12383 to arrayOf("た", "ち", "つ", "て", "と"),
        12394 to arrayOf("な", "に", "ぬ", "ね", "の"),
        12399 to arrayOf("は", "ひ", "ふ", "へ", "ほ"),
        12414 to arrayOf("ま", "み", "む", "め", "も"),
        12420 to arrayOf("や", "「", "ゆ", "」", "よ"),
        12425 to arrayOf("ら", "り", "る", "れ", "ろ"),
        12431 to arrayOf("わ", "を", "ん", "ー", "〜"),
        12289 to arrayOf("、", "。", "?", "!", "…"), // punctuation key
    )
    // Katakana toggle: when on, flick output and key labels show katakana.
    private var flickKatakana = false

    /** Convert hiragana (U+3041..3096) to katakana (U+30A1..30F6). */
    private fun toKatakana(s: String): String = s.map { ch ->
        if (ch.code in 0x3041..0x3096) (ch.code + 0x60).toChar() else ch
    }.joinToString("")

    /** Flick labels for the preview popup (null = not a flick key). */
    private fun flickLabelsFor(code: Int): Array<String>? {
        if (mode != Mode.JA_FLICK) return null
        val labels = flickTable[code] ?: return null
        return if (flickKatakana) Array(labels.size) { i -> toKatakana(labels[i]) } else labels
    }

    /** Update the flick keyboard key labels (kana center + toggle button). */
    private fun updateFlickKeyLabels() {
        val kb = letterKeyboards[Mode.JA_FLICK] ?: return
        for (key in kb.keys) {
            val code = key.codes.firstOrNull() ?: continue
            flickTable[code]?.firstOrNull()?.let { label ->
                key.label = if (flickKatakana) toKatakana(label) else label
            }
            if (code == KEYCODE_KANA_TOGGLE) {
                key.label = if (flickKatakana) "かな" else "カナ"
            }
        }
        keyboardView?.invalidateAllKeys()
    }

    /** A flick landed on a kana key: dir 0=center,1=left,2=up,3=right,4=down. */
    private fun handleFlick(centerCode: Int, dir: Int) {
        val ic = currentInputConnection ?: return
        val set = flickTable[centerCode] ?: return
        val raw = set.getOrNull(dir)?.takeIf { it.isNotEmpty() } ?: set[0]
        clearUndo()
        if (jaConverting) commitCandidate(ic) // a new key finalizes the conversion
        if (centerCode == 12289) {
            // Punctuation: finalize the kana run, then type the mark literally.
            commitComposed(ic)
            ic.commitText(if (flickKatakana) toKatakana(raw) else raw, 1)
            return
        }
        kana.add(raw) // always feed hiragana to the composer
        val display = if (flickKatakana) toKatakana(kana.composingText) else kana.composingText
        ic.setComposingText(display, 1)
    }

    // ── Japanese kana -> kanji conversion (henkan) ──

    private fun isJa() = mode == Mode.JA || mode == Mode.JA_FLICK

    /** The current kana run as composing text (without finalizing). */
    private fun jaComposingKana(): String =
        if (mode == Mode.JA_FLICK) kana.composingText else romaji.composingText

    /** Pre-load the CJK dictionary off the key-press thread when entering JA/ZH. */
    private fun prewarmJa() {
        if (isJa() && !kanjiConv.isReady) Thread { kanjiConv.ensureLoaded() }.start()
        if (isZh() && !pinyinConv.isReady) Thread { pinyinConv.ensureLoaded() }.start()
    }

    /** Space on a kana run: start conversion, showing kanji candidates. */
    private fun startConversion(ic: android.view.inputmethod.InputConnection): Boolean {
        val reading = if (mode == Mode.JA_FLICK) {
            if (!kana.hasComposingText) return false; kana.commit()
        } else {
            if (!romaji.hasComposingText) return false; romaji.commit()
        }
        if (reading.isEmpty()) return false
        jaReading = reading
        jaCandidates = kanjiConv.convert(reading).take(12).ifEmpty {
            // No dictionary match: fallback is the raw reading (hiragana).
            // When katakana toggle is on, convert the fallback to katakana.
            listOf(if (mode == Mode.JA_FLICK && flickKatakana) toKatakana(reading) else reading)
        }
        jaCandIdx = 0
        jaConverting = true
        ic.setComposingText(jaCandidates[0], 1)
        suggestionStrip?.setCandidates(jaCandidates, jaCandIdx, withNumbers = false)
        return true
    }

    /** Space again: move the highlight to the next candidate. */
    private fun cycleCandidate(ic: android.view.inputmethod.InputConnection) {
        if (!jaConverting || jaCandidates.isEmpty()) return
        jaCandIdx = (jaCandIdx + 1) % jaCandidates.size
        ic.setComposingText(jaCandidates[jaCandIdx], 1)
        suggestionStrip?.setCandidates(jaCandidates, jaCandIdx, withNumbers = false)
    }

    /** Finalize the highlighted candidate (enter / a new key). */
    private fun commitCandidate(ic: android.view.inputmethod.InputConnection) {
        if (!jaConverting) return
        ic.finishComposingText() // the composing region already holds the candidate
        endConversion()
    }

    /** A tapped candidate from the strip: commit that exact surface. */
    private fun commitTappedCandidate(word: String) {
        val ic = currentInputConnection ?: return
        ic.setComposingText(word, 1)
        ic.finishComposingText()
        endConversion()
    }

    /** Backspace during conversion: drop back to editing the kana reading. */
    private fun cancelConversion(ic: android.view.inputmethod.InputConnection) {
        val reading = jaReading
        endConversion()
        if (mode == Mode.JA_FLICK) kana.load(reading) else romaji.load(reading)
        val display = if (mode == Mode.JA_FLICK && flickKatakana) toKatakana(reading) else reading
        ic.setComposingText(display, 1)
    }

    private fun endConversion() {
        jaConverting = false
        jaCandidates = emptyList()
        jaCandIdx = 0
        jaReading = ""
        clearSuggestions()
    }

    // ── Chinese pinyin -> hanzi ──

    private fun isZh() = mode == Mode.ZH

    /** Append a pinyin letter and refresh the live hanzi candidates. */
    private fun handlePinyin(ic: android.view.inputmethod.InputConnection, ch: Char) {
        clearUndo()
        pinyin.append(ch.lowercaseChar())
        ic.setComposingText(pinyin, 1)
        refreshZhCandidates()
    }

    private fun refreshZhCandidates() {
        zhCandidates = if (pinyin.isEmpty()) emptyList()
        else pinyinConv.convert(pinyin.toString())
        suggestionStrip?.setCandidates(
            zhCandidates, if (zhCandidates.isEmpty()) -1 else 0, withNumbers = true,
        )
    }

    /** Commit [text] (a chosen hanzi candidate, or the raw pinyin) and reset. */
    private fun commitZh(ic: android.view.inputmethod.InputConnection, text: String) {
        ic.setComposingText(text, 1)
        ic.finishComposingText()
        pinyin.setLength(0)
        zhCandidates = emptyList()
        clearSuggestions()
    }

    private fun commitTappedZh(word: String) {
        val ic = currentInputConnection ?: return
        commitZh(ic, word)
    }

    private fun handleChar(
        ic: android.view.inputmethod.InputConnection,
        ch: Char
    ) {
        clearUndo() // a manual edit invalidates the post-action undo snapshot
        if (jaConverting) commitCandidate(ic) // a new char finalizes the conversion
        if (mode == Mode.ZH && (ch in 'a'..'z' || ch in 'A'..'Z')) {
            // Chinese: accumulate latin pinyin with live hanzi candidates.
            handlePinyin(ic, ch)
            return
        }
        if (mode == Mode.KO) {
            // Korean: feed the jamo to the syllable composer (Shift gives the
            // tense/extra jamo). The whole run stays as composing text.
            val jamo = if (isShifted) tenseJamo(ch) else ch
            hangul.input(jamo)
            ic.setComposingText(hangul.composingText, 1)
            return
        }
        if (mode == Mode.KO_CHUN) {
            // Korean Chunjiin: dot/ㅡ/ㅣ are vowel strokes; the rest are
            // consonant-group taps. ChunjiinComposer feeds HangulComposer.
            when (ch.code) {
                12685 -> chunjiin.vowel('D') // ·
                12641 -> chunjiin.vowel('H') // ㅡ
                12643 -> chunjiin.vowel('V') // ㅣ
                else -> { val g = chunGroup(ch.code); if (g >= 0) chunjiin.consonant(g) else return }
            }
            ic.setComposingText(chunjiin.composingText, 1)
            return
        }
        if (mode == Mode.JA) {
            // Japanese: romaji letters compose into hiragana; anything else
            // finalizes the kana then types literally. (Kana->kanji needs a
            // dictionary - out of scope for the algorithmic build.)
            if (ch in 'a'..'z' || ch in 'A'..'Z' || ch == '-') {
                romaji.input(ch)
                ic.setComposingText(romaji.composingText, 1)
            } else {
                commitComposed(ic)
                ic.commitText(ch.toString(), 1)
            }
            return
        }
        if (mode != Mode.VI || !ch.isLetter()) {
            // EN mode or non-letter (punctuation/digit): auto-correct + commit
            // any in-progress Vietnamese word first, then the char itself.
            commitComposed(ic)
            ic.commitText(ch.toString(), 1)
            return
        }
        // VI Telex path: append to the composer + project as composing
        // text so the user sees the in-progress word with diacritics.
        rawWord.append(ch)
        telex.input(ch)
        ic.setComposingText(telex.composingText, 1)
        refreshSuggestions()
    }

    private fun handleBackspace(ic: android.view.inputmethod.InputConnection) {
        clearUndo() // a manual edit invalidates the post-action undo snapshot
        if (jaConverting) { cancelConversion(ic); return } // back to editing the kana
        if (mode == Mode.ZH && pinyin.isNotEmpty()) {
            pinyin.deleteCharAt(pinyin.length - 1)
            if (pinyin.isEmpty()) { ic.setComposingText("", 1); ic.finishComposingText(); zhCandidates = emptyList(); clearSuggestions() }
            else { ic.setComposingText(pinyin, 1); refreshZhCandidates() }
            return
        }
        if (mode == Mode.KO && hangul.hasComposingText) {
            hangul.backspace()
            if (hangul.hasComposingText) ic.setComposingText(hangul.composingText, 1)
            else { ic.setComposingText("", 1); ic.finishComposingText() }
            return
        }
        if (mode == Mode.JA && romaji.hasComposingText) {
            romaji.backspace()
            if (romaji.hasComposingText) ic.setComposingText(romaji.composingText, 1)
            else { ic.setComposingText("", 1); ic.finishComposingText() }
            return
        }
        if (mode == Mode.KO_CHUN && chunjiin.hasComposingText) {
            chunjiin.backspace()
            if (chunjiin.hasComposingText) ic.setComposingText(chunjiin.composingText, 1)
            else { ic.setComposingText("", 1); ic.finishComposingText() }
            return
        }
        if (mode == Mode.JA_FLICK && kana.hasComposingText) {
            kana.backspace()
            if (kana.hasComposingText) {
                val display = if (flickKatakana) toKatakana(kana.composingText) else kana.composingText
                ic.setComposingText(display, 1)
            } else { ic.setComposingText("", 1); ic.finishComposingText() }
            return
        }
        if (mode == Mode.VI && telex.backspace()) {
            if (rawWord.isNotEmpty()) rawWord.deleteCharAt(rawWord.length - 1)
            ic.setComposingText(telex.composingText, 1)
            if (telex.composingText.isEmpty()) {
                ic.finishComposingText()
            }
            refreshSuggestions()
            return
        }
        // If there's a selection (e.g. Select All), delete the WHOLE selection
        // in one go. A KEYCODE_DEL event deletes only one char in some editors,
        // leaving the rest; replacing the selected text with "" clears it all.
        val selected = ic.getSelectedText(0)
        if (!selected.isNullOrEmpty()) {
            ic.commitText("", 1)
            return
        }
        // Fall through to a hardware-style backspace event for the
        // underlying text field.
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
        maybeAutoCap() // deleting back to a sentence start re-arms caps
    }

    private fun handleEnter(ic: android.view.inputmethod.InputConnection) {
        // While converting, Enter just confirms the highlighted candidate (no
        // newline / editor action) - the Japanese henkan convention.
        if (jaConverting) { commitCandidate(ic); return }
        // Chinese: Enter commits the raw pinyin (latin) as typed.
        if (mode == Mode.ZH && pinyin.isNotEmpty()) { commitZh(ic, pinyin.toString()); return }
        commitComposed(ic)
        val editorInfo = currentInputEditorInfo
        val actionId = editorInfo?.imeOptions?.and(EditorInfo.IME_MASK_ACTION) ?: 0
        if (actionId != 0 && actionId != EditorInfo.IME_ACTION_NONE &&
            editorInfo?.imeOptions?.and(EditorInfo.IME_FLAG_NO_ENTER_ACTION) == 0
        ) {
            ic.performEditorAction(actionId)
        } else {
            ic.commitText("\n", 1)
        }
    }

    /**
     * Commit the in-progress Vietnamese word, auto-correcting it (VI mode) to
     * the nearest valid syllable when what was typed isn't itself valid. No-op
     * when there's nothing composing.
     */
    private fun commitComposed(ic: android.view.inputmethod.InputConnection) {
        if (jaConverting) {
            // Finalize the highlighted kanji candidate first (covers symbols
            // toggle, language switch, field change while converting).
            ic.finishComposingText()
            endConversion()
            return
        }
        if (mode == Mode.ZH) {
            // Finalize the top hanzi candidate (or the raw pinyin if none).
            if (pinyin.isNotEmpty()) {
                commitZh(ic, zhCandidates.firstOrNull() ?: pinyin.toString())
            }
            return
        }
        if (mode == Mode.KO) {
            if (hangul.hasComposingText) { ic.finishComposingText(); hangul.reset() }
            clearSuggestions()
            return
        }
        if (mode == Mode.JA) {
            if (romaji.hasComposingText) {
                ic.setComposingText(romaji.commit(), 1) // finalize trailing n -> ん
                ic.finishComposingText()
            }
            clearSuggestions()
            return
        }
        if (mode == Mode.KO_CHUN) {
            if (chunjiin.hasComposingText) {
                ic.setComposingText(chunjiin.commit(), 1) // flush any mid-stroke jamo
                ic.finishComposingText()
            }
            clearSuggestions()
            return
        }
        if (mode == Mode.JA_FLICK) {
            if (kana.hasComposingText) {
                val text = kana.commit()
                val out = if (flickKatakana) toKatakana(text) else text
                ic.setComposingText(out, 1)
                ic.finishComposingText()
            }
            clearSuggestions()
            return
        }
        if (!telex.hasComposingText) {
            clearSuggestions()
            return
        }
        val literal = telex.literalIntent
        val typed = telex.commitWord()
        val raw = rawWord.toString()
        // We never silently "spell-correct" a word (that would change what the
        // user wrote, like Gboard does NOT). The only substitution is keeping a
        // known English word verbatim when Telex would otherwise mangle it, and
        // only when Telex DIDN'T already change it into valid Vietnamese.
        val out = when {
            mode != Mode.VI -> typed
            literal -> typed // user escaped Telex by repeating a key ("telexx")
            raw == typed && raw.length >= 2 && corrector.isEnglish(raw) -> raw
            // Opt-in spelling fix / split merged words. Off by default.
            autocorrectEnabled && !corrector.isValid(typed) ->
                try { corrector.fix(typed) ?: typed } catch (e: Exception) { typed }
            else -> typed
        }
        ic.commitText(out, 1)
        clearSuggestions()
    }

    /**
     * Light suggestion strip: when Telex turned the keystrokes into something
     * other than what was typed and the literal keystrokes are a known English
     * word ("object" -> "ọbect"), offer the English word as a tappable chip.
     * O(1) dictionary lookups only - no per-keystroke scan, so no typing jank.
     */
    private fun refreshSuggestions() {
        if (mode != Mode.VI || !telex.hasComposingText) {
            clearSuggestions()
            return
        }
        val composed = telex.composingText
        val raw = rawWord.toString()
        if (raw.length >= 2 && raw != composed && corrector.isEnglish(raw)) {
            suggestionStrip?.setSuggestions(listOf(raw))
        } else {
            suggestionStrip?.setSuggestions(emptyList())
        }
    }

    /** Replace the in-progress word with a tapped suggestion + a space. */
    private fun applySuggestion(word: String) {
        val ic = currentInputConnection ?: return
        telex.commitWord()
        rawWord.setLength(0)
        // Replace the active composing region with the chosen word, finalize it,
        // then add a space. (commitText alone doesn't reliably replace the
        // composing text in some editors, leaving the half-typed word behind.)
        ic.beginBatchEdit()
        ic.setComposingText(word, 1)
        ic.finishComposingText()
        ic.commitText(" ", 1)
        ic.endBatchEdit()
        clearSuggestions()
    }

    private fun clearSuggestions() {
        suggestSeq.incrementAndGet() // cancel any pending background suggestion
        rawWord.setLength(0)
        suggestionStrip?.setSuggestions(emptyList())
    }

    // ── Feature buttons: translate / refine the whole field ──

    /**
     * A Context whose resources follow the app's UI language (the same
     * `flutter.tk_ui_locale` pref the bubble reads), so the chip labels match
     * the language the user picked in-app rather than the device locale.
     */
    private fun uiContext(): android.content.Context {
        val stored = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .getString("flutter.tk_ui_locale", null)
        val code = if (stored.isNullOrEmpty()) deviceUiLocale() else stored
        if (code != lastUiLocale || localizedCtx == null) {
            lastUiLocale = code
            val cfg = android.content.res.Configuration(resources.configuration)
            cfg.setLocale(java.util.Locale.forLanguageTag(code))
            localizedCtx = createConfigurationContext(cfg)
        }
        return localizedCtx ?: this
    }

    private fun localized(resId: Int): String = uiContext().getString(resId)

    /** Server feature flag mirrored to plain prefs (see features_provider.dart). */
    private fun featureEnabled(key: String): Boolean = try {
        flutterPrefs().getBoolean("flutter.$key", false)
    } catch (_: ClassCastException) {
        false
    }

    /** Reply replaces Translate for entitled users; both Reply + Refine are paid. */
    private fun replyEnabled() = featureEnabled("tk_feature_reply")
    private fun refineEnabled() = featureEnabled("tk_feature_refine")

    /** Any paid entitlement unlocks the premium keyboard chrome (gradient border). */
    private fun isPaid() = replyEnabled() || refineEnabled()

    /**
     * Paid accounts get a brand-gradient hairline border + lightly rounded top
     * corners on the keyboard panel; free accounts keep the flat dark panel.
     * Called on each onStartInput so an entitlement change is reflected live.
     */
    private fun applyPremiumChrome() {
        val paid = isPaid()
        rootView?.setBackgroundResource(
            if (paid) R.drawable.transkey_kb_panel_premium
            else R.drawable.transkey_kb_panel,
        )
        // The gradient top-edge bar is drawn by the strip (clipped to the panel's
        // rounded corners); the rounded dark fill above is the panel background.
        suggestionStrip?.setTopBar(paid)
    }

    /**
     * Chip modes shown for the current entitlement, in display order:
     *   - chip 0 = Reply (paid) else Translate (always available)
     *   - chip 1 = Refine, only when entitled (paid) - hidden for free users
     * onActionButton maps the tapped index through this same list.
     */
    private fun actionModes(): List<String> = buildList {
        add(if (replyEnabled()) "reply" else "translate")
        if (refineEnabled()) add("refine")
    }

    private fun refreshActionLabels() {
        val labels = actionModes().map { mode ->
            when (mode) {
                "reply" -> localized(R.string.bubble_mode_reply)
                "refine" -> localized(R.string.ime_action_refine)
                else -> localized(R.string.ime_action_translate)
            }
        }
        suggestionStrip?.setActions(labels)
    }

    /** A feature chip was tapped; the index maps through [actionModes]. */
    private fun onActionButton(index: Int) {
        if (actionInFlight) return
        val ic = currentInputConnection ?: return
        val mode = actionModes().getOrNull(index) ?: return
        ic.finishComposingText()
        // Snapshot the exact field (untrimmed) so a successful replace can be
        // undone. Held pending until the result arrives (a failed/cancelled
        // request leaves the field + the existing undo state untouched).
        val snapshot = fullFieldText(ic)
        val text = fullFieldText(ic).trim()
        if (text.isEmpty()) {
            Toast.makeText(this, localized(R.string.ime_no_text), Toast.LENGTH_SHORT).show()
            return
        }
        pendingUndoText = snapshot
        val engine = TransKeyApp.engine
        if (engine == null) {
            Toast.makeText(this, localized(R.string.bubble_panel_app_not_ready), Toast.LENGTH_LONG).show()
            return
        }
        val targetLang = readTargetLang()
        val reqId = imeReqSeq.incrementAndGet()
        currentActionReq = reqId
        actionInFlight = true
        suggestionStrip?.setProcessing(true, localized(R.string.ime_processing))
        TransKeyApp.registerImeResult(reqId) { translation, error ->
            mainHandler.post { onTranslateResult(reqId, translation, error) }
        }
        invokeTranslate(engine, text, mode, targetLang, reqId, attempt = 0)
    }

    /** Read the entire field regardless of cursor position. */
    private fun fullFieldText(ic: android.view.inputmethod.InputConnection): String {
        val extracted = ic.getExtractedText(android.view.inputmethod.ExtractedTextRequest(), 0)
        extracted?.text?.let { return it.toString() }
        // Fallback for editors that don't support extracted text.
        val before = ic.getTextBeforeCursor(MAX_FIELD, 0) ?: ""
        val after = ic.getTextAfterCursor(MAX_FIELD, 0) ?: ""
        return "$before$after"
    }

    /**
     * Invoke Flutter's translateText with the same notImplemented retry the
     * bubble uses: on a cold process the Dart isolate may not have registered
     * its handler yet. The result returns async via deliverResult (routed back
     * to us by requestId through TransKeyApp).
     */
    private fun invokeTranslate(
        engine: io.flutter.embedding.engine.FlutterEngine,
        text: String,
        mode: String,
        targetLang: String,
        reqId: Long,
        attempt: Int,
    ) {
        val channel = io.flutter.plugin.common.MethodChannel(
            engine.dartExecutor.binaryMessenger, BubbleService.METHOD_CHANNEL,
        )
        val args = mapOf(
            "text" to text,
            "mode" to mode,
            "targetLang" to targetLang,
            "requestId" to reqId,
        )
        channel.invokeMethod(
            "translateText",
            args,
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) { /* delivered via deliverResult */ }
                override fun error(code: String, msg: String?, details: Any?) {
                    mainHandler.post { onTranslateResult(reqId, null, msg ?: code) }
                }
                override fun notImplemented() {
                    if (attempt < 5) {
                        mainHandler.postDelayed({
                            invokeTranslate(engine, text, mode, targetLang, reqId, attempt + 1)
                        }, 300L)
                    } else {
                        mainHandler.post {
                            onTranslateResult(reqId, null, localized(R.string.bubble_panel_app_not_ready))
                        }
                    }
                }
            },
        )
    }

    private fun onTranslateResult(reqId: Long, translation: String?, error: String?) {
        // Superseded by a field switch / newer request — drop it.
        if (reqId != currentActionReq || !actionInFlight) return
        actionInFlight = false
        currentActionReq = -1L
        suggestionStrip?.setProcessing(false)
        if (!error.isNullOrEmpty() || translation.isNullOrEmpty()) {
            val msg = error?.takeIf { it.isNotEmpty() }
                ?: localized(R.string.bubble_panel_translation_failed)
            Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
            return
        }
        // The replace succeeded - arm undo with the pre-replace text.
        undoSnapshot = pendingUndoText
        pendingUndoText = null
        replaceAllText(translation)
        refreshUndo()
    }

    /** Restore the field to its pre-action text, then clear the undo state. */
    private fun performUndo() {
        val snapshot = undoSnapshot ?: return
        replaceAllText(snapshot)
        clearUndo()
    }

    /** Drop the undo snapshot and hide the chip (call after edits / field switch). */
    private fun clearUndo() {
        if (undoSnapshot == null && pendingUndoText == null) return
        undoSnapshot = null
        pendingUndoText = null
        refreshUndo()
    }

    private fun refreshUndo() {
        suggestionStrip?.setUndoVisible(undoSnapshot != null)
    }

    /** Replace the entire field content with [text]. */
    private fun replaceAllText(text: String) {
        val ic = currentInputConnection ?: return
        ic.beginBatchEdit()
        ic.finishComposingText()
        val before = ic.getTextBeforeCursor(MAX_FIELD, 0)?.length ?: 0
        val after = ic.getTextAfterCursor(MAX_FIELD, 0)?.length ?: 0
        if (before > 0 || after > 0) ic.deleteSurroundingText(before, after)
        ic.commitText(text, 1)
        ic.endBatchEdit()
    }

    /** Cancel any in-flight feature request (field switched / IME hidden). */
    private fun abortAction() {
        if (!actionInFlight) return
        TransKeyApp.cancelImeResult(currentActionReq)
        actionInFlight = false
        currentActionReq = -1L
        suggestionStrip?.setProcessing(false)
    }

    // ── Translate language (source -> target) ──
    // Both prefs live in FlutterSharedPreferences; the Dart translate path
    // reads tk_source_lang itself and the IME passes tk_target_lang as the
    // translateText arg, so writing these two prefs is all that's needed - no
    // app round-trip.

    private fun flutterPrefs() = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
    private fun readSourceLang() = flutterPrefs().getString("flutter.tk_source_lang", "auto") ?: "auto"
    private fun readTargetLang() = flutterPrefs().getString("flutter.tk_target_lang", "en") ?: "en"
    private fun readReplyLang() = flutterPrefs().getString("flutter.tk_reply_lang", "") ?: ""
    private fun writeSourceLang(code: String) =
        flutterPrefs().edit().putString("flutter.tk_source_lang", code).apply()
    private fun writeTargetLang(code: String) =
        flutterPrefs().edit().putString("flutter.tk_target_lang", code).apply()
    private fun writeReplyLang(code: String) =
        flutterPrefs().edit().putString("flutter.tk_reply_lang", code).apply()

    // The strip's "→ X" half is the TARGET for translate but the REPLY language
    // for the Reply chip (paid users). Reply lang can be empty ("from
    // conversation") - fall back to the general target for display, mirroring
    // BubbleService.showLangPicker. The picker/swap edit whichever pref is live.
    private fun readPillTarget(): String =
        if (replyEnabled()) readReplyLang().ifEmpty { readTargetLang() } else readTargetLang()
    private fun writePillTarget(code: String) =
        if (replyEnabled()) writeReplyLang(code) else writeTargetLang(code)

    /** Update the compact "src→tgt" pill on the strip from the current prefs. */
    private fun refreshLangPill() {
        val src = readSourceLang()
        val tgt = readPillTarget()
        val srcShort = if (src == "auto") "Auto" else src.uppercase()
        suggestionStrip?.setLang("$srcShort→${tgt.uppercase()}")
    }

    /** Show the language picker panel in place of the keyboard. */
    private fun openLangPicker() {
        val root = rootView as? android.view.ViewGroup ?: return
        val kv = keyboardView ?: return
        currentInputConnection?.let { commitComposed(it) }
        val labels = BubbleService.LANG_LABELS
        val sources = BubbleService.SOURCE_LANGS.map { code -> code to (labels[code] ?: code) }
        val targets = BubbleService.TARGET_LANGS.map { code -> code to (labels[code] ?: code) }
        val h = kv.height + (suggestionStrip?.height ?: 0)

        // Drop any stale instance from a previous open, then build fresh.
        langPickerView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        val picker = LanguagePickerView(this)
        langPickerView = picker
        picker.onSourcePick = { code ->
            writeSourceLang(code); picker.setSelection(readSourceLang(), readPillTarget()); refreshLangPill()
        }
        picker.onTargetPick = { code ->
            writePillTarget(code); picker.setSelection(readSourceLang(), readPillTarget()); refreshLangPill()
        }
        picker.onSwap = { swapLangs() }
        picker.onClose = { closeLangPicker() }
        picker.backLabel = localized(R.string.ime_back_keyboard)
        picker.configure(
            sources, targets, readSourceLang(), readPillTarget(),
            localized(R.string.ime_lang_from),
            localized(R.string.ime_lang_to),
            localized(R.string.ime_lang_swap),
        )
        root.addView(picker)
        picker.setPanelHeight(if (h > 0) h else kv.height)
        picker.visibility = View.VISIBLE
        emojiPanel?.visibility = View.GONE
        suggestionStrip?.visibility = View.GONE
        kv.visibility = View.GONE
    }

    private fun closeLangPicker() {
        langPickerView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        langPickerView = null
        suggestionStrip?.visibility = View.VISIBLE
        keyboardView?.visibility = View.VISIBLE
    }

    /** Swap source<->target (no-op while source is Auto - it can't be a target). */
    private fun swapLangs() {
        val src = readSourceLang()
        if (src == "auto") return
        val tgt = readPillTarget()
        writeSourceLang(tgt)
        writePillTarget(src)
        langPickerView?.setSelection(readSourceLang(), readPillTarget())
        refreshLangPill()
    }

    // ── Keyboard settings panel (grid icon) ──

    // Reply chip edits the REPLY tone (tk_reply_tone_override); translate edits
    // the general tone (tk_tone_override). Mirrors Dart _translateForBubble.
    private fun toneKey() =
        if (replyEnabled()) "flutter.tk_reply_tone_override" else "flutter.tk_tone_override"
    private fun readTone() = flutterPrefs().getString(toneKey(), "") ?: ""
    private fun writeTone(code: String) =
        flutterPrefs().edit().putString(toneKey(), code).apply()

    /**
     * Tone codes mirror BubbleService.TONE_CODES; labels reuse its strings. The
     * empty option means "Auto" for translate but "Same as translate tone" for
     * the reply tone (matching the app's reply settings).
     */
    private fun toneOptions(): List<Pair<String, String>> = listOf(
        "" to localized(if (replyEnabled()) R.string.bubble_reply_tone_same else R.string.bubble_tone_auto),
        "business" to localized(R.string.bubble_tone_business),
        "casual" to localized(R.string.bubble_tone_casual),
        "formal" to localized(R.string.bubble_tone_formal),
        "polite" to localized(R.string.bubble_tone_polite),
        "technical" to localized(R.string.bubble_tone_technical),
        "neutral" to localized(R.string.bubble_tone_neutral),
    )

    /** Show the keyboard settings panel in place of the keyboard. */
    private fun openSettings() {
        val root = rootView as? android.view.ViewGroup ?: return
        val kv = keyboardView ?: return
        currentInputConnection?.let { commitComposed(it) }
        val h = kv.height + (suggestionStrip?.height ?: 0)

        settingsView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        val view = KeyboardSettingsView(this)
        settingsView = view
        view.onAutocorrectChange = { on -> prefs.edit().putBoolean("autocorrect", on).apply() }
        view.onHapticChange = { on -> prefs.edit().putBoolean("haptic", on).apply() }
        view.onAutocapChange = { on -> prefs.edit().putBoolean("autocap", on).apply() }
        view.onDoubleSpaceChange = { on -> prefs.edit().putBoolean("dot_double_space", on).apply() }
        view.onAppLangPick = { code ->
            // Persist + force the localized() Context to rebuild, then re-run
            // configure() so the WHOLE panel (title, section/toggle/shortcut
            // labels, tone labels) re-localizes live; configure() preserves the
            // scroll position so the rebuild isn't jarring.
            writeUiLocale(code); refreshActionLabels(); refreshLangPill()
            configureSettings(view)
        }
        view.onTonePick = { code -> writeTone(code) }
        view.onBubble = { toggleBubble() }
        view.onHistory = { openHistory() }
        view.onExplain = { explainField() }
        view.onOpenApp = { openAppSettings() }
        view.onClose = { closeSettings() }
        configureSettings(view)
        root.addView(view)
        view.setPanelHeight(if (h > 0) h else kv.height)
        view.visibility = View.VISIBLE
        emojiPanel?.visibility = View.GONE
        suggestionStrip?.visibility = View.GONE
        kv.visibility = View.GONE
    }

    /** (Re)build the settings panel content with the current localized strings. */
    private fun configureSettings(view: KeyboardSettingsView) {
        view.backLabel = localized(R.string.ime_back_keyboard)
        view.configure(
            localized(R.string.ime_settings_title),
            localized(R.string.ime_section_features), localized(R.string.ime_section_options),
            localized(R.string.ime_set_autocorrect), autocorrectEnabled,
            localized(R.string.ime_set_haptic), hapticEnabled,
            localized(R.string.ime_set_autocap), autocapEnabled,
            localized(R.string.ime_set_double_space), dotDoubleSpaceEnabled,
            localized(R.string.ime_set_app_lang), appLangOptions(), readUiLocale(),
            localized(if (replyEnabled()) R.string.bubble_reply_tone else R.string.ime_set_tone),
            toneOptions(), readTone(),
            localized(R.string.ime_open_bubble), bubbleRunning(),
            localized(R.string.ime_history), localized(R.string.ime_explain),
            localized(R.string.ime_set_open_app),
            localized(R.string.ime_on), localized(R.string.ime_off),
        )
    }

    private fun closeSettings() {
        settingsView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        settingsView = null
        suggestionStrip?.visibility = View.VISIBLE
        keyboardView?.visibility = View.VISIBLE
    }

    private fun invokeBubble(method: String, args: Any? = null) {
        TransKeyApp.engine?.let { engine ->
            try {
                io.flutter.plugin.common.MethodChannel(
                    engine.dartExecutor.binaryMessenger, BubbleService.METHOD_CHANNEL,
                ).invokeMethod(method, args)
            } catch (e: Exception) {
                Log.w(TAG, "$method invoke failed", e)
            }
        }
    }

    private fun bringAppToFront() {
        try {
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP,
                    )
                },
            )
        } catch (e: Exception) {
            Log.w(TAG, "bringAppToFront failed", e)
        }
    }

    /** Bring the app's full keyboard-settings screen to the front. */
    private fun openAppSettings() {
        invokeBubble("openKeyboardSettings")
        bringAppToFront()
        closeSettings()
    }

    // ── App UI language (flutter.tk_ui_locale) ──

    /**
     * Before the user explicitly picks an app language, prefer the DEVICE
     * language (if we ship that UI locale) instead of always defaulting to
     * English. Mirrors the Dart LocaleNotifier default so app + keyboard agree.
     */
    private fun deviceUiLocale(): String {
        var lang = resources.configuration.locales.get(0).language
        if (lang == "in") lang = "id" // Java reports Indonesian as legacy "in"
        return if (lang in APP_UI_LANGS) lang else "en"
    }

    private fun readUiLocale(): String {
        val stored = flutterPrefs().getString("flutter.tk_ui_locale", null)
        return if (stored.isNullOrEmpty()) deviceUiLocale() else stored
    }

    private fun writeUiLocale(code: String) {
        flutterPrefs().edit().putString("flutter.tk_ui_locale", code).apply()
        // Update the live app locale too (also re-persists the pref, harmless).
        invokeBubble("setUiLocale", mapOf("code" to code))
        lastUiLocale = null // force the localized() Context to rebuild
    }

    private fun appLangOptions(): List<Pair<String, String>> {
        val labels = BubbleService.LANG_LABELS
        return APP_UI_LANGS.map { code -> code to (labels[code] ?: code) }
    }

    // ── Inline translation history ──

    /** Ask Dart for recent translations, then show them in a panel. */
    private fun openHistory() {
        TransKeyApp.engine?.let { engine ->
            io.flutter.plugin.common.MethodChannel(
                engine.dartExecutor.binaryMessenger, BubbleService.METHOD_CHANNEL,
            ).invokeMethod(
                "getRecentHistory", null,
                object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {
                        val entries = (result as? List<*>)?.mapNotNull { item ->
                            val m = item as? Map<*, *> ?: return@mapNotNull null
                            val t = m["translation"] as? String ?: return@mapNotNull null
                            t to ((m["source"] as? String) ?: "")
                        } ?: emptyList()
                        mainHandler.post { showHistoryPanel(entries) }
                    }
                    override fun error(code: String, msg: String?, details: Any?) {
                        mainHandler.post { showHistoryPanel(emptyList()) }
                    }
                    override fun notImplemented() {
                        mainHandler.post { showHistoryPanel(emptyList()) }
                    }
                },
            )
        }
    }

    private fun showHistoryPanel(entries: List<Pair<String, String>>) {
        val root = rootView as? android.view.ViewGroup ?: return
        val kv = keyboardView ?: return
        val h = kv.height + (suggestionStrip?.height ?: 0)
        // We arrive from the settings panel; drop it without un-hiding the kbd.
        settingsView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        settingsView = null
        historyPanelView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        val panel = HistoryPanelView(this)
        historyPanelView = panel
        panel.onPick = { text -> insertHistory(text) }
        panel.onClose = { closeHistory() }
        panel.backLabel = localized(R.string.ime_back_keyboard)
        panel.configure(
            localized(R.string.ime_history),
            localized(R.string.ime_history_empty),
            entries,
        )
        root.addView(panel)
        panel.setPanelHeight(if (h > 0) h else kv.height)
        panel.visibility = View.VISIBLE
        suggestionStrip?.visibility = View.GONE
        kv.visibility = View.GONE
    }

    private fun insertHistory(text: String) {
        closeHistory()
        currentInputConnection?.commitText(text, 1)
    }

    private fun closeHistory() {
        historyPanelView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        historyPanelView = null
        suggestionStrip?.visibility = View.VISIBLE
        keyboardView?.visibility = View.VISIBLE
    }

    /** Explain the current field text via the floating bubble's popup overlay. */
    private fun explainField() {
        val ic = currentInputConnection
        val text = if (ic != null) fullFieldText(ic).trim() else ""
        if (text.isEmpty()) {
            Toast.makeText(this, localized(R.string.ime_no_text), Toast.LENGTH_SHORT).show()
            return
        }
        // Drive the bubble's own explain flow: it translates with mode=explain
        // and shows the result in its popup over the current app.
        val intent = Intent(this, BubbleService::class.java).apply {
            action = BubbleService.ACTION_TRANSLATE
            putExtra(BubbleService.EXTRA_TEXT, text)
            putExtra(BubbleService.EXTRA_MODE, BubbleService.MODE_EXPLAIN)
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        closeSettings()
    }

    /**
     * Whether the floating bubble is currently up. Mirrors MainActivity.isRunning:
     * the persisted flag is necessary but not sufficient (overlay grant can be
     * revoked, an OEM killer can bypass START_STICKY), so gate on the live service
     * + overlay grant too.
     */
    private fun bubbleRunning(): Boolean {
        val flagOn = flutterPrefs().getBoolean("flutter.tk_bubble_active", false)
        val hasOverlay = android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.M ||
            android.provider.Settings.canDrawOverlays(this)
        return BubbleService.isAlive && flagOn && hasOverlay
    }

    /**
     * Toggle the floating bubble from the grid tile (gradient when ON, like home).
     * Keeps the settings panel open and re-styles the tile to the new state.
     */
    private fun toggleBubble() {
        if (bubbleRunning()) {
            startService(
                Intent(this, BubbleService::class.java).apply { action = BubbleService.ACTION_STOP },
            )
        } else {
            startBubble()
        }
        // Reflect the new on/off state on the tile once the service has settled.
        mainHandler.postDelayed({ settingsView?.let { configureSettings(it) } }, 400)
    }

    /**
     * Start the floating bubble, mirroring the in-app Settings toggle: needs the
     * "draw over other apps" grant first. ACTION_START -> BubbleService.showBubble
     * which also persists tk_bubble_active so the app toggle stays honest.
     */
    private fun startBubble() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M &&
            !android.provider.Settings.canDrawOverlays(this)
        ) {
            // No overlay permission yet - send the user to grant it. An IME can't
            // host the system dialog, so open the per-app overlay settings page.
            try {
                startActivity(
                    Intent(
                        android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        android.net.Uri.parse("package:$packageName"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (e: Exception) {
                Log.w(TAG, "overlay permission request failed", e)
            }
            closeSettings()
            return
        }
        val intent = Intent(this, BubbleService::class.java).apply {
            action = BubbleService.ACTION_START
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun isNumericClass(info: EditorInfo): Boolean {
        val cls = info.inputType and InputType.TYPE_MASK_CLASS
        return cls == InputType.TYPE_CLASS_NUMBER ||
            cls == InputType.TYPE_CLASS_PHONE ||
            cls == InputType.TYPE_CLASS_DATETIME
    }

    private fun applyShiftState() {
        letterKeyboardFor(mode)?.isShifted = isShifted
        qwertyKeyboard?.isShifted = isShifted
        (keyboardView as? GboardKeyboardView)?.shiftLocked = (shift == Shift.LOCK)
        keyboardView?.invalidateAllKeys()
    }

    /**
     * Set a one-shot shift when the caret sits at a sentence start (field start,
     * or after . ! ? / newline + space). Only promotes NONE -> ONESHOT so it
     * never fights an explicit shift or caps-lock the user set.
     */
    private fun maybeAutoCap() {
        // Korean/Arabic/Japanese have no capital case; for KO a stray one-shot
        // Shift would wrongly produce a tense jamo, so never auto-cap there.
        if (mode == Mode.KO || mode == Mode.KO_CHUN || mode == Mode.AR ||
            mode == Mode.JA || mode == Mode.JA_FLICK || mode == Mode.ZH
        ) return
        if (!autocapEnabled || shift != Shift.NONE) return
        val ic = currentInputConnection ?: return
        val ei = currentInputEditorInfo ?: return
        if (!isAutoCapField(ei)) return
        if (shouldCapNext(ic)) {
            shift = Shift.ONESHOT
            applyShiftState()
        }
    }

    /** Auto-cap only for plain text fields (never password / email / URI). */
    private fun isAutoCapField(ei: EditorInfo): Boolean {
        val cls = ei.inputType and InputType.TYPE_MASK_CLASS
        if (cls != InputType.TYPE_CLASS_TEXT) return false
        val v = ei.inputType and InputType.TYPE_MASK_VARIATION
        return v != InputType.TYPE_TEXT_VARIATION_PASSWORD &&
            v != InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD &&
            v != InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD &&
            v != InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS &&
            v != InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS &&
            v != InputType.TYPE_TEXT_VARIATION_URI
    }

    /** True at a sentence boundary: empty field, or caret right after ". ", "! ",
     *  "? " or a newline. Caret must be at a word start (preceding char a space
     *  or newline) so mid-word typing never re-capitalizes. */
    private fun shouldCapNext(ic: android.view.inputmethod.InputConnection): Boolean {
        val before = ic.getTextBeforeCursor(4, 0) ?: return true
        if (before.isEmpty()) return true
        val last = before.last()
        if (last == '\n') return true
        if (last != ' ') return false // mid-word: don't capitalize
        val trimmed = before.trimEnd(' ')
        if (trimmed.isEmpty()) return true // only spaces back to the start
        val c = trimmed.last()
        return c == '.' || c == '!' || c == '?' || c == '\n'
    }

    /** Top letter row long-press -> its corner number; null for other keys. */
    private fun numberForLongPress(code: Int): String? {
        if (code <= 0) return null
        return when (code.toChar().lowercaseChar()) {
            'q' -> "1"; 'w' -> "2"; 'e' -> "3"; 'r' -> "4"; 't' -> "5"
            'y' -> "6"; 'u' -> "7"; 'i' -> "8"; 'o' -> "9"; 'p' -> "0"
            else -> null
        }
    }

    /** Move the caret one step left (dir<0) or right (dir>0) - space-bar swipe. */
    private fun moveCursor(dir: Int) {
        val ic = currentInputConnection ?: return
        if (telex.hasComposingText) commitComposed(ic)
        ic.finishComposingText()
        val code = if (dir > 0) KeyEvent.KEYCODE_DPAD_RIGHT else KeyEvent.KEYCODE_DPAD_LEFT
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
    }

    private fun updateShiftIcon() = applyShiftState()

    private fun updateLanguageKeyStyle() {
        // The globe key renders as an icon only (no EN/VI text); the active
        // language is shown on the space bar (Gboard pattern). Just repaint.
        keyboardView?.invalidateAllKeys()
    }

    private fun updateLangKeyLabel() {
        val keys = qwertyKeyboard?.keys ?: return
        val target = keys.firstOrNull { it.codes.firstOrNull() == KEYCODE_LANG_SWITCH }
        target?.label = if (mode == Mode.VI) "VI" else "EN"
        keyboardView?.invalidateAllKeys()
    }

    // ── Unused listener callbacks (required by KeyboardView interface) ──
    override fun onPress(primaryCode: Int) {
        // Subtle key-tap haptic. Without this the keyboard feels "dead"
        // vs iOS, which is the #1 cause of users reporting unfamiliar
        // typing even when the visual layout matches. Opt-out via settings.
        if (hapticEnabled) {
            keyboardView?.performHapticFeedback(
                android.view.HapticFeedbackConstants.KEYBOARD_TAP,
                android.view.HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING,
            )
        }
    }
    override fun onRelease(primaryCode: Int) {}
    override fun onText(text: CharSequence?) {
        if (text == null) return
        currentInputConnection?.commitText(text, 1)
    }
    override fun swipeLeft() {}
    override fun swipeRight() {}
    override fun swipeDown() {}
    override fun swipeUp() {}

    companion object {
        private const val TAG = "TransKeyIME"

        // Feature-button request ids. A high base keeps them clear of the
        // bubble's own small counter (routing is by registry membership, so
        // this is belt-and-suspenders against any number overlap).
        private val imeReqSeq = java.util.concurrent.atomic.AtomicLong(1_000_000_000L)
        // Upper bound when reading/replacing the whole field (chars).
        private const val MAX_FIELD = 100_000

        // App UI languages offered in the settings picker (writes tk_ui_locale);
        // mirrors the app's l10n locales. Labels come from BubbleService.LANG_LABELS.
        private val APP_UI_LANGS = listOf(
            "en", "vi", "ar", "de", "es", "fr", "id", "it", "ja", "ko", "pt", "ru", "th", "zh",
        )

        // Keycodes that don't map to printable characters. Picked to
        // avoid colliding with Unicode codepoints (negative for "special",
        // positive printable chars get committed as themselves).
        const val KEYCODE_SHIFT = Keyboard.KEYCODE_SHIFT             // -1
        const val KEYCODE_DELETE = Keyboard.KEYCODE_DELETE           // -5
        const val KEYCODE_ENTER = -4
        const val KEYCODE_SPACE = 32                                  // literal ' '
        const val KEYCODE_LANG_SWITCH = -101
        const val KEYCODE_SYMBOLS = -201
        const val KEYCODE_EMOJI = -202
        const val KEYCODE_SYMBOLS2 = -203
        const val KEYCODE_LANG_GLOBE = -301
        const val KEYCODE_KANA_MOD = -210 // JA flick 小゛゜ (dakuten/small cycle)
        const val KEYCODE_KANA_TOGGLE = -211 // JA flick カナ/かな toggle
    }

    init {
        Log.d(TAG, "TransKeyIME service constructed")
    }
}
