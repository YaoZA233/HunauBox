import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/app_constants.dart';
import 'package:smart_hunan_agri/models/sunshine_models.dart';
import 'package:smart_hunan_agri/services/sunshine_service.dart';
import 'package:smart_hunan_agri/services/session_cookie_manager.dart';

import 'support/session_http_adapter.dart';

const identityHtml =
    '<input id="h_CardCode" value="student">'
    '<input id="UserName" value="测试学生">'
    '<input id="telPhone" value="123"><input id="email" value="a@test">';
const identity = SunshineIdentity('student', '测试学生', '123', 'a@test');
const department = SunshineDepartment('001', '测试单位');

class SunshineFixture {
  SunshineFixture({this.validSso = false, this.validSunshine = false}) {
    adapter = SessionHttpAdapter(handle);
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(SessionCookieManager(jar));
    service = SunshineService(
      dio: dio,
      reauthenticate: () async {
        renewals++;
        validSso = renewalSucceeds;
        return renewalSucceeds;
      },
    );
  }
  final jar = CookieJar();
  late final SessionHttpAdapter adapter;
  late final SunshineService service;
  bool validSso, validSunshine;
  bool renewalSucceeds = true;
  int renewals = 0, callbacks = 0, writes = 0;
  int expireReads = 0;
  String submitResult = '1';
  String formHtml = identityHtml;
  Completer<void>? authorizeGate;
  FutureOr<ResponseBody> handle(RequestOptions request) async {
    expect(request.followRedirects, isFalse);
    expect(request.persistentConnection, isFalse);
    if (request.uri.host == 'sso.hunau.edu.cn') {
      expect(request.headers.containsKey('X-Requested-With'), isFalse);
      await authorizeGate?.future;
      return validSso
          ? sessionResponse(
              '',
              status: 302,
              location:
                  'http://sun.hunau.edu.cn/OAuthLogin.aspx?code=test-code',
            )
          : sessionResponse('<html>统一认证登录</html>');
    }
    if (request.uri.path == '/OAuthLogin.aspx') {
      expect(request.uri.scheme, 'https');
      expect(request.uri.queryParameters['code'], 'test-code');
      callbacks++;
      validSunshine = true;
      return sessionResponse(
        '',
        status: 302,
        location: '/index.aspx',
        cookies: ['ASP.NET_SessionId=fresh; Path=/; HttpOnly; Secure'],
      );
    }
    if (request.uri.path == '/index.aspx') {
      expect(request.headers['cookie'], contains('ASP.NET_SessionId=fresh'));
      return sessionResponse('<html>阳光服务</html>');
    }
    if (request.uri.path == '/form.aspx') {
      return sessionResponse(validSunshine ? formHtml : '<html>登录</html>');
    }
    if (request.uri.queryParameters['AFlag'] == 'insert') {
      writes++;
      return sessionResponse(submitResult);
    }
    if (expireReads > 0) {
      expireReads--;
      validSunshine = false;
      return sessionResponse('', status: 302, location: '/OAuthLogin.aspx');
    }
    if (!validSunshine) return sessionResponse('<html>登录</html>');
    final flag =
        request.uri.queryParameters['AFlag'] ?? (request.data as Map)['AFlag'];
    return sessionResponse(switch (flag) {
      'Statistics' => '{"TCount":3,"ZCount":2,"YCount":1}',
      'LoadCompany' =>
        '{"rows":[{"Company_code":"001","Company_name":"测试单位"}]}',
      'Detail' =>
        '{"rows":[{"Title":"测试诉求","Content":"<html>用户填写的内容</html> cas/login"}]}',
      _ => '{"rows":[{"ID":"42","Title":"测试诉求"}]}',
    });
  }
}

Future<Object> readFeature(SunshineService service, String feature) async =>
    switch (feature) {
      '统计' => await service.fetchStatistics(),
      '列表' => await service.fetchLetters(),
      '详情' => await service.fetchTicketDetail('42'),
      _ => await service.fetchForm(),
    };

Future<String> submit(
  SunshineService service, {
  SunshineIdentity account = identity,
}) => service.submit(
  identity: account,
  department: department,
  type: '2',
  title: '标题',
  content: '内容',
  phone: '123',
  email: '',
  finishTime: '',
);

void main() {
  test('阳光服务重新授权不清除学工和 SSO 共用的父域会话', () async {
    final f = SunshineFixture(validSso: true);
    await f.jar.saveFromResponse(Uri.parse(AppConstants.ssoBaseUrl), [
      Cookie('SHARED', 'keep')
        ..domain = '.hunau.edu.cn'
        ..path = '/',
    ]);
    await f.jar.saveFromResponse(Uri.parse(AppConstants.xgxtBaseUrl), [
      Cookie('JSESSIONID', 'keep-xgxt')..path = '/',
    ]);
    expect(await f.service.fetchLetters(), hasLength(1));
    final cookies = await f.jar.loadForRequest(
      Uri.parse(AppConstants.xgxtWapUrl),
    );
    expect(cookies.map((c) => c.value), containsAll(['keep', 'keep-xgxt']));
    expect(f.renewals, 0);
  });

  for (final feature in ['统计', '列表', '详情', '表单']) {
    test('$feature 在阳光服务和 SSO 同时过期时完整续登', () async {
      final fixture = SunshineFixture();
      await readFeature(fixture.service, feature);
      expect(fixture.renewals, 1);
      expect(fixture.callbacks, 1);
      expect(fixture.writes, 0);
    });
    test('$feature 在请求中途失效时恢复并重试读取一次', () async {
      final fixture = SunshineFixture(validSso: true, validSunshine: true)
        ..expireReads = 1;
      await readFeature(fixture.service, feature);
      expect(fixture.callbacks, 1);
      expect(fixture.renewals, 0);
    });
  }
  test('复用有效 SSO，HTTPS OAuth 逐跳保留中间 ASP Cookie', () async {
    final fixture = SunshineFixture(validSso: true);
    await fixture.jar
        .saveFromResponse(Uri.parse(AppConstants.sunshineBaseUrl), [
          Cookie('ASP.NET_SessionId', 'legacy-domain')
            ..domain = 'sun.hunau.edu.cn'
            ..path = '/',
        ]);
    expect((await fixture.service.fetchLetters()).single.title, '测试诉求');
    expect(fixture.callbacks, 1);
    expect(fixture.renewals, 0);
    final cookie = (await fixture.jar.loadForRequest(
      Uri.parse(AppConstants.sunshineBaseUrl),
    )).single;
    expect(cookie.name, 'ASP.NET_SessionId');
    expect(cookie.httpOnly, isTrue);
    expect(cookie.secure, isTrue);
  });
  test('有效会话不重新认证，JSON 内用户 HTML 不被误认为登录页', () async {
    final fixture = SunshineFixture(validSunshine: true);
    expect(
      (await fixture.service.fetchTicketDetail('42')).content,
      contains('<html>'),
    );
    expect(fixture.callbacks, 0);
    expect(fixture.renewals, 0);
  });
  test('并发统计和列表共用一次续登，恢复后继续各自请求', () async {
    final fixture = SunshineFixture(validSso: true);
    final gate = fixture.authorizeGate = Completer<void>();
    final reads = Future.wait([
      fixture.service.fetchStatistics(),
      fixture.service.fetchLetters(),
    ]);
    while (fixture.adapter.requests.every(
      (r) => r.uri.host != 'sso.hunau.edu.cn',
    )) {
      await Future<void>.delayed(Duration.zero);
    }
    gate.complete();
    await reads;
    expect(fixture.callbacks, 1);
    expect(fixture.renewals, 0);
    expect(identical(SunshineService(), SunshineService()), isTrue);
  });
  test('浏览器独有的有效 SSO 先导入，无需重复密码登录', () async {
    final fixture = SunshineFixture();
    var imports = 0;
    final dio = Dio()..httpClientAdapter = fixture.adapter;
    dio.interceptors.add(SessionCookieManager(fixture.jar));
    final service = SunshineService(
      dio: dio,
      syncSsoCookies: () async {
        imports++;
        fixture.validSso = true;
      },
      reauthenticate: () async => throw StateError('不应密码登录'),
    );
    await service.fetchLetters();
    expect(imports, 1);
    expect(fixture.callbacks, 1);
  });
  test('统一认证失败有界退出，下次读取仍能重试', () async {
    final fixture = SunshineFixture()..renewalSucceeds = false;
    await expectLater(
      fixture.service.fetchLetters(),
      throwsA(isA<SunshineException>()),
    );
    expect(fixture.renewals, 1);
    fixture.renewalSucceeds = true;
    await fixture.service.fetchLetters();
    expect(fixture.renewals, 2);
  });
  test('接口持续失效只重试一次，不返回匿名空列表', () async {
    final fixture = SunshineFixture(validSso: true, validSunshine: true)
      ..expireReads = 2;
    await expectLater(
      fixture.service.fetchLetters(),
      throwsA(isA<SunshineException>()),
    );
    expect(
      fixture.adapter.requests
          .where((r) => r.uri.path.endsWith('index.ashx'))
          .length,
      2,
    );
    expect(fixture.callbacks, 1);
  });
  test('身份探测超时有一次读取重试，不触发密码登录', () async {
    var renewals = 0;
    final adapter = SessionHttpAdapter(
      (r) => throw DioException(
        requestOptions: r,
        type: DioExceptionType.receiveTimeout,
      ),
    );
    final service = SunshineService(
      dio: Dio()..httpClientAdapter = adapter,
      reauthenticate: () async {
        renewals++;
        return true;
      },
    );
    await expectLater(
      service.fetchLetters(),
      throwsA(
        isA<SunshineException>().having(
          (e) => e.message,
          'message',
          contains('超时'),
        ),
      ),
    );
    expect(adapter.requests.length, 2);
    expect(renewals, 0);
  });
  test('GB2312 页面中文正确解码', () async {
    final adapter = SessionHttpAdapter(
      (r) => r.uri.path == '/form.aspx'
          ? ResponseBody.fromBytes(
              gbk.encode(identityHtml),
              200,
              headers: {
                'content-type': ['text/html; charset=gb2312'],
              },
            )
          : sessionResponse(
              '{"rows":[{"Company_code":"001","Company_name":"测试单位"}]}',
            ),
    );
    final service = SunshineService(dio: Dio()..httpClientAdapter = adapter);
    expect((await service.fetchForm()).identity.name, '测试学生');
  });
  test('提交前恢复身份，只发送一次诉求 POST', () async {
    final fixture = SunshineFixture();
    expect(await submit(fixture.service), '1');
    expect(fixture.writes, 1);
    expect(fixture.renewals, 1);
  });
  for (final result in ['1', '2', 'errer', 'unexpected', '<html>登录</html>']) {
    test('提交返回 $result 保留结果且不重复发送', () async {
      final fixture = SunshineFixture(validSunshine: true)
        ..submitResult = result;
      expect(
        await submit(fixture.service),
        ['1', '2', 'errer'].contains(result) ? result : 'unknown',
      );
      expect(fixture.writes, 1);
      expect(fixture.renewals, 0);
    });
  }
  test('账号变化阻止沿用旧表单提交', () async {
    final fixture = SunshineFixture(validSunshine: true);
    await expectLater(
      submit(
        fixture.service,
        account: const SunshineIdentity('other', '其他人', '', ''),
      ),
      throwsA(isA<SunshineException>()),
    );
    expect(fixture.writes, 0);
  });
  test('提交 POST 超时返回待核对状态，不刷新或重发', () async {
    var writes = 0;
    final adapter = SessionHttpAdapter((r) {
      if (r.uri.path == '/form.aspx') return sessionResponse(identityHtml);
      writes++;
      throw DioException(
        requestOptions: r,
        type: DioExceptionType.receiveTimeout,
      );
    });
    final service = SunshineService(
      dio: Dio()..httpClientAdapter = adapter,
      reauthenticate: () async => throw StateError('不应刷新'),
    );
    expect(await submit(service), 'unknown');
    expect(writes, 1);
  });
  for (final location in [
    'https://example.org/?code=secret',
    'http://sso.hunau.edu.cn/cas/login',
    AppConstants.sunshineAuthorizationUrl,
  ]) {
    test('拒绝外域、降级和循环 OAuth 跳转：$location', () async {
      final adapter = SessionHttpAdapter(
        (r) => r.uri.path == '/form.aspx'
            ? sessionResponse('<html>登录</html>')
            : sessionResponse('', status: 302, location: location),
      );
      final service = SunshineService(dio: Dio()..httpClientAdapter = adapter);
      await expectLater(
        service.fetchLetters(),
        throwsA(isA<SunshineException>()),
      );
      expect(adapter.requests.length, lessThanOrEqualTo(2));
    });
  }
}
