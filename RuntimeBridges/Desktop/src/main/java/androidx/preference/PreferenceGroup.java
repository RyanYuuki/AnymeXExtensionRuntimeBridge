package androidx.preference;

import android.content.Context;
import java.util.ArrayList;
import java.util.List;

public class PreferenceGroup extends Preference {
    private List<Preference> preferences = new ArrayList<>();

    public PreferenceGroup(Context context) {
        super(context);
    }

    public boolean addPreference(Preference preference) {
        preferences.add(preference);
        return true;
    }

    public int getPreferenceCount() {
        return preferences.size();
    }

    public Preference getPreference(int index) {
        return preferences.get(index);
    }
    
    public void removeAll() {
        preferences.clear();
    }
}
