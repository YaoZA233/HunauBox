import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/models/campus_card_bill.dart';
import 'package:smart_hunan_agri/models/electricity_model.dart';
import 'package:smart_hunan_agri/models/exam_schedule_model.dart';
import 'package:smart_hunan_agri/models/homework_model.dart';
import 'package:smart_hunan_agri/pages/balance_overview_page.dart';
import 'package:smart_hunan_agri/pages/electricity_recharge_page.dart';
import 'package:smart_hunan_agri/providers/homework_provider.dart';
import 'package:smart_hunan_agri/providers/notice_provider.dart';
import 'package:smart_hunan_agri/services/app_cookie_manager.dart';
import 'package:smart_hunan_agri/services/campus_card_service.dart';
import 'package:smart_hunan_agri/services/electricity_service.dart';
import 'package:smart_hunan_agri/services/homework_storage.dart';
import 'package:smart_hunan_agri/services/chaoxing_cache_store.dart';

const room1 = SavedElectricityRoom(
  areaName: '东湖校区',
  buildingName: '1栋',
  roomId: '101',
  roomName: '101室',
  mertype: 'yk',
);
const room2 = SavedElectricityRoom(
  areaName: '东湖校区',
  buildingName: '2栋',
  roomId: '202',
  roomName: '202室',
  mertype: 'yk',
);

Future<CampusCardInfo> loadCard() async =>
    CampusCardInfo(name: '测试用户', idserial: 'card1', balance: '100.00');

Future<List<CampusCardBill>> noRecentBills(CampusCardBillQuery query) async =>
    const [];

Future<List<ExamScheduleModel>> noExams() async => const [];

Finder overviewCard(String id) => find.byKey(ValueKey(id));

Finder get reorderScrollable => find
    .descendant(
      of: find.byType(ReorderableListView),
      matching: find.byType(Scrollable),
    )
    .first;

Finder get manageScrollable => find
    .descendant(
      of: find.byKey(const ValueKey('manage_list')),
      matching: find.byType(Scrollable),
    )
    .first;

/// 弹层列表是懒构建的：先滚到目标再确保其完整可见，否则点击会落空。
Future<void> revealInSheet(
  WidgetTester tester,
  Finder target,
  Finder list,
) async {
  await tester.scrollUntilVisible(target, 100, scrollable: list);
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

/// 长按卡片拖起后落到目标卡片上（对应真实用户的自由摆放操作）。
Future<void> longPressDragOntoCard(
  WidgetTester tester,
  String fromKey,
  String toKey,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(overviewCard(fromKey)),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(tester.getCenter(overviewCard(toKey)));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

class QuietNoticeNotifier extends NoticeNotifier {
  @override
  Future<void> refresh() async {}
}

class MemoryHomeworkStorage extends HomeworkStorage {
  MemoryHomeworkStorage([this.items = const []]);
  final List<HomeworkModel> items;

  @override
  Future<List<HomeworkModel>?> readHomeworkList() async => items;
}

Widget overviewApp({
  BalanceOverviewPage? page,
  Widget? body,
  List<HomeworkModel> homework = const [],
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      noticeProvider.overrideWith((ref) => QuietNoticeNotifier()),
      homeworkStorageProvider.overrideWith(
        (ref) => MemoryHomeworkStorage(homework),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(brightness: brightness, colorSchemeSeed: Colors.green),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body:
            body ??
            page ??
            BalanceOverviewPage(
              loadCardInfo: loadCard,
              loadRecentBills: noRecentBills,
              loadExams: noExams,
            ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    AppCookieManager().dioCookieJar = CookieJar();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('概览激活时刷新，快速切换合并尚未完成的请求', (tester) async {
    var calls = 0;
    var pending = Completer<CampusCardInfo>();
    Widget app(bool active) => overviewApp(
      page: BalanceOverviewPage(
        isActive: active,
        loadCardInfo: () {
          calls++;
          return pending.future;
        },
        loadRecentBills: noRecentBills,
        loadExams: noExams,
      ),
    );

    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.pumpWidget(app(true));
    expect(calls, 1);
    await tester.pumpWidget(app(false));
    await tester.pumpWidget(app(true));
    expect(calls, 1);
    pending.complete(await loadCard());
    await tester.pumpAndSettle();

    pending = Completer<CampusCardInfo>();
    await tester.pumpWidget(app(false));
    await tester.pumpWidget(app(true));
    expect(calls, 2);
    pending.complete(
      CampusCardInfo(name: '测试用户', idserial: 'card1', balance: '88.00'),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('campus_card'));
    expect(find.text('88.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('滑出可视区后返回复用概览状态，不重复初始化', (tester) async {
    var calls = 0;
    final controller = PageController();
    await tester.pumpWidget(
      overviewApp(
        body: PageView(
          controller: controller,
          children: [
            BalanceOverviewPage(
              loadCardInfo: () async {
                calls++;
                return loadCard();
              },
              loadRecentBills: noRecentBills,
              loadExams: noExams,
            ),
            const SizedBox(),
            const SizedBox(),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(BalanceOverviewPage));
    controller.jumpToPage(2);
    await tester.pumpAndSettle();
    controller.jumpToPage(0);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(BalanceOverviewPage)), same(state));
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('两个宿舍分别显示对应房间的余额', (tester) async {
    SharedPreferences.setMockInitialValues({
      'saved_electricity_room': jsonEncode(room1.toJson()),
      'saved_electricity_room_2': jsonEncode(room2.toJson()),
    });
    await tester.pumpWidget(
      overviewApp(
        page: BalanceOverviewPage(
          loadCardInfo: loadCard,
          loadElectricityBalance: (room) async => ElectricityBalanceInfo(
            balance: room.roomId == '101' ? '12.50' : '68.90',
          ),
          loadRecentBills: noRecentBills,
          loadExams: noExams,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('electricity_2'));
    expect(
      find.descendant(
        of: overviewCard('electricity_1'),
        matching: find.text('12.50'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: overviewCard('electricity_2'),
        matching: find.text('68.90'),
      ),
      findsOneWidget,
    );
    expect(find.text('东湖校区 · 1栋 · 101室'), findsOneWidget);
    expect(find.text('东湖校区 · 2栋 · 202室'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('一个宿舍查询失败不影响另一个宿舍，刷新可恢复', (tester) async {
    SharedPreferences.setMockInitialValues({
      'saved_electricity_room': jsonEncode(room1.toJson()),
      'saved_electricity_room_2': jsonEncode(room2.toJson()),
    });
    var failFirst = true;
    await tester.pumpWidget(
      overviewApp(
        page: BalanceOverviewPage(
          loadCardInfo: loadCard,
          loadElectricityBalance: (room) async {
            if (room.roomId == '101' && failFirst) throw Exception('网络错误');
            return ElectricityBalanceInfo(
              balance: room.roomId == '101' ? '12.50' : '68.90',
            );
          },
          loadRecentBills: noRecentBills,
          loadExams: noExams,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('electricity_2'));
    expect(
      find.descendant(
        of: overviewCard('electricity_1'),
        matching: find.text('获取失败'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: overviewCard('electricity_2'),
        matching: find.text('68.90'),
      ),
      findsOneWidget,
    );
    failFirst = false;
    await tester.scrollUntilVisible(
      find.byTooltip('刷新'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('electricity_1'));
    expect(
      find.descendant(
        of: overviewCard('electricity_1'),
        matching: find.text('12.50'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('学习通卡片显示当前账号缓存并支持添加不同尺寸', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'user': 'alice'});
    final cache = ChaoxingCacheStore(account: () async => 'alice');
    await cache.write('alice', 'messages', {
      'conversations': [{}, {}, {}],
    });
    await cache.write('alice', 'courses', {
      'items': [{}, {}],
    });
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('chaoxing_messages'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: overviewCard('chaoxing_messages'),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: overviewCard('chaoxing_courses'),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 2500));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加卡片'));
    await tester.pumpAndSettle();
    await revealInSheet(tester, find.byTooltip('添加学习通课程大卡'), manageScrollable);
    expect(find.byTooltip('添加学习通课程小卡'), findsOneWidget);
  });

  testWidgets('概览提供排序入口并可查看全部卡片', (tester) async {
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    expect(find.byTooltip('排序'), findsOneWidget);
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    expect(find.text('卡片排序'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, '宿舍电费2'),
      100,
      scrollable: reorderScrollable,
    );
    expect(find.widgetWithText(ListTile, '宿舍电费2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('箭头排序保存后改变概览顺序并在重新进入后恢复', (tester) async {
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('上移宿舍电费2'),
      100,
      scrollable: reorderScrollable,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('上移宿舍电费2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上移宿舍电费2'));
    await tester.pumpAndSettle();
    expect(find.text('卡片排序'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('electricity_1'));
    expect(
      tester.getTopLeft(overviewCard('electricity_2')).dy,
      lessThan(tester.getTopLeft(overviewCard('electricity_1')).dy),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('overview_card_layout'), [
      'notice|small',
      'homework|small',
      'upcoming_homework|large',
      'exam|large',
      'campus_card|large',
      'recent_bill|large',
      'electricity_2|large',
      'electricity_1|large',
      'chaoxing_messages|small',
      'chaoxing_courses|small',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('electricity_1'));
    expect(
      tester.getTopLeft(overviewCard('electricity_2')).dy,
      lessThan(tester.getTopLeft(overviewCard('electricity_1')).dy),
    );
  });

  testWidgets('拖动卡片可跨区域置顶，取消排序不更改已保存顺序', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    final sourceTile = find.byKey(const ValueKey('manage_homework'));
    final handle = find.descendant(
      of: sourceTile,
      matching: find.byType(ReorderableDragStartListener),
    );
    expect(sourceTile, findsOneWidget);
    expect(handle.hitTestable(), findsOneWidget);
    final start = tester.getCenter(handle);
    final target =
        tester.getTopLeft(find.byKey(const ValueKey('manage_notice'))) +
        const Offset(24, 1);
    final gesture = await tester.startGesture(start);
    await tester.pump();
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();
    for (var step = 1; step <= 8; step++) {
      await gesture.moveTo(Offset.lerp(start, target, step / 8)!);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final savedLayout = prefs.getStringList('overview_card_layout')!;
    expect(savedLayout.first, 'homework|small');
    expect(
      tester.getTopLeft(overviewCard('homework')).dx,
      lessThan(tester.getTopLeft(overviewCard('notice')).dx),
    );
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下移待完成作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(prefs.getStringList('overview_card_layout'), savedLayout);
    expect(
      tester.getTopLeft(overviewCard('homework')).dx,
      lessThan(tester.getTopLeft(overviewCard('notice')).dx),
    );
  });

  testWidgets('点击第二电费卡片传入第二槽位并在返回后刷新该房间', (tester) async {
    await tester.pumpWidget(
      overviewApp(
        page: BalanceOverviewPage(
          loadCardInfo: loadCard,
          loadElectricityBalance: (room) async => ElectricityBalanceInfo(
            balance: room.roomId == '202' ? '28.00' : '10.00',
          ),
          loadRecentBills: noRecentBills,
          loadExams: noExams,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('electricity_2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('宿舍电费2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ElectricityRechargePage), findsOneWidget);
    final page = tester.widget<ElectricityRechargePage>(
      find.byType(ElectricityRechargePage),
    );
    expect(page.roomSlot, 1);
    await ElectricityService.instance.saveSavedRoom(room2, slot: 1);
    final context = tester.element(find.byType(ElectricityRechargePage));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(find.text('东湖校区 · 2栋 · 202室'), findsOneWidget);
    expect(
      find.descendant(
        of: overviewCard('electricity_2'),
        matching: find.text('28.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: overviewCard('electricity_1'),
        matching: find.text('尚未关联宿舍房间'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('修改房间返回时重新查询，旧的慢响应不能覆盖新房间', (tester) async {
    SharedPreferences.setMockInitialValues({
      'saved_electricity_room_2': jsonEncode(room1.toJson()),
    });
    final oldBalance = Completer<ElectricityBalanceInfo>();
    await tester.pumpWidget(
      overviewApp(
        page: BalanceOverviewPage(
          loadCardInfo: loadCard,
          loadElectricityBalance: (room) => room.roomId == '101'
              ? oldBalance.future
              : Future.value(ElectricityBalanceInfo(balance: '28.00')),
          loadRecentBills: noRecentBills,
          loadExams: noExams,
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(overviewCard('electricity_2'));
    await tester.pump();
    await tester.tap(find.text('宿舍电费2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(ElectricityRechargePage), findsOneWidget);
    await ElectricityService.instance.saveSavedRoom(room2, slot: 1);
    Navigator.of(tester.element(find.byType(ElectricityRechargePage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    oldBalance.complete(ElectricityBalanceInfo(balance: '99.00'));
    await tester.pumpAndSettle();
    expect(find.text('东湖校区 · 2栋 · 202室'), findsOneWidget);
    expect(
      find.descendant(
        of: overviewCard('electricity_2'),
        matching: find.text('28.00'),
      ),
      findsOneWidget,
    );
    expect(find.text('99.00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('异步查询完成前离开概览不会更新已销毁页面', (tester) async {
    final pending = Completer<CampusCardInfo>();
    await tester.pumpWidget(
      overviewApp(
        page: BalanceOverviewPage(
          loadCardInfo: () => pending.future,
          loadRecentBills: noRecentBills,
          loadExams: noExams,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(await loadCard());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('概览和排序在窄屏大字体 $brightness 下可操作无溢出', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        overviewApp(
          brightness: brightness,
          textScale: 2,
          homework: [
            HomeworkModel(
              id: 'pending',
              courseName: '植物学与农业生态基础',
              title: '第三章课后练习与实验报告',
              endTime: DateTime.now().add(const Duration(days: 2)),
              status: HomeworkStatus.pending,
              studentId: 'test',
            ),
          ],
          page: BalanceOverviewPage(
            loadCardInfo: loadCard,
            loadElectricityBalance: (room) async =>
                ElectricityBalanceInfo(balance: '1234.56'),
            loadRecentBills: (query) async => const [
              CampusCardBill(
                merchantName: '第一食堂超长商户名称用于测试溢出情况',
                amount: '1234.56',
                time: '2026-10-25 12:30',
                tradeType: '1',
              ),
            ],
            loadExams: () async => [
              ExamScheduleModel(
                id: 'e1',
                title: '高等数学期末考试超长考试名称用于测试溢出',
                courseName: '高等数学与农业生态基础',
                time: DateTime.now().add(const Duration(days: 2)),
                location: '教学楼一号楼101考场',
                status: '未开始',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(overviewCard('electricity_2'));
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byTooltip('排序'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('排序'));
      await tester.pumpAndSettle();
      expect(find.text('卡片排序'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byTooltip('上移宿舍电费2'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(ReorderableListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('上移宿舍电费2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('未关联宿舍时显示两个独立的电费卡片', (tester) async {
    await tester.pumpWidget(overviewApp());
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('宿舍电费2'), findsOneWidget);
    expect(find.text('宿舍电费1'), findsOneWidget);
    expect(find.text('尚未关联宿舍房间'), findsNWidgets(2));
    expect(find.text('去选择房间'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('校园卡最近消费随概览自动查询并显示首笔', (tester) async {
    CampusCardBillQuery? captured;
    await tester.pumpWidget(
      overviewApp(
        page: BalanceOverviewPage(
          loadCardInfo: loadCard,
          loadElectricityBalance: (room) async =>
              ElectricityBalanceInfo(balance: '1.00'),
          loadRecentBills: (query) async {
            captured = query;
            return const [
              CampusCardBill(
                merchantName: '第一食堂',
                amount: '12.50',
                time: '2026-10-25 12:30',
                tradeType: '1',
              ),
              CampusCardBill(
                merchantName: '校园超市',
                amount: '8.00',
                time: '2026-10-24 09:00',
                tradeType: '1',
              ),
            ];
          },
          loadExams: noExams,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('recent_bill'));
    expect(captured, isNotNull);
    expect(captured!.type, CampusCardTradeType.consume);
    expect(
      find.descendant(
        of: overviewCard('recent_bill'),
        matching: find.text('12.50'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: overviewCard('recent_bill'),
        matching: find.textContaining('第一食堂'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('校园卡最近消费无记录时显示暂无消费', (tester) async {
    await tester.pumpWidget(
      overviewApp(
        page: BalanceOverviewPage(
          loadCardInfo: loadCard,
          loadElectricityBalance: (room) async =>
              ElectricityBalanceInfo(balance: '1.00'),
          loadRecentBills: (query) async => const [],
          loadExams: noExams,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('recent_bill'));
    expect(
      find.descendant(
        of: overviewCard('recent_bill'),
        matching: find.text('暂无消费'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('校园卡最近消费查询失败显示获取失败', (tester) async {
    await tester.pumpWidget(
      overviewApp(
        page: BalanceOverviewPage(
          loadCardInfo: loadCard,
          loadElectricityBalance: (room) async =>
              ElectricityBalanceInfo(balance: '1.00'),
          loadRecentBills: (query) async => throw Exception('网络错误'),
          loadExams: noExams,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('recent_bill'));
    expect(
      find.descendant(
        of: overviewCard('recent_bill'),
        matching: find.text('获取失败'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('最近考试横幅显示下一场考试与倒计时', (tester) async {
    final exams = [
      ExamScheduleModel(
        id: 'e1',
        title: '高等数学期末考试',
        courseName: '高等数学',
        time: DateTime.now().add(const Duration(days: 3)),
        location: '教一楼101',
        status: '未开始',
      ),
    ];
    await tester.pumpWidget(
      overviewApp(
        page: BalanceOverviewPage(
          loadCardInfo: loadCard,
          loadElectricityBalance: (room) async =>
              ElectricityBalanceInfo(balance: '1.00'),
          loadRecentBills: noRecentBills,
          loadExams: () async => exams,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('exam'));
    expect(
      find.descendant(
        of: overviewCard('exam'),
        matching: find.textContaining('高等数学期末考试'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: overviewCard('exam'),
        matching: find.textContaining('3 天后'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('无最近考试时不显示考试卡片', (tester) async {
    await tester.pumpWidget(
      overviewApp(
        page: BalanceOverviewPage(
          loadCardInfo: loadCard,
          loadElectricityBalance: (room) async =>
              ElectricityBalanceInfo(balance: '1.00'),
          loadRecentBills: noRecentBills,
          loadExams: noExams,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(overviewCard('exam'), findsNothing);
  });

  testWidgets('新卡片进入排序弹层并可调整保存', (tester) async {
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    await revealInSheet(
      tester,
      find.widgetWithText(ListTile, '最近考试'),
      reorderScrollable,
    );
    expect(find.widgetWithText(ListTile, '最近考试'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, '校园卡最近消费'),
      100,
      scrollable: reorderScrollable,
    );
    expect(find.widgetWithText(ListTile, '校园卡最近消费'), findsOneWidget);
    await revealInSheet(tester, find.byTooltip('上移校园卡最近消费'), reorderScrollable);
    await tester.tap(find.byTooltip('上移校园卡最近消费'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final layout = prefs.getStringList('overview_card_layout')!;
    expect(
      layout.indexOf('recent_bill|large'),
      lessThan(layout.indexOf('campus_card|large')),
    );
  });

  testWidgets('默认布局把消息与作业渲染成并排小卡，余额卡保持大卡', (tester) async {
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('campus_card'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(overviewCard('notice')).dy,
      tester.getTopLeft(overviewCard('homework')).dy,
    );
    expect(
      tester.getSize(overviewCard('notice')).width,
      lessThan(tester.getSize(overviewCard('campus_card')).width / 2),
    );
    expect(
      find.descendant(of: overviewCard('notice'), matching: find.text('未读消息')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('小卡渲染成正方形，大卡保持整行长条', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('campus_card'));
    await tester.pumpAndSettle();

    final notice = tester.getSize(overviewCard('notice'));
    final homework = tester.getSize(overviewCard('homework'));
    final campus = tester.getSize(overviewCard('campus_card'));
    expect(notice.height, closeTo(notice.width, 2));
    expect(homework.height, closeTo(homework.width, 2));
    expect(notice.height, homework.height);
    expect(campus.width, greaterThan(2 * campus.height));
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(375, 812), const Size(900, 600)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('带侧栏 $size 字号 $scale 仍是一行两张正方形小卡', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        SharedPreferences.setMockInitialValues({
          'overview_card_layout': [
            'notice|small',
            'homework|small',
            'campus_card|small',
            'electricity_1|small',
          ],
        });
        await tester.pumpWidget(
          overviewApp(
            textScale: scale,
            body: Row(
              children: [
                const SizedBox(width: 78),
                Expanded(
                  child: BalanceOverviewPage(
                    loadCardInfo: loadCard,
                    loadRecentBills: noRecentBills,
                    loadExams: noExams,
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final id in [
          'notice',
          'homework',
          'campus_card',
          'electricity_1',
        ]) {
          final geometry = tester.getSize(overviewCard(id));
          expect(geometry.height, closeTo(geometry.width, .1));
          expect(geometry.width, closeTo((size.width - 78 - 32 - 12) / 2, .1));
        }
        expect(
          tester.getTopLeft(overviewCard('notice')).dy,
          tester.getTopLeft(overviewCard('homework')).dy,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('长按拖动卡片可插入到任意位置并持久化', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    await longPressDragOntoCard(tester, 'notice', 'campus_card');
    await tester.ensureVisible(overviewCard('campus_card'));
    expect(
      tester.getTopLeft(overviewCard('notice')).dy,
      greaterThan(tester.getTopLeft(overviewCard('campus_card')).dy),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('overview_card_layout'), [
      'homework|small',
      'upcoming_homework|large',
      'exam|large',
      'campus_card|large',
      'notice|small',
      'recent_bill|large',
      'electricity_1|large',
      'electricity_2|large',
      'chaoxing_messages|small',
      'chaoxing_courses|small',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('campus_card'));
    expect(
      tester.getTopLeft(overviewCard('notice')).dy,
      greaterThan(tester.getTopLeft(overviewCard('campus_card')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按拖到边缘自动滚动，松手后停止', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(overviewCard('notice')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(const Offset(200, 580));
    await tester.pump(const Duration(milliseconds: 320));
    expect(scrollable.position.pixels, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
    final stoppedAt = scrollable.position.pixels;
    await tester.pump(const Duration(milliseconds: 320));
    expect(scrollable.position.pixels, stoppedAt);
    expect(tester.takeException(), isNull);
  });

  testWidgets('拖动松手落在卡片外不改变布局', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(overviewCard('notice')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(const Offset(200, 20));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('overview_card_layout'), isNull);
    expect(
      tester.getTopLeft(overviewCard('notice')).dy,
      lessThan(tester.getTopLeft(overviewCard('campus_card')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字体添加面板可选择两种尺寸且无溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(overviewApp(textScale: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加卡片'));
    await tester.pumpAndSettle();
    await revealInSheet(tester, find.byTooltip('添加校园卡小卡'), manageScrollable);
    expect(find.byTooltip('添加校园卡大卡'), findsOneWidget);
    expect(find.byTooltip('添加校园卡小卡'), findsOneWidget);
    await tester.tap(find.byTooltip('添加校园卡小卡'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('overview_card_layout'),
      contains('campus_card|small'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('加号弹层可添加同内容的大卡与小卡副本并持久化', (tester) async {
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加卡片'));
    await tester.pumpAndSettle();
    expect(find.text('管理卡片'), findsOneWidget);
    await revealInSheet(tester, find.byTooltip('添加校园卡大卡'), manageScrollable);
    await tester.tap(find.byTooltip('添加校园卡大卡'));
    await tester.pumpAndSettle();
    expect(overviewCard('campus_card·2'), findsOneWidget);
    await tester.tap(find.text('添加卡片'));
    await tester.pumpAndSettle();
    await revealInSheet(tester, find.byTooltip('添加校园卡小卡'), manageScrollable);
    await tester.tap(find.byTooltip('添加校园卡小卡'));
    await tester.pumpAndSettle();
    expect(overviewCard('campus_card·3'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final layout = prefs.getStringList('overview_card_layout')!;
    expect(layout.where((entry) => entry == 'campus_card|large').length, 2);
    expect(layout.where((entry) => entry == 'campus_card|small').length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('加号弹层移除卡片后概览不再显示该卡片', (tester) async {
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加卡片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('卡片排序'));
    await tester.pumpAndSettle();
    await revealInSheet(tester, find.byTooltip('移除未读消息'), reorderScrollable);
    await tester.tap(find.byTooltip('移除未读消息'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('manage_list')),
        matching: find.byTooltip('移除未读消息'),
      ),
      findsNothing,
    );
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(overviewCard('notice'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('overview_card_layout')!.contains('notice|small'),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('小卡在窄屏并排成正方形且长文本不溢出', (tester) async {
    SharedPreferences.setMockInitialValues({
      'overview_card_layout': <String>[
        'recent_bill|small',
        'electricity_1|small',
        'exam|small',
        'campus_card|small',
      ],
    });
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      overviewApp(
        textScale: 1.4,
        page: BalanceOverviewPage(
          loadCardInfo: loadCard,
          loadElectricityBalance: (room) async =>
              ElectricityBalanceInfo(balance: '1234.56'),
          loadRecentBills: (query) async => const [
            CampusCardBill(
              merchantName: '第一食堂超长商户名称用于测试溢出情况',
              amount: '1234.56',
              time: '2026-10-25 12:30',
              tradeType: '1',
            ),
          ],
          loadExams: () async => [
            ExamScheduleModel(
              id: 'e1',
              title: '高等数学期末考试超长考试名称用于测试溢出',
              courseName: '高等数学与农业生态基础',
              time: DateTime.now().add(const Duration(days: 2)),
              location: '教学楼一号楼101考场',
              status: '未开始',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(overviewCard('campus_card'));
    final recent = tester.getSize(overviewCard('recent_bill'));
    expect(recent.width, lessThan(200));
    expect(recent.height, closeTo(recent.width, 2));
    expect(
      tester.getTopLeft(overviewCard('recent_bill')).dy,
      tester.getTopLeft(overviewCard('electricity_1')).dy,
    );
    expect(tester.takeException(), isNull);
  });
}
