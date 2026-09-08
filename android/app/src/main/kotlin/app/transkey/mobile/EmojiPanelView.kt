package app.transkey.mobile

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.AbsListView
import android.widget.BaseAdapter
import android.widget.GridView
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Self-drawn emoji panel (Gboard-style), no extra deps. Shown in place of the
 * keyboard when the emoji key is pressed.
 *
 * Layout: a vertical scroll of an emoji grid (category headers inline), then a
 * bottom bar with a category quick-jump strip + ABC (return) + backspace.
 *
 * [onEmoji] inserts the chosen emoji, [onBackspace] deletes, [onAbc] returns to
 * the letter keyboard.
 */
class EmojiPanelView(context: Context) : LinearLayout(context) {

    var onEmoji: ((String) -> Unit)? = null
    var onBackspace: (() -> Unit)? = null
    var onAbc: (() -> Unit)? = null

    private val d = resources.displayMetrics.density
    private fun dp(v: Int) = (v * d).toInt()

    private val panelBg = 0xFF1C1D21.toInt()
    private val keyText = 0xFFE2E2E9.toInt()
    private val iconColor = 0xFFC4C7CE.toInt()

    private val cols = 8
    // Adapter positions preserve category jumps without creating every cell.
    private val sectionStarts = ArrayList<Int>()
    private val emojis = ArrayList<String?>()
    private val grid = GridView(context)

    init {
        orientation = VERTICAL
        setBackgroundColor(panelBg)

        grid.numColumns = cols
        grid.stretchMode = GridView.STRETCH_COLUMN_WIDTH
        grid.setSelector(android.graphics.drawable.ColorDrawable(Color.TRANSPARENT))
        buildGrid()
        grid.setOnItemClickListener { _, _, position, _ ->
            emojis[position]?.let { onEmoji?.invoke(it) }
        }
        addView(grid, LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))

        addView(buildBottomBar())
    }

    /** Force the panel to the keyboard's pixel height so it doesn't resize the IME. */
    fun setPanelHeight(px: Int) {
        // Parent is the root LinearLayout, so use its LayoutParams type
        // (a plain ViewGroup.LayoutParams throws ClassCastException at measure).
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, px)
    }

    private fun buildGrid() {
        val cellH = dp(48)
        for ((_, category) in CATEGORIES) {
            sectionStarts.add(emojis.size)
            emojis.addAll(category)
            // Keep each category aligned to a row, with untappable padding.
            repeat((cols - category.size % cols) % cols) { emojis.add(null) }
        }
        grid.adapter = object : BaseAdapter() {
            override fun getCount() = emojis.size
            override fun getItem(position: Int) = emojis[position]
            override fun getItemId(position: Int) = position.toLong()
            override fun areAllItemsEnabled() = false
            override fun isEnabled(position: Int) = emojis[position] != null
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View =
                (convertView as? TextView ?: TextView(context).apply {
                    textSize = 22f
                    gravity = Gravity.CENTER
                    setTextColor(keyText)
                    setBackgroundColor(Color.TRANSPARENT)
                    layoutParams = AbsListView.LayoutParams(LayoutParams.MATCH_PARENT, cellH)
                }).apply { text = emojis[position].orEmpty() }
        }
    }

    private fun buildBottomBar(): View {
        val bar = LinearLayout(context).apply {
            orientation = HORIZONTAL
            setBackgroundColor(0xFF17181C.toInt())
            gravity = Gravity.CENTER_VERTICAL
        }
        // ABC return button
        bar.addView(textButton("ABC") { onAbc?.invoke() }, barLp(weight = 0f, widthDp = 64))
        // Category quick-jump icons
        val cats = HorizontalScrollView(context).apply { isHorizontalScrollBarEnabled = false }
        val catRow = LinearLayout(context).apply { orientation = HORIZONTAL }
        CATEGORIES.forEachIndexed { idx, (icon, _) ->
            catRow.addView(textButton(icon) { jumpTo(idx) }, barLp(weight = 0f, widthDp = 44))
        }
        cats.addView(catRow)
        bar.addView(cats, barLp(weight = 1f, widthDp = 0))
        // Backspace
        bar.addView(textButton("⌫") { onBackspace?.invoke() }, barLp(weight = 0f, widthDp = 56))
        return bar
    }

    private fun jumpTo(index: Int) {
        // Category tabs switch directly to the target row. GridView's inherited
        // position scroller can stop before a row following disabled padding.
        grid.setSelection(sectionStarts.getOrElse(index) { 0 })
    }

    private fun textButton(label: String, onClick: () -> Unit): TextView =
        TextView(context).apply {
            text = label
            textSize = if (label.length > 1) 13f else 18f
            gravity = Gravity.CENTER
            setTextColor(iconColor)
            isClickable = true
            setOnClickListener { onClick() }
        }

    private fun barLp(weight: Float, widthDp: Int) =
        LinearLayout.LayoutParams(if (widthDp == 0) 0 else dp(widthDp), dp(46), weight)

    companion object {
        // (tab icon, emojis). Curated common set; expand later.
        private val CATEGORIES: List<Pair<String, List<String>>> = listOf(
            "😀" to "😀 😁 😂 🤣 😊 😇 🙂 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 😋 😛 😝 😜 🤪 🤨 🧐 🤓 😎 🥳 🤩 😏 😒 😞 😔 😟 😕 🙁 ☹️ 😣 😖 😫 😩 🥺 😢 😭 😤 😠 😡 🤬 🤯 😳 🥵 🥶 😱 😨 😰 😥 😓 🤗 🤔 🤭 🤫 🤥 😶 😐 😑 😬 🙄 😯 😦 😧 😮 😲 🥱 😴 🤤 😪 😵 🤐 🥴 🤢 🤮 🤧 😷 🤒 🤕".split(" "),
            "👍" to "👍 👎 👌 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 👇 ☝️ ✋ 🤚 🖐️ 🖖 👋 🤝 👏 🙌 👐 🤲 🙏 ✍️ 💪 🦾 👊 ✊ 🤛 🤜 ❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝".split(" "),
            "🐶" to "🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🐛 🦋 🐌 🐞 🐜 🐢 🐍 🦎 🐙 🦑 🦀 🐠 🐟 🐬 🐳 🐋 🦈".split(" "),
            "🍔" to "🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶️ 🌽 🥕 🧄 🧅 🥔 🍠 🥐 🍞 🥖 🧀 🥚 🍳 🥞 🧇 🥓 🍔 🍟 🍕 🌭 🥪 🌮 🌯 🍜 🍲 🍣 🍦 🍰 🎂 🍫 🍬 🍭 ☕ 🍵 🍺 🍻 🥤".split(" "),
            "⚽" to "⚽ 🏀 🏈 ⚾ 🥎 🎾 🏐 🏉 🎱 🏓 🏸 🥅 🏒 🏑 🏏 ⛳ 🏹 🎣 🥊 🥋 🎽 ⛸️ 🥌 🛷 🎿 ⛷️ 🏂 🏋️ 🤼 🤸 ⛹️ 🤺 🤾 🏌️ 🏇 🧘 🏄 🏊 🤽 🚣 🚴 🚵 🎮 🎲 🎯 🎳 🎸 🎺 🎻 🥁 🎤 🎧 🎼".split(" "),
            "🚗" to "🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🚚 🚛 🚜 🛴 🚲 🛵 🏍️ 🚨 🚔 ✈️ 🛫 🛬 🚀 🛸 🚁 ⛵ 🚤 🛳️ ⚓ 🏠 🏡 🏢 🏥 🏦 🏨 🏪 🏫 ⛪ 🗼 🗽 🌋 🏔️ ⛰️ 🏖️ 🏝️ 🌅 🌄 🌇 🌆 🌃".split(" "),
            "💡" to "⌚ 📱 💻 ⌨️ 🖥️ 🖨️ 🖱️ 💾 💿 📷 📸 🎥 📺 📻 ⏰ ⏱️ 🔋 🔌 💡 🔦 📔 📕 📗 📘 📙 📚 📖 🔖 📰 ✏️ ✒️ 🖊️ 🖌️ 📝 ✂️ 📌 📎 🔑 🔒 🔓 🔨 🪛 🔧 🧰 💰 💳 💎 🛒 🎁 🎈 🎉 🎊".split(" "),
            "❤️" to "✅ ❌ ⭕ ❗ ❓ ‼️ ⚠️ 🔴 🟠 🟡 🟢 🔵 🟣 ⚫ ⚪ 🟥 🟧 🟨 🟩 🟦 🟪 ⬛ ⬜ ➕ ➖ ➗ ✖️ 💲 💯 🔥 ⭐ 🌟 ✨ ⚡ ☀️ 🌙 ⛅ ☁️ 🌈 💧 🔝 🆗 🆕 🆒 🔚 🔙".split(" "),
        )
    }
}
