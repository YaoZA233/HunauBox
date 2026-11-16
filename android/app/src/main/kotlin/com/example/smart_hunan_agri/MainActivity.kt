package com.example.smart_hunan_agri

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.provider.Settings
import android.provider.MediaStore
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import java.io.File

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hunaubox/update_download").setMethodCallHandler { call, result ->
            if (call.method != "saveApk") {
                result.notImplemented()
            } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                result.error("DOWNLOADS", "无法写入 Download 目录，请检查存储权限", null)
            } else {
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                Thread {
                    var uri: android.net.Uri? = null
                    try {
                        require(!path.isNullOrBlank() && !name.isNullOrBlank())
                        val values = ContentValues().apply {
                            put(MediaStore.Downloads.DISPLAY_NAME, name)
                            put(MediaStore.Downloads.MIME_TYPE, "application/vnd.android.package-archive")
                            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                            put(MediaStore.Downloads.IS_PENDING, 1)
                        }
                        val createdUri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                            ?: throw IllegalStateException("无法创建下载文件")
                        uri = createdUri
                        contentResolver.openOutputStream(createdUri, "w")?.use { output ->
                            File(path).inputStream().use { input -> input.copyTo(output) }
                        } ?: throw IllegalStateException("无法写入下载文件")
                        val savedPath = contentResolver.query(createdUri, arrayOf(MediaStore.Downloads.DATA), null, null, null)?.use { cursor ->
                            if (cursor.moveToFirst()) cursor.getString(0) else null
                        } ?: throw IllegalStateException("无法获取下载文件路径")
                        contentResolver.update(createdUri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
                        Handler(Looper.getMainLooper()).post { result.success(savedPath) }
                    } catch (error: Exception) {
                        uri?.let { contentResolver.delete(it, null, null) }
                        Handler(Looper.getMainLooper()).post { result.error("DOWNLOADS", "无法保存到 Download 目录", null) }
                    }
                }.start()
            }
        }

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
