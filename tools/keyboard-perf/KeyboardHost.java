package app.transkey.keyboardperf;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.text.InputType;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Local-only text fields for exercising the real IME without personal drafts. */
public final class KeyboardHost extends Activity {
    private EditText editor;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(24, 40, 24, 24);
        TextView title = new TextView(this);
        title.setText("TransKey keyboard performance test");
        title.setTextSize(20);
        root.addView(title);
        Button clear = new Button(this);
        clear.setText("Clear synthetic text");
        clear.setOnClickListener(v -> editor.setText(""));
        root.addView(clear);
        editor = new EditText(this);
        editor.setTextSize(22);
        editor.setMinLines(4);
        editor.setGravity(android.view.Gravity.TOP);
        root.addView(editor, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);
        configure(getIntent());
    }

    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        configure(intent);
    }

    private void configure(Intent intent) {
        editor.setInputType(intent.getBooleanExtra("numeric", false)
            ? InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL
            : InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        editor.setText(intent.getStringExtra("text") == null ? "" : intent.getStringExtra("text"));
        editor.setSelection(editor.length());
        editor.requestFocus();
        editor.postDelayed(() -> ((InputMethodManager) getSystemService(INPUT_METHOD_SERVICE))
            .showSoftInput(editor, InputMethodManager.SHOW_IMPLICIT), 300);
    }
}
