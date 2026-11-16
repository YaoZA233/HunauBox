import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:smart_hunan_agri/models/chaoxing_course.dart';
import 'package:smart_hunan_agri/pages/chaoxing_courses_page.dart';
import 'package:smart_hunan_agri/providers/chaoxing_course_provider.dart';
import 'package:smart_hunan_agri/services/chaoxing_course_service.dart';

const courses = [
  ChaoxingCourse(
    id: '1:2',
    name: '基础化学实验',
    teacher: '李老师',
    url: 'https://mooc1.chaoxing.com/',
    finishedJobs: 30,
    totalJobs: 84,
  ),
  ChaoxingCourse(
    id: '3:4',
    name: '摄影技术',
    teacher: '王老师',
    folder: '完结',
    url: 'https://mooc1.chaoxing.com/',
  ),
];
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('search and folder filters combine and can be cleared', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chaoxingCoursesProvider.overrideWith((ref) async => courses),
        ],
        child: const MaterialApp(home: ChaoxingCoursesPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我学的课 · 2 门'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(find.text('任务点 30/84 · 35%'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '王老师');
    await tester.pumpAndSettle();
    expect(find.text('摄影技术'), findsOneWidget);
    expect(find.text('基础化学实验'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '未分组'));
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的课程'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('基础化学实验'), findsOneWidget);
    expect(find.text('摄影技术'), findsNothing);
  });
  testWidgets('retry recovers from login error', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chaoxingCoursesProvider.overrideWith((ref) async {
            if (++attempts == 1) {
              throw const ChaoxingCourseException('请登录学习通', needsLogin: true);
            }
            return courses;
          }),
          chaoxingCourseFetcherProvider.overrideWithValue(() async {
            attempts++;
            return courses;
          }),
        ],
        child: const MaterialApp(home: ChaoxingCoursesPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('打开学习通 / 登录'), findsOneWidget);
    await tester.tap(find.text('重新同步'));
    await tester.pumpAndSettle();
    expect(find.text('我学的课 · 2 门'), findsOneWidget);
    expect(attempts, 2);
  });
  for (final size in [
    const Size(320, 700),
    const Size(375, 812),
    const Size(812, 375),
    const Size(1024, 768),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('supports $size, $brightness and large text', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chaoxingCoursesProvider.overrideWith((ref) async => courses),
            ],
            child: MaterialApp(
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.green,
                  brightness: brightness,
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: const ChaoxingCoursesPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
