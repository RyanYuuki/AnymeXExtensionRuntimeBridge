package android.app;

import android.content.Context;
import android.content.DialogInterface;
import android.view.View;

public class Dialog implements DialogInterface {
    private final Context context;

    public Dialog(Context context) {
        this.context = context;
    }

    public Dialog(Context context, int themeResId) {
        this.context = context;
    }

    public Context getContext() {
        return context;
    }

    public void show() {}

    public void dismiss() {}

    public void cancel() {}

    public void setContentView(View view) {}

    public void setContentView(int layoutResID) {}

    public void setTitle(CharSequence title) {}

    public void setCancelable(boolean flag) {}

    public void setCanceledOnTouchOutside(boolean cancel) {}

    public void setOnDismissListener(OnDismissListener listener) {}

    public void setOnCancelListener(OnCancelListener listener) {}

    public void setOnShowListener(OnShowListener listener) {}

    public boolean isShowing() {
        return false;
    }
}
