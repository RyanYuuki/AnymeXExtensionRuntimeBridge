package android.util;

public class Log {
    public static int d(String tag, String msg) {
        System.out.println("DEBUG: " + tag + ": " + msg);
        return 0;
    }

    public static int d(String tag, String msg, Throwable tr) {
        System.out.println("DEBUG: " + tag + ": " + msg);
        if (tr != null) tr.printStackTrace();
        return 0;
    }

    public static int e(String tag, String msg) {
        System.err.println("ERROR: " + tag + ": " + msg);
        return 0;
    }

    public static int e(String tag, String msg, Throwable tr) {
        System.err.println("ERROR: " + tag + ": " + msg);
        if (tr != null) tr.printStackTrace();
        return 0;
    }

    public static int i(String tag, String msg) {
        System.out.println("INFO: " + tag + ": " + msg);
        return 0;
    }

    public static int i(String tag, String msg, Throwable tr) {
        System.out.println("INFO: " + tag + ": " + msg);
        if (tr != null) tr.printStackTrace();
        return 0;
    }

    public static int v(String tag, String msg) {
        System.out.println("VERBOSE: " + tag + ": " + msg);
        return 0;
    }

    public static int v(String tag, String msg, Throwable tr) {
        System.out.println("VERBOSE: " + tag + ": " + msg);
        if (tr != null) tr.printStackTrace();
        return 0;
    }

    public static int w(String tag, String msg) {
        System.err.println("WARN: " + tag + ": " + msg);
        return 0;
    }

    public static int w(String tag, String msg, Throwable tr) {
        System.err.println("WARN: " + tag + ": " + msg);
        if (tr != null) tr.printStackTrace();
        return 0;
    }

    public static int w(String tag, Throwable tr) {
        System.err.println("WARN: " + tag);
        if (tr != null) tr.printStackTrace();
        return 0;
    }
}
