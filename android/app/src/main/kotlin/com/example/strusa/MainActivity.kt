package com.example.strusa

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    
    private val CHANNEL = "com.example.strusa/native"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepScreenOn" -> {
                        try {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    
                    "allowScreenOff" -> {
                        try {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    
                    "getAppVersion" -> {
                        try {
                            val packageInfo = packageManager.getPackageInfo(packageName, 0)
                            val version = packageInfo.versionName
                            result.success(version)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    
                    "getBuildNumber" -> {
                        try {
                            val packageInfo = packageManager.getPackageInfo(packageName, 0)
                            val buildNumber = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                                packageInfo.longVersionCode.toString()
                            } else {
                                @Suppress("DEPRECATION")
                                packageInfo.versionCode.toString()
                            }
                            result.success(buildNumber)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Optional: Prevent screenshots for security
        // Uncomment if you want to block screenshots
        // window.setFlags(
        //     WindowManager.LayoutParams.FLAG_SECURE,
        //     WindowManager.LayoutParams.FLAG_SECURE
        // )
        
        // Keep screen on by default (for POS usage)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    
    override fun onDestroy() {
        super.onDestroy()
        // Clear screen on flag when app is destroyed
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}