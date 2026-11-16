import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/repair_models.dart';
import 'package:smart_hunan_agri/services/repair_service.dart';
import 'support/session_http_adapter.dart';

ResponseBody rpc(dynamic value, {bool encoded = false}) {
  final body = jsonEncode({'jsonrpc': '2.0', 'id': '1', 'result': value});
  return sessionResponse(encoded ? base64Encode(utf8.encode(body)) : body);
}

String method(RequestOptions r) => r.data is Map ? '${r.data['method']}' : '';
Map<String, dynamic> identity(String id) => {
  'id': id,
  'display_name': '测试用户',
  'username': 'test',
};

void main() {
  for (final encoded in [false, true]) {
    test('首次加载使用已认证用户编号，兼容 encoded=$encoded', () async {
      final adapter = SessionHttpAdapter((r) {
        if (method(r).endsWith('isAuthenticated')) {
          return rpc(identity('user-1'), encoded: encoded);
        }
        expect(jsonEncode(r.data['params']), contains('user-1'));
        expect(r.headers['X-User-Lang'], 'zh-CN');
        return rpc({
          'data': [
            {'id': 'order-1', 'dynamic_title': '网络故障'},
          ],
        }, encoded: encoded);
      });
      final result = await RepairService(
        dio: Dio()..httpClientAdapter = adapter,
      ).fetchOrders();
      expect(result.single.title, '网络故障');
      expect(adapter.requests.length, 2);
    });
  }
  test('交换后仍未认证也能静默刷新SSO，自动完成首次加载', () async {
    var refreshed = false, renewals = 0, exchanges = 0;
    final adapter = SessionHttpAdapter((r) {
      if (r.method == 'GET') {
        exchanges++;
        return sessionResponse('认证');
      }
      if (method(r).endsWith('isAuthenticated')) {
        return refreshed
            ? rpc(identity('fresh'))
            : sessionResponse('{"error":{"code":401,"message":"未登录"}}');
      }
      expect(jsonEncode(r.data['params']), contains('fresh'));
      return rpc({'data': []});
    });
    final service = RepairService(
      dio: Dio()..httpClientAdapter = adapter,
      reauthenticate: () async {
        renewals++;
        refreshed = true;
        return true;
      },
    );
    expect(await service.fetchOrders(), isEmpty);
    expect(renewals, 1);
    expect(exchanges, 2);
  });
  test('并发首次请求合并认证流程', () async {
    final release = Completer<void>();
    var probes = 0;
    final adapter = SessionHttpAdapter((r) async {
      if (method(r).endsWith('isAuthenticated')) {
        probes++;
        await release.future;
        return rpc(identity('user'));
      }
      return rpc({'data': []});
    });
    final service = RepairService(dio: Dio()..httpClientAdapter = adapter);
    final requests = Future.wait([
      service.fetchOrders(),
      service.fetchOrders(ongoing: false),
    ]);
    await Future<void>.delayed(Duration.zero);
    release.complete();
    expect(await requests, [[], []]);
    expect(probes, 1);
  });
  test('已打开平台的会话过期可恢复，并用新编号重建查询', () async {
    var uid = 'old', denied = false, lists = 0;
    final adapter = SessionHttpAdapter((r) {
      if (method(r).endsWith('isAuthenticated')) return rpc(identity(uid));
      if (lists++ == 0) {
        uid = 'new';
        denied = true;
        return sessionResponse('', status: 401);
      }
      expect(jsonEncode(r.data['params']), contains('new'));
      return rpc({'data': []});
    });
    expect(
      await RepairService(
        dio: Dio()..httpClientAdapter = adapter,
      ).fetchOrders(),
      isEmpty,
    );
    expect(denied, isTrue);
    expect(lists, 2);
  });
  test('工单响应异常不会伪装成空列表', () async {
    final adapter = SessionHttpAdapter(
      (r) => rpc(
        method(r).endsWith('isAuthenticated')
            ? identity('user')
            : {'unexpected': []},
      ),
    );
    await expectLater(
      RepairService(dio: Dio()..httpClientAdapter = adapter).fetchOrders(),
      throwsA(isA<RepairException>()),
    );
  });
  test('报修CAS逐跳处理HTTP升级和Cookie跳转', () async {
    var exchanged = false;
    final adapter = SessionHttpAdapter((r) {
      if (r.method == 'GET') {
        if (r.uri.host == 'sso.hunau.edu.cn') {
          return sessionResponse(
            '',
            status: 302,
            location:
                'http://bxpt.hunau.edu.cn/relax/sso/cas/login?ticket=ST-test',
          );
        }
        expect(r.uri.scheme, 'https');
        exchanged = true;
        return sessionResponse('首页');
      }
      if (method(r).endsWith('isAuthenticated')) {
        return rpc(exchanged ? identity('user') : null);
      }
      return rpc({'data': []});
    });
    expect(
      await RepairService(
        dio: Dio()..httpClientAdapter = adapter,
      ).fetchOrders(),
      isEmpty,
    );
    expect(exchanged, isTrue);
  });
  test('按学校配置选择提交动作、工单类型和验证规则', () async {
    final catalog = RepairService.catalogs.first;
    final adapter = SessionHttpAdapter((r) {
      return switch (method(r)) {
        '/v2/login/isAuthenticated' => rpc(identity('user')),
        '/v2/cmdb/ci/id' => rpc('instance'),
        '/v2/workorder/serviceitem/card/getMobileCatalogById' => rpc({
          'type': {'id': 'actual-type'},
        }),
        '/v2/workorder/view/form/getNotRelationOrderForm' => rpc([
          {
            'constructData': jsonEncode({
              'ciType': 'actual-type',
              'components': [
                {
                  'editor': 'group',
                  'children': [
                    {
                      'name': 'wtmsh',
                      'label': '问题描述',
                      'editor': 'textarea',
                      'required': true,
                    },
                  ],
                },
              ],
              'rules': [
                {'rule_id': 'rule'},
              ],
            }),
          },
        ]),
        '/v2/workorder/orderConfig/getNodeByServiceCatalog' => rpc('node'),
        '/v2/workorder/action/list' => rpc([
          {'id': 'draft', 'name': '保存草稿'},
          {'id': 'submit', 'name': '提交'},
        ]),
        '/v2/workorder/action/executeWithValidate' => (() {
          final params = r.data['params'] as List;
          expect(params[0], 'submit');
          expect(params[1][0]['type'], 'actual-type');
          expect(params[2], ['rule']);
          expect(params[1][1]['apply_user'], 'user');
          return rpc({'state': true});
        })(),
        _ => throw StateError('unexpected method'),
      };
    });
    final service = RepairService(dio: Dio()..httpClientAdapter = adapter);
    final session = await service.loadForm(catalog);
    expect(session.fields.single.name, 'wtmsh');
    expect(session.ciType, isNot(catalog.processId));
    await service.submitForm(session, {'wtmsh': '网络故障'});
  });
  for (final status in [401, 500]) {
    test('提交发生$status错误不自动重复写入', () async {
      var writes = 0;
      final adapter = SessionHttpAdapter((r) {
        if (method(r).endsWith('isAuthenticated')) return rpc(identity('user'));
        writes++;
        return sessionResponse('服务异常', status: status);
      });
      final service = RepairService(dio: Dio()..httpClientAdapter = adapter);
      final session = RepairFormSession(
        catalog: RepairService.catalogs.first,
        instanceId: 'id',
        ciType: 'type',
        nodeId: 'node',
        submitActionId: 'submit',
        formRuleId: null,
        fields: [],
        initialValues: {},
      );
      await expectLater(service.submitForm(session, {}), throwsA(anything));
      expect(writes, 1);
    });
  }
  test('预约时间保留小时和分钟', () {
    expect(
      RepairService.parseDateToTimestamp('2026-10-12 14:35'),
      DateTime(2026, 10, 12, 14, 35).millisecondsSinceEpoch,
    );
  });
}
