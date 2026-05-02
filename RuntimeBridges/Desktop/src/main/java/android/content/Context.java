package android.content;

import java.io.File;

public class Context {
    public static final int MODE_PRIVATE = 0;

    private static final java.util.Map<String, SharedPreferences> prefsCache = new java.util.HashMap<>();

    public SharedPreferences getSharedPreferences(String name, int mode) {
        synchronized (prefsCache) {
            if (!prefsCache.containsKey(name)) {
                prefsCache.put(name, new DesktopSharedPreferences(name));
            }
            return prefsCache.get(name);
        }
    }

    public File getFilesDir() {
        File dir = new File(System.getProperty("user.home"), ".anymex/files");
        dir.mkdirs();
        return dir;
    }

    public File getCacheDir() {
        File dir = new File(System.getProperty("user.home"), ".anymex/cache");
        dir.mkdirs();
        return dir;
    }

    public File getExternalCacheDir() {
        return getCacheDir();
    }

    public String getString(int resId) {
        return "";
    }
}
