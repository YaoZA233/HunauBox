package com.example.smart_hunan_agri

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Enhanced live course notifications with improved UI and dynamic island support */
object EnhancedLiveCourseNotifications {
    private const val CHANNEL = "enhanced_course_live"
    private const val ID = 7301
    private const val BOUNDARY = "course.live.enhanced.BOUNDARY"
    private const val TICK = "course.live.enhanced.TICK"
    const val DISMISS = "course.live.enhanced.DISMISS"

    // Enhanced color palette - more vibrant and modern
    private val ACCENT_GREEN = 0xff2F8F83.toInt()
    private val ACCENT_BLUE = 0xff007AFF.toInt()        // iOS-like primary blue
    private val ACCENT_ORANGE = 0xffFF9500.toInt()      // iOS-like warning
    private val ACCENT_PURPLE = 0xffAF52DE.toInt()      // Modern purple
    private val BG_GRADIENT_START = 0xff1C1C1E.toInt()  // Dark theme start
    private val BG_GRADIENT_END = 0xff2C2C2E.toInt()    // Dark theme end
    private val TEXT_PRIMARY = 0xffFFFFFF.toInt()
    private val TEXT_SECONDARY = 0xffAAAAAA.toInt()

    private fun prefs(context: Context) = context.getSharedPreferences("enhanced_course_live", Context.MODE_PRIVATE)
    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)
    private fun alarms(context: Context) = context.getSystemService(AlarmManager::class.java)

    fun configure(context: Context, arguments: Map<*, *>) {
        val courses = JSONArray()
        (arguments["courses"] as? List<*>)?.forEach { value ->
            val item = JSONObject(value as Map<*, *>)
            require(item.getLong("end") > item.getLong("start"))
            courses.put(item)
        }
        prefs(context).edit()
            .putBoolean("enabled", arguments["enabled"] == true)
            .putInt("lead", (arguments["minutesBefore"] as? Number)?.toInt()?.coerceIn(1, 60) ?: 15)
            .putString("courses", courses.toString()).apply()
        refresh(context)
    }

    fun capabilities(context: Context): Map<String, Any> {
        val manufacturer = Build.MANUFACTURER.lowercase(Locale.ROOT)
        val isHonor = manufacturer.contains("honor") || manufacturer.contains("荣耀")
        val isHuawei = manufacturer.contains("huawei") || manufacturer.contains("华为")
        val isXiaomi = manufacturer.contains("xiaomi") || manufacturer.contains("redmi")
        val isOppo = manufacturer.contains("oppo") || manufacturer.contains("realme")
        val isVivo = manufacturer.contains("vivo") || manufacturer.contains("iqoo")

        return mapOf(
            "supported" to true,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "sdk" to Build.VERSION.SDK_INT,
            "notificationsEnabled" to manager(context).areNotificationsEnabled(),
            "exactAlarms" to (Build.VERSION.SDK_INT < 31 || alarms(context).canScheduleExactAlarms()),
            "liveUpdates" to (Build.VERSION.SDK_INT >= 36),
            "dynamicIslandSupport" to (isHonor || isHuawei || isXiaomi),
            "capsuleStyle" to when {
                isHonor -> "honor_magic_capsule"
                isHuawei -> "huawei_live_window"
                isXiaomi -> "xiaomi_notification_capsule"
                isOppo -> "oppo_sidebar"
                isVivo -> "vivo_notification_style"
                else -> "standard"
            },
            "promotionAllowed" to (Build.VERSION.SDK_INT >= 36 && manager(context).canPostPromotedNotifications()),
            "promoted" to (Build.VERSION.SDK_INT >= 36 && manager(context).activeNotifications.any {
                it.id == ID && it.notification.flags and Notification.FLAG_PROMOTED_ONGOING != 0
            }),
        )
    }

    private fun courses(context: Context): List<JSONObject> {
        if (!prefs(context).getBoolean("enabled", false)) return emptyList()
        val list = JSONArray(prefs(context).getString("courses", "[]"))
        return (0 until list.length()).map { list.getJSONObject(it) }.sortedBy { it.getLong("start") }
    }

    fun startCurrent(context: Context): Boolean {
        val now = System.currentTimeMillis()
        val course = courses(context).firstOrNull { now >= it.getLong("start") && now < it.getLong("end") }
            ?: return false
        prefs(context).edit().putString("tracking", course.getString("id")).remove("dismissed").apply()
        refresh(context)
        return true
    }

    fun sample(context: Context, upcoming: Boolean) {
        val now = System.currentTimeMillis()
        val start = now + if (upcoming) 12 * 60_000L else -28 * 60_000L
        val item = JSONObject().put("id", "sample").put("name", "植物生理学")
            .put("room", "文渊馆 B203").put("periods", "第 3–4 节")
            .put("start", start).put("end", start + 100 * 60_000L)
        prefs(context).edit().putString("sample", item.toString()).putLong("sampleUntil", now + 120_000L).apply()
        refresh(context)
    }

    fun stopSample(context: Context) {
        prefs(context).edit().remove("sample").remove("sampleUntil").apply()
        refresh(context)
    }

    fun dismiss(context: Context, id: String?) {
        if (id == "sample") stopSample(context)
        else {
            prefs(context).edit().putString("dismissed", id).apply()
            refresh(context)
        }
    }

    fun refresh(context: Context) {
        val now = System.currentTimeMillis()
        val saved = prefs(context)
        val all = courses(context)
        val lead = saved.getInt("lead", 15) * 60_000L
        val sampleUntil = saved.getLong("sampleUntil", 0)
        val sample = saved.getString("sample", null)?.takeIf { sampleUntil > now }?.let(::JSONObject)
        if (sample == null && sampleUntil > 0) saved.edit().remove("sample").remove("sampleUntil").apply()
        val eligible = all.filter {
            it.getString("id") != saved.getString("dismissed", null) &&
                now >= it.getLong("start") - lead && now < it.getLong("end")
        }
        val selected = sample ?: eligible.firstOrNull { now >= it.getLong("start") } ?: eligible.firstOrNull()
        if (selected == null || !manager(context).areNotificationsEnabled()) manager(context).cancel(ID)
        else publishEnhanced(context, selected, all, now, selected.getString("id") == "sample")

        val next = (all.flatMap { listOf(it.getLong("start") - lead, it.getLong("start"), it.getLong("end")) } +
            listOf(sampleUntil)).filter { it > now }.minOrNull()
        val alarmManager = alarms(context)
        val boundary = alarmIntent(context, BOUNDARY, 0)
        alarmManager.cancel(boundary)
        if (next != null) {
            try {
                if (Build.VERSION.SDK_INT < 31 || alarmManager.canScheduleExactAlarms())
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, boundary)
                else alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, boundary)
            } catch (_: SecurityException) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, boundary)
            }
        }
        val tick = alarmIntent(context, TICK, 1)
        alarmManager.cancel(tick)
        if (selected != null) {
            alarmManager.set(AlarmManager.RTC, now + 60_000L, tick)
        }
    }

    private fun alarmIntent(context: Context, action: String, requestCode: Int) = PendingIntent.getBroadcast(
        context, requestCode, Intent(context, EnhancedLiveCourseReceiver::class.java).setAction(action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun createProgressIcon(context: Context, progress: Int, color: Int): Bitmap {
        val size = 128
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val strokeWidth = 8f
        val radius = (size - strokeWidth) / 2f
        val center = size / 2f

        // Background circle
        paint.color = 0x30FFFFFF.toInt()
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = strokeWidth
        canvas.drawCircle(center, center, radius, paint)

        // Progress arc
        paint.color = color
        paint.strokeCap = Paint.Cap.ROUND
        val rect = RectF(strokeWidth / 2, strokeWidth / 2, size - strokeWidth / 2, size - strokeWidth / 2)
        canvas.drawArc(rect, -90f, progress * 3.6f, false, paint)

        // Center text
        paint.style = Paint.Style.FILL
        paint.color = TEXT_PRIMARY
        paint.textSize = 32f
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        val text = "$progress%"
        val yPos = center - (paint.descent() + paint.ascent()) / 2
        canvas.drawText(text, center, yPos, paint)

        return bitmap
    }

    private fun publishEnhanced(context: Context, course: JSONObject, all: List<JSONObject>, now: Long, sample: Boolean) {
        val nm = manager(context)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "增强课程实况", NotificationManager.IMPORTANCE_LOW).apply {
                description = "智能显示课程信息，支持灵动岛和胶囊展示"
                setShowBadge(false)
                enableLights(true)
                lightColor = ACCENT_GREEN
            })
        }

        val start = course.getLong("start")
        val end = course.getLong("end")
        val ongoing = now >= start
        val target = if (ongoing) end else start
        val remaining = ((target - now + 59_999) / 60_000).coerceAtLeast(1).toInt()
        val totalMinutes = ((end - start) / 60_000).toInt()
        val progress = if (ongoing) ((now - start).toDouble() / (end - start) * 100).toInt().coerceIn(0, 100) else 0

        val state = if (ongoing) "🎯 上课中" else "⏰ 即将上课"
        val hint = if (ongoing) "还剩 $remaining 分钟" else "$remaining 分钟后开始"
        val room = course.getString("room")
        val courseName = course.getString("name")
        val time = SimpleDateFormat("HH:mm", Locale.CHINA)
        val hours = "${time.format(Date(start))}–${time.format(Date(end))}"

        val next = all.firstOrNull { it.getLong("start") >= end && it.getString("id") != course.getString("id") }
        val sameDay = next != null && SimpleDateFormat("yyyyMMdd", Locale.CHINA).run {
            format(Date(next.getLong("start"))) == format(Date(start))
        }
        val nextText = if (sample) "💡 预览将在 2 分钟后自动收起"
            else if (sameDay) "📚 下节 ${time.format(Date(next!!.getLong("start")))}  ${next.getString("name")} @ ${next.getString("room")}"
            else "✓ 今天的课程已全部完成"

        val launch = Intent(context, MainActivity::class.java).setAction("course.live.enhanced.OPEN")
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val open = PendingIntent.getActivity(context, 7301, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val close = PendingIntent.getBroadcast(context, 7302,
            Intent(context, EnhancedLiveCourseReceiver::class.java).setAction(DISMISS).putExtra("id", course.getString("id")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        // Choose accent color based on state
        val accentColor = when {
            !ongoing -> ACCENT_BLUE
            remaining > 20 -> ACCENT_GREEN
            remaining > 10 -> ACCENT_ORANGE
            else -> ACCENT_PURPLE
        }

        val title = "$state  $courseName"
        val subtitle = "📍 $room  •  🕐 $hours"

        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder.setSmallIcon(R.drawable.ic_course_notification)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setSubText(hint)
            .setColor(accentColor)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setShowWhen(true)
            .setWhen(target)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setContentIntent(open)
            .setDeleteIntent(close)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setLargeIcon(createProgressIcon(context, if (ongoing) progress else 0, accentColor))

        // Custom public version for lockscreen
        if (Build.VERSION.SDK_INT >= 21) {
            val publicBuilder = if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(context, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            builder.setPublicVersion(publicBuilder
                .setSmallIcon(R.drawable.ic_course_notification)
                .setContentTitle("📚 课程进行中")
                .setContentText("解锁查看详细信息")
                .setColor(accentColor)
                .build())
        }

        // Add action buttons with icons
        if (Build.VERSION.SDK_INT >= 23) {
            builder.addAction(Notification.Action.Builder(
                android.R.drawable.ic_menu_view,
                "📋 查看课表",
                open
            ).build())
            builder.addAction(Notification.Action.Builder(
                android.R.drawable.ic_menu_close_clear_cancel,
                "🔕 暂时关闭",
                close
            ).build())
        } else {
            builder.addAction(Notification.Action.Builder(null, "📋 查看课表", open).build())
            builder.addAction(Notification.Action.Builder(null, "🔕 暂时关闭", close).build())
        }

        // Enhanced BigTextStyle with rich information
        val detailedText = buildString {
            appendLine("📚 课程：$courseName")
            appendLine("📍 教室：$room")
            appendLine("🕐 时间：$hours  •  ${course.getString("periods")}")
            appendLine("⏱️ 时长：$totalMinutes 分钟")
            if (ongoing) {
                appendLine("📊 进度：$progress% ($remaining 分钟后下课)")
            } else {
                appendLine("⏰ 距上课：$remaining 分钟")
            }
            appendLine()
            append(nextText)
        }

        builder.setStyle(Notification.BigTextStyle()
            .bigText(detailedText)
            .setBigContentTitle(title)
            .setSummaryText(if (ongoing) "进行中" else "即将开始"))

        // Set timeout
        if (Build.VERSION.SDK_INT >= 26) {
            builder.setTimeoutAfter(
                if (sample) (prefs(context).getLong("sampleUntil", now) - now).coerceAtLeast(1)
                else end - now
            )
        }

        // Avoid Android's full-width progress bar: on Honor it becomes a heavy
        // green strip in the expanded shade. The countdown and icon update once
        // per minute and provide the same live signal with much less visual noise.

        // Android 15+ (API 36) enhanced live updates with promoted notification
        if (Build.VERSION.SDK_INT >= 36) {
            if (ongoing) {
                try {
                    builder.javaClass.getMethod(
                        "setRequestPromotedOngoing",
                        Boolean::class.javaPrimitiveType,
                    ).invoke(builder, true)
                    builder.setShortCriticalText("${remaining}分")

                    // Request dynamic island / capsule promotion
                    if (sample || prefs(context).getString("tracking", null) == course.getString("id")) {
                        builder.addExtras(Bundle().apply {
                            putBoolean("android.requestPromotedOngoing", true)
                            // Honor Magic Capsule specific metadata
                            putString("honor.magic.capsule.style", "course_progress")
                            putInt("honor.magic.capsule.priority", 2)
                            // Xiaomi notification capsule metadata
                            putString("xiaomi.capsule.mode", "live_activity")
                            putBoolean("xiaomi.capsule.expand", true)
                        })
                    }
                } catch (e: Exception) {
                    // Fallback if ProgressStyle is not available
                }
            }
        }

        // Set category for better system integration
        if (Build.VERSION.SDK_INT >= 21) {
            builder.setCategory(Notification.CATEGORY_EVENT)
        }

        // Priority for better visibility
        if (Build.VERSION.SDK_INT >= 16) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_DEFAULT)
        }

        try {
            nm.notify(ID, builder.build())
        } catch (_: SecurityException) {
            // Notification permission revoked
        }
    }
}

class EnhancedLiveCourseReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == EnhancedLiveCourseNotifications.DISMISS)
            EnhancedLiveCourseNotifications.dismiss(context, intent.getStringExtra("id"))
        else EnhancedLiveCourseNotifications.refresh(context)
    }
}
