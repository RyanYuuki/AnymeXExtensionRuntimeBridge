package android.webkit;

import java.util.HashMap;
import java.util.Map;

public class CookieManager {
    private static CookieManager instance;
    private final Map<String, String> cookies = new HashMap<>();

    public static synchronized CookieManager getInstance() {
        if (instance == null) {
            instance = new CookieManager();
        }
        return instance;
    }

    public String getCookie(String url) {
        for (String key : cookies.keySet()) {
            if (url.contains(key)) {
                return cookies.get(key);
            }
        }
        return "";
    }

    public void setCookie(String url, String value) {
        String domain = url;
        try {
            java.net.URL u = new java.net.URL(url);
            domain = u.getHost();
        } catch (Exception e) {

        }
        
        String existing = cookies.get(domain);
        if (existing != null && !existing.isEmpty()) {
            cookies.put(domain, existing + "; " + value);
        } else {
            cookies.put(domain, value);
        }
    }

    public void flush() {
    }

    public void removeAllCookies(Object callback) {
        cookies.clear();
    }
}
