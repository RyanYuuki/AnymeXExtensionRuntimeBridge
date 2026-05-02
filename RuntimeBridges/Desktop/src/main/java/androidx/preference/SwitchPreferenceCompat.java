package androidx.preference;

import android.content.Context;

public class SwitchPreferenceCompat extends Preference {
    private boolean checked;

    public SwitchPreferenceCompat(Context context) {
        super(context);
    }

    public void setChecked(boolean checked) { this.checked = checked; }
    public boolean isChecked() { return checked; }
}
