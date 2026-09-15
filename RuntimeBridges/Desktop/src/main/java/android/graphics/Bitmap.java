package android.graphics;

public class Bitmap {
    public enum Config {
        ALPHA_8,
        RGB_565,
        ARGB_8888,
        RGBA_F16,
        HARDWARE
    }

    private int width = 0;
    private int height = 0;
    private Config config;

    public Bitmap() {}

    public Bitmap(int width, int height, Config config) {
        this.width = width;
        this.height = height;
        this.config = config;
    }

    public int getWidth() { return width; }
    public int getHeight() { return height; }
    public Config getConfig() { return config; }
    public void recycle() {}

    public static Bitmap createBitmap(int width, int height, Config config) {
        return new Bitmap(width, height, config);
    }
}
