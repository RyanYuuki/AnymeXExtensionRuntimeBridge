package android.app;

import android.content.Context;
import android.content.ContextWrapper;
import android.view.LayoutInflater;

public class Activity extends ContextWrapper {
    public Activity() {
        super();
    }

    public Activity(Context base) {
        super(base);
    }

    public Application getApplication() {
        Context app = getApplicationContext();
        if (app instanceof Application) {
            return (Application) app;
        }
        return new Application();
    }

    public Activity getActivity() {
        return this;
    }

    public void runOnUiThread(Runnable action) {
        if (action != null) {
            action.run();
        }
    }

    public boolean isFinishing() {
        return false;
    }

    public boolean isDestroyed() {
        return false;
    }

    public Object getWindow() {
        return null;
    }

    public void setTheme(int resid) {
    }

    public LayoutInflater getLayoutInflater() {
        return new LayoutInflater();
    }
}
