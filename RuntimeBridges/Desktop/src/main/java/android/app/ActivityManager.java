package android.app;

public class ActivityManager {
    public static class MemoryInfo {
        public long availMem = 4L * 1024 * 1024 * 1024;
        public long totalMem = 8L * 1024 * 1024 * 1024;
        public boolean lowMemory = false;
        public long threshold = 0L;
    }

    public void getMemoryInfo(MemoryInfo outInfo) {
        if (outInfo != null) {
            outInfo.availMem = 4L * 1024 * 1024 * 1024;
            outInfo.totalMem = 8L * 1024 * 1024 * 1024;
            outInfo.lowMemory = false;
            outInfo.threshold = 0L;
        }
    }

    public boolean isLowRamDevice() {
        return false;
    }

    public int getMemoryClass() {
        return 256;
    }

    public int getLargeMemoryClass() {
        return 512;
    }
}
