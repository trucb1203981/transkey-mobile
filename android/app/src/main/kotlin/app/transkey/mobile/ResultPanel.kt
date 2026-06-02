package app.transkey.mobile

import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView

/** Per-mode tab in the result panel header: icon column with label below. */
data class PanelModeTab(
    val container: LinearLayout,
    val icon: ImageView,
    val label: TextView,
)

/**
 * Holder for the view + state references that the result panel needs to
 * keep around between show/hide cycles. Previously this state lived as
 * 13 loose `private var panel*` fields on BubbleService — grouping them
 * here keeps related lifecycle (`removeResultPanel()` nulls all of them)
 * in one place and sets up the eventual full extraction of
 * `showResultPanel` / `showResult` / `showError` into a dedicated
 * controller class.
 *
 * Mutable fields only — this is a state bag, not a behaviour class.
 * Methods (showResultPanel et al) still live on BubbleService for now;
 * moving them requires deciding how to thread the controller's host
 * dependencies (`windowManager`, `prefs`, `refreshLocale()`, the
 * `currentMode` / `currentTargetLang` source-of-truth, the Flutter
 * MethodChannel callbacks) which is out of scope for this commit.
 */
class ResultPanel {
    var view: View? = null

    // Resize / fullscreen state for the result panel. When `fullscreen`
    // is true the panel grows to (almost) the full screen; otherwise
    // `heightPx > 0` then pins a custom height.
    var heightPx: Int = 0
    var fullscreen: Boolean = false
    var fullscreenBtn: ImageView? = null
    var contentScroll: ScrollView? = null

    var sourceExpanded: Boolean = false
    var sourceToggle: TextView? = null
    var source: TextView? = null
    var output: TextView? = null
    var romanization: TextView? = null
    var suggestionsLabel: TextView? = null
    var suggestionsContainer: LinearLayout? = null
    var status: TextView? = null
    var copyBtn: View? = null
    var ttsBtn: TextView? = null

    // Header chips + spinner
    var langChip: TextView? = null
    var sourceLangChip: TextView? = null
    var detectedLangTv: TextView? = null
    var toneChip: ImageView? = null
    var loadingSpinner: ProgressBar? = null

    // Per-mode tabs (Translate / Reply / Summarize / Explain / Refine)
    val modeButtons: MutableMap<String, PanelModeTab> = mutableMapOf()
}
