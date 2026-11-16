import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/campus_card_bill.dart';
import 'package:smart_hunan_agri/models/app_constants.dart';
import 'package:smart_hunan_agri/models/quick_action_item.dart';
import 'package:smart_hunan_agri/pages/campus_card_bill_page.dart';
import 'package:smart_hunan_agri/pages/function_page.dart';
import 'package:smart_hunan_agri/services/campus_card_bill_service.dart';

const bill = CampusCardBill(
  merchantName: '校园第二食堂一楼特色餐饮窗口超长商户名称完整显示',
  amount: '-12.50',
  time: '2026-01-01 12:30:00',
  tradeType: '1',
);

void main() {
  testWidgets('功能页提供唯一的校园卡账单入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FunctionPage()));
    expect(find.text('校园卡账单'), findsOneWidget);
    expect(find.text('查询消费、充值、补助与转账记录'), findsOneWidget);
  });

  test('学费与体测入口使用指定地址并可加入首页快捷入口', () {
    expect(
      AppConstants.tuitionPaymentUrl,
      'https://cwcx.hunau.edu.cn/SFPT_H5/?v=1794803240834#/query',
    );
    expect(
      AppConstants.physicalFitnessScoreUrl,
      'http://ndtzcs.hunau.edu.cn/weixin/main.jsp',
    );
    expect(QuickActionCatalog.byId('tuition_payment')?.label, '学费缴费');
    expect(QuickActionCatalog.byId('physical_fitness_score')?.label, '体测成绩');
  });

  testWidgets('进入查询近七天，切换条件清除旧账单，查询提交对应类型', (tester) async {
    final calls = <CampusCardBillQuery>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CampusCardBillPage(
          loadBills: (query) async {
            calls.add(query);
            return [bill];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.single.type, CampusCardTradeType.all);
    expect(
      DateTime.utc(
            calls.single.endDate.year,
            calls.single.endDate.month,
            calls.single.endDate.day,
          )
          .difference(
            DateTime.utc(
              calls.single.beginDate.year,
              calls.single.beginDate.month,
              calls.single.beginDate.day,
            ),
          )
          .inDays,
      6,
    );
    expect(find.text(bill.merchantName), findsOneWidget);
    expect(find.text('¥ -12.50'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '充值'));
    await tester.pumpAndSettle();
    expect(find.text(bill.merchantName), findsNothing);
    expect(find.textContaining('条件已修改'), findsOneWidget);
    await tester.tap(find.text('查询账单'));
    await tester.pumpAndSettle();
    expect(calls.last.type, CampusCardTradeType.recharge);
    // Actual per-record type takes precedence over the query filter.
    expect(find.text('消费 · 2026-01-01 12:30:00'), findsOneWidget);
  });

  testWidgets('加载期间禁止重复查询和修改条件，退出后的结果被忽略', (tester) async {
    final pending = Completer<List<CampusCardBill>>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CampusCardBillPage(
          loadBills: (_) {
            calls++;
            return pending.future;
          },
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<ChoiceChip>(find.byType(ChoiceChip).first).onSelected,
      isNull,
    );
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete([bill]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务错误可重试，空账单与失败状态区分', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CampusCardBillPage(
          loadBills: (_) async {
            if (calls++ == 0) throw const CampusCardBillException('服务维护，请稍后重试');
            return [];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('服务维护，请稍后重试'), findsOneWidget);
    expect(find.textContaining('暂无交易记录'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('所选日期和类型下暂无交易记录'), findsOneWidget);
    expect(find.text('0 笔'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('账单窄屏大字体、长商户和时间在 $brightness 下完整显示且无溢出', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorSchemeSeed: Colors.green,
            brightness: brightness,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: CampusCardBillPage(loadBills: (_) async => [bill]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(bill.merchantName), 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(find.text(bill.merchantName)).maxLines,
        isNull,
      );
      expect(
        tester.widget<Text>(find.text(bill.merchantName)).overflow,
        isNot(TextOverflow.ellipsis),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
