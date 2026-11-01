import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/ics_parser.dart';
import 'course_notification_settings_store.dart';
import 'course_schedule_service.dart';
import 'timetable_storage.dart';

/// Android owns the clock and alarms, so tracking survives Flutter suspension.
class LiveCourseService {
  LiveCourseService._();
  static final instance = LiveCourseService._();
  static const channel = MethodChannel('hunaubox/live_course');
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static List<Map<String, Object>> encodeOccurrences(
    List<CourseOccurrence> occurrences,
  ) => [
    for (final item in occurrences)
      {
        'id': '${item.course.id}:${item.start.millisecondsSinceEpoch}',
        'name': item.course.name,
        'room': item.course.classroom.trim().isEmpty
            ? '教室待定'
            : item.course.classroom,
        'start': item.start.millisecondsSinceEpoch,
        'end': item.end.millisecondsSinceEpoch,
        'periods': '第 ${item.course.startPeriod}–${item.course.endPeriod} 节',
      },
  ];

  Future<List<CourseOccurrence>> _readOccurrences() async {
    final storage = TimetableStorage();
    final metadata = await storage.readMetadata();
    final monday = DateTime.tryParse('${metadata?['firstWeekMonday']}');
    final ics = await storage.readTimetable();
    if (monday == null || ics == null) return const [];
    return CourseScheduleService.upcomingOccurrences(
      courses: IcsParser.parse(ics),
      firstWeekMonday: monday,
      from: DateTime.now(),
      adjustments: await storage.readAdjustments(),
    );
  }

  Future<void> sync() async {
    if (!supported) return;
    final store = CourseNotificationSettingsStore.instance;
    await store.load();
    await channel.invokeMethod<void>('configure', {
      'enabled': store.settings.value.liveActivityEnabled,
      'minutesBefore': store.settings.value.minutesBefore,
      'courses': encodeOccurrences(
        store.settings.value.liveActivityEnabled
            ? await _readOccurrences()
            : const [],
      ),
    });
  }

  Future<Map<String, dynamic>> deviceInfo() async {
    if (!supported) return {'supported': false};
    return Map<String, dynamic>.from(
      await channel.invokeMapMethod<String, dynamic>('capabilities') ?? {},
    );
  }

  Future<bool> startCurrent() async {
    if (!supported) return false;
    await sync();
    return await channel.invokeMethod<bool>('startCurrent') ?? false;
  }

  Future<void> showSample({required bool upcoming}) async {
    if (!supported) return;
    await channel.invokeMethod<void>('sample', {'upcoming': upcoming});
  }

  Future<void> stopSample() async {
    if (supported) await channel.invokeMethod<void>('stopSample');
  }

  Future<void> openNotificationSettings() async {
    if (supported) await channel.invokeMethod<void>('openSettings');
  }
}
