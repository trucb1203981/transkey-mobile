package app.transkey.mobile

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.File

/**
 * Offline kana -> kanji conversion backed by a compact SQLite dictionary
 * (reading -> surface, built from EDICT2 / EDRDG). Conversion is whole-reading
 * lookup plus greedy longest-prefix segmentation (no full morphological
 * analysis - the compact tier). A downloaded larger pack, if present in
 * filesDir, supersedes the bundled one.
 *
 * The DB is copied from assets to filesDir once (SQLite can't open a compressed
 * asset directly). Lookups are indexed and sub-millisecond, so running them on
 * the key-press thread is fine for typical word lengths.
 */
class KanaKanjiConverter(private val context: Context) {

    @Volatile private var db: SQLiteDatabase? = null
    val isReady: Boolean get() = db != null

    companion object {
        private const val ASSET = "jadict.db"
        private const val VER = "1"               // bump to force re-copy on update
        private const val LARGE = "jadict_large.db" // optional downloaded pack
        private const val MAX_SEG = 8             // longest reading chunk to try
        private val PARTICLES = setOf('は', 'を', 'が', 'に', 'へ', 'で', 'と', 'も', 'の')
    }

    /** Open the dict, copying the bundled asset on first run. Safe to call on a
     *  background thread; cheap no-op once loaded. */
    fun ensureLoaded() {
        if (db != null) return
        synchronized(this) {
            if (db != null) return
            val large = File(context.filesDir, LARGE)
            val target = if (large.exists()) large else copyBundled()
            db = runCatching {
                SQLiteDatabase.openDatabase(target.path, null, SQLiteDatabase.OPEN_READONLY)
            }.getOrNull()
        }
    }

    private fun copyBundled(): File {
        val out = File(context.filesDir, ASSET)
        val ver = File(context.filesDir, "jadict.ver")
        if (out.exists() && ver.exists() && ver.readText() == VER) return out
        runCatching {
            context.assets.open(ASSET).use { input -> out.outputStream().use { input.copyTo(it) } }
            ver.writeText(VER)
        }
        return out
    }

    private fun surfaces(reading: String, limit: Int): List<String> {
        val d = db ?: return emptyList()
        val out = ArrayList<String>(limit)
        runCatching {
            d.rawQuery(
                "SELECT surface FROM dict WHERE reading=? ORDER BY common DESC LIMIT ?",
                arrayOf(reading, limit.toString()),
            ).use { c -> while (c.moveToNext()) out.add(c.getString(0)) }
        }
        return out
    }

    /** Greedy longest-prefix conversion; common 1-kana particles stay kana. */
    private fun segment(reading: String): String {
        val sb = StringBuilder()
        var i = 0
        while (i < reading.length) {
            var matched = false
            val end = minOf(i + MAX_SEG, reading.length)
            var j = end
            while (j > i + 1) {
                val s = surfaces(reading.substring(i, j), 1)
                if (s.isNotEmpty()) { sb.append(s[0]); i = j; matched = true; break }
                j--
            }
            if (!matched) {
                // single char: convert only if it is not a bare particle
                val ch = reading[i]
                if (ch !in PARTICLES) {
                    val s = surfaces(ch.toString(), 1)
                    if (s.isNotEmpty()) { sb.append(s[0]); i++; continue }
                }
                sb.append(ch); i++
            }
        }
        return sb.toString()
    }

    /** Candidates for [reading]: exact matches, then segmented, then kana forms. */
    fun convert(reading: String): List<String> {
        if (reading.isEmpty()) return emptyList()
        if (db == null) ensureLoaded()
        val res = LinkedHashSet<String>()
        for (s in surfaces(reading, 8)) res.add(s)
        val seg = segment(reading)
        if (seg != reading) res.add(seg)
        res.add(reading)                 // plain hiragana
        res.add(toKatakana(reading))     // katakana
        return res.toList()
    }

    private fun toKatakana(s: String): String = buildString {
        for (c in s) {
            // Hiragana block ぁ..ゖ (0x3041..0x3096) -> Katakana (+0x60).
            append(if (c.code in 0x3041..0x3096) (c + 0x60) else c)
        }
    }
}
