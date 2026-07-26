package android.net;

import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class Uri {
    private final String uriString;
    private URI parsedUri;

    private Uri(String uriString) {
        this.uriString = uriString;
        try {
            this.parsedUri = new URI(uriString);
        } catch (Exception e) {
            this.parsedUri = null;
        }
    }

    public static Uri parse(String uriString) {
        if (uriString == null) {
            return new Uri("");
        }
        return new Uri(uriString);
    }

    public static String encode(String s) {
        return encode(s, null);
    }

    public static String encode(String s, String allow) {
        if (s == null) return null;
        StringBuilder encoded = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (isAllowed(c, allow)) {
                encoded.append(c);
            } else {
                byte[] bytes = String.valueOf(c).getBytes(StandardCharsets.UTF_8);
                for (byte b : bytes) {
                    encoded.append(String.format("%%%02X", b));
                }
            }
        }
        return encoded.toString();
    }

    private static boolean isAllowed(char c, String allow) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
                || "_-!.~'()*".indexOf(c) != -1
                || (allow != null && allow.indexOf(c) != -1);
    }

    public static String decode(String s) {
        if (s == null) return null;
        try {
            return URLDecoder.decode(s, StandardCharsets.UTF_8.name());
        } catch (Exception e) {
            return s;
        }
    }

    public static Uri fromFile(java.io.File file) {
        if (file == null) return new Uri("");
        return new Uri("file://" + file.getAbsolutePath());
    }

    public static Uri fromParts(String scheme, String ssp, String fragment) {
        StringBuilder sb = new StringBuilder();
        if (scheme != null) sb.append(scheme).append(":");
        if (ssp != null) sb.append(ssp);
        if (fragment != null) sb.append("#").append(fragment);
        return new Uri(sb.toString());
    }

    @Override
    public String toString() {
        return uriString;
    }

    public String getScheme() {
        return parsedUri != null ? parsedUri.getScheme() : null;
    }

    public String getHost() {
        return parsedUri != null ? parsedUri.getHost() : null;
    }

    public String getPath() {
        return parsedUri != null ? parsedUri.getPath() : null;
    }

    public String getQuery() {
        return parsedUri != null ? parsedUri.getQuery() : null;
    }

    public String getEncodedQuery() {
        return parsedUri != null ? parsedUri.getRawQuery() : null;
    }

    public String getEncodedPath() {
        return parsedUri != null ? parsedUri.getRawPath() : null;
    }

    public String getFragment() {
        return parsedUri != null ? parsedUri.getFragment() : null;
    }

    public String getQueryParameter(String key) {
        String query = getQuery();
        if (query == null) return null;
        String[] pairs = query.split("&");
        for (String pair : pairs) {
            int idx = pair.indexOf("=");
            String currentKey = idx > 0 ? pair.substring(0, idx) : pair;
            if (currentKey.equals(key)) {
                String value = idx > 0 && pair.length() > idx + 1 ? pair.substring(idx + 1) : "";
                try {
                    return URLDecoder.decode(value, StandardCharsets.UTF_8.name());
                } catch (Exception e) {
                    return value;
                }
            }
        }
        return null;
    }

    public List<String> getQueryParameters(String key) {
        List<String> result = new ArrayList<>();
        String query = getQuery();
        if (query == null) return result;
        String[] pairs = query.split("&");
        for (String pair : pairs) {
            int idx = pair.indexOf("=");
            String currentKey = idx > 0 ? pair.substring(0, idx) : pair;
            if (currentKey.equals(key)) {
                String value = idx > 0 && pair.length() > idx + 1 ? pair.substring(idx + 1) : "";
                try {
                    result.add(URLDecoder.decode(value, StandardCharsets.UTF_8.name()));
                } catch (Exception e) {
                    result.add(value);
                }
            }
        }
        return result;
    }

    public Set<String> getQueryParameterNames() {
        Set<String> result = new LinkedHashSet<>();
        String query = getQuery();
        if (query == null) return result;
        String[] pairs = query.split("&");
        for (String pair : pairs) {
            int idx = pair.indexOf("=");
            result.add(idx > 0 ? pair.substring(0, idx) : pair);
        }
        return result;
    }

    public String getLastPathSegment() {
        List<String> segments = getPathSegments();
        if (segments.isEmpty()) return null;
        return segments.get(segments.size() - 1);
    }

    public List<String> getPathSegments() {
        String path = getPath();
        if (path == null || path.isEmpty()) return Collections.emptyList();
        List<String> result = new ArrayList<>();
        String[] segments = path.split("/");
        for (String segment : segments) {
            if (!segment.isEmpty()) {
                result.add(segment);
            }
        }
        return result;
    }

    public Builder buildUpon() {
        Builder builder = new Builder();
        builder.scheme(getScheme());
        builder.encodedAuthority(parsedUri != null ? parsedUri.getRawAuthority() : null);
        builder.path(getPath());
        builder.encodedQuery(getEncodedQuery());
        builder.fragment(getFragment());
        return builder;
    }

    public static class Builder {
        private String scheme;
        private String authority;
        private String path;
        private String query;
        private String fragment;

        public Builder() {}

        public Builder scheme(String scheme) {
            this.scheme = scheme;
            return this;
        }

        public Builder authority(String authority) {
            this.authority = authority;
            return this;
        }

        public Builder encodedAuthority(String authority) {
            this.authority = authority;
            return this;
        }

        public Builder path(String path) {
            this.path = path;
            return this;
        }

        public Builder appendPath(String segment) {
            if (segment == null || segment.isEmpty()) return this;
            if (this.path == null) {
                this.path = "/" + segment;
            } else {
                if (this.path.endsWith("/")) {
                    this.path += segment;
                } else {
                    this.path += "/" + segment;
                }
            }
            return this;
        }

        public Builder encodedQuery(String query) {
            this.query = query;
            return this;
        }

        public Builder query(String query) {
            this.query = query;
            return this;
        }

        public Builder appendQueryParameter(String key, String value) {
            String encodedPair = key + "=" + (value != null ? value : "");
            if (this.query == null || this.query.isEmpty()) {
                this.query = encodedPair;
            } else {
                this.query += "&" + encodedPair;
            }
            return this;
        }

        public Builder fragment(String fragment) {
            this.fragment = fragment;
            return this;
        }

        public Uri build() {
            StringBuilder sb = new StringBuilder();
            if (scheme != null) {
                sb.append(scheme).append("://");
            }
            if (authority != null) {
                sb.append(authority);
            }
            if (path != null) {
                if (authority != null && !path.startsWith("/")) {
                    sb.append("/");
                }
                sb.append(path);
            }
            if (query != null && !query.isEmpty()) {
                sb.append("?").append(query);
            }
            if (fragment != null) {
                sb.append("#").append(fragment);
            }
            return new Uri(sb.toString());
        }
    }
}