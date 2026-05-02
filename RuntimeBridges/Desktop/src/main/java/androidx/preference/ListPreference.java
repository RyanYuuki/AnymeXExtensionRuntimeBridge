package androidx.preference;

import android.content.Context;

public class ListPreference extends Preference {
    private CharSequence[] entries;
    private CharSequence[] entryValues;
    private String value;

    public ListPreference(Context context) {
        super(context);
    }

    public void setEntries(CharSequence[] entries) { this.entries = entries; }
    public CharSequence[] getEntries() { return entries; }

    public void setEntryValues(CharSequence[] entryValues) { this.entryValues = entryValues; }
    public CharSequence[] getEntryValues() { return entryValues; }

    public void setValue(String value) { this.value = value; }
    public String getValue() { return value; }

    public void setDialogTitle(CharSequence dialogTitle) { }
    public void setDialogMessage(CharSequence dialogMessage) { }

    public int findIndexOfValue(String value) {
        if (value != null && entryValues != null) {
            for (int i = 0; i < entryValues.length; i++) {
                if (value.equals(entryValues[i].toString())) {
                    return i;
                }
            }
        }
        return -1;
    }
}
