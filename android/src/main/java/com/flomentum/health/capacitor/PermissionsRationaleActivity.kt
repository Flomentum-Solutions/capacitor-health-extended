/**
 * ──────────────────────────────────────────────────────────────────────────────
 *  IMPORTANT SETUP NOTICE FOR HEALTH CONNECT PERMISSIONS RATIONALE ACTIVITY
 * ──────────────────────────────────────────────────────────────────────────────
 *
 * This `PermissionsRationaleActivity` class must be copied into your **end-user app**
 * (typically at: `android/app/src/main/java/<your-app-package>/PermissionsRationaleActivity.kt`)
 * and registered in your app's `AndroidManifest.xml`.
 *
 * WHY THIS IS NECESSARY:
 * Health Connect requires this Activity to be declared in the final **merged manifest**.
 * Android will not recognize it if it's only inside a Capacitor plugin or library module.
 * If this class is not present in the main app project, the following issues will occur:
 *
 *   - `Health Connect rationale screen not found` warnings
 *   - The Health Connect permissions dialog may silently fail to appear
 *   - Permissions will never be granted, breaking health data access on Android
 *
 * ──────────────────────────────────────────────────────────────────────────────
 * TO FIX:
 * 1. Copy this file to your app's native Android directory.
 * 2. Add the `<activity>` and `<activity-alias>` declarations for this class
 *    into your AndroidManifest.xml file (in the app module). --> You can find an example manifest block in the plugin README.
 * 3. Rebuild and re-deploy your app.
 *
 */

// package com.my.app.package.name  // <-- CHANGE THIS TO YOUR APP'S PACKAGE NAME

import android.os.Bundle
import android.util.Log
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.addCallback
import androidx.appcompat.app.AppCompatActivity

class PermissionsRationaleActivity : AppCompatActivity() {
    private lateinit var webView: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        supportActionBar?.apply {
            title = "Privacy Policy"
            setDisplayHomeAsUpEnabled(true)
        }

        webView = WebView(this).apply {
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                useWideViewPort = true
                loadWithOverviewMode = true
            }
            webChromeClient = WebChromeClient()
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: android.webkit.WebResourceRequest) = false
                override fun onReceivedError(
                    view: WebView,
                    request: android.webkit.WebResourceRequest,
                    error: android.webkit.WebResourceError
                ) {
                    Log.e("WebView", "Failed to load: ${error.description}")
                }
                override fun onPageFinished(view: WebView, url: String) {
                    Log.d("WebView", "Loaded: $url")
                }
            }
            loadUrl("https://flomentumsolutions.com/privacy-policy")
        }

        setContentView(webView)

        // Device back button behavior
        onBackPressedDispatcher.addCallback(this) {
            finish()
        }
    }

    // Toolbar Up button behavior
    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }
}