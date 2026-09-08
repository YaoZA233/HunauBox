import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/homework_model.dart';
import '../models/message_model.dart';
import '../utils/ics_parser.dart';
import 'course_notification_settings_store.dart';
import 'course_schedule_service.dart';
import 'homework_storage.dart';
import 'timetable_storage.dart';

class CourseNotificationService with WidgetsBindingObserver {
  CourseNotificationService._();
  static final instance = CourseNotificationService._();
  static const _channelId = 'course_reminders';
  static const _messageChannelId = 'message_updates';
  static const _homeworkChannelId = 'homework_updates';
  static const _homeworkDeadlineChannelId = 'homework_deadlines';
  static const _maxScheduledNotifications = 60;
  static const _homeworkNotificationStartId = 1001;
  static const _seenMessagesKey = 'notification_seen_message_ids';
  static const _seenHomeworkKey = 'notification_seen_homework_ids';
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final Map<int, Timer> _foregroundTimers = <int, Timer>{};
  bool _initialized = false;
  bool _isForeground = false;
  bool _observerRegistered = false;
  Future<void> _scheduleOperation = Future<void>.value();

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
    );
    await _notifications.initialize(settings: settings);
    _isForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }
    _initialized = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_isForeground == foreground) return;
    _isForeground = foreground;
    unawaited(rescheduleIfEnabled());
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted = await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    final ios = _notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await ios?.requestPermissions(alert: true, badge: true, sound: true);
    return androidGranted ?? iosGranted ?? true;
  }

  Future<void> rescheduleIfEnabled() {
    return _enqueueSchedule(() async {
      final store = CourseNotificationSettingsStore.instance;
      await store.load();
      final settings = store.settings.value;
      if (!settings.enabled && !settings.homeworkDeadlineEnabled) {
        await initialize();
        await _cancelScheduledNotifications();
        _cancelForegroundTimers();
        return;
      }
      await _rescheduleInternal(settings);
    });
  }

  Future<void> reschedule({required int minutesBefore}) {
    return _enqueueSchedule(() async {
      final store = CourseNotificationSettingsStore.instance;
      await store.load();
      await _rescheduleInternal(store.settings.value.copyWith(minutesBefore: _validMinutes(minutesBefore)));
    });
  }

  Future<void> cancelAll() {
    return _enqueueSchedule(() async {
      await initialize();
      await _cancelScheduledNotifications();
      _cancelForegroundTimers();
    });
  }

  Future<void> _rescheduleInternal(CourseNotificationSettings settings) async {
    await initialize();
    await _cancelScheduledNotifications();
    _cancelForegroundTimers();
    if (settings.enabled) await _scheduleCourseReminders(settings.minutesBefore);
    if (settings.homeworkDeadlineEnabled) await _scheduleHomeworkDeadlineReminders(settings.homeworkMinutesBefore);
  }

  Future<void> _scheduleCourseReminders(int minutesBefore) async {
    final storage = TimetableStorage();
    final metadata = await storage.readMetadata();
    final icsContent = await storage.readTimetable();
    final value = metadata?['firstWeekMonday'];
    if (icsContent == null || value is! String) return;
    final monday = DateTime.tryParse(value);
    if (monday == null) return;
    final now = DateTime.now();
    final occurrences = CourseScheduleService.upcomingOccurrences(courses: IcsParser.parse(icsContent), firstWeekMonday: monday, from: now.subtract(Duration(minutes: minutesBefore)), limit: _maxScheduledNotifications);
    var id = 1;
    for (final occurrence in occurrences) {
      final at = occurrence.start.subtract(Duration(minutes: minutesBefore));
      if (!at.isAfter(now)) continue;
      await _scheduleNotification(id: id++, title: '下一节课：${occurrence.course.name}', body: '$minutesBefore分钟后在${occurrence.course.classroom.trim().isEmpty ? '待定教室' : occurrence.course.classroom}上课', scheduledAt: at, notificationDetails: const NotificationDetails(android: AndroidNotificationDetails(_channelId, '上课提醒', channelDescription: '下一节课程开始前的提醒', importance: Importance.high, priority: Priority.high), iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true)));
      if (id > _maxScheduledNotifications) break;
    }
  }

  Future<void> _scheduleHomeworkDeadlineReminders(int minutesBefore) async {
    final homework = await HomeworkStorage().readHomeworkList() ?? const <HomeworkModel>[];
    final now = DateTime.now();
    var id = _homeworkNotificationStartId;
    for (final item in homework) {
      final deadline = item.endTime;
      if (item.status != HomeworkStatus.pending || deadline == null) continue;
      final at = deadline.subtract(Duration(minutes: minutesBefore));
      if (!at.isAfter(now)) continue;
      final subject = item.courseName.trim().isEmpty ? item.title : '${item.courseName}：${item.title}';
      await _scheduleNotification(id: id++, title: '作业截止提醒', body: '$subject将在${_formatDateTime(deadline)}截止（提前$minutesBefore分钟提醒）', scheduledAt: at, notificationDetails: const NotificationDetails(android: AndroidNotificationDetails(_homeworkDeadlineChannelId, '作业截止提醒', channelDescription: '作业截止前的提醒', importance: Importance.high, priority: Priority.high), iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true)));
      if (id >= _homeworkNotificationStartId + _maxScheduledNotifications) break;
    }
  }

  Future<void> _scheduleNotification({required int id, required String title, required String body, required DateTime scheduledAt, required NotificationDetails notificationDetails}) async {
    final delay = scheduledAt.difference(DateTime.now());
    if (delay <= Duration.zero) return;
    // Dart timers are useful while the UI is visible, but have a platform
    // duration limit. Keep long-range reminders in the OS scheduler.
    if (_isForeground && delay <= const Duration(days: 20)) {
      _foregroundTimers[id] = Timer(delay, () async {
        _foregroundTimers.remove(id);
        if (_isForeground) await _notifications.show(id: id, title: title, body: body, notificationDetails: notificationDetails);
      });
      return;
    }
    final date = tz.TZDateTime.from(scheduledAt, tz.local);
    try {
      await _notifications.zonedSchedule(id: id, title: title, body: body, scheduledDate: date, notificationDetails: notificationDetails, androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      await _notifications.zonedSchedule(id: id, title: title, body: body, scheduledDate: date, notificationDetails: notificationDetails, androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  Future<void> notifyNewMessages(List<MessageModel> messages) async => _notifyNewItems(ids: messages.map(_messageId).toList(), titleFor: (_) => '新校园通知', bodyFor: (i) => messages[i].title, preference: (s) => s.messageEnabled, seenKey: _seenMessagesKey, channelId: _messageChannelId, channelName: '消息通知');

  Future<void> notifyNewHomework(List<HomeworkModel> homework) async => _notifyNewItems(ids: homework.map((item) => item.id).toList(), titleFor: (_) => '新作业提醒', bodyFor: (i) { final item = homework[i]; return item.courseName.isEmpty ? item.title : '${item.courseName}：${item.title}'; }, preference: (s) => s.homeworkEnabled, seenKey: _seenHomeworkKey, channelId: _homeworkChannelId, channelName: '作业通知');

  Future<void> _notifyNewItems({required List<String> ids, required String Function(int) titleFor, required String Function(int) bodyFor, required bool Function(CourseNotificationSettings) preference, required String seenKey, required String channelId, required String channelName}) async {
    await initialize();
    final store = CourseNotificationSettingsStore.instance;
    await store.load();
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getStringList(seenKey);
    final clean = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (previous == null) { await prefs.setStringList(seenKey, clean); return; }
    final indexes = <int>[];
    for (var i = 0; i < ids.length; i++) { if (ids[i].isNotEmpty && !previous.contains(ids[i])) indexes.add(i); }
    final seen = <String>{...previous, ...clean}.toList();
    if (seen.length > 500) seen.removeRange(0, seen.length - 500);
    await prefs.setStringList(seenKey, seen);
    if (!preference(store.settings.value)) return;
    for (final (position, index) in indexes.take(3).indexed) {
      await _notifications.show(id: (DateTime.now().millisecondsSinceEpoch + position).remainder(1 << 31), title: titleFor(index), body: bodyFor(index), notificationDetails: NotificationDetails(android: AndroidNotificationDetails(channelId, channelName, channelDescription: channelName, importance: Importance.defaultImportance, priority: Priority.defaultPriority), iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true)));
    }
  }

  String _messageId(MessageModel message) => message.uuid.isNotEmpty ? message.uuid : (message.idCode.isNotEmpty ? message.idCode : '${message.title}|${message.sendTime}');

  Future<void> _cancelScheduledNotifications() async {
    for (var id = 1; id <= _maxScheduledNotifications; id++) await _notifications.cancel(id: id);
    for (var id = _homeworkNotificationStartId; id < _homeworkNotificationStartId + _maxScheduledNotifications; id++) await _notifications.cancel(id: id);
  }

  void _cancelForegroundTimers() { for (final timer in _foregroundTimers.values) timer.cancel(); _foregroundTimers.clear(); }
  Future<void> _enqueueSchedule(Future<void> Function() action) { final next = _scheduleOperation.then((_) => action()); _scheduleOperation = next.catchError((_) {}); return next; }
  static int _validMinutes(int value) => const [10, 15, 20, 30].contains(value) ? value : 15;
  static String _formatDateTime(DateTime value) { final v = value.toLocal(); String two(int n) => n.toString().padLeft(2, '0'); return '${v.month}月${v.day}日 ${two(v.hour)}:${two(v.minute)}'; }
}
