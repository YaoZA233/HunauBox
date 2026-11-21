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
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 统一胶囊通知系统 - 支持多种消息类型
 *
 * 支持的通知类型：
 * - COURSE: 课程提醒（上课地点、时间、进度）
 * - HOMEWORK: 作业截止（作业标题、截止时间、倒计时）
 * - MESSAGE: 校园通知（通知标题、发送者、时间）
 * - EXAM: 考试提醒（考试科目、地点、时间）
 * - ACTIVITY: 活动提醒（活动名称、地点、时间）
 */
object UnifiedCapsuleNotifications {

    // 通知类型常量
    object NotificationType {
        const val COURSE = "course"
        const val HOMEWORK = "homework"
        const val MESSAGE = "message"
        const val EXAM = "exam"
        const val ACTIVITY = "activity"
    }

    // 通知通道
    private const val CHANNEL_COURSE = "capsule_course"
    private const val CHANNEL_HOMEWORK = "capsule_homework"
    private const val CHANNEL_MESSAGE = "capsule_message"
    private const val CHANNEL_EXAM = "capsule_exam"
    private const val CHANNEL_ACTIVITY = "capsule_activity"

    // 通知ID范围
    private const val ID_COURSE_START = 8000
    private const val ID_HOMEWORK_START = 8100
    private const val ID_MESSAGE_START = 8200
    private const val ID_EXAM_START = 8300
    private const val ID_ACTIVITY_START = 8400

    // Action常量
    private const val ACTION_REFRESH = "unified.capsule.REFRESH"
    const val ACTION_DISMISS = "unified.capsule.DISMISS"

    // 配色方案
    private object Colors {
        // 课程配色
        val COURSE_UPCOMING = 0xff007AFF.toInt()      // 蓝色 - 即将上课
        val COURSE_ONGOING = 0xff34C759.toInt()       // 绿色 - 进行中
        val COURSE_ENDING = 0xffFF9500.toInt()        // 橙色 - 快结束
        val COURSE_LAST = 0xffAF52DE.toInt()          // 紫色 - 临近结束

        // 作业配色
        val HOMEWORK_SAFE = 0xff34C759.toInt()        // 绿色 - 时间充裕
        val HOMEWORK_WARNING = 0xffFF9500.toInt()     // 橙色 - 快到期
        val HOMEWORK_URGENT = 0xffFF3B30.toInt()      // 红色 - 紧急

        // 消息配色
        val MESSAGE_INFO = 0xff007AFF.toInt()         // 蓝色 - 普通消息
        val MESSAGE_IMPORTANT = 0xffFF9500.toInt()    // 橙色 - 重要消息
        val MESSAGE_URGENT = 0xffFF3B30.toInt()       // 红色 - 紧急消息

        // 考试配色
        val EXAM_NORMAL = 0xff5856D6.toInt()          // 紫色 - 普通考试
        val EXAM_IMPORTANT = 0xffFF3B30.toInt()       // 红色 - 重要考试

        // 活动配色
        val ACTIVITY_NORMAL = 0xff32ADE6.toInt()      // 青色 - 普通活动
        val ACTIVITY_IMPORTANT = 0xffFF2D55.toInt()   // 粉色 - 重要活动
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences("unified_capsule", Context.MODE_PRIVATE)
    private fun manager(context: Context) =
        context.getSystemService(NotificationManager::class.java)
    private fun alarms(context: Context) =
        context.getSystemService(AlarmManager::class.java)

    /**
     * 配置统一胶囊通知
     *
     * @param arguments 包含以下字段：
     *   - enabledTypes: List<String> 启用的通知类型列表
     *   - courses: List<Map> 课程列表
     *   - homework: List<Map> 作业列表
     *   - messages: List<Map> 消息列表
     *   - exams: List<Map> 考试列表
     *   - activities: List<Map> 活动列表
     */
    fun configure(context: Context, arguments: Map<*, *>) {
        val enabledTypes = (arguments["enabledTypes"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList()

        prefs(context).edit().apply {
            putStringSet("enabled_types", enabledTypes.toSet())

            // 保存各类型的数据
            putString("courses", encodeList(arguments["courses"] as? List<*>))
            putString("homework", encodeList(arguments["homework"] as? List<*>))
            putString("messages", encodeList(arguments["messages"] as? List<*>))
            putString("exams", encodeList(arguments["exams"] as? List<*>))
            putString("activities", encodeList(arguments["activities"] as? List<*>))

            apply()
        }

        refresh(context)
    }

    /** Update one data stream without erasing the other capsule streams. */
    fun patch(context: Context, arguments: Map<*, *>) {
        val edit = prefs(context).edit()
        @Suppress("UNCHECKED_CAST")
        listOf("courses", "homework", "messages", "exams", "activities").forEach { key ->
            if (arguments.containsKey(key)) {
                edit.putString(key, encodeList(arguments[key] as? List<*>))
            }
        }
        if (arguments.containsKey("enabledTypes")) {
            edit.putStringSet(
                "enabled_types",
                ((arguments["enabledTypes"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList()).toSet(),
            )
        }
        edit.apply()
        refresh(context)
    }

    private fun encodeList(list: List<*>?): String {
        val array = JSONArray()
        list?.forEach { item ->
            if (item is Map<*, *>) {
                array.put(JSONObject(item))
            }
        }
        return array.toString()
    }

    private fun decodeList(json: String?): List<JSONObject> {
        if (json.isNullOrEmpty()) return emptyList()
        val array = JSONArray(json)
        return (0 until array.length()).map { array.getJSONObject(it) }
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
            "promotionAllowed" to (Build.VERSION.SDK_INT >= 36 &&
                manager(context).canPostPromotedNotifications()),
            "supportedTypes" to listOf(
                NotificationType.COURSE,
                NotificationType.HOMEWORK,
                NotificationType.MESSAGE,
                NotificationType.EXAM,
                NotificationType.ACTIVITY
            )
        )
    }

    fun refresh(context: Context) {
        val prefs = prefs(context)
        val enabledTypes = prefs.getStringSet("enabled_types", emptySet()) ?: emptySet()

        if (enabledTypes.isEmpty() || !manager(context).areNotificationsEnabled()) {
            cancelAll(context)
            return
        }

        val now = System.currentTimeMillis()

        // 创建通知通道
        createChannels(context)

        // 处理各类型通知
        if (enabledTypes.contains(NotificationType.COURSE)) {
            handleCourseNotifications(context, now)
        } else {
            manager(context).cancel(ID_COURSE_START)
        }

        if (enabledTypes.contains(NotificationType.HOMEWORK)) {
            handleHomeworkNotifications(context, now)
        } else {
            cancelRange(context, ID_HOMEWORK_START, 3)
        }

        if (enabledTypes.contains(NotificationType.MESSAGE)) {
            handleMessageNotifications(context, now)
        } else {
            cancelRange(context, ID_MESSAGE_START, 3)
        }

        if (enabledTypes.contains(NotificationType.EXAM)) {
            handleExamNotifications(context, now)
        } else {
            cancelRange(context, ID_EXAM_START, 2)
        }

        if (enabledTypes.contains(NotificationType.ACTIVITY)) {
            handleActivityNotifications(context, now)
        } else {
            cancelRange(context, ID_ACTIVITY_START, 2)
        }

        // 设置下次刷新
        scheduleNextRefresh(context, enabledTypes, now)
    }

    private fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return

        val nm = manager(context)

        // 课程通道
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL_COURSE,
            "📚 课程胶囊",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "显示课程信息、上课地点和进度"
            setShowBadge(false)
            enableLights(true)
            lightColor = Colors.COURSE_ONGOING
        })

        // 作业通道
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL_HOMEWORK,
            "✍️ 作业胶囊",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "显示作业截止时间和倒计时"
            setShowBadge(true)
            enableLights(true)
            lightColor = Colors.HOMEWORK_WARNING
        })

        // 消息通道
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL_MESSAGE,
            "📬 校园通知胶囊",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "显示校园通知和重要消息"
            setShowBadge(true)
            enableLights(true)
            lightColor = Colors.MESSAGE_INFO
        })

        // 考试通道
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL_EXAM,
            "📝 考试胶囊",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "显示考试信息和考场位置"
            setShowBadge(true)
            enableLights(true)
            lightColor = Colors.EXAM_NORMAL
        })

        // 活动通道
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL_ACTIVITY,
            "🎉 活动胶囊",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "显示校园活动和讲座信息"
            setShowBadge(false)
            enableLights(true)
            lightColor = Colors.ACTIVITY_NORMAL
        })
    }

    private fun handleCourseNotifications(context: Context, now: Long) {
        val courses = decodeList(prefs(context).getString("courses", null))
        val current = courses.firstOrNull { course ->
            now >= course.getLong("start") && now < course.getLong("end")
        }

        if (current != null) {
            publishCourseNotification(context, current, now)
        } else {
            manager(context).cancel(ID_COURSE_START)
        }
    }

    private fun publishCourseNotification(context: Context, course: JSONObject, now: Long) {
        val start = course.getLong("start")
        val end = course.getLong("end")
        val progress = ((now - start).toDouble() / (end - start) * 100).toInt().coerceIn(0, 100)
        val remaining = ((end - now + 59_999) / 60_000).toInt()

        val color = when {
            remaining > 40 -> Colors.COURSE_ONGOING
            remaining > 20 -> Colors.COURSE_ENDING
            else -> Colors.COURSE_LAST
        }

        val courseName = course.getString("name")
        val room = course.getString("room")
        val time = SimpleDateFormat("HH:mm", Locale.CHINA)
        val timeStr = "${time.format(Date(start))}–${time.format(Date(end))}"

        val builder = createNotificationBuilder(context, CHANNEL_COURSE)
            .setSmallIcon(R.drawable.ic_course_notification)
            .setContentTitle("📚 $courseName")
            .setContentText("📍 $room  •  ⏰ 还剩 $remaining 分钟")
            .setSubText("🕐 $timeStr")
            .setColor(color)
            .setOngoing(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setWhen(end)

        // 详细信息
        val detailText = buildString {
            appendLine("📚 课程：$courseName")
            appendLine("📍 教室：$room")
            appendLine("🕐 时间：$timeStr")
            appendLine("📊 进度：$progress%")
            appendLine("⏰ 距下课：$remaining 分钟")
        }

        builder.setStyle(NotificationCompat.BigTextStyle()
            .bigText(detailText)
            .setBigContentTitle("📚 正在上课"))

        applyDynamicIslandMetadata(builder, NotificationType.COURSE, progress)

        try {
            manager(context).notify(ID_COURSE_START, builder.build())
        } catch (_: SecurityException) {}
    }

    private fun handleHomeworkNotifications(context: Context, now: Long) {
        val homeworkList = decodeList(prefs(context).getString("homework", null))
        pruneDismissed(
            context,
            NotificationType.HOMEWORK,
            homeworkList.filter { it.optLong("deadline", 0) > now }.map { itemId(it) }.toSet(),
        )
        val dismissed = dismissedIds(context, NotificationType.HOMEWORK)
        val urgent = homeworkList.filter { hw ->
            val deadline = hw.getLong("deadline")
            deadline > now && deadline - now < 48 * 3600_000 && itemId(hw) !in dismissed
        }.sortedBy { it.getLong("deadline") }

        urgent.take(3).forEachIndexed { index, hw ->
            publishHomeworkNotification(context, hw, now, ID_HOMEWORK_START + index)
        }

        // 清除多余的通知
        for (i in urgent.size until 3) {
            manager(context).cancel(ID_HOMEWORK_START + i)
        }
    }

    private fun publishHomeworkNotification(
        context: Context,
        homework: JSONObject,
        now: Long,
        notificationId: Int
    ) {
        val title = homework.getString("title")
        val courseName = homework.optString("course", "")
        val deadline = homework.getLong("deadline")
        val hoursRemaining = ((deadline - now) / 3600_000).toInt()

        val color = when {
            hoursRemaining > 24 -> Colors.HOMEWORK_SAFE
            hoursRemaining > 6 -> Colors.HOMEWORK_WARNING
            else -> Colors.HOMEWORK_URGENT
        }

        val urgencyText = when {
            hoursRemaining > 24 -> "还有 ${hoursRemaining / 24} 天"
            hoursRemaining > 1 -> "还有 $hoursRemaining 小时"
            else -> "即将截止！"
        }

        val displayTitle = if (courseName.isNotEmpty()) "$courseName - $title" else title

        val time = SimpleDateFormat("MM月dd日 HH:mm", Locale.CHINA)
        val deadlineStr = time.format(Date(deadline))

        val builder = createNotificationBuilder(context, CHANNEL_HOMEWORK)
            .setSmallIcon(R.drawable.ic_course_notification)
            .setContentTitle("✍️ $displayTitle")
            .setContentText("⏰ ${urgencyText}截止")
            .setSubText("📅 $deadlineStr")
            .setColor(color)
            .setDeleteIntent(dismissIntent(context, NotificationType.HOMEWORK, itemId(homework), notificationId))
            .setOngoing(false)
            .setTimeoutAfter((deadline - now).coerceAtLeast(1))
            .setLargeIcon(createIconWithText(context, "✍️", color))

        val detailText = buildString {
            appendLine("✍️ 作业：$title")
            if (courseName.isNotEmpty()) {
                appendLine("📚 课程：$courseName")
            }
            appendLine("📅 截止时间：$deadlineStr")
            appendLine("⏰ 剩余时间：$urgencyText")
            if (hoursRemaining <= 6) {
                appendLine("⚠️ 请尽快完成！")
            }
        }

        builder.setStyle(NotificationCompat.BigTextStyle()
            .bigText(detailText)
            .setBigContentTitle("✍️ 作业提醒"))

        applyDynamicIslandMetadata(builder, NotificationType.HOMEWORK, hoursRemaining)

        try {
            manager(context).notify(notificationId, builder.build())
        } catch (_: SecurityException) {}
    }

    private fun handleMessageNotifications(context: Context, now: Long) {
        val messages = decodeList(prefs(context).getString("messages", null))
        val unreadMessages = messages.filter { msg -> !msg.optBoolean("read", false) }
        pruneDismissed(context, NotificationType.MESSAGE, unreadMessages.map { itemId(it) }.toSet())
        val dismissed = dismissedIds(context, NotificationType.MESSAGE)
        val unread = unreadMessages.filter { msg -> itemId(msg) !in dismissed }.take(3)

        unread.forEachIndexed { index, msg ->
            publishMessageNotification(context, msg, now, ID_MESSAGE_START + index)
        }

        for (i in unread.size until 3) {
            manager(context).cancel(ID_MESSAGE_START + i)
        }
    }

    private fun publishMessageNotification(
        context: Context,
        message: JSONObject,
        now: Long,
        notificationId: Int
    ) {
        val title = message.getString("title")
        val sender = message.optString("sender", "校园通知")
        val priority = message.optString("priority", "normal")
        val time = message.optLong("time", now)

        val color = when (priority) {
            "urgent" -> Colors.MESSAGE_URGENT
            "important" -> Colors.MESSAGE_IMPORTANT
            else -> Colors.MESSAGE_INFO
        }

        val icon = when (priority) {
            "urgent" -> "🚨"
            "important" -> "⚡"
            else -> "📬"
        }

        val timeFormat = SimpleDateFormat("HH:mm", Locale.CHINA)
        val timeStr = timeFormat.format(Date(time))

        val builder = createNotificationBuilder(context, CHANNEL_MESSAGE)
            .setSmallIcon(R.drawable.ic_course_notification)
            .setContentTitle("$icon $title")
            .setContentText("👤 $sender")
            .setSubText("🕐 $timeStr")
            .setColor(color)
            .setDeleteIntent(dismissIntent(context, NotificationType.MESSAGE, itemId(message), notificationId))
            .setOngoing(false)
            .setLargeIcon(createIconWithText(context, icon, color))

        val content = message.optString("content", "")
        if (content.isNotEmpty()) {
            builder.setStyle(NotificationCompat.BigTextStyle()
                .bigText(content)
                .setBigContentTitle("$icon $title")
                .setSummaryText("来自 $sender"))
        }

        applyDynamicIslandMetadata(builder, NotificationType.MESSAGE, 0)

        try {
            manager(context).notify(notificationId, builder.build())
        } catch (_: SecurityException) {}
    }

    private fun handleExamNotifications(context: Context, now: Long) {
        val exams = decodeList(prefs(context).getString("exams", null))
        val upcomingExams = exams.filter { exam ->
            val examTime = exam.getLong("time")
            examTime > now && examTime - now < 7 * 24 * 3600_000 // 7天内
        }
        pruneDismissed(context, NotificationType.EXAM, upcomingExams.map { itemId(it) }.toSet())
        val dismissed = dismissedIds(context, NotificationType.EXAM)
        val upcoming = upcomingExams.filter { itemId(it) !in dismissed }.sortedBy { it.getLong("time") }

        upcoming.take(2).forEachIndexed { index, exam ->
            publishExamNotification(context, exam, now, ID_EXAM_START + index)
        }

        for (i in upcoming.size until 2) {
            manager(context).cancel(ID_EXAM_START + i)
        }
    }

    private fun publishExamNotification(
        context: Context,
        exam: JSONObject,
        now: Long,
        notificationId: Int
    ) {
        val subject = exam.getString("subject")
        val location = exam.optString("location", "待定")
        val examTime = exam.getLong("time")
        val important = exam.optBoolean("important", false)

        val daysRemaining = ((examTime - now) / (24 * 3600_000)).toInt()
        val color = if (important) Colors.EXAM_IMPORTANT else Colors.EXAM_NORMAL

        val urgencyText = when {
            daysRemaining > 1 -> "还有 $daysRemaining 天"
            daysRemaining == 1 -> "明天考试"
            else -> "今天考试"
        }

        val timeFormat = SimpleDateFormat("MM月dd日 HH:mm", Locale.CHINA)
        val timeStr = timeFormat.format(Date(examTime))

        val builder = createNotificationBuilder(context, CHANNEL_EXAM)
            .setSmallIcon(R.drawable.ic_course_notification)
            .setContentTitle("📝 $subject")
            .setContentText("📍 $location  •  ⏰ $urgencyText")
            .setSubText("🕐 $timeStr")
            .setColor(color)
            .setDeleteIntent(dismissIntent(context, NotificationType.EXAM, itemId(exam), notificationId))
            .setOngoing(false)
            .setTimeoutAfter((examTime - now).coerceAtLeast(1))
            .setLargeIcon(createIconWithText(context, "📝", color))

        val detailText = buildString {
            appendLine("📝 考试科目：$subject")
            appendLine("📍 考场：$location")
            appendLine("🕐 时间：$timeStr")
            appendLine("⏰ 倒计时：$urgencyText")
            if (important) {
                appendLine("⚠️ 重要考试，请做好准备")
            }
        }

        builder.setStyle(NotificationCompat.BigTextStyle()
            .bigText(detailText)
            .setBigContentTitle("📝 考试提醒"))

        applyDynamicIslandMetadata(builder, NotificationType.EXAM, daysRemaining)

        try {
            manager(context).notify(notificationId, builder.build())
        } catch (_: SecurityException) {}
    }

    private fun handleActivityNotifications(context: Context, now: Long) {
        val activities = decodeList(prefs(context).getString("activities", null))
        val upcomingActivities = activities.filter { activity ->
            val activityTime = activity.getLong("time")
            activityTime > now && activityTime - now < 24 * 3600_000 // 24小时内
        }
        pruneDismissed(context, NotificationType.ACTIVITY, upcomingActivities.map { itemId(it) }.toSet())
        val dismissed = dismissedIds(context, NotificationType.ACTIVITY)
        val upcoming = upcomingActivities.filter { itemId(it) !in dismissed }.sortedBy { it.getLong("time") }

        upcoming.take(2).forEachIndexed { index, activity ->
            publishActivityNotification(context, activity, now, ID_ACTIVITY_START + index)
        }

        for (i in upcoming.size until 2) {
            manager(context).cancel(ID_ACTIVITY_START + i)
        }
    }

    private fun publishActivityNotification(
        context: Context,
        activity: JSONObject,
        now: Long,
        notificationId: Int
    ) {
        val name = activity.getString("name")
        val location = activity.optString("location", "待定")
        val activityTime = activity.getLong("time")
        val important = activity.optBoolean("important", false)

        val hoursRemaining = ((activityTime - now) / 3600_000).toInt()
        val color = if (important) Colors.ACTIVITY_IMPORTANT else Colors.ACTIVITY_NORMAL

        val urgencyText = when {
            hoursRemaining > 3 -> "还有 $hoursRemaining 小时"
            hoursRemaining > 0 -> "还有 $hoursRemaining 小时"
            else -> "即将开始"
        }

        val timeFormat = SimpleDateFormat("HH:mm", Locale.CHINA)
        val timeStr = timeFormat.format(Date(activityTime))

        val builder = createNotificationBuilder(context, CHANNEL_ACTIVITY)
            .setSmallIcon(R.drawable.ic_course_notification)
            .setContentTitle("🎉 $name")
            .setContentText("📍 $location  •  ⏰ $urgencyText")
            .setSubText("🕐 $timeStr")
            .setColor(color)
            .setDeleteIntent(dismissIntent(context, NotificationType.ACTIVITY, itemId(activity), notificationId))
            .setOngoing(false)
            .setTimeoutAfter((activityTime - now).coerceAtLeast(1))
            .setLargeIcon(createIconWithText(context, "🎉", color))

        val detailText = buildString {
            appendLine("🎉 活动：$name")
            appendLine("📍 地点：$location")
            appendLine("🕐 时间：$timeStr")
            appendLine("⏰ 倒计时：$urgencyText")
        }

        builder.setStyle(NotificationCompat.BigTextStyle()
            .bigText(detailText)
            .setBigContentTitle("🎉 活动提醒"))

        applyDynamicIslandMetadata(builder, NotificationType.ACTIVITY, hoursRemaining)

        try {
            manager(context).notify(notificationId, builder.build())
        } catch (_: SecurityException) {}
    }

    private fun createNotificationBuilder(context: Context, channelId: String): NotificationCompat.Builder {
        return if (Build.VERSION.SDK_INT >= 26) {
            NotificationCompat.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            NotificationCompat.Builder(context)
        }.apply {
            setShowWhen(true)
            setOnlyAlertOnce(true)
            setAutoCancel(false)
        }
    }

    private fun createProgressIcon(context: Context, progress: Int, color: Int, emoji: String): Bitmap {
        val size = 128
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        // Background circle
        paint.color = 0x30FFFFFF.toInt()
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 8f
        val radius = (size - 8f) / 2f
        val center = size / 2f
        canvas.drawCircle(center, center, radius, paint)

        // Progress arc
        paint.color = color
        paint.strokeCap = Paint.Cap.ROUND
        val rect = RectF(4f, 4f, size - 4f, size - 4f)
        canvas.drawArc(rect, -90f, progress * 3.6f, false, paint)

        // Emoji text
        paint.style = Paint.Style.FILL
        paint.color = 0xFFFFFFFF.toInt()
        paint.textSize = 48f
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.DEFAULT
        val yPos = center - (paint.descent() + paint.ascent()) / 2
        canvas.drawText(emoji, center, yPos, paint)

        return bitmap
    }

    private fun createIconWithText(context: Context, text: String, color: Int): Bitmap {
        val size = 128
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        // Background circle
        paint.color = color
        paint.style = Paint.Style.FILL
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)

        // Text
        paint.color = 0xFFFFFFFF.toInt()
        paint.textSize = 64f
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.DEFAULT
        val center = size / 2f
        val yPos = center - (paint.descent() + paint.ascent()) / 2
        canvas.drawText(text, center, yPos, paint)

        return bitmap
    }

    private fun applyDynamicIslandMetadata(
        builder: NotificationCompat.Builder,
        type: String,
        progress: Int
    ) {
        if (Build.VERSION.SDK_INT < 36) return

        val extras = Bundle().apply {
            if (type == NotificationType.COURSE) {
                putBoolean("android.requestPromotedOngoing", true)
            }

            // Honor Magic Capsule
            putString("honor.magic.capsule.style", "unified_notification")
            putInt("honor.magic.capsule.priority", when(type) {
                NotificationType.COURSE -> 3
                NotificationType.HOMEWORK -> 2
                NotificationType.EXAM -> 2
                NotificationType.MESSAGE -> 1
                NotificationType.ACTIVITY -> 1
                else -> 1
            })
            putString("honor.magic.capsule.type", type)

            // Xiaomi Capsule
            putString("xiaomi.capsule.mode", "live_activity")
            putBoolean("xiaomi.capsule.expand", true)
            putString("xiaomi.capsule.category", type)
        }

        builder.addExtras(extras)
    }

    private fun scheduleNextRefresh(context: Context, enabledTypes: Set<String>, now: Long) {
        val alarmManager = alarms(context)
        val intent = Intent(context, UnifiedCapsuleReceiver::class.java)
            .setAction(ACTION_REFRESH)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            9000,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val nextRefresh = nextRefreshAt(context, enabledTypes, now) ?: run {
            alarmManager.cancel(pendingIntent)
            return
        }

        try {
            if (Build.VERSION.SDK_INT < 31 || alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    nextRefresh,
                    pendingIntent
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    nextRefresh,
                    pendingIntent
                )
            }
        } catch (_: SecurityException) {}
    }

    private fun nextRefreshAt(context: Context, enabledTypes: Set<String>, now: Long): Long? {
        val candidates = mutableListOf<Long>()
        if (NotificationType.COURSE in enabledTypes) {
            decodeList(prefs(context).getString("courses", null)).forEach { course ->
                val start = course.optLong("start", 0)
                val end = course.optLong("end", 0)
                if (now >= start && now < end) candidates.add(now + 60_000)
                else {
                    if (start > now) candidates.add(start)
                    if (end > now) candidates.add(end)
                }
            }
        }
        if (NotificationType.HOMEWORK in enabledTypes) {
            decodeList(prefs(context).getString("homework", null)).forEach { item ->
                val deadline = item.optLong("deadline", 0)
                if (deadline > now) {
                    val entersWindow = deadline - 48 * 3600_000L
                    if (entersWindow > now) candidates.add(entersWindow)
                    candidates.add(deadline)
                }
            }
        }
        if (NotificationType.EXAM in enabledTypes) {
            decodeList(prefs(context).getString("exams", null)).forEach { item ->
                val time = item.optLong("time", 0)
                if (time > now) {
                    val entersWindow = time - 7 * 24 * 3600_000L
                    if (entersWindow > now) candidates.add(entersWindow)
                    candidates.add(time)
                }
            }
        }
        if (NotificationType.ACTIVITY in enabledTypes) {
            decodeList(prefs(context).getString("activities", null)).forEach { item ->
                val time = item.optLong("time", 0)
                if (time > now) {
                    val entersWindow = time - 24 * 3600_000L
                    if (entersWindow > now) candidates.add(entersWindow)
                    candidates.add(time)
                }
            }
        }
        return candidates.filter { it > now }.minOrNull()
    }

    private fun itemId(item: JSONObject): String = item.optString("id").ifBlank {
        "${item.optLong("time", item.optLong("deadline", 0))}:${item.optString("title")}"
    }

    private fun dismissedKey(type: String) = "dismissed_$type"

    private fun dismissedIds(context: Context, type: String): Set<String> =
        prefs(context).getStringSet(dismissedKey(type), emptySet())?.toSet() ?: emptySet()

    private fun pruneDismissed(context: Context, type: String, activeIds: Set<String>) {
        val old = dismissedIds(context, type)
        val retained = old.intersect(activeIds)
        if (old != retained) {
            prefs(context).edit().putStringSet(dismissedKey(type), retained).apply()
        }
    }

    private fun dismissIntent(
        context: Context,
        type: String,
        itemId: String,
        notificationId: Int,
    ): PendingIntent {
        val intent = Intent(context, UnifiedCapsuleReceiver::class.java)
            .setAction(ACTION_DISMISS)
            .putExtra("type", type)
            .putExtra("itemId", itemId)
            .putExtra("notificationId", notificationId)
        return PendingIntent.getBroadcast(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun dismiss(context: Context, intent: Intent) {
        val type = intent.getStringExtra("type") ?: return
        val itemId = intent.getStringExtra("itemId") ?: return
        val notificationId = intent.getIntExtra("notificationId", -1)
        if (notificationId >= 0) manager(context).cancel(notificationId)
        val dismissed = dismissedIds(context, type) + itemId
        prefs(context).edit().putStringSet(dismissedKey(type), dismissed).apply()
        refresh(context)
    }

    private fun cancelRange(context: Context, start: Int, count: Int) {
        repeat(count) { manager(context).cancel(start + it) }
    }

    fun cancelAll(context: Context) {
        val nm = manager(context)

        // 取消所有通知
        for (i in 0 until 10) {
            nm.cancel(ID_COURSE_START + i)
            nm.cancel(ID_HOMEWORK_START + i)
            nm.cancel(ID_MESSAGE_START + i)
            nm.cancel(ID_EXAM_START + i)
            nm.cancel(ID_ACTIVITY_START + i)
        }

        // 取消刷新alarm
        val alarmManager = alarms(context)
        val intent = Intent(context, UnifiedCapsuleReceiver::class.java)
            .setAction(ACTION_REFRESH)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            9000,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
    }
}

class UnifiedCapsuleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == UnifiedCapsuleNotifications.ACTION_DISMISS) {
            UnifiedCapsuleNotifications.dismiss(context, intent)
        } else {
            UnifiedCapsuleNotifications.refresh(context)
        }
    }
}
