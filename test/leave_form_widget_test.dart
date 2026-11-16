import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/leave_models.dart';
import 'package:smart_hunan_agri/pages/leave_page.dart';
import 'package:smart_hunan_agri/services/leave_service.dart';

class FakeLeaveService extends LeaveService {
  int typesCalls = 0, submits = 0;
  bool fail = false;
  Completer<List<LeaveDictItem>>? pending;
  @override
  Future<List<LeaveDictItem>> fetchTypes() async {
    typesCalls++;
    if (fail) throw const LeaveException('学校暂时不可用');
    if (pending != null) return pending!.future;
    return [const LeaveDictItem('1', '事假')];
  }

  @override
  Future<List<RegionNode>> fetchRegions() async => const [
    RegionNode('p1', '湖南', [
      RegionNode('c1', '长沙', [RegionNode('d1', '芙蓉区')]),
    ]),
    RegionNode('p2', '湖北', [
      RegionNode('c2', '武汉', [RegionNode('d2', '洪山区')]),
    ]),
  ];
  @override
  Future<void> submit({
    required Map<String, String> fields,
    String? attachmentPath,
  }) async {
    submits++;
  }
}

Future<void> reveal(WidgetTester tester, String text, {bool up = false}) async {
  await tester.scrollUntilVisible(
    find.text(text),
    up ? -240 : 240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('完整表单可滚动，省市区切换清除旧选项，深色窄屏无溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: LeaveApplyPage(service: FakeLeaveService()),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, '紧急联系人 *');
    expect(find.text('紧急联系人电话 *'), findsOneWidget);
    await reveal(tester, '是否离校');
    await tester.tap(find.widgetWithText(SwitchListTile, '是否离校'));
    await tester.pumpAndSettle();
    await reveal(tester, '省份 *');
    await tester.tap(find.byType(DropdownButtonFormField<RegionNode>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('湖南').last);
    await tester.pumpAndSettle();
    await reveal(tester, '城市 *');
    await tester.tap(
      find.ancestor(
        of: find.text('城市 *'),
        matching: find.byType(DropdownButtonFormField<RegionNode>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('长沙').last);
    await tester.pumpAndSettle();
    await reveal(tester, '区县 *');
    await tester.tap(
      find.ancestor(
        of: find.text('区县 *'),
        matching: find.byType(DropdownButtonFormField<RegionNode>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('芙蓉区').last);
    await tester.pumpAndSettle();
    await reveal(tester, '省份 *', up: true);
    await tester.tap(find.byType(DropdownButtonFormField<RegionNode>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('湖北').last);
    await tester.pumpAndSettle();
    expect(find.text('长沙'), findsNothing);
    expect(find.text('芙蓉区'), findsNothing);
    expect(find.byType(DropdownButtonFormField<RegionNode>), findsNWidgets(2));
    await reveal(tester, '离校详细地址 *');
    await reveal(tester, '离校备注 *');
    await reveal(tester, '是否出省');
    await reveal(tester, '证明附件（选填）');
    expect(tester.takeException(), isNull);
  });
  testWidgets('缺少联系人和时间时阻止提交，校验提示可见', (tester) async {
    final service = FakeLeaveService();
    await tester.pumpWidget(
      MaterialApp(home: LeaveApplyPage(service: service)),
    );
    await tester.pumpAndSettle();
    await reveal(tester, '提交申请');
    await tester.tap(find.text('提交申请'));
    await tester.pumpAndSettle();
    expect(service.submits, 0);
    expect(find.text('请选择开始和结束时间'), findsOneWidget);
    await reveal(tester, '请填写紧急联系人');
    expect(find.text('请填写紧急联系人'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('字典加载失败可重试，恢复后显示完整表单', (tester) async {
    final service = FakeLeaveService()..fail = true;
    await tester.pumpWidget(
      MaterialApp(home: LeaveApplyPage(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('学校暂时不可用'), findsOneWidget);
    service.fail = false;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('事假'), findsOneWidget);
    expect(service.typesCalls, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('离开页面后请求返回不会setState已销毁页面', (tester) async {
    final service = FakeLeaveService()
      ..pending = Completer<List<LeaveDictItem>>();
    await tester.pumpWidget(
      MaterialApp(home: LeaveApplyPage(service: service)),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    service.pending!.complete([const LeaveDictItem('1', '事假')]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
