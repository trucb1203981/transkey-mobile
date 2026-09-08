import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Objects;
import java.util.Random;

/** Compare optimized output with an independently compiled baseline artifact. */
public final class KeyboardParity {
    private static int checks;
    private static void equal(Object a, Object b, String context) {
        checks++;
        if (!Objects.equals(String.valueOf(a), String.valueOf(b))) {
            throw new AssertionError(context + ": " + a + " != " + b);
        }
    }
    public static void main(String[] args) throws Exception {
        URL runtime = Path.of(args[2]).toUri().toURL();
        URL android = Path.of(args[4]).toUri().toURL();
        try (URLClassLoader oldLoader = new URLClassLoader(new URL[]{Path.of(args[0]).toUri().toURL(), runtime, android}, ClassLoader.getPlatformClassLoader());
             URLClassLoader newLoader = new URLClassLoader(new URL[]{Path.of(args[1]).toUri().toURL(), runtime, android}, ClassLoader.getPlatformClassLoader())) {
            Class<?> oldType = oldLoader.loadClass("app.transkey.mobile.TelexProcessor");
            Class<?> newType = newLoader.loadClass("app.transkey.mobile.TelexProcessor");
            Random random = new Random(20260908);
            for (int test = 0; test < 80; test++) {
                Object old = oldType.getConstructor().newInstance();
                Object now = newType.getConstructor().newInstance();
                boolean auto = test % 2 == 0;
                oldType.getMethod("setAutoRime", boolean.class).invoke(old, auto);
                newType.getMethod("setAutoRime", boolean.class).invoke(now, auto);
                String alphabet = "aaeeooddwwsfjrxnghiyuqu";
                StringBuilder input = new StringBuilder();
                if (test < 8) input.append("nghieng".repeat(85)).append("thuongwss");
                else for (int i = 0; i < 90; i++) input.append(alphabet.charAt(random.nextInt(alphabet.length())));
                for (char c : input.toString().toCharArray()) {
                    oldType.getMethod("input", char.class).invoke(old, c);
                    newType.getMethod("input", char.class).invoke(now, c);
                    equal(oldType.getMethod("getComposingText").invoke(old), newType.getMethod("getComposingText").invoke(now), "append " + test);
                    equal(oldType.getMethod("getLiteralIntent").invoke(old), newType.getMethod("getLiteralIntent").invoke(now), "literal " + test);
                }
                for (int i = 0; i < input.length(); i++) {
                    oldType.getMethod("backspace").invoke(old);
                    newType.getMethod("backspace").invoke(now);
                    equal(oldType.getMethod("getComposingText").invoke(old), newType.getMethod("getComposingText").invoke(now), "delete " + test);
                }
            }
            List<String> words = Files.readAllLines(Path.of(args[3], "vn_syllables.txt"));
            List<String> english = Files.readAllLines(Path.of(args[3], "en_words.txt"));
            oldType = oldLoader.loadClass("app.transkey.mobile.VietWordCorrector");
            newType = newLoader.loadClass("app.transkey.mobile.VietWordCorrector");
            Object old = oldType.getConstructor(Iterable.class, Iterable.class).newInstance(words, english);
            Object now = newType.getConstructor(Iterable.class, Iterable.class).newInstance(words, english);
            Method oldSuggest = oldType.getMethod("suggest", String.class, int.class);
            Method newSuggest = newType.getMethod("suggest", String.class, int.class);
            for (int i = 0; i < 150; i++) {
                String word = words.get(random.nextInt(words.size()));
                String query = i % 3 == 0 ? word + "n" : i % 3 == 1 ? word.substring(1) : word + words.get(random.nextInt(words.size()));
                for (int max : new int[]{1, 3, 8}) equal(oldSuggest.invoke(old, query, max), newSuggest.invoke(now, query, max), "suggest " + query);
                equal(oldType.getMethod("fix", String.class).invoke(old, query), newType.getMethod("fix", String.class).invoke(now, query), "fix " + query);
            }
        }
        System.out.println("PARITY_CHECKS=" + checks + " FAILURES=0");
    }
}
