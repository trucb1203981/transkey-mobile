package app.transkey.mobile

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.File

/**
 * Offline pinyin -> hanzi conversion backed by a compact SQLite dictionary
 * (pinyin -> hanzi, freq). Pinyin + hanzi come from CC-CEDICT (CC-BY-SA - keep
 * attribution); ranking frequency from jieba (MIT). Keys are toneless joined
 * pinyin (你好 -> "nihao"), so a full word reading is a direct lookup.
 *
 * Candidates = exact-pinyin matches, then predictive prefix completions, then a
 * greedy longest-prefix segmentation - all ranked by frequency. A downloaded
 * larger pack (filesDir/zhdict_large.db) supersedes the bundled one.
 */
class PinyinHanziConverter(private val context: Context) {

    @Volatile private var db: SQLiteDatabase? = null
    @Volatile private var syllables: Set<String> = emptySet()
    val isReady: Boolean get() = db != null

    companion object {
        private const val ASSET = "zhdict.db"
        private const val VER = "2"               // syllable table added
        private const val LARGE = "zhdict_large.db"
        private const val MAX_SYL_LEN = 6         // longest pinyin syllable (e.g. zhuang)
        private const val MAX_WORD = 6            // longest word (syllables) to group
    }

    fun ensureLoaded() {
        if (db != null) return
        synchronized(this) {
            if (db != null) return
            val large = File(context.filesDir, LARGE)
            val target = if (large.exists()) large else copyBundled()
            db = runCatching {
                SQLiteDatabase.openDatabase(target.path, null, SQLiteDatabase.OPEN_READONLY)
            }.getOrNull()
            syllables = query("SELECT s FROM syllables", emptyArray()).toHashSet()
        }
    }

    private fun copyBundled(): File {
        val out = File(context.filesDir, ASSET)
        val ver = File(context.filesDir, "zhdict.ver")
        if (out.exists() && ver.exists() && ver.readText() == VER) return out
        runCatching {
            context.assets.open(ASSET).use { input -> out.outputStream().use { input.copyTo(it) } }
            ver.writeText(VER)
        }
        return out
    }

    private fun query(sql: String, args: Array<String>): List<String> {
        val d = db ?: return emptyList()
        val out = ArrayList<String>()
        runCatching {
            d.rawQuery(sql, args).use { c -> while (c.moveToNext()) out.add(c.getString(0)) }
        }
        return out
    }

    private fun exact(pinyin: String, limit: Int) =
        query("SELECT hanzi FROM zhdict WHERE pinyin=? ORDER BY freq DESC LIMIT ?",
            arrayOf(pinyin, limit.toString()))

    /** Words whose pinyin starts with [pinyin] (predictive), excluding exact. */
    private fun prefix(pinyin: String, limit: Int) =
        query(
            "SELECT hanzi FROM zhdict WHERE pinyin>? AND pinyin<? ORDER BY freq DESC LIMIT ?",
            arrayOf(pinyin, pinyin + "{", limit.toString()), // '{' = 'z'+1
        )

    /** Split pinyin into valid syllables (greedy longest), or null if some
     *  tail can't be covered - e.g. an incomplete syllable while still typing. */
    private fun splitSyllables(pinyin: String): List<String>? {
        val out = ArrayList<String>()
        var i = 0
        while (i < pinyin.length) {
            var matched = false
            var j = minOf(i + MAX_SYL_LEN, pinyin.length)
            while (j > i) {
                val sub = pinyin.substring(i, j)
                if (sub in syllables) { out.add(sub); i = j; matched = true; break }
                j--
            }
            if (!matched) return null
        }
        return out
    }

    /**
     * Convert a full multi-syllable reading: split into syllables, then greedily
     * group the longest run of syllables that is a dictionary word, else take the
     * best single character per syllable (你很好 -> 你/很/好). Null if the input
     * isn't cleanly splittable into syllables (still mid-typing).
     */
    private fun segment(pinyin: String): String? {
        val syl = splitSyllables(pinyin) ?: return null
        if (syl.size < 2) return null // single syllable already covered by exact()
        val sb = StringBuilder()
        var i = 0
        while (i < syl.size) {
            var matched = false
            var j = minOf(i + MAX_WORD, syl.size)
            while (j > i) {
                val key = syl.subList(i, j).joinToString("")
                val s = exact(key, 1)
                if (s.isNotEmpty()) { sb.append(s[0]); i = j; matched = true; break }
                j--
            }
            if (!matched) {
                val s = exact(syl[i], 1)
                sb.append(if (s.isNotEmpty()) s[0] else syl[i]); i++
            }
        }
        return sb.toString()
    }

    /** Candidates for [pinyin] (lowercase a-z). Exact, prefix, then segmented. */
    fun convert(pinyin: String): List<String> {
        if (pinyin.isEmpty()) return emptyList()
        if (db == null) ensureLoaded()
        val res = LinkedHashSet<String>()
        // More than fit on the strip: the surplus is browsable in the expand-all
        // grid (▼), and number-key / long-press selection picks the first few.
        for (s in exact(pinyin, 9)) res.add(s)
        for (s in prefix(pinyin, 18)) res.add(s)
        segment(pinyin)?.let { if (it.isNotEmpty() && it != pinyin) res.add(it) }
        return res.toList()
    }
}
