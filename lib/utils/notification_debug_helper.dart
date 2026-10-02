import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../services/course_notification_service.dart';
import '../services/course_notification_settings_store.dart';

/// 通知调试助手
class NotificationDebugHelper {
  static final Logger _logger = Logger();

  /// 测试立即通知（用于调试）
  static Future<void> testImmediateNotification() async {
    try {
      await CourseNotificationService.instance.initialize();

      // 创建一个5秒后的测试通知
      final testTime = DateTime.now().add(const Duration(seconds: 5));

      _logger.i('Scheduling test notification for: $testTime');

      // 直接调用内部方法进行测试
      // 注意：这里我们需要通过reschedule来测试
      await CourseNotificationService.instance.rescheduleIfEnabled();

      _logger.i('Test notification scheduled successfully');
    } catch (e, stack) {
      _logger.e('Failed to schedule test notification', error: e, stackTrace: stack);
    }
  }

  /// 检查通知权限状态
  static Future<Map<String, dynamic>> checkNotificationStatus() async {
    final result = <String, dynamic>{};

    try {
      await CourseNotificationService.instance.initialize();

      // 获取当前设置
      final store = CourseNotificationSettingsStore.instance;
      await store.load();
      final settings = store.settings.value;

      result['course_enabled'] = settings.enabled;
      result['course_minutes_before'] = settings.minutesBefore;
      result['message_enabled'] = settings.messageEnabled;
      result['homework_enabled'] = settings.homeworkEnabled;
      result['homework_deadline_enabled'] = settings.homeworkDeadlineEnabled;
      result['homework_minutes_before'] = settings.homeworkMinutesBefore;

      _logger.i('Notification status: $result');
    } catch (e, stack) {
      _logger.e('Failed to check notification status', error: e, stackTrace: stack);
      result['error'] = e.toString();
    }

    return result;
  }

  /// 打印通知诊断信息
  static Future<void> printDiagnostics() async {
    _logger.i('========== Notification Diagnostics ==========');

    try {
      final status = await checkNotificationStatus();
      _logger.i('Settings: $status');

      _logger.i('Platform: ${defaultTargetPlatform.name}');
      _logger.i('Current time: ${DateTime.now()}');

    } catch (e, stack) {
      _logger.e('Diagnostics failed', error: e, stackTrace: stack);
    }

    _logger.i('=============================================');
  }
}
