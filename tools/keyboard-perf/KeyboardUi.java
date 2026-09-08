package app.transkey.keyboardperf;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Rect;
import android.inputmethodservice.Keyboard;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.MotionEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONObject;

/** Real touch input against the installed IME; no direct text injection. */
public final class KeyboardUi extends Instrumentation {
    private Context app;
    private File output;
    private String layout = "keyboard_qwerty";
    private String phase;
    private String first;
    @Override public void onCreate(Bundle args) {
        phase = args.getString("phase", "ui"); first = args.getString("first", "en"); start();
    }
    private interface Match { boolean matches(AccessibilityNodeInfo node); }
    private AccessibilityNodeInfo find(AccessibilityNodeInfo root, Match match) {
        if (root == null) return null;
        if (match.matches(root)) return root;
        for (int i = 0; i < root.getChildCount(); i++) {
            AccessibilityNodeInfo found = find(root.getChild(i), match);
            if (found != null) return found;
        }
        return null;
    }
    private AccessibilityNodeInfo find(Match match) {
        for (AccessibilityWindowInfo window : getUiAutomation().getWindows()) {
            AccessibilityNodeInfo node = find(window.getRoot(), match);
            if (node != null) return node;
        }
        return null;
    }
    private void touch(float x, float y, int hold, int flickY) {
        long down = SystemClock.uptimeMillis();
        MotionEvent e = MotionEvent.obtain(down, down, MotionEvent.ACTION_DOWN, x, y, 0);
        e.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        getUiAutomation().injectInputEvent(e, true); e.recycle();
        SystemClock.sleep(hold);
        if (flickY != 0) {
            e = MotionEvent.obtain(down, SystemClock.uptimeMillis(), MotionEvent.ACTION_MOVE, x, y + flickY, 0);
            e.setSource(InputDevice.SOURCE_TOUCHSCREEN);
            getUiAutomation().injectInputEvent(e, true); e.recycle();
        }
        e = MotionEvent.obtain(down, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP, x, y + flickY, 0);
        e.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        getUiAutomation().injectInputEvent(e, true); e.recycle();
    }
    private void tap(AccessibilityNodeInfo node) {
        Rect r = new Rect(); node.getBoundsInScreen(r); touch(r.centerX(), r.centerY(), 15, 0);
    }
    private float[] keyPoint(int code) throws Exception {
        AccessibilityNodeInfo node = find(n -> "app.transkey.mobile:id/keyboard_view".equals(n.getViewIdResourceName()));
        if (node == null) throw new IllegalStateException("Keyboard view missing: " + layout);
        Rect bounds = new Rect(); node.getBoundsInScreen(bounds);
        Keyboard kb = new Keyboard(app, app.getResources().getIdentifier(layout, "xml", "app.transkey.mobile"));
        Keyboard.Key target = null;
        for (Keyboard.Key k : kb.getKeys()) if (k.codes[0] == code) { target = k; break; }
        if (target == null) throw new IllegalArgumentException("No key " + code + " in " + layout);
        int left = Integer.MAX_VALUE, right = 0;
        for (Keyboard.Key k : kb.getKeys()) if (k.y == target.y) {
            left = Math.min(left, k.x); right = Math.max(right, k.x + k.width);
        }
        float x = bounds.left + target.x + (bounds.width() - (right - left)) / 2 - left + target.width / 2f;
        float y = bounds.top + (target.y + target.height / 2f) * bounds.height() / kb.getHeight();
        return new float[]{x, y};
    }
    private void key(int code, int hold, int flickY) throws Exception {
        float[] point = keyPoint(code);
        touch(point[0], point[1], hold, flickY);
    }
    private void key(int code) throws Exception { key(code, 15, 0); }
    private void select(String label) throws Exception {
        if (layout.equals("keyboard_japanese_flick")) {
            key(-201); layout = "keyboard_symbols";
        }
        key(-301, 650, 0); SystemClock.sleep(150);
        for (int attempt = 0; attempt < 12; attempt++) {
            AccessibilityNodeInfo choice = find(n -> n.isVisibleToUser() && n.getText() != null && n.getText().toString().startsWith(label));
            // A partially clipped row may report bounds behind the bottom bar.
            // Invoke its accessibility click; all typing still uses real touches.
            if (choice != null && choice.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                SystemClock.sleep(180);
                if (layout.equals("keyboard_symbols")) key(-201);
                return;
            }
            AccessibilityNodeInfo scroll = find(n -> "android.widget.ScrollView".contentEquals(n.getClassName()));
            if (scroll == null || !scroll.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)) break;
            SystemClock.sleep(120);
        }
        throw new IllegalStateException("Language not found: " + label);
    }
    private String text() {
        AccessibilityNodeInfo editor = find(n -> "android.widget.EditText".contentEquals(n.getClassName()));
        return editor == null || editor.getText() == null ? "" : editor.getText().toString();
    }
    private void clear() {
        AccessibilityNodeInfo b = find(n -> n.getText() != null && n.getText().toString().equalsIgnoreCase("Clear synthetic text"));
        if (b == null) throw new IllegalStateException("Test host not visible");
        tap(b); SystemClock.sleep(60);
    }
    private String shell(String command) throws Exception {
        try (ParcelFileDescriptor fd = getUiAutomation().executeShellCommand(command);
             java.io.FileInputStream in = new java.io.FileInputStream(fd.getFileDescriptor())) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
    private void shot(String name) throws Exception {
        Bitmap b = getUiAutomation().takeScreenshot();
        try (FileOutputStream out = new FileOutputStream(new File(output, name + ".png"))) {
            b.compress(Bitmap.CompressFormat.PNG, 100, out);
        }
        b.recycle();
    }
    private void describe(AccessibilityNodeInfo node, StringBuilder result) {
        if (node == null) return;
        result.append(node.getClassName()).append(" ").append(node.getText()).append("\n");
        for (int i = 0; i < node.getChildCount(); i++) describe(node.getChild(i), result);
    }
    private AccessibilityNodeInfo waitForEmoji(String value) throws Exception {
        long deadline = SystemClock.uptimeMillis() + 4000;
        do {
            AccessibilityNodeInfo grid = find(n -> "android.widget.GridView".contentEquals(n.getClassName()));
            AccessibilityNodeInfo item = find(grid, n -> n.isVisibleToUser() && n.getText() != null && value.contentEquals(n.getText()));
            if (item != null) {
                SystemClock.sleep(250);
                return find(find(n -> "android.widget.GridView".contentEquals(n.getClassName())),
                    n -> n.isVisibleToUser() && n.getText() != null && value.contentEquals(n.getText()));
            }
            SystemClock.sleep(100);
        } while (SystemClock.uptimeMillis() < deadline);
        shot("emoji_category_timeout");
        StringBuilder nodes = new StringBuilder();
        for (AccessibilityWindowInfo window : getUiAutomation().getWindows()) {
            if (window.getType() == AccessibilityWindowInfo.TYPE_INPUT_METHOD) describe(window.getRoot(), nodes);
        }
        Files.writeString(new File(output, "emoji-category-nodes.txt").toPath(), nodes.toString());
        throw new IllegalStateException("Emoji category did not become visible: " + value);
    }
    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            app = getTargetContext().createPackageContext("app.transkey.mobile", 0);
            output = new File(getTargetContext().getExternalFilesDir(null), phase); output.mkdirs();
            AccessibilityServiceInfo info = getUiAutomation().getServiceInfo();
            info.flags |= AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS | AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
            getUiAutomation().setServiceInfo(info);
            startActivitySync(new Intent(getTargetContext(), KeyboardHost.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            SystemClock.sleep(700);
            String[][] cases = {
                {"en", "English", "keyboard_qwerty", "hello", "hello"},
                {"vi", "Tiếng Việt (Telex)", "keyboard_qwerty", "chaof", "chào"},
                {"vi_vni", "Tiếng Việt (VNI)", "keyboard_vietnamese_vni", "cha2o", "chào"},
                {"zh", "中文 (拼音)", "keyboard_qwerty", "nihao", "你好"},
                {"es", "Español", "keyboard_qwerty", "hola", "hola"},
                {"fr", "Français", "keyboard_qwerty", "salut", "salut"},
                {"ar", "العربية", "keyboard_arabic", "سلام", "سلام"},
                {"pt", "Português", "keyboard_qwerty", "ola", "ola"},
                {"ru", "Русский (ЙЦУКЕН)", "keyboard_russian", "привет", "привет"},
                {"ru_phon", "Русский (фонетический)", "keyboard_russian_phonetic", "привет", "привет"},
                {"id", "Bahasa Indonesia", "keyboard_qwerty", "halo", "halo"},
                {"de", "Deutsch", "keyboard_qwerty", "hallo", "hallo"},
                {"ja", "日本語 (Romaji)", "keyboard_qwerty", "nihongo", "日本語"},
                {"ja_flick", "日本語 (フリック)", "keyboard_japanese_flick", "か", "く"},
                {"ko", "한국어 (두벌식)", "keyboard_korean", "ㅎㅏㄴㄱㅡㄹ", "한글"},
                {"ko_chun", "한국어 (천지인)", "keyboard_korean_chunjiin", "ㄱㅣㆍ", "가"},
                {"it", "Italiano", "keyboard_qwerty", "ciao", "ciao"},
                {"th", "ไทย", "keyboard_thai", "สวัสดี", "สวัสดี"}
            };
            List<String> records = new ArrayList<>();
            boolean started = false;
            for (String[] c : cases) {
                if (c[0].equals(first)) started = true;
                if (!started) continue;
                select(c[1]); layout = c[2]; clear();
                shell("dumpsys gfxinfo app.transkey.mobile reset");
                for (int repeat = 0; repeat < 5; repeat++) {
                    for (char ch : c[3].toCharArray()) {
                        if (c[0].equals("ja_flick")) key(ch, 80, -80); else key(ch);
                    }
                    if (c[0].equals("ja_flick")) key(-4);
                    else { key(32); if (c[0].equals("ja")) key(-4); }
                }
                SystemClock.sleep(150);
                String actual = text();
                boolean passed = actual.replaceAll("\\s", "").equalsIgnoreCase(c[4].repeat(5));
                shot(c[0]);
                Files.writeString(new File(output, c[0] + "-gfx.txt").toPath(), shell("dumpsys gfxinfo app.transkey.mobile framestats"));
                String record = new JSONObject().put("mode", c[0]).put("passed", passed).put("text", actual).toString();
                records.add(record); Files.write(new File(output, "results.jsonl").toPath(), records, StandardCharsets.UTF_8);
                Bundle progress = new Bundle(); progress.putString("mode", record); sendStatus(0, progress);
                key(-201); layout = "keyboard_symbols";
                key('1'); key('@'); key(-203); layout = "keyboard_symbols2";
                key(8364); key(-5);
                String symbols = new JSONObject().put("mode", c[0] + "_symbols").put("passed", text().equals(actual + "1@")).put("text", text()).toString();
                records.add(symbols);
                Files.write(new File(output, "results.jsonl").toPath(), records, StandardCharsets.UTF_8);
                shot(c[0] + "_symbols");
                progress = new Bundle(); progress.putString("mode", symbols); sendStatus(0, progress);
                key(-201); layout = c[2];
            }
            select("Tiếng Việt (Telex)");
            layout = "keyboard_qwerty"; clear();
            shell("dumpsys gfxinfo app.transkey.mobile reset");
            key(',', 650, 0); SystemClock.sleep(150);
            shot("emoji_open");
            Files.writeString(new File(output, "emoji-gfx.txt").toPath(), shell("dumpsys gfxinfo app.transkey.mobile framestats"));
            AccessibilityNodeInfo emoji = find(n -> n.getText() != null && "😀".contentEquals(n.getText()));
            if (emoji == null) throw new IllegalStateException("Emoji panel missing");
            tap(emoji); SystemClock.sleep(100); shot("emoji_insert");
            records.add(new JSONObject().put("mode", "emoji").put("passed", text().equals("😀")).put("text", text()).toString());
            AccessibilityNodeInfo back = find(n -> n.getText() != null && "⌫".contentEquals(n.getText()));
            tap(back); SystemClock.sleep(100);
            records.add(new JSONObject().put("mode", "emoji_delete").put("passed", text().isEmpty()).toString());
            tap(find(n -> n.getText() != null && "🐶".contentEquals(n.getText())));
            AccessibilityNodeInfo dog = waitForEmoji("🐶");
            shot("emoji_animals");
            tap(dog);
            tap(find(n -> n.getText() != null && "🍔".contentEquals(n.getText())));
            AccessibilityNodeInfo apple = waitForEmoji("🍏");
            shot("emoji_food");
            AccessibilityNodeInfo foodGrid = find(n -> "android.widget.GridView".contentEquals(n.getClassName()));
            tap(apple);
            SystemClock.sleep(100);
            records.add(new JSONObject().put("mode", "emoji_categories").put("passed", text().equals("🐶🍏"))
                .put("visible_cells", foodGrid.getChildCount()).put("text", text()).toString());
            tap(find(n -> n.getText() != null && "ABC".contentEquals(n.getText())));
            getTargetContext().startActivity(new Intent(getTargetContext(), KeyboardHost.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra("numeric", true));
            SystemClock.sleep(500); layout = "keyboard_number";
            for (char c : "12345".toCharArray()) key(c);
            SystemClock.sleep(100); shot("numeric");
            records.add(new JSONObject().put("mode", "numeric").put("passed", text().equals("12345")).put("text", text()).toString());
            Files.write(new File(output, "results.jsonl").toPath(), records, StandardCharsets.UTF_8);
            getTargetContext().startActivity(new Intent(getTargetContext(), KeyboardHost.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP));
            SystemClock.sleep(400); layout = "keyboard_qwerty";
            float[] b = keyPoint('b'), a = keyPoint('a');
            shell("dumpsys gfxinfo app.transkey.mobile reset");
            for (int i = 0; i < 80; i++) {
                touch(b[0], b[1], 0, 0); touch(a[0], a[1], 0, 0);
            }
            SystemClock.sleep(150); shot("burst_typing");
            records.add(new JSONObject().put("mode", "burst_typing").put("passed", text().equalsIgnoreCase("ba".repeat(80))).put("length", text().length()).toString());
            Files.writeString(new File(output, "burst-gfx.txt").toPath(), shell("dumpsys gfxinfo app.transkey.mobile framestats"));
            key(-5, 1200, 0); SystemClock.sleep(100);
            String afterHold = text(); SystemClock.sleep(350);
            records.add(new JSONObject().put("mode", "hold_delete_stops").put("passed", afterHold.length() < 160 && text().equals(afterHold)).put("remaining", text().length()).toString());
            shot("hold_delete");
            Files.write(new File(output, "results.jsonl").toPath(), records, StandardCharsets.UTF_8);
            result.putString("result", output.toString()); finish(android.app.Activity.RESULT_OK, result);
        } catch (Throwable error) {
            result.putString("error", android.util.Log.getStackTraceString(error)); finish(android.app.Activity.RESULT_CANCELED, result);
        }
    }
}
