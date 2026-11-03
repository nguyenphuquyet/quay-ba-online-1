package com.quaybar.webview;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.graphics.Color;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/**
 * WebView native cho màn TV sân khấu.
 *
 * Game gọi `open(url)` để mở một lớp phủ toàn màn hình chứa WebView thật
 * (YouTube iframe chính thức) và `close()` để quay lại club. Đây là native
 * view nằm trên Godot, không phải texture, nên phù hợp cho chế độ "xem TV".
 */
public class QBOWebViewAndroid extends GodotPlugin {

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private FrameLayout overlay;
    private WebView webView;
    private String lastUrl = "";

    public QBOWebViewAndroid(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "QBOWebViewAndroid";
    }

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    public View onMainCreate(Activity activity) {
        overlay = new FrameLayout(activity);
        overlay.setBackgroundColor(Color.BLACK);
        overlay.setVisibility(View.GONE);

        webView = new WebView(activity);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        webView.setBackgroundColor(Color.BLACK);
        webView.setWebViewClient(new WebViewClient());
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                request.grant(request.getResources());
            }
        });
        overlay.addView(webView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        Button closeButton = new Button(activity);
        closeButton.setText("✕ Đóng TV");
        closeButton.setAlpha(0.85f);
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.gravity = Gravity.TOP | Gravity.END;
        params.setMargins(0, 48, 24, 0);
        overlay.addView(closeButton, params);
        closeButton.setOnClickListener(v -> hideOverlay());

        return overlay;
    }

    @UsedByGodot
    public void open(final String url) {
        if (url == null || url.isEmpty()) {
            return;
        }
        mainHandler.post(() -> {
            if (webView == null || overlay == null) {
                return;
            }
            if (!url.equals(lastUrl)) {
                lastUrl = url;
                webView.loadUrl(url);
            }
            overlay.setVisibility(View.VISIBLE);
            overlay.bringToFront();
            webView.onResume();
            webView.requestFocus();
        });
    }

    @UsedByGodot
    public void close() {
        mainHandler.post(this::hideOverlay);
    }

    @UsedByGodot
    public boolean isOpen() {
        return overlay != null && overlay.getVisibility() == View.VISIBLE;
    }

    /** Đổi kích thước vùng an toàn (dp) để chừa tai thỏ / thanh gesture. */
    @UsedByGodot
    public void setInsets(final int top, final int bottom, final int left, final int right) {
        mainHandler.post(() -> {
            if (overlay == null || webView == null) {
                return;
            }
            float density = overlay.getResources().getDisplayMetrics().density;
            int t = Math.round(top * density);
            int b = Math.round(bottom * density);
            int l = Math.round(left * density);
            int r = Math.round(right * density);
            FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
            params.setMargins(l, t, r, b);
            webView.setLayoutParams(params);
        });
    }

    private void hideOverlay() {
        if (overlay != null) {
            overlay.setVisibility(View.GONE);
        }
        if (webView != null) {
            webView.onPause();
        }
    }

    @Override
    public void onMainPause() {
        if (webView != null) {
            webView.onPause();
        }
    }

    @Override
    public void onMainResume() {
        if (webView != null && isOpen()) {
            webView.onResume();
        }
    }

    @Override
    public boolean onMainBackPressed() {
        // Nút Back đóng lớp phủ TV thay vì thoát game.
        if (isOpen()) {
            mainHandler.post(this::hideOverlay);
            return true;
        }
        return false;
    }

    @Override
    public void onMainDestroy() {
        if (webView != null) {
            overlay.removeView(webView);
            webView.destroy();
            webView = null;
        }
        overlay = null;
    }
}
