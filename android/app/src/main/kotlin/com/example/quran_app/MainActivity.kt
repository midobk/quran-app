package com.example.quran_app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_AWAKE_CHANNEL)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "setEnabled" -> {
            val enabled = call.argument<Boolean>("enabled") ?: false
            runOnUiThread {
              if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
              } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
              }
              result.success(null)
            }
          }
          else -> result.notImplemented()
        }
      }
  }

  companion object {
    private const val SCREEN_AWAKE_CHANNEL = "quran_app/screen_awake"
  }
}
