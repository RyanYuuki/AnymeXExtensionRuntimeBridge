package android.util;

public class Base64 {
    public static final int DEFAULT = 0;
    public static final int NO_PADDING = 1;
    public static final int NO_WRAP = 2;
    public static final int CRLF = 4;
    public static final int URL_SAFE = 8;
    public static final int NO_CLOSE = 16;

    public static byte[] decode(String str, int flags) {
        if ((flags & URL_SAFE) != 0) {
            return java.util.Base64.getUrlDecoder().decode(str);
        }
        return java.util.Base64.getMimeDecoder().decode(str);
    }

    public static byte[] decode(byte[] input, int flags) {
        if ((flags & URL_SAFE) != 0) {
            return java.util.Base64.getUrlDecoder().decode(input);
        }
        return java.util.Base64.getMimeDecoder().decode(input);
    }

    public static String encodeToString(byte[] input, int flags) {
        if ((flags & URL_SAFE) != 0) {
            return java.util.Base64.getUrlEncoder().encodeToString(input);
        }
        return java.util.Base64.getEncoder().encodeToString(input);
    }
}
