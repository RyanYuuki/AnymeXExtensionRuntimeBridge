package androidx.preference;

import android.content.Context;

public class EditTextPreference extends Preference {
    private String text;

    public EditTextPreference(Context context) {
        super(context);
    }

    public void setText(String text) { this.text = text; }
    public String getText() { return text; }

    private CharSequence dialogTitle;
    private CharSequence dialogMessage;

    public void setDialogTitle(CharSequence dialogTitle) { this.dialogTitle = dialogTitle; }
    public CharSequence getDialogTitle() { return dialogTitle; }

    public void setDialogMessage(CharSequence dialogMessage) { this.dialogMessage = dialogMessage; }
    public CharSequence getDialogMessage() { return dialogMessage; }

    public interface OnBindEditTextListener {
        void onBindEditText(Object editText);
    }

    public void setOnBindEditTextListener(OnBindEditTextListener onBindEditTextListener) {
    }
}
