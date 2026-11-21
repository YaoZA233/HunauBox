import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'course_schedule_service.dart';
import 'enhanced_live_course_service.dart';

/// Compatibility facade for existing routes; Android uses one course notification implementation.
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

  Future<void> sync() => EnhancedLiveCourseService.instance.sync();

  Future<Map<String, dynamic>> deviceInfo() =>
      EnhancedLiveCourseService.instance.deviceInfo();

  Future<bool> startCurrent() =>
      EnhancedLiveCourseService.instance.startCurrent();

  Future<void> showSample({required bool upcoming}) =>
      EnhancedLiveCourseService.instance.showSample(upcoming: upcoming);

  Future<void> stopSample() => EnhancedLiveCourseService.instance.stopSample();

  Future<void> openNotificationSettings() =>
      EnhancedLiveCourseService.instance.openNotificationSettings();
}
