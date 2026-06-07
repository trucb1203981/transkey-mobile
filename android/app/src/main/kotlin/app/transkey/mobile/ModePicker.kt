package app.transkey.mobile

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import app.transkey.mobile.BubbleService.Companion.ACTION_READ_CLIPBOARD
import app.transkey.mobile.BubbleService.Companion.ALL_MODES
import app.transkey.mobile.BubbleService.Companion.EXTRA_MODE
// LANG_LABELS replaced by getEffectiveLangLabels() so the result-panel
// chip + mode-picker header render the server-catalog label (e.g.
// "Filipino" instead of falling back to "FIL") when the admin enables
// a language that isn't in the hardcoded set.
import app.transkey.mobile.BubbleService.Companion.MODE_EXPLAIN
import app.transkey.mobile.BubbleService.Companion.MODE_REFINE
import app.transkey.mobile.BubbleService.Companion.MODE_SUBTITLE
import app.transkey.mobile.BubbleService.Companion.MODE_SUMMARIZE
import app.transkey.mobile.BubbleService.Companion.MODE_TRANSLATE

/**
 * Plan-gate lookup for the bubble's feature entries. Each mode that
 * costs money on at least one tier has a SharedPreferences key mirrored
 * by `featuresProvider.dart`. `MODE_TRANSLATE` is always free → null.
 * The display name is what we pass to `openFeatureUpsell` so the
 * upgrade-nudge sheet's headline matches the picker label the user
 * just tapped.
 */
internal data class ModeGate(val prefsKey: String, val displayName: String)

internal fun modeGateFor(mode: String): ModeGate? = when (mode) {
    MODE_SUMMARIZE -> ModeGate("tk_feature_summarize", "Summarize")
    MODE_EXPLAIN   -> ModeGate("tk_feature_explain",   "Explain")
    MODE_REFINE    -> ModeGate("tk_feature_refine",    "Refine")
    else           -> null  // MODE_TRANSLATE is always available
}

/**
 * Bubble's primary action menu — shown when the user taps the floating
 * bubble. Renders title + source/target chips + 5 feature buttons +
 * alternative-input rows (type / voice / scan screen / region scan) +
 * an optional "Last result" shortcut.
 *
 * Also owns the shared `buildPickerLayoutParams` helper — every
 * full-screen-modal picker in BubbleService uses the same layout params
 * (MATCH_PARENT × MATCH_PARENT TYPE_APPLICATION_OVERLAY FLAG_NOT_FOCUSABLE)
 * so the helper lives next to its first caller.
 *
 * `onTranslateModePicked` is the dispatch path that runs after the user
 * picks a feature — it routes through ShareActivity (the only component
 * allowed to read primaryClip on Android 10+).
 */
internal fun BubbleService.showModePicker() {
    ensureWindowManager()
    // Pick up any recent in-app UI language change so the picker labels
    // are rendered in the locale the user actually wants.
    refreshLocale()
    // Cancel any pending half-hide and bring the bubble fully on-screen
    // so the picker doesn't anchor to an off-screen origin.
    cancelBubbleHalfHide()
    snapBubbleToEdge(resources.displayMetrics.density, halfHidden = false)

    val style = BubbleStyle.of(this)
    val dp = style.dp
    val isDark = style.isDark
    val bg = style.bg
    val textCol = style.text
    val mutedCol = style.muted
    val accent = style.accent

    // Semi-transparent backdrop — tap outside card to dismiss
    val backdrop = FrameLayout(this).apply {
        setBackgroundColor(Palette.BACKDROP_DIM)
        setOnClickListener { hideModePicker() }
    }

    val card = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = GradientDrawable().apply { setColor(bg); cornerRadius = 20 * dp }
        elevation = 20 * dp
        setPadding((18 * dp).toInt(), (16 * dp).toInt(), (18 * dp).toInt(), (18 * dp).toInt())
        isClickable = true
    }

    card.addView(TextView(this).apply {
        text = localized(R.string.bubble_choose_action)
        setTextColor(textCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
        setPadding(0, 0, 0, (8 * dp).toInt())
    })
    // Amber tip card — surfaces the two reliable input paths up front.
    // The Android text-selection action menu's PROCESS_TEXT entries get
    // stripped by many apps (Chrome / Facebook / WebView / Compose
    // custom toolbars), so we cannot rely on the system menu being the
    // discovery path. The dim 11sp subtitle this replaced was easy to
    // overlook — same amber palette as the result-panel a11y warning
    // so the visual language is consistent.
    val tipBg = if (isDark) Color.parseColor("#3A2E10") else Color.parseColor("#FFF6D6")
    val tipFg = if (isDark) Color.parseColor("#FFD86E") else Color.parseColor("#7A5A00")
    card.addView(TextView(this).apply {
        text = "💡  " + localized(R.string.bubble_need_text)
        setTextColor(tipFg)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        typeface = Typeface.DEFAULT_BOLD
        setLineSpacing(2 * dp, 1f)
        background = GradientDrawable().apply {
            setColor(tipBg)
            cornerRadius = 10 * dp
        }
        setPadding(
            (10 * dp).toInt(), (8 * dp).toInt(),
            (10 * dp).toInt(), (8 * dp).toInt(),
        )
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = (2 * dp).toInt(); bottomMargin = (10 * dp).toInt() }
    })

    // Source → Target language chips. Each side is independently
    // tappable so the user can change either direction without first
    // opening the result panel. Without this the user could only see
    // the source-lang setting from inside the bubble; the target was
    // hidden behind a translate-first workflow.
    val pickedSource = readSourceLang()
    val pickedTarget = readTargetLang()
    val labels = getEffectiveLangLabels()
    val sourceLabel = if (pickedSource == "auto") "Auto"
        else (labels[pickedSource] ?: pickedSource.uppercase())
    val targetLabel = labels[pickedTarget] ?: pickedTarget.uppercase()
    val chipBgColor = Color.parseColor(if (isDark) "#2A2A40" else "#F0EFFF")
    fun langChip(label: String, onTap: () -> Unit): TextView = TextView(this).apply {
        text = label
        setTextColor(accent)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(
            (12 * dp).toInt(), (6 * dp).toInt(),
            (12 * dp).toInt(), (6 * dp).toInt(),
        )
        background = GradientDrawable().apply {
            setColor(chipBgColor)
            cornerRadius = 12 * dp
        }
        isClickable = true
        isFocusable = true
        setOnClickListener {
            hideModePicker()
            onTap()
        }
    }
    val langRow = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { bottomMargin = (12 * dp).toInt() }
    }
    langRow.addView(langChip(sourceLabel) { showSourceLangPicker() })
    langRow.addView(TextView(this).apply {
        text = "  →  "
        setTextColor(mutedCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        gravity = Gravity.CENTER
    })
    langRow.addView(langChip(targetLabel) { showLangPicker() })
    card.addView(langRow)

    // 5 feature buttons — matches the in-app feature-button row in
    // home_screen.dart: icon on top, label below, first action gets a
    // "primary" purple fill so it stands out.
    val modesRow = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
    }
    ALL_MODES.forEachIndexed { index, mode ->
        val isPrimary = mode == MODE_TRANSLATE
        val subduedBg = if (isDark) "#2A2A40" else "#F0EFFF"
        // Plan gate per mode: TRANSLATE is always free; the other 4
        // (SUMMARIZE / EXPLAIN / REFINE / REPLY) are mirrored from
        // /features into SharedPreferences. Locked → dimmed column +
        // muted icon/label + tap opens the upgrade-nudge sheet instead
        // of running the action (server still 403s as a backstop).
        val gate = modeGateFor(mode)
        val isLocked = gate != null && !readFeatureEnabled(gate.prefsKey)
        val fgColor = when {
            isPrimary -> Color.WHITE
            isLocked  -> accent
            else      -> accent
        }

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding((4 * dp).toInt(), (10 * dp).toInt(), (4 * dp).toInt(), (10 * dp).toInt())
            background = GradientDrawable().apply {
                when {
                    isPrimary -> {
                        // Gradient fill matches app's primary action gradient (#6366F1 → #A855F7).
                        colors = intArrayOf(Palette.ACCENT, Palette.ACCENT_END)
                        orientation = GradientDrawable.Orientation.TL_BR
                    }
                    isLocked -> {
                        // Locked mode: subtle purple tint + visible border so the
                        // "paid feature" cue reads at a glance (mirrors the
                        // Flutter FeatureButtons locked style).
                        setColor(Color.argb(26, 0x63, 0x66, 0xF1))   // ~10% indigo
                        setStroke((1 * dp).toInt(),
                            Color.argb(102, 0x63, 0x66, 0xF1))       // ~40% indigo
                    }
                    else -> setColor(Color.parseColor(subduedBg))
                }
                cornerRadius = 14 * dp
            }
            isClickable = true
            isFocusable = true
            setOnClickListener {
                hideModePicker()
                if (isLocked && gate != null) {
                    openFeatureUpsell(gate.displayName)
                } else {
                    onTranslateModePicked(mode)
                }
            }
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                .apply { marginEnd = if (index < ALL_MODES.size - 1) (6 * dp).toInt() else 0 }
        }
        // Icon on top — overlay a small 🔒 emoji-as-TextView on the
        // bottom-right when locked so the row's identity (mode icon)
        // stays visible alongside the lock state.
        val iconHolder = FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams((20 * dp).toInt(), (20 * dp).toInt())
        }
        iconHolder.addView(ImageView(this).apply {
            setImageResource(modeIcon(mode))
            setColorFilter(fgColor)
            layoutParams = FrameLayout.LayoutParams(
                (18 * dp).toInt(), (18 * dp).toInt(), Gravity.CENTER,
            )
        })
        if (isLocked) {
            iconHolder.addView(TextView(this).apply {
                text = "🔒"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f)
                gravity = Gravity.CENTER
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.BOTTOM or Gravity.END,
                )
            })
        }
        column.addView(iconHolder)
        // Label below — tiny enough to fit one line for all known
        // locales (Vietnamese "Tinh chỉnh" being the longest)
        column.addView(TextView(this).apply {
            text = modeLabel(mode)
            setTextColor(fgColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            gravity = Gravity.CENTER
            maxLines = 1
            setSingleLine(true)
            ellipsize = android.text.TextUtils.TruncateAt.END
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, (4 * dp).toInt(), 0, 0)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        })
        modesRow.addView(column)
    }
    card.addView(modesRow)

    // Divider + secondary actions row ("Type text" / "Show last result")
    val dividerBg = if (isDark) "#3A3A50" else "#E0DFF8"
    card.addView(View(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, (1 * dp).toInt(),
        ).apply { topMargin = (12 * dp).toInt(); bottomMargin = (8 * dp).toInt() }
        setBackgroundColor(Color.parseColor(dividerBg))
    })

    // Always-available "Type your own text" entry — for when the user
    // wants to translate something they haven't selected/copied (e.g.
    // composing a message from scratch). Opens a focusable input window
    // so the soft keyboard can attach.
    card.addView(TextView(this).apply {
        text = "✎  ${localized(R.string.bubble_type_text)}"
        setTextColor(accent)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
        isClickable = true
        isFocusable = true
        setOnClickListener {
            hideModePicker()
            showInputPicker(MODE_TRANSLATE)
        }
    })

    // "Voice input" — dictation for users who'd rather speak than type.
    // Routes through MicPermissionActivity the first time to request
    // RECORD_AUDIO; subsequent uses skip straight to the voice picker.
    card.addView(TextView(this).apply {
        text = "🎤  ${localized(R.string.bubble_voice)}"
        setTextColor(accent)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
        isClickable = true
        isFocusable = true
        setOnClickListener {
            hideModePicker()
            handleVoiceRequest()
        }
    })

    // "Scan screen (OCR)" + "Translate selected area" — both share the
    // Lens MediaProjection pipeline (region OCR + translate-batch), so
    // they're plan-gated by the same `lens` flag. When locked: prefix
    // with 🔒, muted color, tap opens the upgrade-nudge sheet labelled
    // "Lens" instead of starting the capture flow.
    val lensEnabled = readFeatureEnabled("tk_feature_lens")
    val lensColor = if (lensEnabled) accent else mutedCol

    // Icon is 📱 (phone) — the action captures THIS phone's screen,
    // not a desktop monitor (🖥️ misread as PC). Pairs visually with
    // 📸 below so phone-screen vs physical-camera capture stays
    // distinct at a glance.
    card.addView(TextView(this).apply {
        text = if (lensEnabled) {
            "📱  ${localized(R.string.bubble_scan_screen)}"
        } else {
            "🔒📱  ${localized(R.string.bubble_scan_screen)}"
        }
        setTextColor(lensColor)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
        isClickable = true
        isFocusable = true
        setOnClickListener {
            hideModePicker()
            if (lensEnabled) showScanModeChooser(isRegion = false)
            else openFeatureUpsell("Lens")
        }
    })

    // "Translate selected area" — same Lens pipeline but with a
    // rubber-band step between capture and OCR so the user can crop
    // out the rest of the screen (chat header, ads, app chrome).
    // Cheaper to translate AND avoids translating things the user
    // doesn't care about.
    //
    // Icon was 🎯 (target) — read as "aim" or "goal", not "crop".
    // Swapped to ✂️ (scissors) so the action self-documents as
    // "cut out a region".
    card.addView(TextView(this).apply {
        text = if (lensEnabled) {
            "✂️  ${localized(R.string.bubble_lens_region)}"
        } else {
            "🔒✂️  ${localized(R.string.bubble_lens_region)}"
        }
        setTextColor(lensColor)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
        isClickable = true
        isFocusable = true
        setOnClickListener {
            hideModePicker()
            if (lensEnabled) showScanModeChooser(isRegion = true)
            else openFeatureUpsell("Lens")
        }
    })

    // "Camera translate" — opens the Flutter camera screen for
    // snapshot-mode OCR on live camera feed (menus, signs, etc.).
    // Plan gate: read the mirrored `flutter.tk_feature_camera` bool
    // that featuresProvider persists on every /features fetch. When
    // false (free plan / camera disabled), render the entry with a
    // lock icon + dimmed colour + a tap that opens the Flutter
    // upgrade nudge sheet instead of the camera screen. Server
    // would still 403 on the API call, but the lock state surfaces
    // the gate BEFORE the user wastes a tap.
    val cameraEnabled = readCameraFeatureEnabled()
    card.addView(TextView(this).apply {
        text = if (cameraEnabled) {
            "📸  ${localized(R.string.bubble_camera)}"
        } else {
            // Keep the camera glyph even when locked so the row's
            // identity is unambiguous; lock prefix communicates the
            // "needs upgrade" state.
            "🔒📸  ${localized(R.string.bubble_camera)}"
        }
        setTextColor(if (cameraEnabled) accent else mutedCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
        isClickable = true
        isFocusable = true
        setOnClickListener {
            hideModePicker()
            if (cameraEnabled) {
                openCameraScreen()
            } else {
                openCameraUpsell()
            }
        }
    })

    // "Last result" shortcut if we have a cached output
    if (currentOutput != null) {
        card.addView(TextView(this).apply {
            text = localized(R.string.bubble_show_last_result)
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            gravity = Gravity.CENTER
            setPadding(0, (6 * dp).toInt(), 0, (4 * dp).toInt())
            setOnClickListener {
                hideModePicker()
                showResultPanel(loading = false, error = null, output = currentOutput)
            }
        })
    }

    // Small camera icon pinned to the BOTTOM-RIGHT corner of the card —
    // "hide the bubble for a few seconds so you can take a clean
    // screenshot" (the bubble is a third-party overlay, so it otherwise
    // lands in every system screenshot, and there's no way to exclude just
    // it on MIUI). A camera glyph reads as "capture the screen"; kept as a
    // compact corner action so it doesn't crowd the main mode rows.
    card.addView(LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.END
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = (4 * dp).toInt() }
        addView(ImageView(this@showModePicker).apply {
            setImageResource(R.drawable.ic_screenshot)
            setColorFilter(mutedCol)
            // Padding gives a comfortable touch target around the small glyph.
            setPadding((6 * dp).toInt(), (6 * dp).toInt(), (2 * dp).toInt(), (2 * dp).toInt())
            isClickable = true
            isFocusable = true
            contentDescription = localized(R.string.bubble_hide_for_screenshot)
            layoutParams = LinearLayout.LayoutParams((30 * dp).toInt(), (30 * dp).toInt())
            setOnClickListener {
                hideModePicker()
                hideBubbleForScreenshot()
            }
        })
    })

    val screenWidth = resources.displayMetrics.widthPixels
    val cardWidth = (screenWidth - (48 * dp).toInt()).coerceAtMost((360 * dp).toInt())
    backdrop.addView(card, FrameLayout.LayoutParams(cardWidth, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))

    modePickerView = backdrop
    windowManager?.addView(backdrop, buildPickerLayoutParams())
}

internal fun BubbleService.buildPickerLayoutParams(): WindowManager.LayoutParams {
    return WindowManager.LayoutParams(
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.MATCH_PARENT,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
        PixelFormat.TRANSLUCENT,
    )
}

internal fun BubbleService.hideModePicker() {
    modePickerView?.let {
        try { windowManager?.removeView(it) } catch (_: Exception) {}
    }
    modePickerView = null
    pendingPickerText = null
    // Mode picker dismissed — let the bubble peek half-hidden again
    // so it doesn't sit in the way of whatever app is in the foreground.
    scheduleBubbleHalfHide(resources.displayMetrics.density)
}

internal fun BubbleService.onTranslateModePicked(mode: String) {
    // Live subtitles is a continuous screen-capture mode, not a clipboard
    // translate — route it to its own toggle instead of ShareActivity.
    if (mode == MODE_SUBTITLE) {
        toggleSubtitleMode()
        return
    }
    android.util.Log.w("TKBubble", "onTranslateModePicked: mode=$mode → ShareActivity")
    // Always route via ShareActivity — that's the only component that
    // can read primaryClip on Android 10+ (background services are
    // blocked). ShareActivity reads the clipboard and forwards the
    // result back via ACTION_TRANSLATE.
    currentMode = mode
    val i = Intent(this, ShareActivity::class.java).apply {
        action = ACTION_READ_CLIPBOARD
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                Intent.FLAG_ACTIVITY_NO_HISTORY or
                Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
        putExtra(EXTRA_MODE, mode)
    }
    try {
        startActivity(i)
    } catch (e: Exception) {
        android.util.Log.w("TKBubble", "ShareActivity launch failed: ${e.message}")
        Toast.makeText(this, localized(R.string.bubble_need_copy), Toast.LENGTH_LONG).show()
    }
}
