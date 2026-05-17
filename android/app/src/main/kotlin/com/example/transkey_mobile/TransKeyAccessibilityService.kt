package com.example.transkey_mobile

import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Lets TransKey paste a reply directly into the focused text field of any app.
 *
 * Requires the user to enable "TransKey" in Settings → Accessibility.
 * We do NOT cache nodes between events; we re-query `rootInActiveWindow` at
 * action time so a stale node doesn't crash performAction.
 */
class TransKeyAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "TransKeyA11y"

        @Volatile
        var instance: TransKeyAccessibilityService? = null

        fun isAvailable(): Boolean = instance != null

        // Sentence-ending punctuation (Latin + CJK + a few others) used by
        // looksLikeContent() to keep short-but-meaningful nodes like "Tnx!"
        // while dropping short button labels like "OK", "Cancel".
        private val PUNCT_CHARS = setOf(
            '.', '!', '?', '…', '。', '！', '？', '،', ';', '；', ':', '：',
        )

        /**
         * Max age of a cached text-selection event we'll still trust.
         * 15 s covers the realistic "highlight → reach for the bubble"
         * delay without letting an abandoned selection from earlier in
         * the session leak into a fresh translation request.
         */
        private const val CACHE_TTL_MS = 15_000L

        /**
         * Hard cap on findSelectedTextRecursive depth — each level is a
         * Binder IPC, deep trees were the source of the ~2 s bubble-tap
         * lag. 20 covers any real EditText / TextView nesting.
         */
        private const val MAX_TREE_DEPTH = 20
    }

    /**
     * Last-seen text selection (full text of the node + start/end indices),
     * plus the wall-clock timestamp when we observed it. Used as a fallback
     * inside [getSelectedText] for the common case where the user highlights
     * text, taps the floating bubble, and the source app dismisses the
     * selection between "user tapped" and "we queried rootInActiveWindow".
     * Without this cache, getSelectedText() would return null even though
     * the user clearly DID have something selected a moment ago.
     */
    @Volatile private var cachedSelectionText: String? = null
    @Volatile private var cachedSelectionTimestampMs: Long = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Cache live text-selection events so a subsequent tap on the
        // bubble (which can race the source app dismissing the selection)
        // can still recover what was just highlighted.
        if (event?.eventType != AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED) return

        // Pre-flight on the event itself BEFORE asking for source — every
        // node lookup costs an IPC round-trip and this listener fires
        // continuously while the user types in any EditText (one event
        // per character). The event already carries `fromIndex` /
        // `toIndex`; if they're equal it's a cursor move, not a real
        // selection, and we skip the IPC entirely. Drops accessibility
        // CPU cost during typing roughly to zero.
        val from = event.fromIndex
        val to   = event.toIndex
        if (from < 0 || to <= from) return

        val source = event.source ?: return
        try {
            val full = source.text?.toString() ?: return
            if (to > full.length) return
            val sel = full.substring(from, to).trim()
            if (sel.isNotEmpty()) {
                cachedSelectionText = sel
                cachedSelectionTimestampMs = System.currentTimeMillis()
            }
        } finally {
            try { source.recycle() } catch (_: Exception) {}
        }
    }

    override fun onInterrupt() {}

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    /**
     * Replace text in the currently focused editable field. Tries three
     * strategies in order — different apps respond to different actions:
     *
     *   1. ACTION_SET_TEXT alone — works for most native EditText.
     *   2. ACTION_FOCUS + ACTION_SET_TEXT — some apps lose input focus when an
     *      overlay appears (even if FLAG_NOT_FOCUSABLE) and need an explicit
     *      re-focus before they accept SET_TEXT.
     *   3. Clipboard + ACTION_SET_SELECTION (select all) + ACTION_PASTE —
     *      fallback for WebView, Jetpack Compose TextField, and React Native
     *      TextInput, which silently no-op ACTION_SET_TEXT.
     *
     * Returns true if ANY strategy succeeded.
     */
    fun replaceFocusedText(text: String): Boolean {
        val node = findFocusedEditable() ?: run {
            Log.w(TAG, "replaceFocusedText: no focused editable node found")
            return false
        }

        val setTextArgs = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                text,
            )
        }

        // Strategy 1
        if (safePerform(node, AccessibilityNodeInfo.ACTION_SET_TEXT, setTextArgs)) {
            Log.d(TAG, "paste: SET_TEXT ok")
            return true
        }

        // Strategy 2 — refresh + focus + retry
        if (node.refresh()) {
            if (safePerform(node, AccessibilityNodeInfo.ACTION_FOCUS, null)) {
                if (safePerform(node, AccessibilityNodeInfo.ACTION_SET_TEXT, setTextArgs)) {
                    Log.d(TAG, "paste: FOCUS+SET_TEXT ok")
                    return true
                }
            }
        }

        // Strategy 3 — clipboard + select all + PASTE
        // ACTION_PASTE is supported by AbsListView/EditText/WebView consistently,
        // unlike ACTION_SET_TEXT which is opt-in per widget.
        try {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("TransKey", text))
        } catch (e: Exception) {
            Log.w(TAG, "paste: clipboard set failed: ${e.message}")
            return false
        }

        // Select all existing text so PASTE replaces, doesn't append.
        val existing = node.text?.length ?: 0
        if (existing > 0) {
            val selectArgs = Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, 0)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, existing)
            }
            safePerform(node, AccessibilityNodeInfo.ACTION_SET_SELECTION, selectArgs)
        }

        val pasted = safePerform(node, AccessibilityNodeInfo.ACTION_PASTE, null)
        Log.d(TAG, "paste: CLIPBOARD+PASTE result=$pasted")
        return pasted
    }

    /**
     * Read current text from the focused editable field, if any.
     */
    fun readFocusedText(): String? {
        val node = findFocusedEditable() ?: return null
        return node.text?.toString()
    }

    private fun findFocusedEditable(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        // Prefer the input-focused node (where the cursor is). Some apps mark
        // a non-editable ancestor as input-focused — climb up until we find
        // an editable, or fall back to a recursive search.
        val direct = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (direct?.isEditable == true) return direct
        return findFirstEditable(root)
    }

    private fun findFirstEditable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isEditable && node.isFocused) return node
        for (i in 0 until node.childCount) {
            val result = findFirstEditable(node.getChild(i))
            if (result != null) return result
        }
        return null
    }

    private fun safePerform(
        node: AccessibilityNodeInfo,
        action: Int,
        args: Bundle?,
    ): Boolean {
        return try {
            node.performAction(action, args)
        } catch (e: Exception) {
            Log.w(TAG, "performAction $action failed: ${e.message}")
            false
        }
    }

    /**
     * Read ALL visible text from the currently-active app window via the
     * accessibility node tree — covers apps that disable text selection
     * (banking, anti-copy chat apps, anti-piracy readers) as long as they
     * render text via standard TextView / EditText / WebView. Will NOT
     * pick up canvas/OpenGL game UI, image-only content, or apps that
     * disable accessibility entirely (those need OCR / Phase 2).
     *
     * De-dupes via LinkedHashSet so nested views (parent View + child
     * TextView reporting the same string) only contribute once. Result is
     * capped at 5000 chars to match the translate input limit.
     *
     * Returns null if a11y service is not connected OR if the active
     * window has no readable text at all.
     */
    fun getScreenText(): String? {
        val root = rootInActiveWindow ?: return null
        val ownPackage = packageName
        val collected = LinkedHashSet<String>()
        collectVisibleText(root, ownPackage, collected)
        if (collected.isEmpty()) return null
        val merged = collected.joinToString("\n").trim()
        return merged.take(5000).takeIf { it.isNotEmpty() }
    }

    private fun collectVisibleText(
        node: AccessibilityNodeInfo?,
        ownPackage: CharSequence?,
        out: LinkedHashSet<String>,
    ) {
        if (node == null) return
        // Don't echo back our own bubble / pickers if they happen to be in
        // the active window when called.
        if (node.packageName != null && node.packageName == ownPackage) return

        // Skip the entire subtree of "UI chrome" containers — toolbars,
        // tab bars, bottom navigation. The labels they hold are app UI
        // ("Home", "Settings", "Search"), not content the user wants to
        // translate; pulling them in just makes the result picker noisy
        // and forces the user to manually trim.
        if (isChromeContainer(node.className)) return

        // Prefer node.text, fall back to contentDescription so we still pick
        // up text the developer attached as a11y description instead of as
        // visible text (common in some compose / RN apps).
        val text = node.text?.toString()?.trim()
        val desc = node.contentDescription?.toString()?.trim()
        val value = when {
            !text.isNullOrEmpty() -> text
            !desc.isNullOrEmpty() -> desc
            else -> null
        }
        if (value != null && looksLikeContent(value, node)) out.add(value)

        for (i in 0 until node.childCount) {
            collectVisibleText(node.getChild(i), ownPackage, out)
        }
    }

    /**
     * Whitelist of substrings that mark a node as part of the surrounding
     * app frame rather than the article / chat / document the user is
     * actually reading. Skipping the WHOLE subtree of these drops nav
     * labels in one pass instead of trying to filter each text node
     * individually.
     */
    private fun isChromeContainer(className: CharSequence?): Boolean {
        val cls = className?.toString() ?: return false
        return cls.contains("Toolbar", ignoreCase = true) ||
            cls.contains("ActionBar", ignoreCase = true) ||
            cls.contains("TabLayout", ignoreCase = true) ||
            cls.contains("TabBar", ignoreCase = true) ||
            cls.contains("BottomNavigation", ignoreCase = true) ||
            cls.contains("BottomBar", ignoreCase = true) ||
            cls.contains("NavigationBar", ignoreCase = true) ||
            cls.contains("AppBar", ignoreCase = true)
    }

    /**
     * Distinguish content text from UI labels. Heuristics tuned for "user
     * is reading something" — chat message, article, doc paragraph:
     *
     *  - Long enough on its own (≥ 8 chars), or
     *  - Multi-word (has whitespace), or
     *  - Ends with sentence punctuation (Latin or CJK).
     *
     * Buttons / tab labels / chips are usually 1-3 short words without
     * punctuation, so they get filtered out without us needing per-class
     * rules. Short content (one-word reply "ok") is the false-negative
     * we accept — user can fall back to Type or paste.
     */
    private fun looksLikeContent(text: String, node: AccessibilityNodeInfo): Boolean {
        // Editable fields are almost always real content (the user's draft
        // message etc), keep regardless of length.
        if (node.isEditable) return true

        val trimmed = text.trim()
        if (trimmed.length >= 8) return true
        if (trimmed.contains(' ') || trimmed.contains('\t') || trimmed.contains('\n')) return true
        if (trimmed.any { it in PUNCT_CHARS }) return true
        // CJK scripts are information-dense — a 3-char Japanese / Chinese
        // / Korean line carries as much meaning as 8-10 chars of Latin.
        // Without this exception the 8-char threshold silently drops most
        // CJK content (chat bubbles, headlines, manga speech bubbles).
        if (trimmed.any { isCjk(it) }) return true
        return false
    }

    private fun isCjk(ch: Char): Boolean {
        val code = ch.code
        return (code in 0x4E00..0x9FFF) ||   // CJK Unified Ideographs
            (code in 0x3040..0x309F) ||      // Hiragana
            (code in 0x30A0..0x30FF) ||      // Katakana
            (code in 0xAC00..0xD7AF) ||      // Hangul Syllables
            (code in 0x3400..0x4DBF) ||      // CJK Ext A
            (code in 0xFF66..0xFF9F)         // Halfwidth Katakana
    }

    /**
     * Returns the currently selected text from any view in the active window
     * (TextView, EditText, WebView, etc) — works even for apps that block
     * clipboard copy (LinkedIn, banking apps).
     *
     * Falls back to whole text of the first node with non-empty text if no
     * actual selection range is present but a node is marked selected.
     */
    fun getSelectedText(): String? {
        // Order reversed (cache first, live tree second) for latency.
        // The live-tree walk is a recursive cross-process IPC over the
        // entire active window's node tree — on chat apps and webviews
        // it routinely takes 1-2 s because every node.getChild() hops
        // the Binder. Users were reporting "bubble tap delays ~2 s
        // before the picker opens" because we ran this synchronously on
        // every bubble tap. The accessibility-event cache is almost
        // always fresh (we update it the instant the user highlights
        // anything), so it covers the common case at ~0 ms. Falling
        // back to the live tree only when cache is empty preserves the
        // edge-case correctness for apps whose widgets don't emit
        // TYPE_VIEW_TEXT_SELECTION_CHANGED events.
        val cached = cachedSelectionText
        if (cached != null) {
            if (System.currentTimeMillis() - cachedSelectionTimestampMs <= CACHE_TTL_MS) {
                return cached
            }
            cachedSelectionText = null
        }

        return rootInActiveWindow?.let { findSelectedTextRecursive(it, depth = 0) }
    }

    /**
     * Mark the cached selection as consumed so a second bubble tap doesn't
     * translate the same stale highlight. Call right after we've actually
     * used the selection to start a translation.
     */
    fun consumeCachedSelection() {
        cachedSelectionText = null
        cachedSelectionTimestampMs = 0L
    }

    /**
     * Perform ACTION_COPY on the best target node so the system's own
     * "Copy" handler runs — that's the only reliable way to capture a
     * MULTI-NODE selection in Chrome WebView (and most webview-based
     * apps), because [TYPE_VIEW_TEXT_SELECTION_CHANGED] events there
     * fire per text run, so our cache only retains the last word.
     *
     * Routing priority for the target node:
     *   1. The node currently holding INPUT focus (real EditText / form
     *      field — usually owns the selection authoritatively).
     *   2. Otherwise, the first node in the tree that has a real
     *      selection range (textSelectionStart < textSelectionEnd).
     *   3. Otherwise, fall back to the active window's root — Chrome
     *      WebView usually accepts ACTION_COPY at the root and forwards
     *      it to the renderer's current selection.
     *
     * Returns true if the system accepted the copy action — caller
     * should then read clipboard after a brief settle (~100-200 ms)
     * for the new clip text to land.
     */
    fun copyCurrentSelection(): Boolean {
        val root = rootInActiveWindow ?: return false
        val target =
            root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                ?: findFirstSelectionRangeNode(root, depth = 0)
                ?: root
        return try {
            target.performAction(AccessibilityNodeInfo.ACTION_COPY)
        } catch (error: Exception) {
            Log.w(TAG, "ACTION_COPY failed: ${error.message}")
            false
        }
    }

    private fun findFirstSelectionRangeNode(
        node: AccessibilityNodeInfo?,
        depth: Int,
    ): AccessibilityNodeInfo? {
        if (node == null || depth > MAX_TREE_DEPTH) return null
        val start = node.textSelectionStart
        val end = node.textSelectionEnd
        if (start in 0 until end) return node
        for (i in 0 until node.childCount) {
            findFirstSelectionRangeNode(node.getChild(i), depth + 1)?.let { return it }
        }
        return null
    }

    private fun findSelectedTextRecursive(node: AccessibilityNodeInfo?, depth: Int): String? {
        if (node == null) return null
        // Depth cap: every recursion level costs at least one Binder
        // round-trip (childCount + getChild). Real selectable widgets
        // are well under 20 levels deep — beyond that we're usually
        // walking scroll containers, list adapters, and webview
        // shadows that we won't find a selection in anyway. Hard cap
        // turns a worst-case 2 s walk into a worst-case <200 ms one.
        if (depth > MAX_TREE_DEPTH) return null
        val text = node.text?.toString()
        if (!text.isNullOrEmpty()) {
            val start = node.textSelectionStart
            val end = node.textSelectionEnd
            if (start in 0 until end && end <= text.length) {
                val selected = text.substring(start, end).trim()
                if (selected.isNotEmpty()) return selected
            }
        }
        for (i in 0 until node.childCount) {
            val result = findSelectedTextRecursive(node.getChild(i), depth + 1)
            if (result != null) return result
        }
        return null
    }
}
