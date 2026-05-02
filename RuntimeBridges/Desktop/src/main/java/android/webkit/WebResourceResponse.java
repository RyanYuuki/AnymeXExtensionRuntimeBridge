package android.webkit;

import java.io.InputStream;
import java.util.Map;

public class WebResourceResponse {
    public WebResourceResponse(String mimeType, String encoding, InputStream data) {
    }

    public WebResourceResponse(String mimeType, String encoding, int statusCode,
                               String reasonPhrase, Map<String, String> responseHeaders, InputStream data) {
    }

    public String getMimeType() {
        return null;
    }

    public String getEncoding() {
        return null;
    }

    public int getStatusCode() {
        return 0;
    }

    public String getReasonPhrase() {
        return null;
    }

    public Map<String, String> getResponseHeaders() {
        return null;
    }

    public InputStream getData() {
        return null;
    }
}
