import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CourseNotificationSettings {
  const CourseNotificationSettings({
    required this.enabled,
    required this.minutesBefore,
    this.messageEnabled = false,
    this.homeworkEnabled = false,
    this.homeworkDeadlineEnabled = false,
    this.homeworkMinutesBefore = 15,
  });

  final bool enabled;
  final int minutesBefore;
  final bool messageEnabled;
  final bool homeworkEnabled;
  final bool homeworkDeadlineEnabled;
  final int homeworkMinutesBefore;

  CourseNotificationSettings copyWith({
    bool? enabled,
    int? minutesBefore,
    bool? messageEnabled,
    bool? homeworkEnabled,
    bool? homeworkDeadlineEnabled,
    int? homeworkMinutesBefore,
  }) {
    return CourseNotificationSettings(
      enabled: enabled ?? this.enabled,
      minutesBefore: minutesBefore ?? this.minutesBefore,
      messageEnabled: messageEnabled ?? this.messageEnabled,
      homeworkEnabled: homeworkEnabled ?? this.homeworkEnabled,
      homeworkDeadlineEnabled:
          homeworkDeadlineEnabled ?? this.homeworkDeadlineEnabled,
      homeworkMinutesBefore:
          homeworkMinutesBefore ?? this.homeworkMinutesBefore,
    );
  }
}

class CourseNotificationSettingsStore {
  CourseNotificationSettingsStore._();

  static final instance = CourseNotificationSettingsStore._();
  static const _enabledKey = 'course_notification_enabled';
  static const _minutesKey = 'course_notification_minutes_before';
  static const _messageEnabledKey = 'message_notification_enabled';
  static const _homeworkEnabledKey = 'homework_notification_enabled';
  static const _homeworkDeadlineEnabledKey =
      'homework_deadline_notification_enabled';
  static const _homeworkMinutesKey = 'homework_notification_minutes_before';

  final ValueNotifier<CourseNotificationSettings> settings = ValueNotifier(
    const CourseNotificationSettings(enabled: false, minutesBefore: 15),
  );
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    settings.value = CourseNotificationSettings(
      enabled: prefs.getBool(_enabledKey) ?? false,
      minutesBefore: _validMinutes(prefs.getInt(_minutesKey) ?? 15),
      messageEnabled: prefs.getBool(_messageEnabledKey) ?? false,
      homeworkEnabled: prefs.getBool(_homeworkEnabledKey) ?? false,
      homeworkDeadlineEnabled:
          prefs.getBool(_homeworkDeadlineEnabledKey) ?? false,
      homeworkMinutesBefore: _validMinutes(
        prefs.getInt(_homeworkMinutesKey) ?? 15,
      ),
    );
    _loaded = true;
  }

  Future<void> save(CourseNotificationSettings value) async {
    settings.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value.enabled);
    await prefs.setInt(_minutesKey, _validMinutes(value.minutesBefore));
    await prefs.setBool(_messageEnabledKey, value.messageEnabled);
    await prefs.setBool(_homeworkEnabledKey, value.homeworkEnabled);
    await prefs.setBool(
      _homeworkDeadlineEnabledKey,
      value.homeworkDeadlineEnabled,
    );
    await prefs.setInt(
      _homeworkMinutesKey,
      _validMinutes(value.homeworkMinutesBefore),
    );
    _loaded = true;
  }

  static int _validMinutes(int value) {
    return const [10, 15, 20, 30].contains(value) ? value : 15;
  }
}
