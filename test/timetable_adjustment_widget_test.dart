import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/models/course_model.dart';
import 'package:smart_hunan_agri/models/timetable_adjustment.dart';
import 'package:smart_hunan_agri/pages/agent_page.dart';
import 'package:smart_hunan_agri/pages/timetable_page.dart';
import 'package:smart_hunan_agri/services/timetable_adjustment_service.dart';
import 'package:smart_hunan_agri/services/timetable_storage.dart';
import 'package:smart_hunan_agri/widgets/timetable_adjustment_form.dart';
import 'package:smart_hunan_agri/widgets/weekly_calendar_view.dart';

import 'agent_widget_test.dart' show app, memorySettings;
import 'timetable_adjustment_service_test.dart' show course;

class MemoryTimetableStorage extends TimetableStorage {
  MemoryTimetableStorage(this.monday);
  final DateTime monday;
  final courses = [
    course('植物学'),
    course('土壤学', weeks: '2,4'),
    course('实验', end: 4),
  ];
  List<TimetableAdjustment> adjustments = [];
  bool failWrite = false;
  @override
  Future<bool> hasLocalTimetable() async => true;
  @override
  Future<String?> readTimetable() async => 'BEGIN:VCALENDAR\nEND:VCALENDAR';
  @override
  Future<Map<String, dynamic>?> readMetadata() async => {
    'firstWeekMonday': monday.toIso8601String(),
  };
  @override
  Future<List<CourseModel>> readCourseList() async => courses;
  @override
  Future<List<TimetableAdjustment>> readAdjustments() async => adjustments;
  @override
  Future<void> saveAdjustments(List<TimetableAdjustment> values) async {
    if (failWrite) throw StateError('磁盘写入失败');
    adjustments = values;
  }
}

Future<void> openMode(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('课表功能'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('临时调课'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> saveForm(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, '保存临时安排');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> selectSourceDate(WidgetTester tester, DateTime date) async {
  await selectDate(tester, '来源日期', date);
}

Future<void> selectDate(
  WidgetTester tester,
  String label,
  DateTime date,
) async {
  await tester.tap(find.textContaining('$label：'));
  await tester.pumpAndSettle();
  final strings = MaterialLocalizations.of(
    tester.element(find.byType(DatePickerDialog)),
  );
  await tester.tap(find.byTooltip(strings.inputDateModeButtonLabel));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byType(TextFormField),
    strings.formatCompactDate(date),
  );
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> selectDropdown(
  WidgetTester tester,
  int index,
  String label,
) async {
  final dropdown = find.byType(DropdownButtonFormField<int>).at(index);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  final now = DateTime.now();
  final monday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('AI 入口跳转 Agent，返回时重新读取调课结果', (tester) async {
    final storage = MemoryTimetableStorage(monday);
    await tester.pumpWidget(
      app(await memorySettings(), TimetablePage(storage: storage)),
    );
    await tester.pumpAndSettle();
    await openMode(tester, 'AI 智能调课');
    expect(find.byType(AgentPage), findsOneWidget);
    storage.adjustments = TimetableAdjustmentService.forWeeks(
      course: storage.courses.first,
      sourceWeeks: {1},
      targetDay: 3,
      start: 5,
      end: 6,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<WeeklyCalendarView>(find.byType(WeeklyCalendarView))
          .adjustments,
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('日期入口直接显示日期，连续停课只处理选中日期，写入失败不改变课表', (tester) async {
    final storage = MemoryTimetableStorage(monday);
    await tester.pumpWidget(MaterialApp(home: TimetablePage(storage: storage)));
    await tester.pumpAndSettle();
    await openMode(tester, '日期时间调课');
    expect(find.byType(TimetableAdjustmentForm), findsOneWidget);
    expect(find.textContaining('来源日期：'), findsOneWidget);
    expect(find.text('目标星期'), findsNothing);
    await selectSourceDate(tester, monday);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('停课结束日期：'), findsOneWidget);
    storage.failWrite = true;
    await saveForm(tester);
    expect(find.textContaining('保存调课失败'), findsOneWidget);
    expect(storage.adjustments, isEmpty);
    expect(
      tester
          .widget<WeeklyCalendarView>(find.byType(WeeklyCalendarView))
          .adjustments,
      isEmpty,
    );
    storage.failWrite = false;
    await openMode(tester, '日期时间调课');
    await selectSourceDate(tester, monday);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await saveForm(tester);
    expect(storage.adjustments, hasLength(2));
    expect(
      storage.adjustments.every((a) => a.cancelled && a.sourceWeek == 1),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量周次有周次多选，取消一个周次后仅保存其他周次', (tester) async {
    final storage = MemoryTimetableStorage(monday);
    await tester.pumpWidget(MaterialApp(home: TimetablePage(storage: storage)));
    await tester.pumpAndSettle();
    await openMode(tester, '批量周次调课');
    await tester.tap(find.text('植物学').last);
    await tester.pumpAndSettle();
    expect(find.byType(FilterChip), findsNWidgets(3));
    expect(find.text('来源周次'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, '第2周'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await saveForm(tester);
    expect(storage.adjustments.map((a) => a.sourceWeek), [1, 3]);
    expect(
      storage.adjustments.every((a) => a.sourceWeek == a.targetWeek),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量课程有课程多选，节次长度不同的课程不被误选', (tester) async {
    final storage = MemoryTimetableStorage(monday);
    await tester.pumpWidget(MaterialApp(home: TimetablePage(storage: storage)));
    await tester.pumpAndSettle();
    await openMode(tester, '批量课程调课');
    await tester.tap(find.text('植物学').last);
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    await tester.tap(find.widgetWithText(CheckboxListTile, '植物学'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await saveForm(tester);
    expect(storage.adjustments, hasLength(2));
    expect(storage.adjustments.every((a) => a.courseId == '土壤学'), isTrue);
    expect(storage.adjustments.map((a) => a.sourceWeek), [2, 4]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单周次可选择来源周次和目标周次，其他周次不受影响', (tester) async {
    final storage = MemoryTimetableStorage(monday);
    await tester.pumpWidget(MaterialApp(home: TimetablePage(storage: storage)));
    await tester.pumpAndSettle();
    await openMode(tester, '单周次调课');
    await tester.tap(find.text('植物学').last);
    await tester.pumpAndSettle();
    expect(find.text('来源周次'), findsOneWidget);
    expect(find.text('目标周次'), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    await selectDropdown(tester, 0, '第2周');
    await selectDropdown(tester, 1, '第4周');
    await selectDropdown(tester, 2, '星期五');
    await selectDropdown(tester, 3, '第5节');
    await selectDropdown(tester, 4, '第6节');
    storage.adjustments = TimetableAdjustmentService.forWeeks(
      course: storage.courses[1],
      sourceWeeks: {2},
      targetDay: 3,
      start: 7,
      end: 8,
    );
    await saveForm(tester);
    expect(storage.adjustments, hasLength(2));
    final changed = storage.adjustments.singleWhere((a) => a.courseId == '植物学');
    expect(changed.sourceWeek, 2);
    expect(
      (
        changed.targetWeek,
        changed.targetDay,
        changed.targetStartPeriod,
        changed.targetEndPeriod,
      ),
      (4, 5, 5, 6),
    );
    expect(changed.cancelled, isFalse);
    expect(storage.adjustments.any((a) => a.courseId == '土壤学'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日期表单保存整天迁移，其他日期与节次不被覆盖', (tester) async {
    final storage = MemoryTimetableStorage(monday);
    await tester.pumpWidget(MaterialApp(home: TimetablePage(storage: storage)));
    await tester.pumpAndSettle();
    await openMode(tester, '日期时间调课');
    await selectSourceDate(tester, monday);
    await selectDate(tester, '目标日期', monday.add(const Duration(days: 9)));
    await saveForm(tester);
    expect(storage.adjustments, hasLength(2));
    expect(
      storage.adjustments.every(
        (a) => a.sourceWeek == 1 && a.targetWeek == 2 && a.targetDay == 3,
      ),
      isTrue,
    );
    expect(storage.adjustments.map((a) => a.targetEndPeriod), [2, 4]);
    expect(storage.adjustments.every((a) => !a.cancelled), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('跨周课程长按仍带入原来源周次，重复修改不创建另一周的规则', (tester) async {
    final storage = MemoryTimetableStorage(monday);
    storage.adjustments = TimetableAdjustmentService.forWeeks(
      course: storage.courses.first,
      sourceWeeks: {1},
      targetWeek: 2,
      targetDay: 4,
      start: 5,
      end: 6,
    );
    await tester.pumpWidget(MaterialApp(home: TimetablePage(storage: storage)));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    final movedCard = find.text('植物学').last;
    await tester.ensureVisible(movedCard);
    await tester.longPress(movedCard);
    await tester.pumpAndSettle();
    await tester.tap(find.text('单周次调课'));
    await tester.pumpAndSettle();
    final dropdown = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>).first,
    );
    expect(dropdown.initialValue, 1);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await saveForm(tester);
    expect(storage.adjustments, hasLength(1));
    expect(storage.adjustments.single.sourceWeek, 1);
    expect(storage.adjustments.single.cancelled, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final mode in AdjustmentMode.values.where(
    (m) => m != AdjustmentMode.ai,
  )) {
    testWidgets('${mode.title} 窄屏大字体可以滚动操作，无溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemoryTimetableStorage(monday);
      await tester.pumpWidget(
        app(
          await memorySettings(),
          TimetablePage(storage: storage),
          scale: 1.4,
        ),
      );
      await tester.pumpAndSettle();
      await openMode(tester, mode.title);
      if (mode != AdjustmentMode.date) {
        await tester.tap(find.text('植物学').last);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.widgetWithText(FilledButton, '保存临时安排'));
      expect(tester.takeException(), isNull);
    });
  }
}
