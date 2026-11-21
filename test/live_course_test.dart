import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/models/course_model.dart';
import 'package:smart_hunan_agri/pages/live_course_page.dart';
import 'package:smart_hunan_agri/services/course_notification_settings_store.dart';
import 'package:smart_hunan_agri/services/course_schedule_service.dart';
import 'package:smart_hunan_agri/services/enhanced_live_course_service.dart';
import 'package:smart_hunan_agri/services/live_course_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LiveCourseService.channel, (call) async {
          calls.add(call);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(EnhancedLiveCourseService.channel, (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'capabilities') {
            return {
              'supported': true,
              'manufacturer': 'Test phone',
              'model': 'Android',
              'sdk': 35,
              'notificationsEnabled': true,
              'exactAlarms': false,
              'liveUpdates': false,
              'promoted': false,
            };
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LiveCourseService.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(EnhancedLiveCourseService.channel, null);
  });

  test('通知设置保留其他开关，课程实况默认关闭并可持久化', () async {
    const original = CourseNotificationSettings(
      enabled: true,
      minutesBefore: 20,
      homeworkEnabled: true,
    );
    expect(original.liveActivityEnabled, isFalse);
    final updated = original.copyWith(liveActivityEnabled: true);
    expect(updated.homeworkEnabled, isTrue);
    expect(updated.minutesBefore, 20);
    await CourseNotificationSettingsStore.instance.save(updated);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('course_live_activity_enabled'), isTrue);
    await CourseNotificationSettingsStore.instance.save(original);
  });

  test('本地课程传入原生层时保留绝对时间、独立场次标识和缺省教室', () {
    const course = CourseModel(
      id: 'botany',
      name: '植物生理学',
      teacher: '',
      classroom: ' ',
      weeks: '1-16',
      periods: '3-4',
      dayOfWeek: 1,
      startPeriod: 3,
      endPeriod: 4,
    );
    final start = DateTime(2026, 10, 26, 9, 50);
    final end = DateTime(2026, 10, 26, 11, 30);
    final encoded = LiveCourseService.encodeOccurrences([
      CourseOccurrence(course: course, start: start, end: end),
      CourseOccurrence(
        course: course,
        start: start.add(const Duration(days: 7)),
        end: end.add(const Duration(days: 7)),
      ),
    ]);
    expect(encoded.first['start'], start.millisecondsSinceEpoch);
    expect(encoded.first['end'], end.millisecondsSinceEpoch);
    expect(encoded.first['room'], '教室待定');
    expect(encoded.first['id'], isNot(encoded.last['id']));
  });

  for (final brightness in Brightness.values) {
    testWidgets('课程实况在窄屏大字 $brightness 可读且正确说明系统支持', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: brightness,
            colorSchemeSeed: Colors.green,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.7),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: const LiveCoursePage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('下一站，教室。'), findsOneWidget);
      await tester.ensureVisible(find.text('课前'));
      await tester.tap(find.text('课前'));
      await tester.pumpAndSettle();
      expect(find.text('12 分钟后上课'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('系统通知设置'), 300);
      expect(find.textContaining('当前使用原生通知栏展示'), findsOneWidget);
      await tester.tap(find.text('系统通知设置'));
      await tester.pumpAndSettle();
      expect(calls.any((call) => call.method == 'openSettings'), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
