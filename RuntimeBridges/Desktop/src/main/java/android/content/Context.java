package android.content;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileNotFoundException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;
import android.content.pm.PackageManager;
import android.content.pm.ApplicationInfo;
import android.content.res.Resources;
import android.os.Looper;

public class Context {
    public static final int MODE_PRIVATE = 0;
    public static final int MODE_WORLD_READABLE = 1;
    public static final int MODE_MULTI_PROCESS = 4;
    public static final int BIND_AUTO_CREATE = 1;

    public static final String ACTIVITY_SERVICE = "activity";
    public static final String LAYOUT_INFLATER_SERVICE = "layout_inflater";
    public static final String CONNECTIVITY_SERVICE = "connectivity";
    public static final String WINDOW_SERVICE = "window";
    public static final String INPUT_METHOD_SERVICE = "input_method";
    public static final String KEYGUARD_SERVICE = "keyguard";
    public static final String POWER_SERVICE = "power";
    public static final String NOTIFICATION_SERVICE = "notification";
    public static final String AUDIO_SERVICE = "audio";

    private static final Map<String, SharedPreferences> prefsCache = new HashMap<>();
    private static final PackageManager packageManager = new PackageManager();
    private static android.app.Application sAppInstance;

    public SharedPreferences getSharedPreferences(String name, int mode) {
        synchronized (prefsCache) {
            if (!prefsCache.containsKey(name)) {
                prefsCache.put(name, new DesktopSharedPreferences(name));
            }
            return prefsCache.get(name);
        }
    }

    public Context getApplicationContext() {
        if (sAppInstance == null) {
            sAppInstance = new android.app.Application();
        }
        return sAppInstance;
    }

    public String getPackageName() {
        return "com.ryan.anymex";
    }

    public PackageManager getPackageManager() {
        return packageManager;
    }

    public ApplicationInfo getApplicationInfo() {
        return packageManager.getApplicationInfo(getPackageName(), 0);
    }

    public ClassLoader getClassLoader() {
        ClassLoader cl = getClass().getClassLoader();
        return cl != null ? cl : ClassLoader.getSystemClassLoader();
    }

    public Resources getResources() {
        return Resources.getSystem();
    }

    public Object getSystemService(String name) {
        if (ACTIVITY_SERVICE.equals(name)) {
            return new android.app.ActivityManager();
        }
        return null;
    }

    @SuppressWarnings("unchecked")
    public <T> T getSystemService(Class<T> serviceClass) {
        if (serviceClass != null && "android.app.ActivityManager".equals(serviceClass.getName())) {
            return (T) new android.app.ActivityManager();
        }
        return null;
    }

    public Looper getMainLooper() {
        return Looper.getMainLooper();
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

    public String getString(int resId, Object... formatArgs) {
        return "";
    }

    public InputStream openFileInput(String name) throws FileNotFoundException {
        return new FileInputStream(new File(getFilesDir(), name));
    }

    public OutputStream openFileOutput(String name, int mode) throws FileNotFoundException {
        return new FileOutputStream(new File(getFilesDir(), name));
    }

    public boolean deleteFile(String name) {
        return new File(getFilesDir(), name).delete();
    }

    public File getDatabasePath(String name) {
        return new File(getFilesDir(), name);
    }
}
