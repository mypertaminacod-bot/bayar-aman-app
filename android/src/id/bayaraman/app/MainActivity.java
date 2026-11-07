package id.bayaraman.app;

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Bundle;
import android.graphics.Color;
import android.net.Uri;
import android.view.View;
import android.view.WindowInsets;
import android.webkit.*;
import android.widget.FrameLayout;
import java.io.ByteArrayInputStream;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/** Bundled first-party pages on an HTTPS origin. No native JavaScript bridge. */
public final class MainActivity extends Activity {
    private WebView web;
    private static final String HOST = "appassets.androidplatform.net";
    private static final Set<String> FILES = new HashSet<>(Arrays.asList(
        "index.html", "admin.html", "app.css", "icons.svg", "route.js",
        "user.js", "admin.js", "config.js", "vendor/supabase.min.js"));
    private String entry;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        entry = getPackageName().endsWith(".admin") ? "admin.html" : "index.html";
        getWindow().setStatusBarColor(Color.rgb(166,25,46));
        getWindow().setNavigationBarColor(Color.WHITE);
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.WHITE);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets.consumeSystemWindowInsets();
        });
        web = new WebView(this);
        root.addView(web, new FrameLayout.LayoutParams(-1,-1));
        setContentView(root);
        web.setBackgroundColor(Color.WHITE);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setMediaPlaybackRequiresUserGesture(true);
        settings.setSupportMultipleWindows(false);
        if (android.os.Build.VERSION.SDK_INT >= 26) settings.setSafeBrowsingEnabled(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false);
        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                // Navigation stays within this app; remote content cannot replace our trusted page.
                return !"https".equals(uri.getScheme()) || !HOST.equals(uri.getHost());
            }
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (!HOST.equals(uri.getHost())) return null;
                String file = uri.getPath() == null ? "" : uri.getPath().substring(1);
                if (!"https".equals(uri.getScheme()) || !FILES.contains(file)
                    || (entry.equals("index.html") && (file.equals("admin.html") || file.equals("admin.js")))
                    || (entry.equals("admin.html") && (file.equals("index.html") || file.equals("user.js"))))
                    return missing();
                try {
                    String mime = file.endsWith(".js") ? "application/javascript" : file.endsWith(".css") ? "text/css"
                        : file.endsWith(".svg") ? "image/svg+xml" : "text/html";
                    WebResourceResponse response = new WebResourceResponse(mime,"UTF-8",getAssets().open(file));
                    java.util.Map<String,String> headers = new java.util.HashMap<>();
                    headers.put("X-Content-Type-Options", "nosniff");
                    headers.put("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src https://zspldrspzljdysmuzucs.supabase.co wss://zspldrspzljdysmuzucs.supabase.co; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'");
                    response.setResponseHeaders(headers);
                    return response;
                } catch (java.io.IOException error) { return missing(); }
            }
        });
        // Auth sessions live in WebView's per-package private storage; User and Admin are isolated.
        if (state == null || web.restoreState(state) == null) web.loadUrl("https://"+HOST+"/"+entry);
    }
    private WebResourceResponse missing() {
        return new WebResourceResponse("text/plain","UTF-8",404,"Not Found",null,
            new ByteArrayInputStream(new byte[0]));
    }
    @Override public void onBackPressed() {
        web.evaluateJavascript("(()=>{const busy=document.querySelector('[aria-busy=true]');if(busy)return true;const d=document.querySelector('dialog[open]');if(d){d.close();return true}const b=document.querySelector('.screen.active [data-page]');if(b){if(!b.disabled)b.click();return true}return false})()", result -> {
            if (!"true".equals(result)) new AlertDialog.Builder(this)
                .setMessage("Keluar dari BAYAR AMAN?")
                .setPositiveButton("Keluar", (dialog, which) -> finish())
                .setNegativeButton("Batal", null).show();
        });
    }
    @Override protected void onSaveInstanceState(Bundle state) { web.saveState(state);super.onSaveInstanceState(state); }
    @Override protected void onPause() { web.onPause();super.onPause(); }
    @Override protected void onResume() { super.onResume();web.onResume(); }
    @Override protected void onDestroy() { web.destroy();super.onDestroy(); }
}
