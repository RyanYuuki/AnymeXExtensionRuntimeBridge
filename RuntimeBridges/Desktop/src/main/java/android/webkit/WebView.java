package android.webkit;

import android.content.Context;
import java.util.Map;

public class WebView {
    private String currentUrl;

    public WebView(Context context) {
    }

    public void loadUrl(String url) {
        this.currentUrl = url;
    }

    public void loadUrl(String url, Map<String, String> additionalHttpHeaders) {
        this.currentUrl = url;
    }

    public WebSettings getSettings() {
        return new WebSettings();
    }

    public void setWebViewClient(WebViewClient client) {
    }

    public void setWebChromeClient(WebChromeClient client) {
    }

    public void evaluateJavascript(String script, ValueCallback<String> callback) {
        if (callback != null) {
            callback.onReceiveValue(null);
        }
    }

    public void addJavascriptInterface(Object object, String name) {
    }

    public void removeJavascriptInterface(String name) {
    }

    public void stopLoading() {
    }

    public void reload() {
    }

    public void goBack() {
    }

    public boolean canGoBack() {
        return false;
    }

    public String getUrl() {
        return currentUrl;
    }

    public void clearCache(boolean includeDiskFiles) {
    }

    public void destroy() {
    }

    public void loadData(String data, String mimeType, String encoding) {
    }

    public void loadDataWithBaseURL(String baseUrl, String data, String mimeType, String encoding, String historyUrl) {
        this.currentUrl = baseUrl;
    }

    public void post(Runnable action) {
        if (action != null) {
            action.run();
        }
    }

    public void onPause() {
    }

    public void onResume() {
    }

    public static void setWebContentsDebuggingEnabled(boolean enabled) {
    }
}
