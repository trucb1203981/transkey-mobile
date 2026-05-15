package com.example.transkey_mobile

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
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
     * Replace text in the currently focused editable field across the active
     * window. Returns true on success.
     */
    fun replaceFocusedText(text: String): Boolean {
        val node = findFocusedEditable() ?: return false
        return try {
            val args = Bundle().apply {
                putCharSequence(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                    text,
                )
            }
            node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        } catch (e: Exception) {
            false
        }
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
        val node = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return null
        return if (node.isEditable) node else null
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
