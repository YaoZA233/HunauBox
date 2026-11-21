import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/ics_parser.dart';
import 'course_notification_settings_store.dart';
import 'course_schedule_service.dart';
import 'timetable_storage.dart';

/// Enhanced live course service with improved UI and dynamic island support
class EnhancedLiveCourseService {
  EnhancedLiveCourseService._();
  static final instance = EnhancedLiveCourseService._();
  static const channel = MethodChannel('hunaubox/enhanced_live_course');
  static const _legacyChannel = MethodChannel('hunaubox/live_course');

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
    await _legacyChannel.invokeMethod<void>('configure', {
      'enabled': false,
      'minutesBefore': store.settings.value.minutesBefore,
      'courses': const <Map<String, Object>>[],
    });
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

  /// Get capsule style information based on device manufacturer
  String getCapsuleStyleDescription(Map<String, dynamic> deviceInfo) {
    final style = deviceInfo['capsuleStyle'] as String?;
    final manufacturer = deviceInfo['manufacturer'] as String? ?? '';
    final hasIslandSupport = deviceInfo['dynamicIslandSupport'] == true;

    switch (style) {
      case 'honor_magic_capsule':
        return '✨ 荣耀灵动胶囊 - 支持智能展示\n'
            '在屏幕顶部以胶囊形态显示课程进度和剩余时间，'
            '轻触可快速查看详情或展开完整信息。';

      case 'huawei_live_window':
        return '🎯 华为实时窗口 - 动态信息展示\n'
            '在通知栏顶部以卡片形式展示课程状态，'
            '支持进度条和倒计时显示。';

      case 'xiaomi_notification_capsule':
        return '🔔 小米通知胶囊 - 智能聚合显示\n'
            '在状态栏以胶囊样式聚合展示课程信息，'
            '支持展开查看完整内容。';

      case 'oppo_sidebar':
        return '📱 OPPO 侧边栏通知\n'
            '支持侧边快速展示课程信息。';

      case 'vivo_notification_style':
        return '💫 vivo 通知样式\n'
            '优化的通知卡片展示，支持快捷操作。';

      default:
        if (hasIslandSupport) {
          return '📲 标准灵动岛适配\n'
              '您的设备 ($manufacturer) 支持类灵动岛功能，'
              '课程信息将以智能胶囊形式展示。';
        }
        return '📋 标准通知展示\n'
            '使用增强的通知样式，包含丰富的课程信息、'
            '进度条和快捷操作按钮。';
    }
  }

  /// Check if device supports dynamic island / capsule features
  bool supportsDynamicIsland(Map<String, dynamic> deviceInfo) {
    return deviceInfo['dynamicIslandSupport'] == true ||
        deviceInfo['liveUpdates'] == true;
  }
}
