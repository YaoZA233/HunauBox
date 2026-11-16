import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/repair_models.dart';
import 'package:smart_hunan_agri/pages/repair_page.dart';
import 'package:smart_hunan_agri/services/repair_service.dart';

class FakeRepairService extends RepairService {
  int lists = 0, submissions = 0;
  final release = Completer<void>();
  @override
  Future<List<RepairOrder>> fetchOrders({
    bool ongoing = true,
    bool isDraft = false,
  }) async {
    lists++;
    return [];
  }

  @override
  Future<RepairFormSession> loadForm(RepairCatalog catalog) async =>
      RepairFormSession(
        catalog: catalog,
        instanceId: 'id',
        ciType: 'type',
        nodeId: 'node',
        submitActionId: 'submit',
        formRuleId: 'rule',
        fields: const [
          RepairField(
            name: 'wtmsh',
            label: '问题描述',
            editor: 'textarea',
            required: true,
            hidden: false,
            readonly: false,
          ),
          RepairField(
            name: 'lxfs',
            label: '联系电话',
            editor: 'text',
            required: true,
            hidden: false,
            readonly: false,
          ),
          RepairField(
            name: 'building',
            label: '楼栋',
            editor: 'reference',
            reference: 'buildings',
            required: true,
            hidden: false,
            readonly: false,
          ),
        ],
        initialValues: {},
      );
  @override
  Future<List<RepairChoice>> references(
    String type, {
    String query = '',
  }) async => [const RepairChoice('building-1', '测试楼栋')];
  @override
  Future<String> submitForm(
    RepairFormSession session,
    Map<String, dynamic> values, {
    bool isDraft = false,
  }) async {
    expect(values['building'], 'building-1');
    expect(values['lxfs'], '13800138000');
    submissions++;
    await release.future;
    return 'ok';
  }
}

void main() {
  testWidgets('按学校字段渲染和校验，选择使用编号，提交后自动刷新列表且防重复', (tester) async {
    final service = FakeRepairService();
    await tester.pumpWidget(MaterialApp(home: RepairPage(service: service)));
    await tester.pumpAndSettle();
    expect(service.lists, 1);
    await tester.tap(find.text('新建报修'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('后勤报修'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交报修'));
    await tester.pumpAndSettle();
    expect(service.submissions, 0);
    expect(find.text('请填写问题描述'), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '水龙头漏水');
    await tester.enterText(fields.at(1), '13800138000');
    await tester.tap(fields.at(2));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('测试楼栋'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交报修'));
    await tester.pump();
    expect(service.submissions, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    service.release.complete();
    await tester.pumpAndSettle();
    expect(find.text('报修平台'), findsOneWidget);
    expect(service.lists, 2);
    expect(tester.takeException(), isNull);
  });
}
