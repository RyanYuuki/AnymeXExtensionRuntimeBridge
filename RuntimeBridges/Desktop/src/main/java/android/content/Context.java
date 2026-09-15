package android.content;

import java.io.File;

public class Context {
    public static final int MODE_PRIVATE = 0;
    public static final int MODE_WORLD_READABLE = 1;
    public static final int MODE_MULTI_PROCESS = 4;
    public static final int BIND_AUTO_CREATE = 1;

    private static final java.util.Map<String, SharedPreferences> prefsCache = new java.util.HashMap<>();
    private static final android.content.pm.PackageManager packageManager = new android.content.pm.PackageManager();

    public SharedPreferences getSharedPreferences(String name, int mode) {
        synchronized (prefsCache) {
            if (!prefsCache.containsKey(name)) {
                prefsCache.put(name, new DesktopSharedPreferences(name));
            }
            return prefsCache.get(name);
        }
    }

    public Context getApplicationContext() {
        return this;
    }

    public String getPackageName() {
        return "com.ryan.anymex";
    }

    public android.content.pm.PackageManager getPackageManager() {
        return packageManager;
    }

    public android.content.pm.ApplicationInfo getApplicationInfo() {
        return packageManager.getApplicationInfo(getPackageName(), 0);
    }

    public ClassLoader getClassLoader() {
        ClassLoader cl = getClass().getClassLoader();
        return cl != null ? cl : ClassLoader.getSystemClassLoader();
    }

    public Object getSystemService(String name) {
        return null;
    }

    public Object getAssets() {
        return null;
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

    public java.io.InputStream openFileInput(String name) throws java.io.FileNotFoundException {
        return new java.io.FileInputStream(new File(getFilesDir(), name));
    }

    public java.io.OutputStream openFileOutput(String name, int mode) throws java.io.FileNotFoundException {
        return new java.io.FileOutputStream(new File(getFilesDir(), name));
    }

    public boolean deleteFile(String name) {
        return new File(getFilesDir(), name).delete();
    }

    public File getDatabasePath(String name) {
        return new File(getFilesDir(), name);
    }
}
