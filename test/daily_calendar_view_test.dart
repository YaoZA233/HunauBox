import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/course_model.dart';
import 'package:smart_hunan_agri/models/timetable_adjustment.dart';
import 'package:smart_hunan_agri/pages/timetable_page.dart';
import 'package:smart_hunan_agri/services/timetable_adjustment_service.dart';
import 'package:smart_hunan_agri/widgets/daily_calendar_view.dart';
import 'package:smart_hunan_agri/widgets/weekly_calendar_view.dart';

import 'timetable_adjustment_service_test.dart' show course;
import 'timetable_adjustment_widget_test.dart' show MemoryTimetableStorage;

void main() {
  final monday = DateTime(2026, 10, 5);

  Future<void> showDay(
    WidgetTester tester, {
    required List<CourseModel> courses,
    DateTime? date,
    DateTime Function()? now,
    List<TimetableAdjustment> adjustments = const [],
    void Function(CourseModel, int)? onLongPress,
    GlobalKey<DailyCalendarViewState>? viewKey,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.blue, brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: DailyCalendarView(
          key: viewKey,
          courses: courses,
          firstWeekMonday: monday,
          adjustments: adjustments,
          initialDate: date,
          now: now ?? () => DateTime(2026, 10, 5, 10, 5),
          onCourseLongPress: onLongPress,
        ),
      ),
    ),
  );

  Future<void> selectDay(WidgetTester tester, DateTime date) async {
    final target = find.byKey(ValueKey('day-${date.toIso8601String()}'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('默认今天，按上课时间排序并显示时间、节次、教室、老师和状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await showDay(
      tester,
      courses: [
        course('下午', start: 5, end: 6),
        course('上午').copyWith(teacher: '李老师', classroom: '八教北223'),
        course('第二堂', start: 3, end: 4),
      ],
    );
    expect(find.text('今日课程 · 3门'), findsOneWidget);
    expect(find.text('2026年10月5日'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('上午')).dy,
      lessThan(tester.getTopLeft(find.text('第二堂')).dy),
    );
    expect(
      tester.getTopLeft(find.text('第二堂')).dy,
      lessThan(tester.getTopLeft(find.text('下午')).dy),
    );
    for (final text in [
      '08:00',
      '09:40',
      '1-2节',
      '14:30',
      '16:10',
      '5-6节',
      '教室：八教北223',
      '老师：李老师',
      '已结束',
      '上课中',
      '未开始',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    await tester.tap(find.text('上午'));
    await tester.pumpAndSettle();
    expect(find.text('日期：2026年10月5日'), findsOneWidget);
    expect(find.text('时间：08:00–09:40 · 1-2节'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日期选择、周切换、无课日和回到今天', (tester) async {
    final key = GlobalKey<DailyCalendarViewState>();
    await showDay(
      tester,
      viewKey: key,
      courses: [
        course('周一'),
        course('周二', day: 2, weeks: '2'),
      ],
    );
    expect(find.text('1课'), findsOneWidget);
    await selectDay(tester, DateTime(2026, 10, 6));
    expect(find.text('当天没有课程'), findsOneWidget);
    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    expect(find.text('2026年10月13日'), findsOneWidget);
    expect(find.text('周二'), findsOneWidget);
    expect(find.text('1课'), findsNWidgets(2));
    await tester.tap(find.byTooltip('上一周'));
    await tester.pumpAndSettle();
    expect(find.text('当天没有课程'), findsOneWidget);
    key.currentState!.jumpToToday();
    await tester.pumpAndSettle();
    expect(find.text('今日课程 · 1门'), findsOneWidget);
    expect(find.text('周一'), findsOneWidget);
  });

  testWidgets('跨周调课替换原日期，停课不计数，长按传回原课程及来源周', (tester) async {
    final moved = course('跨周', weeks: '1');
    final cancelled = course('停课', day: 2, weeks: '2');
    final changes = [
      ...TimetableAdjustmentService.forWeeks(
        course: moved,
        sourceWeeks: {1},
        targetDay: 2,
        start: 5,
        end: 6,
        targetWeek: 2,
      ),
      ...TimetableAdjustmentService.forWeeks(
        course: cancelled,
        sourceWeeks: {2},
        targetDay: 2,
        start: 1,
        end: 2,
        cancelled: true,
      ),
    ];
    CourseModel? pressed;
    int? sourceWeek;
    await showDay(
      tester,
      courses: [moved, cancelled],
      adjustments: changes,
      onLongPress: (value, week) {
        pressed = value;
        sourceWeek = week;
      },
    );
    expect(find.text('今天没有课程'), findsOneWidget);
    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    await selectDay(tester, DateTime(2026, 10, 13));
    expect(find.text('当天课程 · 1门'), findsOneWidget);
    expect(find.text('跨周'), findsOneWidget);
    expect(find.text('停课'), findsNothing);
    expect(find.text('14:30'), findsOneWidget);
    expect(find.text('5-6节'), findsOneWidget);
    expect(find.text('已调课'), findsOneWidget);
    await tester.longPress(find.text('跨周'));
    expect(pressed, same(moved));
    expect(sourceWeek, 1);
    await tester.tap(find.text('跨周'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整这次课程'));
    await tester.pumpAndSettle();
    expect(sourceWeek, 1);
    expect(find.text('日期：2026年10月13日'), findsNothing);
  });

  testWidgets('调课保存后更新当前列表与日期数量', (tester) async {
    final courses = [course('移动课程', weeks: '1')];
    await showDay(tester, courses: courses);
    expect(find.text('移动课程'), findsOneWidget);
    await showDay(
      tester,
      courses: courses,
      adjustments: TimetableAdjustmentService.forWeeks(
        course: courses.single,
        sourceWeeks: {1},
        targetDay: 2,
        start: 3,
        end: 4,
      ),
    );
    expect(find.text('今天没有课程'), findsOneWidget);
    await selectDay(tester, DateTime(2026, 10, 6));
    expect(find.text('移动课程'), findsOneWidget);
    expect(find.text('10:05'), findsOneWidget);
  });

  testWidgets('在开课和结束边界自动更新状态，跨午夜自动切换今天', (tester) async {
    var now = DateTime(2026, 10, 5, 7, 59);
    final courses = [course('早课')];
    await showDay(tester, courses: courses, now: () => now);
    expect(find.text('未开始'), findsOneWidget);
    now = DateTime(2026, 10, 5, 8);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('上课中'), findsOneWidget);
    now = DateTime(2026, 10, 5, 9, 40);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('已结束'), findsOneWidget);
    now = DateTime(2026, 10, 6);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('2026年10月6日'), findsOneWidget);
    expect(find.text('今天没有课程'), findsOneWidget);
  });

  testWidgets('周末跨月跨年及学期前日期均可查看', (tester) async {
    await showDay(
      tester,
      courses: [course('课程')],
      date: DateTime(2026, 12, 31),
    );
    await selectDay(tester, DateTime(2027, 1, 3));
    expect(find.text('2027年1月3日'), findsOneWidget);
    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    expect(find.text('2027年1月10日'), findsOneWidget);
    await showDay(
      tester,
      viewKey: GlobalKey(),
      courses: [course('课程')],
      date: DateTime(2026, 10, 4),
    );
    expect(find.text('学期开始前 · 星期日'), findsOneWidget);
    expect(find.text('当天没有课程'), findsOneWidget);
  });

  testWidgets('点击日期可通过日历选择远期日期', (tester) async {
    await showDay(tester, courses: [course('课程')]);
    await tester.tap(find.text('2026年10月5日'));
    await tester.pumpAndSettle();
    final strings = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    );
    await tester.tap(find.byTooltip(strings.inputDateModeButtonLabel));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      strings.formatCompactDate(DateTime(2027, 1, 2)),
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('2027年1月2日'), findsOneWidget);
    expect(find.text('当天没有课程'), findsOneWidget);
  });

  testWidgets('周日视图切换保留位置，菜单在日视图返回今天', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final today = DateUtils.dateOnly(DateTime.now());
    final firstMonday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    final storage = MemoryTimetableStorage(firstMonday);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.4)),
          child: child!,
        ),
        home: TimetablePage(storage: storage),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WeeklyCalendarView), findsOneWidget);
    expect(find.textContaining('今日课程'), findsNothing);
    await tester.tap(find.text('日视图'));
    await tester.pumpAndSettle();
    expect(find.byType(DailyCalendarView), findsOneWidget);
    expect(find.textContaining('今日课程'), findsOneWidget);
    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    final next = DateTime(today.year, today.month, today.day + 7);
    final label = '${next.year}年${next.month}月${next.day}日';
    expect(find.text(label), findsOneWidget);
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日视图'));
    await tester.pumpAndSettle();
    expect(find.text(label), findsOneWidget);
    await tester.tap(find.byTooltip('课表功能'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回到今天'));
    await tester.pumpAndSettle();
    expect(find.textContaining('今日课程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('窄屏大字体及${brightness.name}主题可阅读长课程和缺失信息', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await showDay(
        tester,
        courses: [
          course('一门名称很长的植物营养与环境科学实验课程').copyWith(classroom: '', teacher: ''),
        ],
        scale: 1.8,
        brightness: brightness,
      );
      await tester.scrollUntilVisible(
        find.text('老师：暂未提供'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('教室：暂未提供'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
