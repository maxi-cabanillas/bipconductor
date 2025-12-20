package com.macmovil.driver

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent

class MainActivity : FlutterFragmentActivity() {

    // Tu canal actual (lo dejamos tal cual)
    private val awakeChannel = "flutter.app/awake"

    // Canal nuevo para minimizar la app desde Flutter
    private val appChannel = "bip/app"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ===== Canal AWAKE (tu lógica existente) =====
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, awakeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "awakeapp" -> {
                        awakeapp()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ===== Canal MINIMIZE (nuevo) =====
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "minimize" -> {
                        minimizeApp()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun minimizeApp() {
        // Esto manda la app al background (como si apretaras Home)
        moveTaskToBack(true)
    }

    private fun awakeapp() {
        try {
            val bringToForegroundIntent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(bringToForegroundIntent)
        } catch (e: Exception) {
            // Fallback por si algo raro pasa
            val launchIntent = packageManager.getLaunchIntentForPackage("com.macmovil.driver")
            if (launchIntent != null) {
                startActivity(launchIntent)
            }
        }
    }
}

