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
import app.transkey.mobile.BubbleService.Companion.LANG_LABELS
import app.transkey.mobile.BubbleService.Companion.MODE_TRANSLATE

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
    card.addView(TextView(this).apply {
        // Single subtitle: the picker's action rows translate the
        // clipboard; the alternative-input rows (OCR / Region / etc)
        // are explicit. We no longer try to second-guess what the
        // user has captured because source text always comes from an
        // explicit action.
        text = localized(R.string.bubble_need_text)
        setTextColor(mutedCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        setPadding(0, 0, 0, (8 * dp).toInt())
    })

    // Source → Target language chips. Each side is independently
    // tappable so the user can change either direction without first
    // opening the result panel. Without this the user could only see
    // the source-lang setting from inside the bubble; the target was
    // hidden behind a translate-first workflow.
    val pickedSource = readSourceLang()
    val pickedTarget = readTargetLang()
    val sourceLabel = if (pickedSource == "auto") "Auto"
        else (LANG_LABELS[pickedSource] ?: pickedSource.uppercase())
    val targetLabel = LANG_LABELS[pickedTarget] ?: pickedTarget.uppercase()
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
        val primaryBg = "#7C6EFA"
        val subduedBg = if (isDark) "#2A2A40" else "#F0EFFF"
        val fgColor = if (isPrimary) Color.WHITE else accent

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding((4 * dp).toInt(), (10 * dp).toInt(), (4 * dp).toInt(), (10 * dp).toInt())
            background = GradientDrawable().apply {
                setColor(Color.parseColor(if (isPrimary) primaryBg else subduedBg))
                cornerRadius = 14 * dp
            }
            isClickable = true
            isFocusable = true
            setOnClickListener {
                hideModePicker()
                onTranslateModePicked(mode)
            }
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                .apply { marginEnd = if (index < ALL_MODES.size - 1) (6 * dp).toInt() else 0 }
        }
        // Icon on top
        column.addView(ImageView(this).apply {
            setImageResource(modeIcon(mode))
            setColorFilter(fgColor)
            layoutParams = LinearLayout.LayoutParams((18 * dp).toInt(), (18 * dp).toInt())
        })
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

    // "Scan screen (OCR)" — full-screen Lens flow. Captures the
    // whole frame, OCRs everything that passes the content heuristic,
    // and renders translated blocks at their original positions.
    card.addView(TextView(this).apply {
        text = "📷  ${localized(R.string.bubble_scan_screen)}"
        setTextColor(accent)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
        isClickable = true
        isFocusable = true
        setOnClickListener {
            hideModePicker()
            showScanModeChooser(isRegion = false)
        }
    })

    // "Translate selected area" — same Lens pipeline but with a
    // rubber-band step between capture and OCR so the user can crop
    // out the rest of the screen (chat header, ads, app chrome).
    // Cheaper to translate AND avoids translating things the user
    // doesn't care about.
    card.addView(TextView(this).apply {
        text = "🎯  ${localized(R.string.bubble_lens_region)}"
        setTextColor(accent)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
        isClickable = true
        isFocusable = true
        setOnClickListener {
            hideModePicker()
            showScanModeChooser(isRegion = true)
        }
    })

    // "Camera translate" — opens the Flutter camera screen for
    // snapshot-mode OCR on live camera feed (menus, signs, etc.).
    card.addView(TextView(this).apply {
        text = "📷  ${localized(R.string.bubble_camera)}"
        setTextColor(accent)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
        isClickable = true
        isFocusable = true
        setOnClickListener {
            hideModePicker()
            openCameraScreen()
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
}

internal fun BubbleService.onTranslateModePicked(mode: String) {
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
