import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:smart_hunan_agri/models/app_constants.dart';
import 'package:smart_hunan_agri/services/campus_card_service.dart';
import 'package:smart_hunan_agri/utils/dkyw_crypto.dart';

const cardPage =
    '<input id="username" value="测试同学">'
    '<input id="idserial" value="20260001"><span>余额：0.00</span>';
const returnUrl =
    'http://fin-serv.hunau.edu.cn/common/paySuccess?idserial=20260001';

Map<String, dynamic> orderJson({String? returnurl}) => {
  'success': true,
  'message': 'CORE10008',
  'resultData': {
    'partnerjourno': 'order-123',
    'mweb_url':
        'https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?prepay_id=test',
    'returnurl':
        returnurl ?? Uri.encodeComponent(Uri.encodeComponent(returnUrl)),
    'redirect_url': 'http://fin-serv1.hunau.edu.cn/',
    'prepay_id': 'test',
  },
};

ResponseBody body(String value, {int status = 200}) => ResponseBody.fromString(
  value,
  status,
  headers: {
    Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
  },
);

ResponseBody jsonBody(Object value, {bool encrypted = true}) => body(
  jsonEncode(
    encrypted ? {'datajson': DkywCrypto.encryptPayload(value)} : value,
  ),
);

class PaymentAdapter implements HttpClientAdapter {
  PaymentAdapter(this.handle);
  final FutureOr<ResponseBody> Function(RequestOptions) handle;
  final requests = <RequestOptions>[];
  final sentBodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(
        [],
        (a, b) => a..addAll(b),
      );
      sentBodies.add(Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes))));
    }
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

class Harness {
  Harness({
    FutureOr<ResponseBody> Function(RequestOptions)? handle,
    bool hasSession = true,
  }) {
    adapter = PaymentAdapter(handle ?? (r) => normalResponse(r));
    final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
    dio.httpClientAdapter = adapter;
    service = CampusCardService.forTesting(
      dio: dio,
      openid: hasSession ? 'old-openid' : null,
      cachedInfo: hasSession
          ? CampusCardInfo(
              name: '旧信息',
              idserial: 'stale-card',
              balance: '99.00',
            )
          : null,
      authorize: () async {
        authCalls++;
        return 'fresh-openid';
      },
      clearSession: () async {
        clearCalls++;
      },
    );
  }
  late final PaymentAdapter adapter;
  late final CampusCardService service;
  int authCalls = 0;
  int clearCalls = 0;

  static ResponseBody normalResponse(RequestOptions r) {
    if (r.method == 'GET') return body(cardPage);
    if (r.uri.path.endsWith('userlastbind')) return jsonBody({'success': true});
    return jsonBody(orderJson());
  }

  List<RequestOptions> get orders => adapter.requests
      .where((r) => r.uri.path.endsWith('transferFromWx2Card'))
      .toList();
}

Matcher failsWith(String message) =>
    throwsA(predicate<Object>((e) => e.toString().contains(message)));

void main() {
  final originalLogLevel = Logger.level;
  setUpAll(() => Logger.level = Level.off);
  tearDownAll(() => Logger.level = originalLogLevel);
  test('下单和支付方式记录发送加密 JSON，解析加密订单和双重编码返回地址', () async {
    final h = Harness();
    final order = await h.service.createWeChatOrder(10);
    expect(h.adapter.requests.map((r) => r.method), ['GET', 'POST', 'POST']);
    expect(h.adapter.sentBodies, hasLength(2));
    for (final data in h.adapter.sentBodies) {
      expect(data.keys, ['datajson']);
      expect(data['datajson'], isA<String>());
    }
    expect(DkywCrypto.decryptPayload(h.adapter.sentBodies[0]['datajson']), {
      'payinfo': {'cardpayWay': '1'},
      'idserial': '20260001',
    });
    expect(DkywCrypto.decryptPayload(h.adapter.sentBodies[1]['datajson']), {
      'txamt': '10',
      'payWay': '1',
      'openid': 'old-openid',
      'idserial': '20260001',
      'tradetype': 'WAP',
    });
    for (final r in h.adapter.requests.where((r) => r.method == 'POST')) {
      expect(r.queryParameters, {
        'openid': 'old-openid',
        'connect_redirect': '1',
      });
      expect(r.contentType, Headers.jsonContentType);
      expect(r.responseType, ResponseType.plain);
      expect(r.headers['User-Agent'], AppConstants.campusCardUA);
      expect(r.headers['X-Requested-With'], 'XMLHttpRequest');
      expect(
        r.headers['Referer'],
        contains('cardpay/openCardPay?openid=old-openid'),
      );
      expect(r.headers['Accept'], contains('application/json'));
    }
    expect(order.partnerjourno, 'order-123');
    expect(order.mwebUrl, startsWith('https://wx.tenpay.com/'));
    expect(order.returnurl, returnUrl.replaceFirst('http:', 'https:'));
    expect(order.prepayId, 'test');
    expect(h.service.cachedInfo!.balance, '0.00');
  });

  test('兼容历史明文 JSON 订单', () async {
    final h = Harness(
      handle: (r) => r.uri.path.endsWith('transferFromWx2Card')
          ? jsonBody(orderJson(), encrypted: false)
          : Harness.normalResponse(r),
    );
    expect((await h.service.createWeChatOrder(1)).partnerjourno, 'order-123');
  });
  test('兼容带引号的 HTML 转义加密订单', () async {
    final escaped = jsonEncode(
      jsonEncode({
        'datajson': DkywCrypto.encryptPayload(orderJson()),
      }).replaceAll('"', '&quot;'),
    );
    final h = Harness(
      handle: (r) => r.uri.path.endsWith('transferFromWx2Card')
          ? body(escaped)
          : Harness.normalResponse(r),
    );
    expect(
      (await h.service.createWeChatOrder(1000)).partnerjourno,
      'order-123',
    );
  });
  for (final url in [
    returnUrl,
    Uri.encodeComponent(returnUrl),
    'https://fin-serv.hunau.edu.cn/common/paySuccess?token=a%2Fb%26c',
  ]) {
    test('返回地址规范化且不损坏查询参数：$url', () async {
      final h = Harness(
        handle: (r) => r.uri.path.endsWith('transferFromWx2Card')
            ? jsonBody(orderJson(returnurl: url))
            : Harness.normalResponse(r),
      );
      final expected = url.startsWith('https:')
          ? url
          : returnUrl.replaceFirst('http:', 'https:');
      expect((await h.service.createWeChatOrder(1)).returnurl, expected);
    });
  }
  test('未授权时先授权并使用新 OpenID', () async {
    final h = Harness(hasSession: false);
    await h.service.createWeChatOrder(10);
    expect(h.authCalls, 1);
    expect(h.orders.single.queryParameters['openid'], 'fresh-openid');
  });
  test('旧会话失效时只重试只读校验，下单仅一次', () async {
    var gets = 0;
    final h = Harness(
      handle: (r) {
        if (r.method == 'GET' && gets++ == 0) return body('<html>资源受限</html>');
        return Harness.normalResponse(r);
      },
    );
    await h.service.createWeChatOrder(10);
    expect(h.clearCalls, 1);
    expect(h.authCalls, 1);
    expect(h.orders, hasLength(1));
    expect(h.orders.single.queryParameters['openid'], 'fresh-openid');
  });
  for (final status in [200, 401, 403]) {
    test('持续会话失效（HTTP $status）不能回退旧缓存或下单', () async {
      final h = Harness(
        handle: (_) => body('<html>页面丢失</html>', status: status),
      );
      await expectLater(h.service.createWeChatOrder(10), failsWith('会话失效'));
      expect(h.orders, isEmpty);
      expect(h.service.cachedInfo, isNull);
      expect(h.service.openid, isNull);
      expect(h.authCalls, 1);
    });
  }
  test('记录支付方式时会话失效必须停止，不继续发送订单', () async {
    final h = Harness(
      handle: (r) => r.uri.path.endsWith('userlastbind')
          ? body('<html>资源受限</html>')
          : Harness.normalResponse(r),
    );
    await expectLater(h.service.createWeChatOrder(10), failsWith('会话失效'));
    expect(h.orders, isEmpty);
    expect(h.clearCalls, 1);
  });
  test('下单期间会话失效不自动重放 POST', () async {
    final h = Harness(
      handle: (r) => r.uri.path.endsWith('transferFromWx2Card')
          ? body('<html>统一身份认证 cas/login</html>')
          : Harness.normalResponse(r),
    );
    await expectLater(h.service.createWeChatOrder(10), failsWith('会话失效'));
    expect(h.orders, hasLength(1));
    expect(h.clearCalls, 1);
  });
  test('支付偏好接口非会话错误不影响下单', () async {
    final h = Harness(
      handle: (r) => r.uri.path.endsWith('userlastbind')
          ? body('bad gateway', status: 502)
          : Harness.normalResponse(r),
    );
    expect((await h.service.createWeChatOrder(10)).partnerjourno, 'order-123');
    expect(h.orders, hasLength(1));
  });
  test('保留加密响应的服务端拒绝原因', () async {
    final h = Harness(
      handle: (r) => r.uri.path.endsWith('transferFromWx2Card')
          ? jsonBody({'success': false, 'message': '当前卡片状态不允许充值'})
          : Harness.normalResponse(r),
    );
    await expectLater(
      h.service.createWeChatOrder(10),
      failsWith('当前卡片状态不允许充值'),
    );
    expect(h.orders, hasLength(1));
  });
  for (final amount in [0.0, -1.0, 1001.0, 1.5, double.nan, double.infinity]) {
    test('非法金额 $amount 不发送任何请求', () async {
      final h = Harness();
      await expectLater(h.service.createWeChatOrder(amount), failsWith('整数'));
      expect(h.adapter.requests, isEmpty);
    });
  }
  final invalidResponses = {
    'HTML': body('<html>unexpected</html>'),
    '损坏密文': body('{"datajson":"bad-cipher"}'),
    '缺少订单': jsonBody({'success': true}),
    '缺少字段': jsonBody({
      'success': true,
      'resultData': {'mweb_url': 'https://wx.tenpay.com/'},
    }),
    'HTTP 503': body('unavailable', status: 503),
  };
  for (final entry in invalidResponses.entries) {
    test('无效响应 ${entry.key} 不能作为可支付订单', () async {
      final h = Harness(
        handle: (r) => r.uri.path.endsWith('transferFromWx2Card')
            ? entry.value
            : Harness.normalResponse(r),
      );
      await expectLater(h.service.createWeChatOrder(10), throwsException);
      expect(h.orders, hasLength(1));
    });
  }
  test('下单超时不自动重试，后续操作可重新进入', () async {
    var shouldTimeout = true;
    final h = Harness(
      handle: (r) {
        if (r.uri.path.endsWith('transferFromWx2Card') && shouldTimeout) {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return Harness.normalResponse(r);
      },
    );
    await expectLater(h.service.createWeChatOrder(10), failsWith('勿重复支付'));
    expect(h.orders, hasLength(1));
    shouldTimeout = false;
    await h.service.createWeChatOrder(10);
    expect(h.orders, hasLength(2));
  });
  test('并发点击只创建一个订单', () async {
    final gate = Completer<void>();
    final h = Harness(
      handle: (r) async {
        if (r.method == 'GET') await gate.future;
        return Harness.normalResponse(r);
      },
    );
    final first = h.service.createWeChatOrder(10);
    await expectLater(h.service.createWeChatOrder(10), failsWith('请勿重复提交'));
    gate.complete();
    expect((await first).partnerjourno, 'order-123');
    expect(h.orders, hasLength(1));
  });
  test('连续获取余额不会返回旧的正余额缓存', () async {
    var gets = 0;
    final h = Harness(
      handle: (r) {
        if (r.method == 'GET') {
          return body(
            cardPage.replaceFirst('0.00', gets++ == 0 ? '10.00' : '20.00'),
          );
        }
        return Harness.normalResponse(r);
      },
    );
    expect((await h.service.fetchRechargeInfo()).balance, '10.00');
    expect((await h.service.fetchRechargeInfo()).balance, '20.00');
    expect(h.orders, isEmpty);
  });
}
