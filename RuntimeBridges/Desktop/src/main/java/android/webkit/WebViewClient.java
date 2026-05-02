package android.webkit;

import android.graphics.Bitmap;

public class WebViewClient {
    public void onPageStarted(WebView view, String url, Bitmap favicon) {
    }

    public void onPageFinished(WebView view, String url) {
    }

    public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
    }

    public void shouldOverrideUrlLoading(WebView view, String url) {
    }

    public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
        return null;
    }

    public WebResourceResponse shouldInterceptRequest(WebView view, String url) {
        return null;
    }
}
