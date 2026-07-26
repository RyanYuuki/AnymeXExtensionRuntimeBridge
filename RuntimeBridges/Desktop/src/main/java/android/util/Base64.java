package android.util;

import java.nio.charset.StandardCharsets;

public class Base64 {
    public static final int DEFAULT = 0;
    public static final int NO_PADDING = 1;
    public static final int NO_WRAP = 2;
    public static final int CRLF = 4;
    public static final int URL_SAFE = 8;
    public static final int NO_CLOSE = 16;

    public static byte[] decode(String str, int flags) {
        if (str == null) return new byte[0];
        return decode(str.getBytes(StandardCharsets.US_ASCII), flags);
    }

    public static byte[] decode(byte[] input, int flags) {
        if (input == null) return new byte[0];
        return decode(input, 0, input.length, flags);
    }

    public static byte[] decode(byte[] input, int offset, int len, int flags) {
        if (input == null || len <= 0) return new byte[0];
        byte[] data = input;
        if (offset != 0 || len != input.length) {
            data = new byte[len];
            System.arraycopy(input, offset, data, 0, len);
        }
        java.util.Base64.Decoder decoder;
        if ((flags & URL_SAFE) != 0) {
            decoder = java.util.Base64.getUrlDecoder();
        } else {
            decoder = java.util.Base64.getMimeDecoder();
        }
        try {
            return decoder.decode(data);
        } catch (Exception e) {
            return java.util.Base64.getDecoder().decode(data);
        }
    }

    public static byte[] encode(byte[] input, int flags) {
        if (input == null) return new byte[0];
        return encode(input, 0, input.length, flags);
    }

    public static byte[] encode(byte[] input, int offset, int len, int flags) {
        if (input == null || len <= 0) return new byte[0];
        byte[] data = input;
        if (offset != 0 || len != input.length) {
            data = new byte[len];
            System.arraycopy(input, offset, data, 0, len);
        }
        java.util.Base64.Encoder encoder;
        if ((flags & URL_SAFE) != 0) {
            encoder = (flags & NO_PADDING) != 0
                    ? java.util.Base64.getUrlEncoder().withoutPadding()
                    : java.util.Base64.getUrlEncoder();
        } else {
            encoder = (flags & NO_PADDING) != 0
                    ? java.util.Base64.getEncoder().withoutPadding()
                    : java.util.Base64.getEncoder();
        }
        return encoder.encode(data);
    }

    public static String encodeToString(byte[] input, int flags) {
        if (input == null) return "";
        return encodeToString(input, 0, input.length, flags);
    }

    public static String encodeToString(byte[] input, int offset, int len, int flags) {
        if (input == null || len <= 0) return "";
        byte[] encoded = encode(input, offset, len, flags);
        return new String(encoded, StandardCharsets.US_ASCII);
    }
}
