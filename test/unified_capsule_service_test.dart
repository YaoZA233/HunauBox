import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/services/course_notification_settings_store.dart';
import 'package:smart_hunan_agri/services/unified_capsule_service.dart';

void main() {
  test('本地消息提醒开启时胶囊不再重复投递消息', () {
    final effective = UnifiedCapsuleService.resolveEffectiveEnabledTypes(
      {
        UnifiedCapsuleService.typesCourse,
        UnifiedCapsuleService.typesMessage,
        UnifiedCapsuleService.typesHomework,
      },
      const CourseNotificationSettings(
        enabled: false,
        minutesBefore: 15,
        messageEnabled: true,
      ),
    );

    expect(effective, {
      UnifiedCapsuleService.typesCourse,
      UnifiedCapsuleService.typesHomework,
    });
  });

  test('任一作业提醒开启时只保留一个作业通知来源', () {
    final newAssignmentEnabled =
        UnifiedCapsuleService.resolveEffectiveEnabledTypes(
          {UnifiedCapsuleService.typesHomework},
          const CourseNotificationSettings(
            enabled: false,
            minutesBefore: 15,
            homeworkEnabled: true,
          ),
        );
    final deadlineEnabled = UnifiedCapsuleService.resolveEffectiveEnabledTypes(
      {UnifiedCapsuleService.typesHomework},
      const CourseNotificationSettings(
        enabled: false,
        minutesBefore: 15,
        homeworkDeadlineEnabled: true,
      ),
    );

    expect(newAssignmentEnabled, isEmpty);
    expect(deadlineEnabled, isEmpty);
  });

  test('本地提醒关闭时保留用户配置的胶囊类别', () {
    const configured = {
      UnifiedCapsuleService.typesMessage,
      UnifiedCapsuleService.typesHomework,
    };
    final effective = UnifiedCapsuleService.resolveEffectiveEnabledTypes(
      configured,
      const CourseNotificationSettings(enabled: false, minutesBefore: 15),
    );

    expect(effective, configured);
  });
}
