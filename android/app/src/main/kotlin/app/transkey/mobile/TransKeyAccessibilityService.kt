package app.transkey.mobile

import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Accessibility-mediated text-injection surface for TransKey.
 *
 * Per the feature spec (Translate / Summary / Refine / Explain / Reply),
 * source text is ALWAYS captured via explicit user actions — Copy + tap
 * bubble, OCR, Region select, system Share, or ACTION_PROCESS_TEXT menu —
 * never via accessibility selection events. The single legitimate use of
 * accessibility is the OUTPUT side of Reply: paste the generated reply
 * straight into the currently-focused text field so the user doesn't have
 * to switch apps and long-press > paste. [readFocusedText] is a small
 * helper for pre-filling the reply context with the user's existing draft.
 *
 * We do NOT cache accessibility nodes between events; every action re-
 * queries `rootInActiveWindow` so a stale node doesn't crash performAction.
 */
class TransKeyAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "TransKeyA11y"

        @Volatile
        var instance: TransKeyAccessibilityService? = null

        fun isAvailable(): Boolean = instance != null
    }

    /**
     * No-op. This service is only invoked via direct calls
     * (replaceFocusedText / readFocusedText) from the Reply flow; the
     * XML config subscribes to the minimum event type to keep the system
     * from waking us on every focus / scroll / text change.
     */
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

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
     *   2. ACTION_FOCUS + ACTION_SET_TEXT — some apps lose input focus
     *      when an overlay appears (even FLAG_NOT_FOCUSABLE) and need an
     *      explicit re-focus before they accept SET_TEXT.
     *   3. Clipboard + ACTION_SET_SELECTION (select all) + ACTION_PASTE —
     *      fallback for WebView, Jetpack Compose TextField, and React
     *      Native TextInput, which silently no-op ACTION_SET_TEXT.
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

        if (safePerform(node, AccessibilityNodeInfo.ACTION_SET_TEXT, setTextArgs)) {
            Log.d(TAG, "paste: SET_TEXT ok")
            return true
        }

        if (node.refresh()) {
            if (safePerform(node, AccessibilityNodeInfo.ACTION_FOCUS, null)) {
                if (safePerform(node, AccessibilityNodeInfo.ACTION_SET_TEXT, setTextArgs)) {
                    Log.d(TAG, "paste: FOCUS+SET_TEXT ok")
                    return true
                }
            }
        }

        // Strategy 3 — clipboard + select all + PASTE.
        // ACTION_PASTE is widely supported, unlike opt-in ACTION_SET_TEXT.
        try {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("TransKey", text))
        } catch (e: Exception) {
            Log.w(TAG, "paste: clipboard set failed: ${e.message}")
            return false
        }

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
     * Read current text from the focused editable field, if any. Used to
     * pre-fill the input picker with the user's draft reply context.
     */
    fun readFocusedText(): String? {
        val node = findFocusedEditable() ?: return null
        return node.text?.toString()
    }

    private fun findFocusedEditable(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        val direct = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (direct?.isEditable == true) { root.recycle(); return direct }
        val found = findFirstEditable(root)
        root.recycle()
        return found
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

}
