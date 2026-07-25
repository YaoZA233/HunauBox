import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CourseNotificationSettings {
  const CourseNotificationSettings({
    required this.enabled,
    required this.minutesBefore,
  });

  final bool enabled;
  final int minutesBefore;

  CourseNotificationSettings copyWith({bool? enabled, int? minutesBefore}) {
    return CourseNotificationSettings(
      enabled: enabled ?? this.enabled,
      minutesBefore: minutesBefore ?? this.minutesBefore,
    );
  }
}

class CourseNotificationSettingsStore {
  CourseNotificationSettingsStore._();

  static final instance = CourseNotificationSettingsStore._();
  static const _enabledKey = 'course_notification_enabled';
  static const _minutesKey = 'course_notification_minutes_before';

  final ValueNotifier<CourseNotificationSettings> settings =
      ValueNotifier(const CourseNotificationSettings(enabled: false, minutesBefore: 15));
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    settings.value = CourseNotificationSettings(
      enabled: prefs.getBool(_enabledKey) ?? false,
      minutesBefore: prefs.getInt(_minutesKey) ?? 15,
    );
    _loaded = true;
  }

  Future<void> save(CourseNotificationSettings value) async {
    settings.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value.enabled);
    await prefs.setInt(_minutesKey, value.minutesBefore);
    _loaded = true;
  }
}
