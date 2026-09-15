package android.content;

import java.io.File;

public class ContextWrapper extends Context {
    private Context mBase;

    public ContextWrapper() {
    }

    public ContextWrapper(Context base) {
        mBase = base;
    }

    protected void attachBaseContext(Context base) {
        if (mBase != null) {
            throw new IllegalStateException("Base context already set");
        }
        mBase = base;
    }

    public Context getBaseContext() {
        return mBase;
    }

    @Override
    public Context getApplicationContext() {
        return mBase != null ? mBase.getApplicationContext() : super.getApplicationContext();
    }

    @Override
    public String getPackageName() {
        return mBase != null ? mBase.getPackageName() : super.getPackageName();
    }

    @Override
    public android.content.pm.PackageManager getPackageManager() {
        return mBase != null ? mBase.getPackageManager() : super.getPackageManager();
    }

    @Override
    public android.content.pm.ApplicationInfo getApplicationInfo() {
        return mBase != null ? mBase.getApplicationInfo() : super.getApplicationInfo();
    }

    @Override
    public ClassLoader getClassLoader() {
        return mBase != null ? mBase.getClassLoader() : super.getClassLoader();
    }

    @Override
    public Object getSystemService(String name) {
        return mBase != null ? mBase.getSystemService(name) : super.getSystemService(name);
    }

    @Override
    public Object getAssets() {
        return mBase != null ? mBase.getAssets() : super.getAssets();
    }

    @Override
    public SharedPreferences getSharedPreferences(String name, int mode) {
        return mBase != null ? mBase.getSharedPreferences(name, mode) : super.getSharedPreferences(name, mode);
    }

    @Override
    public File getFilesDir() {
        return mBase != null ? mBase.getFilesDir() : super.getFilesDir();
    }

    @Override
    public File getCacheDir() {
        return mBase != null ? mBase.getCacheDir() : super.getCacheDir();
    }

    @Override
    public File getExternalCacheDir() {
        return mBase != null ? mBase.getExternalCacheDir() : super.getExternalCacheDir();
    }

    @Override
    public String getString(int resId) {
        return mBase != null ? mBase.getString(resId) : super.getString(resId);
    }

    @Override
    public java.io.InputStream openFileInput(String name) throws java.io.FileNotFoundException {
        return mBase != null ? mBase.openFileInput(name) : super.openFileInput(name);
    }

    @Override
    public java.io.OutputStream openFileOutput(String name, int mode) throws java.io.FileNotFoundException {
        return mBase != null ? mBase.openFileOutput(name, mode) : super.openFileOutput(name, mode);
    }

    @Override
    public boolean deleteFile(String name) {
        return mBase != null ? mBase.deleteFile(name) : super.deleteFile(name);
    }

    @Override
    public File getDatabasePath(String name) {
        return mBase != null ? mBase.getDatabasePath(name) : super.getDatabasePath(name);
    }
}
