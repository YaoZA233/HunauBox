import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/pages/semester_courses_page.dart';
import 'package:smart_hunan_agri/pages/timetable_page.dart';
import 'package:smart_hunan_agri/services/timetable_adjustment_service.dart';

import 'timetable_adjustment_service_test.dart' show course;
import 'timetable_adjustment_widget_test.dart' show MemoryTimetableStorage;

void main() {
  final monday = DateTime(2026, 10, 5);
  final courses = [
    course('植物学').copyWith(teacher: '李老师', classroom: '教学楼 A101'),
    course(
      '植物学实验',
      day: 3,
      start: 5,
      end: 6,
      weeks: '2,4',
    ).copyWith(name: '植物学', teacher: '王老师', classroom: '实验楼 B203'),
    course(
      '土壤学',
      day: 5,
      start: 3,
      end: 4,
      weeks: '5-8',
    ).copyWith(teacher: '陈老师', classroom: ''),
  ];

  testWidgets('右上角聚合为一个菜单，可进入包含整学期课程的列表', (tester) async {
    final storage = MemoryTimetableStorage(monday);
    await tester.pumpWidget(MaterialApp(home: TimetablePage(storage: storage)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('课表功能'), findsOneWidget);
    expect(find.byTooltip('导入课表'), findsNothing);
    expect(find.byTooltip('临时调课'), findsNothing);
    await tester.tap(find.byTooltip('课表功能'));
    await tester.pumpAndSettle();
    for (final text in ['本学期课程', '临时调课', '回到本周', '导入课表', '导出 ICS']) {
      expect(find.text(text), findsOneWidget);
    }
    await tester.tap(find.text('本学期课程'));
    await tester.pumpAndSettle();
    expect(find.byType(SemesterCoursesPage), findsOneWidget);
    expect(
      tester
          .widget<SemesterCoursesPage>(find.byType(SemesterCoursesPage))
          .courses,
      storage.courses,
    );
    expect(find.text('共 3 门课程 · 3 条上课安排'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '土壤学');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Card), matching: find.text('土壤学')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('同名课程合并展示，保留不同时间、周次、老师、教室', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SemesterCoursesPage(courses: courses, firstWeekMonday: monday),
      ),
    );
    expect(find.text('共 2 门课程 · 3 条上课安排'), findsOneWidget);
    expect(find.text('植物学'), findsOneWidget);
    expect(find.text('时间：星期一 · 第1-2节 · 08:00–09:40'), findsOneWidget);
    expect(find.text('时间：星期三 · 第5-6节 · 14:30–16:10'), findsOneWidget);
    expect(find.text('周次：第1-3周'), findsOneWidget);
    expect(find.text('周次：第2,4周'), findsOneWidget);
    expect(find.text('老师：李老师'), findsOneWidget);
    expect(find.text('老师：王老师'), findsOneWidget);
    expect(find.text('教室：教学楼 A101'), findsOneWidget);
    expect(find.text('教室：实验楼 B203'), findsOneWidget);
    expect(find.text('日期：2026年10月5日 至 2026年10月19日（按上述周次上课）'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '土壤学');
    await tester.pumpAndSettle();
    expect(find.text('教室：暂未提供'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索课程、老师、教室，清除后恢复全部课程', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SemesterCoursesPage(courses: courses)),
    );
    for (final query in ['植物学', '王老师', ' b203 ']) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(Card), matching: find.text('植物学')),
        findsOneWidget,
      );
      expect(find.text('土壤学'), findsNothing);
    }
    await tester.enterText(find.byType(TextField), '没有的课程');
    await tester.pumpAndSettle();
    expect(find.textContaining('没有找到相关课程'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.text('植物学'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '陈老师');
    await tester.pumpAndSettle();
    expect(find.text('土壤学'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('课程详情展示跨周调课与停课，课程总数保留', (tester) async {
    final changes = [
      ...TimetableAdjustmentService.forWeeks(
        course: courses.first,
        sourceWeeks: {1},
        targetWeek: 4,
        targetDay: 4,
        start: 7,
        end: 8,
      ),
      ...TimetableAdjustmentService.forWeeks(
        course: courses.first,
        sourceWeeks: {2},
        targetDay: 1,
        start: 1,
        end: 2,
        cancelled: true,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: SemesterCoursesPage(
          courses: courses,
          firstWeekMonday: monday,
          adjustments: changes,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '植物学');
    await tester.pumpAndSettle();
    final title = find.text('临时安排（2 次）');
    await tester.ensureVisible(title);
    expect(title, findsOneWidget);
    expect(find.textContaining('2026年10月29日（第4周 星期四）'), findsOneWidget);
    expect(find.textContaining('第7-8节 · 16:35–18:15'), findsOneWidget);
    expect(find.textContaining('2026年10月12日（第2周 星期一） → 停课'), findsOneWidget);
    expect(find.text('共 2 门课程 · 3 条上课安排'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有课程时提供说明，缺少学期日期时仍显示上课时间', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SemesterCoursesPage(courses: [])),
    );
    expect(find.textContaining('导入课表后'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: SemesterCoursesPage(
          courses: [course('测试课程').copyWith(teacher: '', classroom: '')],
        ),
      ),
    );
    expect(find.text('时间：星期一 · 第1-2节 · 08:00–09:40'), findsOneWidget);
    expect(find.text('老师：暂未提供'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('全部课程页 320px、大字体、${brightness.name} 无溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: SemesterCoursesPage(courses: courses, firstWeekMonday: monday),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
