package com.example.smart_hunan_agri

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Local alarms, no permanent foreground service or network heartbeat. */
object LiveCourseNotifications {
    private const val CHANNEL = "course_live_activity"
    private const val ID = 7201
    private const val BOUNDARY = "course.live.BOUNDARY"
    private const val TICK = "course.live.TICK"
    const val DISMISS = "course.live.DISMISS"
    private val GREEN = 0xff23765b.toInt()

    private fun prefs(context: Context) = context.getSharedPreferences("course_live", Context.MODE_PRIVATE)
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

    fun capabilities(context: Context): Map<String, Any> = mapOf(
        "supported" to true,
        "manufacturer" to Build.MANUFACTURER,
        "model" to Build.MODEL,
        "sdk" to Build.VERSION.SDK_INT,
        "notificationsEnabled" to manager(context).areNotificationsEnabled(),
        "exactAlarms" to (Build.VERSION.SDK_INT < 31 || alarms(context).canScheduleExactAlarms()),
        "liveUpdates" to (Build.VERSION.SDK_INT >= 36),
        "promotionAllowed" to (Build.VERSION.SDK_INT >= 36 && manager(context).canPostPromotedNotifications()),
        "promoted" to (Build.VERSION.SDK_INT >= 36 && manager(context).activeNotifications.any {
            it.id == ID && it.notification.flags and Notification.FLAG_PROMOTED_ONGOING != 0
        }),
    )

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
        val item = JSONObject().put("id", "sample").put("name", "植物生理学 · 示例")
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
        // Prefer an ongoing class over a reminder for an overlapping next class.
        val selected = sample ?: eligible.firstOrNull { now >= it.getLong("start") } ?: eligible.firstOrNull()
        if (selected == null || !manager(context).areNotificationsEnabled()) manager(context).cancel(ID)
        else publish(context, selected, all, now, selected.getString("id") == "sample")

        val next = (all.flatMap { listOf(it.getLong("start") - lead, it.getLong("start"), it.getLong("end")) } +
            listOf(sampleUntil)).filter { it > now }.minOrNull()
        val alarmManager = alarms(context)
        val boundary = alarmIntent(context, BOUNDARY, 0)
        alarmManager.cancel(boundary)
        if (next != null) {
            // Permission may be revoked between the check and setExact.
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
            // Progress refresh can wait in Doze; the system chronometer keeps time.
            alarmManager.set(AlarmManager.RTC, now + 60_000L, tick)
        }
    }

    private fun alarmIntent(context: Context, action: String, requestCode: Int) = PendingIntent.getBroadcast(
        context, requestCode, Intent(context, LiveCourseReceiver::class.java).setAction(action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun publish(context: Context, course: JSONObject, all: List<JSONObject>, now: Long, sample: Boolean) {
        val nm = manager(context)
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel(CHANNEL, "课程实况", NotificationManager.IMPORTANCE_LOW).apply {
            description = "课前地点、上课进度和下课倒计时，静音更新"
            setShowBadge(false)
        })
        val start = course.getLong("start")
        val end = course.getLong("end")
        val ongoing = now >= start
        val target = if (ongoing) end else start
        val remaining = ((target - now + 59_999) / 60_000).coerceAtLeast(1)
        val state = if (ongoing) "上课中" else "即将上课"
        val hint = if (ongoing) "距下课 ${remaining} 分钟" else "${remaining} 分钟后上课"
        val room = course.getString("room")
        val time = SimpleDateFormat("HH:mm", Locale.CHINA)
        val hours = "${time.format(Date(start))}–${time.format(Date(end))}"
        val next = all.firstOrNull { it.getLong("start") >= end && it.getString("id") != course.getString("id") }
        val sameDay = next != null && SimpleDateFormat("yyyyMMdd", Locale.CHINA).run {
            format(Date(next.getLong("start"))) == format(Date(start))
        }
        val nextText = if (sample) "预览将在 2 分钟后自动收起"
            else if (sameDay) "下一节 ${time.format(Date(next!!.getLong("start")))}  ${next.getString("name")} · ${next.getString("room")}"
            else "今天没有下一节课了"
        val launch = Intent(context, MainActivity::class.java).setAction("course.live.OPEN")
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val open = PendingIntent.getActivity(context, 7201, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val close = PendingIntent.getBroadcast(context, 7202,
            Intent(context, LiveCourseReceiver::class.java).setAction(DISMISS).putExtra("id", course.getString("id")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val title = "$state · ${course.getString("name")}"
        val builder = newBuilder(context)
            .setSmallIcon(R.drawable.ic_course_notification)
            .setContentTitle(title).setContentText("$room · $hours")
            .setSubText(hint).setColor(GREEN).setOnlyAlertOnce(true)
            .setOngoing(true).setShowWhen(true).setWhen(target)
            .setUsesChronometer(true).setChronometerCountDown(true)
            .setContentIntent(open).setDeleteIntent(close)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(newBuilder(context)
                .setSmallIcon(R.drawable.ic_course_notification).setContentTitle("课程实况")
                .setContentText("解锁查看课程与教室").build())
            .addAction(Notification.Action.Builder(null, "查看课表", open).build())
            .addAction(Notification.Action.Builder(null, "收起本节", close).build())
        if (Build.VERSION.SDK_INT >= 26) builder.setTimeoutAfter(
            if (sample) (prefs(context).getLong("sampleUntil", now) - now).coerceAtLeast(1) else end - now)
        val progress = ((now - start).toDouble() / (end - start) * 100).toInt().coerceIn(0, 100)
        if (Build.VERSION.SDK_INT >= 36 && ongoing) {
            builder.setShortCriticalText("${remaining}分")
            // A calendar reminder is not eligible. Only an explicitly started
            // ongoing study session requests promotion; OEM/user policy decides.
            if (sample || prefs(context).getString("tracking", null) == course.getString("id")) {
                builder.addExtras(Bundle().apply { putBoolean("android.requestPromotedOngoing", true) })
            }
        } else {
            builder.setStyle(Notification.BigTextStyle().bigText(
                "$room\n$hours  ·  ${course.getString("periods")}\n$hint\n\n$nextText"))
        }
        try { nm.notify(ID, builder.build()) } catch (_: SecurityException) { /* Notification permission revoked. */ }
    }

    @Suppress("DEPRECATION")
    private fun newBuilder(context: Context) = if (Build.VERSION.SDK_INT >= 26)
        Notification.Builder(context, CHANNEL) else Notification.Builder(context)
}

class LiveCourseReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == LiveCourseNotifications.DISMISS)
            LiveCourseNotifications.dismiss(context, intent.getStringExtra("id"))
        else LiveCourseNotifications.refresh(context)
    }
}
