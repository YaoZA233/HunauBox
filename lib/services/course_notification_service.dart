import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../utils/ics_parser.dart';
import 'course_notification_settings_store.dart';
import 'course_schedule_service.dart';
import 'timetable_storage.dart';

class CourseNotificationService {
  CourseNotificationService._();

  static final instance = CourseNotificationService._();
  static const _channelId = 'course_reminders';
  static const _maxScheduledNotifications = 60;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _notifications.initialize(settings: settings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted = await android?.requestNotificationsPermission();
    final ios = _notifications
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await ios?.requestPermissions(alert: true, badge: true, sound: true);
    return androidGranted ?? iosGranted ?? true;
  }

  Future<void> rescheduleIfEnabled() async {
    try {
      await CourseNotificationSettingsStore.instance.load();
      final settings = CourseNotificationSettingsStore.instance.settings.value;
      if (settings.enabled) {
        await reschedule(minutesBefore: settings.minutesBefore);
      }
    } catch (_) {
      // A failed background restore must not affect application startup.
    }
  }

  Future<void> reschedule({required int minutesBefore}) async {
    await initialize();
    await _cancelCourseNotifications();

    final storage = TimetableStorage();
    final metadata = await storage.readMetadata();
    final icsContent = await storage.readTimetable();
    final firstWeekMondayValue = metadata?['firstWeekMonday'];
    if (icsContent == null || firstWeekMondayValue is! String) return;

    final firstWeekMonday = DateTime.tryParse(firstWeekMondayValue);
    if (firstWeekMonday == null) return;

    final now = DateTime.now();
    final occurrences = CourseScheduleService.upcomingOccurrences(
      courses: IcsParser.parse(icsContent),
      firstWeekMonday: firstWeekMonday,
      from: now.subtract(Duration(minutes: minutesBefore)),
    );
    var notificationId = 1;
    for (final occurrence in occurrences) {
      final scheduledAt = occurrence.start.subtract(Duration(minutes: minutesBefore));
      if (!scheduledAt.isAfter(now)) continue;
      await _notifications.zonedSchedule(
        id: notificationId++,
        title: '下一节课：${occurrence.course.name}',
        body:
            '$minutesBefore分钟后在${occurrence.course.classroom.trim().isEmpty ? '待定教室' : occurrence.course.classroom}上课',
        scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            '上课提醒',
            channelDescription: '下一节课程开始前的提醒',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      if (notificationId > _maxScheduledNotifications) break;
    }
  }

  Future<void> cancelAll() async {
    await initialize();
    await _cancelCourseNotifications();
  }

  Future<void> _cancelCourseNotifications() async {
    for (var notificationId = 1;
        notificationId <= _maxScheduledNotifications;
        notificationId++) {
      await _notifications.cancel(id: notificationId);
    }
  }
}
