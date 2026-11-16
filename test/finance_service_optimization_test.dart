import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:smart_hunan_agri/models/electricity_model.dart';
import 'package:smart_hunan_agri/services/campus_card_service.dart';
import 'package:smart_hunan_agri/services/electricity_service.dart';
import 'package:smart_hunan_agri/services/finance_cache_store.dart';
import 'package:smart_hunan_agri/utils/dkyw_crypto.dart';

import 'campus_card_wechat_order_test.dart' as fixtures;

void main() {
  final originalLogLevel = Logger.level;
  setUpAll(() => Logger.level = Level.off);
  tearDownAll(() => Logger.level = originalLogLevel);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'user': 'student-a'});
  });

  test('并行读取余额只发送一次查询，后续主动读取仍获取新数据', () async {
    final gate = Completer<void>();
    var reads = 0;
    final h = fixtures.Harness(
      handle: (r) async {
        reads++;
        await gate.future;
        return fixtures.body(fixtures.cardPage);
      },
    );
    final results = List.generate(4, (_) => h.service.fetchRechargeInfo());
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future.wait(results);
    expect(reads, 1);
    await h.service.fetchRechargeInfo();
    expect(reads, 2);
    final cached = await FinanceCacheStore.read('card');
    expect(cached!.data['balance'], '0.00');
    expect(cached.data.containsKey('openid'), isFalse);
  });

  test('网络错误不引起重复授权和重放余额查询', () async {
    final h = fixtures.Harness(
      handle: (r) => throw DioException(
        requestOptions: r,
        type: DioExceptionType.receiveTimeout,
      ),
    );
    await expectLater(
      h.service.fetchRechargeInfo(),
      throwsA(isA<DioException>()),
    );
    expect(h.adapter.requests, hasLength(1));
    expect(h.authCalls, 0);
  });

  test('付款码解析失败不清除会话或重复授权', () async {
    final h = fixtures.Harness();
    await expectLater(
      h.service.fetchPaymentCode(),
      fixtures.failsWith('解析付款码'),
    );
    expect(h.adapter.requests, hasLength(1));
    expect(h.authCalls, 0);
    expect(h.service.openid, 'old-openid');
  });

  test('电费下单超时不自动重放，且并发提交被拦截', () async {
    final gate = Completer<void>();
    var orders = 0;
    final h = fixtures.Harness();
    final adapter = fixtures.PaymentAdapter((r) async {
      if (r.method == 'GET') return fixtures.body('电费首页');
      if (r.uri.path.endsWith('createPreThirdTrade')) {
        orders++;
        await gate.future;
        throw DioException(
          requestOptions: r,
          type: DioExceptionType.receiveTimeout,
        );
      }
      return fixtures.jsonBody({'success': true});
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final service = ElectricityService.forTesting(dio: dio, card: h.service);
    Future<bool> pay() => service.recharge(
      areaName: '东湖',
      buildingName: '1栋',
      roomId: '101',
      mertype: 'yk',
      amount: 10,
    );
    final first = pay();
    await expectLater(pay(), fixtures.failsWith('请勿重复操作'));
    gate.complete();
    await expectLater(first, fixtures.failsWith('勿重复支付'));
    expect(orders, 1);
  });

  test('HTTP OAuth 合并并发请求，逐跳保存 Cookie 后才完成授权', () async {
    final jar = CookieJar();
    final gate = Completer<void>();
    final adapter = fixtures.PaymentAdapter((r) async {
      if (r.uri.host == 'auth.chaoxing.com') {
        await gate.future;
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['http://fin-serv.hunau.edu.cn/homecx/openCXOAuthPage'],
            'set-cookie': ['CX=test; Path=/'],
          },
        );
      }
      if (r.uri.path.endsWith('openCXOAuthPage')) {
        expect(r.headers['cookie'] ?? '', isNot(contains('CX=test')));
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': [
              'https://fin-serv.hunau.edu.cn/homeCX/openHomePage?openid=fresh&usertype=2',
            ],
            'set-cookie': ['FIN=test; Path=/'],
          },
        );
      }
      expect(r.headers['cookie'], contains('FIN=test'));
      return fixtures.body('<html>财务首页</html>');
    });
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = adapter;
    final service = CampusCardService.forTesting(
      dio: dio,
      cookieJar: jar,
      clearSession: () async {},
    );
    final calls = List.generate(3, (_) => service.authenticate());
    gate.complete();
    expect(await Future.wait(calls), ['fresh', 'fresh', 'fresh']);
    expect(adapter.requests, hasLength(3));
    expect(
      (await jar.loadForRequest(
        Uri.parse('https://fin-serv.hunau.edu.cn/'),
      )).map((c) => c.name),
      contains('FIN'),
    );
  });

  test('带 openid 的重定向最终落到错误页不能当作授权成功', () async {
    var step = 0;
    final adapter = fixtures.PaymentAdapter((r) {
      if (step++ == 0) {
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': [
              'https://fin-serv.hunau.edu.cn/homeCX/openHomePage?openid=stale',
            ],
          },
        );
      }
      return fixtures.body('<html>资源受限，页面丢失</html>');
    });
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = adapter;
    final service = CampusCardService.forTesting(
      dio: dio,
      cookieJar: CookieJar(),
      clearSession: () async {},
    );
    expect(await service.authenticate(), isNull);
    expect(service.openid, isNull);
  });

  test('支付宝使用加密 JSON 并解析 htmlpost', () async {
    final h = fixtures.Harness(
      handle: (r) {
        if (r.uri.path.endsWith('transferFromAlipay2Card')) {
          return fixtures.jsonBody({
            'success': true,
            'resultData': {
              'htmlpost':
                  '<form action="https://openapi.alipay.com/gateway.do"></form>',
            },
          });
        }
        return fixtures.Harness.normalResponse(r);
      },
    );
    expect(await h.service.getAlipayForm(20), contains('<form'));
    expect(h.adapter.sentBodies, hasLength(2));
    expect(DkywCrypto.decryptPayload(h.adapter.sentBodies.last['datajson']), {
      'txamt': '20',
      'payWay': '4',
      'openid': 'old-openid',
      'idserial': '20260001',
    });
  });

  test('支付宝下单超时只发一次，不自动重新下单', () async {
    final h = fixtures.Harness(
      handle: (r) {
        if (r.uri.path.endsWith('transferFromAlipay2Card')) {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return fixtures.Harness.normalResponse(r);
      },
    );
    await expectLater(h.service.getAlipayForm(10), fixtures.failsWith('勿重复支付'));
    expect(
      h.adapter.requests.where(
        (r) => r.uri.path.endsWith('transferFromAlipay2Card'),
      ),
      hasLength(1),
    );
  });

  test('余额快照按账户隔离，旧账户完成的查询不能写入新账户', () async {
    final now = DateTime.now();
    await FinanceCacheStore.write('student-a', 'card', {'balance': '10'}, now);
    FlutterSecureStorage.setMockInitialValues({'user': 'student-b'});
    expect(await FinanceCacheStore.read('card'), isNull);
    await FinanceCacheStore.write('student-a', 'card', {'balance': '999'}, now);
    expect(await FinanceCacheStore.read('card'), isNull);
    FlutterSecureStorage.setMockInitialValues({'user': 'student-a'});
    expect((await FinanceCacheStore.read('card'))!.data['balance'], '10');
  });

  test('并发电费查询合并授权和同宿舍请求，不同宿舍分别保存余额', () async {
    final gate = Completer<void>();
    var entryCalls = 0;
    var balanceCalls = 0;
    final h = fixtures.Harness();
    final adapter = fixtures.PaymentAdapter((r) async {
      if (r.method == 'GET') {
        entryCalls++;
        await gate.future;
        return fixtures.body('电费首页');
      }
      balanceCalls++;
      final payload = DkywCrypto.decryptPayload((r.data as Map)['datajson']);
      return fixtures.jsonBody({
        'success': true,
        'resultData': {
          'balance': payload['roomid'] == '101' ? '10.00' : '20.00',
        },
      });
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final service = ElectricityService.forTesting(dio: dio, card: h.service);
    Future<ElectricityBalanceInfo> query(String room) => service.getBalance(
      areaName: '东湖',
      buildingName: '1栋',
      roomId: room,
      mertype: 'yk',
    );
    final calls = [query('101'), query('101'), query('202')];
    gate.complete();
    expect((await Future.wait(calls)).map((b) => b.balance), [
      '10.00',
      '10.00',
      '20.00',
    ]);
    expect(entryCalls, 1);
    expect(balanceCalls, 2);
    final snapshot = await FinanceCacheStore.read(
      ElectricityService.balanceCacheKey(
        const SavedElectricityRoom(
          areaName: '东湖',
          buildingName: '1栋',
          roomId: '202',
          roomName: '202室',
          mertype: 'yk',
        ),
      ),
    );
    expect(snapshot!.data['balance'], '20.00');
  });

  test('宿舍缓存键包含校区楼栋房间和电表类型，显示名不影响匹配', () {
    SavedElectricityRoom room(String id, {String name = '宿舍'}) =>
        SavedElectricityRoom(
          areaName: '东湖',
          buildingName: '1栋',
          roomId: id,
          roomName: name,
          mertype: 'yk',
        );
    expect(
      ElectricityService.balanceCacheKey(room('101')),
      isNot(ElectricityService.balanceCacheKey(room('202'))),
    );
    expect(
      ElectricityService.balanceCacheKey(room('101')),
      ElectricityService.balanceCacheKey(room('101', name: '101室')),
    );
  });
}
