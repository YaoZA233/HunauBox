package com.example.smart_hunan_agri

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.provider.Settings

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var enhancedChannel: MethodChannel? = null
    private var unifiedChannel: MethodChannel? = null
    private var pendingOpen = false
    private var pendingEnhancedOpen = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingOpen = intent?.action == "course.live.OPEN"
        pendingEnhancedOpen = intent?.action == "course.live.enhanced.OPEN"

        // Original channel
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hunaubox/live_course").apply {
            setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "configure" -> { LiveCourseNotifications.configure(this@MainActivity, call.arguments as Map<*, *>); result.success(null) }
                        "capabilities" -> result.success(LiveCourseNotifications.capabilities(this@MainActivity))
                        "startCurrent" -> result.success(LiveCourseNotifications.startCurrent(this@MainActivity))
                        "sample" -> { LiveCourseNotifications.sample(this@MainActivity, call.argument<Boolean>("upcoming") == true); result.success(null) }
                        "stopSample" -> { LiveCourseNotifications.stopSample(this@MainActivity); result.success(null) }
                        "consumeOpen" -> { result.success(pendingOpen); pendingOpen = false }
                        "openSettings" -> {
                            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("COURSE_LIVE", error.message, null)
                }
            }
        }

        // Enhanced channel
        enhancedChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hunaubox/enhanced_live_course").apply {
            setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "configure" -> { EnhancedLiveCourseNotifications.configure(this@MainActivity, call.arguments as Map<*, *>); result.success(null) }
                        "capabilities" -> result.success(EnhancedLiveCourseNotifications.capabilities(this@MainActivity))
                        "startCurrent" -> result.success(EnhancedLiveCourseNotifications.startCurrent(this@MainActivity))
                        "sample" -> { EnhancedLiveCourseNotifications.sample(this@MainActivity, call.argument<Boolean>("upcoming") == true); result.success(null) }
                        "stopSample" -> { EnhancedLiveCourseNotifications.stopSample(this@MainActivity); result.success(null) }
                        "consumeOpen" -> { result.success(pendingEnhancedOpen); pendingEnhancedOpen = false }
                        "openSettings" -> {
                            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("ENHANCED_COURSE_LIVE", error.message, null)
                }
            }
        }

        // Unified capsule channel
        unifiedChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hunaubox/unified_capsule").apply {
            setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "configure" -> {
                            UnifiedCapsuleNotifications.configure(this@MainActivity, call.arguments as Map<*, *>)
                            result.success(null)
                        }
                        "patch" -> {
                            UnifiedCapsuleNotifications.patch(this@MainActivity, call.arguments as Map<*, *>)
                            result.success(null)
                        }
                        "capabilities" -> result.success(UnifiedCapsuleNotifications.capabilities(this@MainActivity))
                        "refresh" -> {
                            UnifiedCapsuleNotifications.refresh(this@MainActivity)
                            result.success(null)
                        }
                        "cancelAll" -> {
                            UnifiedCapsuleNotifications.cancelAll(this@MainActivity)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("UNIFIED_CAPSULE", error.message, null)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == "course.live.OPEN") channel?.invokeMethod("openTimetable", null)
        if (intent.action == "course.live.enhanced.OPEN") enhancedChannel?.invokeMethod("openTimetable", null)
    }
}
