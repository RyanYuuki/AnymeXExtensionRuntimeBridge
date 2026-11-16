package android.app;

import android.content.Context;
import android.content.DialogInterface;
import android.view.View;

public class AlertDialog extends Dialog {
    public AlertDialog(Context context) {
        super(context);
    }

    public static class Builder {
        private final Context context;

        public Builder(Context context) {
            this.context = context;
        }

        public Builder setTitle(CharSequence title) { return this; }
        public Builder setTitle(int titleId) { return this; }
        public Builder setMessage(CharSequence message) { return this; }
        public Builder setMessage(int messageId) { return this; }
        public Builder setView(View view) { return this; }
        public Builder setPositiveButton(CharSequence text, DialogInterface.OnClickListener listener) { return this; }
        public Builder setPositiveButton(int textId, DialogInterface.OnClickListener listener) { return this; }
        public Builder setNegativeButton(CharSequence text, DialogInterface.OnClickListener listener) { return this; }
        public Builder setNegativeButton(int textId, DialogInterface.OnClickListener listener) { return this; }
        public Builder setNeutralButton(CharSequence text, DialogInterface.OnClickListener listener) { return this; }
        public Builder setNeutralButton(int textId, DialogInterface.OnClickListener listener) { return this; }
        public Builder setItems(CharSequence[] items, DialogInterface.OnClickListener listener) { return this; }
        public Builder setItems(int itemsId, DialogInterface.OnClickListener listener) { return this; }
        public Builder setCancelable(boolean cancelable) { return this; }
        public Builder setOnDismissListener(DialogInterface.OnDismissListener listener) { return this; }
        public AlertDialog create() { return new AlertDialog(context); }
        public AlertDialog show() {
            AlertDialog dialog = create();
            dialog.show();
            return dialog;
        }
    }
}
