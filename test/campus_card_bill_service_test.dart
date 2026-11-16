import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/campus_card_bill.dart';
import 'package:smart_hunan_agri/services/campus_card_bill_service.dart';
import 'package:smart_hunan_agri/utils/dkyw_crypto.dart';

import 'support/session_http_adapter.dart';

CampusCardBillQuery query({
  CampusCardTradeType type = CampusCardTradeType.all,
}) => CampusCardBillQuery(
  beginDate: DateTime(2026, 1, 1),
  endDate: DateTime(2026, 1, 7),
  type: type,
);

ResponseBody encrypted(Object data) =>
    sessionResponse(jsonEncode({'datajson': DkywCrypto.encryptPayload(data)}));

void main() {
  test('先建会话再发送动态加密查询，日期、类型、openid、请求头及 Cookie 与参考协议一致', () async {
    final adapter = SessionHttpAdapter((r) {
      if (r.method == 'GET') {
        expect(r.uri.path, '/selftrade/openQueryCardSelfTrade');
        expect(r.uri.queryParameters, {
          'openid': 'test-id',
          'displayflag': '1',
          'id': '4',
        });
        return sessionResponse(
          '<html>查询流水</html>',
          cookies: ['JSESSIONID=bill-session; Path=/'],
        );
      }
      expect(r.uri.path, '/selftrade/queryCardSelfTradeList');
      expect(r.uri.queryParameters, {
        'openid': 'test-id',
        'connect_redirect': '1',
      });
      expect(
        r.headers['Referer'],
        contains('openQueryCardSelfTrade?openid=test-id'),
      );
      expect(r.headers['X-Requested-With'], 'XMLHttpRequest');
      expect(r.headers['cookie'], contains('JSESSIONID=bill-session'));
      expect(DkywCrypto.decryptPayload((r.data as Map)['datajson']), {
        'beginDate': '2026-01-01',
        'endDate': '2026-01-07',
        'tradeType': '1',
        'openid': 'test-id',
      });
      return encrypted({
        'success': true,
        'resultData': [
          {
            'mername': '二食堂',
            'txamt': '-12.50',
            'txdate': '2026-01-07 12:30:00',
            'tradetype': '1',
          },
        ],
      });
    });
    final service = CampusCardBillService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
      authorize: (_) async => 'test-id',
    );
    final result = await service.query(
      query(type: CampusCardTradeType.consume),
    );
    expect(result.single.merchantName, '二食堂');
    expect(result.single.amount, '-12.50');
    expect(result.single.time, '2026-01-07 12:30:00');
    expect(result.single.tradeType, '1');
    expect(adapter.requests, hasLength(2));
  });

  for (final htmlExpired in [false, true]) {
    test('会话失效仅恢复一次，重试使用新的 OpenID：HTML=$htmlExpired', () async {
      final attempts = <bool>[];
      final adapter = SessionHttpAdapter((r) {
        final expired = r.uri.queryParameters['openid'] == 'old-id';
        if (r.method == 'GET') return sessionResponse('<html>查询</html>');
        if (expired) {
          return htmlExpired
              ? sessionResponse('<html>统一身份认证 cas/login</html>')
              : encrypted({'success': false, 'message': 'openid无效'});
        }
        expect(
          DkywCrypto.decryptPayload((r.data as Map)['datajson'])['openid'],
          'new-id',
        );
        return encrypted({'success': true, 'resultData': []});
      });
      final service = CampusCardBillService(
        dio: Dio()..httpClientAdapter = adapter,
        cookieJar: CookieJar(),
        authorize: (force) async {
          attempts.add(force);
          return force ? 'new-id' : 'old-id';
        },
      );
      expect(await service.query(query()), isEmpty);
      expect(attempts, [false, true]);
      expect(adapter.requests, hasLength(4));
    });
  }

  test('初始化页重定向登录时不提交查询，两次失败后有界退出', () async {
    final attempts = <bool>[];
    final adapter = SessionHttpAdapter(
      (r) => sessionResponse(
        '',
        status: 302,
        location: 'https://sso.hunau.edu.cn/cas/login',
      ),
    );
    final service = CampusCardBillService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
      authorize: (force) async {
        attempts.add(force);
        return 'id';
      },
    );
    await expectLater(
      service.query(query()),
      throwsA(
        isA<CampusCardBillException>().having(
          (e) => e.message,
          'message',
          contains('会话已失效'),
        ),
      ),
    );
    expect(attempts, [false, true]);
    expect(adapter.requests.every((r) => r.method == 'GET'), isTrue);
    expect(adapter.requests, hasLength(2));
  });

  test('商户名称包含登录字样不影响成功响应，兼容嵌套列表与备用字段', () async {
    final adapter = SessionHttpAdapter(
      (r) => r.method == 'GET'
          ? sessionResponse('查询')
          : encrypted({
              'success': true,
              'resultData': {
                'rows': [
                  {
                    'mercname': '未登录资源受限商店',
                    'txamt': 10,
                    'paytime': '2026-01-01',
                    'txtype': 2,
                  },
                ],
              },
            }),
    );
    final attempts = <bool>[];
    final service = CampusCardBillService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
      authorize: (force) async {
        attempts.add(force);
        return 'id';
      },
    );
    final bill = (await service.query(query())).single;
    expect(bill.amount, '10');
    expect(bill.tradeType, '2');
    expect(bill.merchantName, '未登录资源受限商店');
    expect(attempts, [false]);
  });

  for (final data in [
    {'success': false, 'message': '查询服务正在维护'},
    {
      'success': true,
      'resultData': {'unknown': 'changed'},
    },
    {
      'success': true,
      'resultData': [123],
    },
    '<html>服务器异常</html>',
  ]) {
    test('失败或格式异常不能展示为空账单：$data', () async {
      final adapter = SessionHttpAdapter(
        (r) => r.method == 'GET' ? sessionResponse('查询') : encrypted(data),
      );
      var authCalls = 0;
      final service = CampusCardBillService(
        dio: Dio()..httpClientAdapter = adapter,
        cookieJar: CookieJar(),
        authorize: (_) async {
          authCalls++;
          return 'id';
        },
      );
      await expectLater(
        service.query(query()),
        throwsA(isA<CampusCardBillException>()),
      );
      expect(authCalls, 1);
      expect(adapter.requests, hasLength(2));
    });
  }

  test('服务器故障不反复清理登录态', () async {
    var authCalls = 0;
    final adapter = SessionHttpAdapter(
      (r) => sessionResponse('维护', status: 503),
    );
    final service = CampusCardBillService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
      authorize: (_) async {
        authCalls++;
        return 'id';
      },
    );
    await expectLater(
      service.query(query()),
      throwsA(isA<CampusCardBillException>()),
    );
    expect(authCalls, 1);
    expect(adapter.requests, hasLength(1));
  });

  test('服务层拒绝非法日期范围，跨月和闰日验证不受时区时长影响', () async {
    final adapter = SessionHttpAdapter((r) => throw StateError('不应联网'));
    final service = CampusCardBillService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
      authorize: (_) async => throw StateError('不应授权'),
    );
    for (final invalid in [
      CampusCardBillQuery(
        beginDate: DateTime(2026, 1, 2),
        endDate: DateTime(2026, 1, 1),
      ),
      CampusCardBillQuery(
        beginDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 2, 2),
      ),
      CampusCardBillQuery(
        beginDate: DateTime(2099, 1, 1),
        endDate: DateTime(2099, 1, 1),
      ),
    ]) {
      await expectLater(
        service.query(invalid),
        throwsA(isA<CampusCardBillException>()),
      );
    }
    expect(adapter.requests, isEmpty);
    expect(
      CampusCardBillQuery(
        beginDate: DateTime(2024, 2, 1),
        endDate: DateTime(2024, 3, 3),
      ).validate(now: DateTime(2024, 3, 3)),
      isNull,
    );
    expect(
      CampusCardBillQuery(
        beginDate: DateTime(2026, 1, 1, 23),
        endDate: DateTime(2026, 1, 1, 1),
      ).validate(),
      isNull,
    );
  });
}
