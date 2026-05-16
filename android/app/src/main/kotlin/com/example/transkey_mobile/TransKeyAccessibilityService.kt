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
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No tracking needed — we look up the focused node on demand.
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
     * Returns the currently selected text from any view in the active window
     * (TextView, EditText, WebView, etc) — works even for apps that block
     * clipboard copy (LinkedIn, banking apps).
     *
     * Falls back to whole text of the first node with non-empty text if no
     * actual selection range is present but a node is marked selected.
     */
    fun getSelectedText(): String? {
        val root = rootInActiveWindow ?: return null
        return findSelectedTextRecursive(root)
    }

    private fun findSelectedTextRecursive(node: AccessibilityNodeInfo?): String? {
        if (node == null) return null
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
            val result = findSelectedTextRecursive(node.getChild(i))
            if (result != null) return result
        }
        return null
    }
}
