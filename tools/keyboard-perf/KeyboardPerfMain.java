package app.transkey.mobile;

import android.content.ContextWrapper;
import android.content.res.AssetManager;
import java.io.File;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.List;
import org.json.JSONObject;

/** Device CPU benchmark using the app's compiled, unmodified Kotlin classes. */
public final class KeyboardPerfMain {
    private static volatile Object sink;

    private static void measure(String name, int count, Runnable action) throws Exception {
        for (int i = 0; i < 5; i++) action.run();
        double[] times = new double[count];
        for (int i = 0; i < count; i++) {
            long start = System.nanoTime();
            action.run();
            times[i] = (System.nanoTime() - start) / 1e6;
        }
        Arrays.sort(times);
        System.out.println(new JSONObject().put("case", name).put("n", count)
            .put("median_ms", times[count / 2]).put("p95_ms", times[(int) Math.ceil(count * .95) - 1])
            .put("max_ms", times[count - 1]));
    }

    public static void main(String[] args) throws Exception {
        File root = new File(args[0]);
        AssetManager assets = AssetManager.class.getDeclaredConstructor().newInstance();
        AssetManager.class.getMethod("addAssetPath", String.class).invoke(assets, args[1]);
        ContextWrapper context = new ContextWrapper(null) {
            @Override public File getFilesDir() { return root; }
            @Override public AssetManager getAssets() { return assets; }
        };
        List<String> vi = Files.readAllLines(new File(root, "vn_syllables.txt").toPath());
        List<String> en = Files.readAllLines(new File(root, "en_words.txt").toPath());
        VietWordCorrector corrector = new VietWordCorrector(vi, en);
        for (String word : new String[]{"banm", "nghieng", "bạnkhỏe", "nguoivietnam", "abcdefghijklmno"}) {
            measure("vi_suggest_" + word, 30, () -> sink = corrector.suggest(word, 3));
            measure("vi_fix_" + word, 12, () -> sink = corrector.fix(word));
        }
        for (int size : new int[]{12, 120, 600}) {
            String input = "nghieng".repeat((size + 6) / 7).substring(0, size);
            TelexProcessor telex = new TelexProcessor();
            measure("telex_run_" + size, 12, () -> {
                telex.reset();
                for (char c : input.toCharArray()) { telex.input(c); sink = telex.getComposingText(); }
            });
            VniProcessor vni = new VniProcessor();
            measure("vni_run_" + size, 12, () -> {
                vni.reset();
                for (char c : input.toCharArray()) { vni.input(c); sink = vni.getComposingText(); }
            });
            ChunjiinComposer chun = new ChunjiinComposer();
            measure("chunjiin_run_" + size, 12, () -> {
                chun.reset();
                for (int i = 0; i < size / 3; i++) {
                    chun.consonant(i % 7); sink = chun.getComposingText();
                    chun.vowel('V'); sink = chun.getComposingText();
                    chun.vowel('D'); sink = chun.getComposingText();
                }
            });
        }
        PinyinHanziConverter zh = new PinyinHanziConverter(context);
        long cold = System.nanoTime(); zh.ensureLoaded();
        System.out.println(new JSONObject().put("case", "zh_cold_load").put("ms", (System.nanoTime() - cold) / 1e6));
        for (String word : new String[]{"n", "s", "z", "nihao", "zhongguo", "nihaoshijie"}) {
            measure("zh_" + word, 30, () -> sink = zh.convert(word));
        }
        KanaKanjiConverter ja = new KanaKanjiConverter(context);
        cold = System.nanoTime(); ja.ensureLoaded();
        System.out.println(new JSONObject().put("case", "ja_cold_load").put("ms", (System.nanoTime() - cold) / 1e6));
        for (String word : new String[]{"こんにちは", "にほんご", "ありがとうございます", "あ".repeat(120)}) {
            measure("ja_" + word.length() + "_" + word.substring(0, Math.min(5, word.length())), 20, () -> sink = ja.convert(word));
        }
    }
}
