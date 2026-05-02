package androidx.preference;

import android.content.Context;

public class CheckBoxPreference extends Preference {
    private boolean checked;

    public CheckBoxPreference(Context context) {
        super(context);
    }

    public void setChecked(boolean checked) { this.checked = checked; }
    public boolean isChecked() { return checked; }
}
