package android.content;

import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class DesktopSharedPreferences implements SharedPreferences {
    private final File file;
    private final Gson gson = new Gson();
    private Map<String, Object> map = new HashMap<>();

    public DesktopSharedPreferences(String fileName) {
        String home = System.getProperty("user.home");
        File dir = new File(home, "Documents/AnymeX/ExtensionSettings");
        if (!dir.exists()) dir.mkdirs();
        this.file = new File(dir, fileName + ".json");
        load();
    }

    private void load() {
        if (!file.exists()) return;
        try (FileReader reader = new FileReader(file, StandardCharsets.UTF_8)) {
            Map<String, Object> loaded = gson.fromJson(reader, new TypeToken<Map<String, Object>>(){}.getType());
            if (loaded != null) {
                map = loaded;
            }
        } catch (Exception e) {
            System.err.println("Error loading preferences from " + file.getAbsolutePath() + ": " + e.getMessage());
        }
    }

    private void save() {
        try (FileWriter writer = new FileWriter(file, StandardCharsets.UTF_8)) {
            gson.toJson(map, writer);
        } catch (Exception e) {
            System.err.println("Error saving preferences to " + file.getAbsolutePath() + ": " + e.getMessage());
        }
    }

    @Override
    public Map<String, ?> getAll() { return new HashMap<>(map); }

    @Override
    public String getString(String key, String defValue) {
        Object val = map.get(key);
        return val instanceof String ? (String) val : defValue;
    }

    @Override
    public Set<String> getStringSet(String key, Set<String> defValues) {
        Object val = map.get(key);
        if (val instanceof List) {
            return new HashSet<>((List<String>) val);
        }
        return defValues;
    }

    @Override
    public int getInt(String key, int defValue) {
        Object val = map.get(key);
        if (val instanceof Number) return ((Number) val).intValue();
        return defValue;
    }

    @Override
    public long getLong(String key, long defValue) {
        Object val = map.get(key);
        if (val instanceof Number) return ((Number) val).longValue();
        return defValue;
    }

    @Override
    public float getFloat(String key, float defValue) {
        Object val = map.get(key);
        if (val instanceof Number) return ((Number) val).floatValue();
        return defValue;
    }

    @Override
    public boolean getBoolean(String key, boolean defValue) {
        Object val = map.get(key);
        return val instanceof Boolean ? (Boolean) val : defValue;
    }

    @Override
    public boolean contains(String key) { return map.containsKey(key); }

    @Override
    public Editor edit() { return new DesktopEditor(); }

    private final Set<OnSharedPreferenceChangeListener> listeners = Collections.newSetFromMap(new java.util.WeakHashMap<>());

    @Override
    public void registerOnSharedPreferenceChangeListener(OnSharedPreferenceChangeListener listener) {
        synchronized (listeners) {
            listeners.add(listener);
        }
    }

    @Override
    public void unregisterOnSharedPreferenceChangeListener(OnSharedPreferenceChangeListener listener) {
        synchronized (listeners) {
            listeners.remove(listener);
        }
    }

    private class DesktopEditor implements Editor {
        private final Map<String, Object> tempMap = new HashMap<>(map);

        @Override
        public Editor putString(String key, String value) { tempMap.put(key, value); return this; }
        @Override
        public Editor putStringSet(String key, Set<String> values) { tempMap.put(key, new ArrayList<>(values)); return this; }
        @Override
        public Editor putInt(String key, int value) { tempMap.put(key, value); return this; }
        @Override
        public Editor putLong(String key, long value) { tempMap.put(key, value); return this; }
        @Override
        public Editor putFloat(String key, float value) { tempMap.put(key, value); return this; }
        @Override
        public Editor putBoolean(String key, boolean value) { tempMap.put(key, value); return this; }
        @Override
        public Editor remove(String key) { tempMap.remove(key); return this; }
        @Override
        public Editor clear() { tempMap.clear(); return this; }
        
        @Override
        public boolean commit() {
            List<String> keysChanged = new ArrayList<>();
            for (String key : tempMap.keySet()) {
                Object oldVal = map.get(key);
                Object newVal = tempMap.get(key);
                if (oldVal == null || !oldVal.equals(newVal)) {
                    keysChanged.add(key);
                }
            }
            for (String key : map.keySet()) {
                if (!tempMap.containsKey(key)) {
                    keysChanged.add(key);
                }
            }

            map.clear();
            map.putAll(tempMap);
            save();

            if (!keysChanged.isEmpty()) {
                synchronized (listeners) {
                    for (OnSharedPreferenceChangeListener l : listeners) {
                        for (String k : keysChanged) {
                            l.onSharedPreferenceChanged(DesktopSharedPreferences.this, k);
                        }
                    }
                }
            }
            return true;
        }

        @Override
        public void apply() {
            commit();
        }
    }
}
