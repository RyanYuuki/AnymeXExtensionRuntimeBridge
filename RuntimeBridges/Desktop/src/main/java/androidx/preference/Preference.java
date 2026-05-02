package androidx.preference;

import android.content.Context;

public class Preference {
    private Context context;
    private String key;
    private CharSequence title;
    private CharSequence summary;
    private Object defaultValue;
    private boolean enabled = true;
    
    private OnPreferenceClickListener onPreferenceClickListener;
    private OnPreferenceChangeListener onPreferenceChangeListener;

    public Preference(Context context) {
        this.context = context;
    }

    public Context getContext() { return context; }
    
    public String getKey() { return key; }
    public void setKey(String key) { this.key = key; }
    
    public CharSequence getTitle() { return title; }
    public void setTitle(CharSequence title) { this.title = title; }
    public void setTitle(int titleRes) { this.title = "ResID_" + titleRes; }
    
    public CharSequence getSummary() { return summary; }
    public void setSummary(CharSequence summary) { this.summary = summary; }
    
    public void setDefaultValue(Object defaultValue) { this.defaultValue = defaultValue; }
    public Object getDefaultValue() { return defaultValue; }
    
    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }

    public void setOnPreferenceClickListener(OnPreferenceClickListener listener) {
        this.onPreferenceClickListener = listener;
    }
    public OnPreferenceClickListener getOnPreferenceClickListener() { return onPreferenceClickListener; }

    public void setOnPreferenceChangeListener(OnPreferenceChangeListener listener) {
        this.onPreferenceChangeListener = listener;
    }
    public OnPreferenceChangeListener getOnPreferenceChangeListener() { return onPreferenceChangeListener; }

    public interface OnPreferenceClickListener {
        boolean onPreferenceClick(Preference preference);
    }

    public interface OnPreferenceChangeListener {
        boolean onPreferenceChange(Preference preference, Object newValue);
    }
}
