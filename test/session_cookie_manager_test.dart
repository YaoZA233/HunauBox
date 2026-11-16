import 'package:cookie_jar/cookie_jar.dart';
import 'dart:io' show Directory;
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/services/session_cookie_manager.dart';

import 'support/session_http_adapter.dart';

void main() {
  test('业务 Cookie 清理结果持久化后仍保留父域与 SSO，不复活旧会话', () async {
    final directory = await Directory.systemTemp.createTemp(
      'xgxt-cookie-scope-',
    );
    addTearDown(() => directory.delete(recursive: true));
    PersistCookieJar open() =>
        PersistCookieJar(storage: FileStorage(directory.path));
    final jar = open();
    final origin = Uri.parse('https://xgxt.hunau.edu.cn/');
    await jar.saveFromResponse(origin, [
      Cookie('SHARED', 'keep')
        ..domain = '.hunau.edu.cn'
        ..path = '/',
      Cookie('JSESSIONID', 'old')..path = '/',
      Cookie('JSESSIONID', 'shadow')
        ..domain = 'xgxt.hunau.edu.cn'
        ..path = '/',
    ]);
    await SessionCookieManager.clearHostCookies(jar, [origin]);
    final reopened = open();
    final cookies = await reopened.loadForRequest(origin);
    expect(cookies.map((cookie) => cookie.name), ['SHARED']);
    expect(
      (await reopened.loadForRequest(
        Uri.parse('https://sso.hunau.edu.cn/cas/login'),
      )).single.value,
      'keep',
    );
  });

  for (final host in ['xgxt.hunau.edu.cn', 'sun.hunau.edu.cn']) {
    test('重登 $host 只清理本站 Cookie，保留父域、统一认证和其他业务会话', () async {
      final jar = CookieJar();
      final origin = Uri.https(host, '/');
      final content = Uri.https(host, '/content/tabledata/session');
      await jar.saveFromResponse(origin, [
        Cookie('COMMON_SSO', 'shared')
          ..domain = '.hunau.edu.cn'
          ..path = '/',
        Cookie('host', 'old')..path = '/',
        Cookie('domain', 'old')
          ..domain = host
          ..path = '/',
        Cookie('path', 'old')
          ..domain = '.$host'
          ..path = '/content',
        Cookie('hidden', 'old')..path = '/other/path',
      ]);
      final sso = Uri.https('sso.hunau.edu.cn', '/cas/login');
      final sibling = Uri.https(
        host.startsWith('sun') ? 'xgxt.hunau.edu.cn' : 'sun.hunau.edu.cn',
        '/',
      );
      await jar.saveFromResponse(sso, [
        Cookie('TGC', 'keep-sso')..path = '/cas',
      ]);
      await jar.saveFromResponse(sibling, [
        Cookie('sibling', 'keep-sibling')..path = '/',
      ]);
      await SessionCookieManager.clearHostCookies(jar, [origin, content]);
      for (final uri in [origin, content, Uri.https(host, '/other/path')]) {
        expect((await jar.loadForRequest(uri)).map((c) => c.name), [
          'COMMON_SSO',
        ]);
      }
      expect(
        (await jar.loadForRequest(sso)).map((c) => c.value),
        containsAll(['keep-sso', 'shared']),
      );
      expect(
        (await jar.loadForRequest(sibling)).map((c) => c.value),
        containsAll(['keep-sibling', 'shared']),
      );
    });
  }

  for (final destination in ['xgxt.hunau.edu.cn', 'sun.hunau.edu.cn']) {
    test('SSO 重定向至 $destination 时仅保存响应域 Cookie', () async {
      final jar = CookieJar();
      final adapter = SessionHttpAdapter(
        (r) => r.uri.host == 'sso.hunau.edu.cn'
            ? sessionResponse(
                '',
                status: 302,
                location: 'https://$destination/cas?ticket=ST-test',
                cookies: ['SSO_SESSION=private; Path=/; HttpOnly; Secure'],
              )
            : sessionResponse('服务页'),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      // Installation removes the unsafe upstream interceptor, including when
      // a client was prepared by another feature before the auth flow.
      dio.interceptors.add(CookieManager(jar));
      SessionCookieManager.install(dio, jar);
      final options = Options(
        followRedirects: false,
        validateStatus: (_) => true,
      );
      final response = await dio.get(
        'https://sso.hunau.edu.cn/cas/login',
        options: options,
      );
      await dio.get(response.headers.value('location')!, options: options);
      expect(dio.interceptors.whereType<CookieManager>().length, 1);
      expect(
        (await jar.loadForRequest(
          Uri.parse('https://sso.hunau.edu.cn/'),
        )).single.value,
        'private',
      );
      expect(
        await jar.loadForRequest(Uri.parse('https://$destination/')),
        isEmpty,
      );
      expect(
        '${adapter.requests.last.headers['cookie']}',
        isNot(contains('SSO_SESSION')),
      );
    });
  }

  test('同域中间重定向保存 Cookie，缺省 Path 按响应路径计算', () async {
    final jar = CookieJar();
    final adapter = SessionHttpAdapter(
      (r) => sessionResponse(
        '',
        status: 302,
        location: '/cas/next',
        cookies: [
          'TGC=test; HttpOnly; Secure',
          'sid=stage; Path=/; SameSite=Lax',
        ],
      ),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(SessionCookieManager(jar));
    await dio.get(
      'https://sso.hunau.edu.cn/cas/login',
      options: Options(followRedirects: false, validateStatus: (_) => true),
    );
    final root = await jar.loadForRequest(
      Uri.parse('https://sso.hunau.edu.cn/'),
    );
    expect(root.map((c) => c.name), ['sid']);
    final cas = await jar.loadForRequest(
      Uri.parse('https://sso.hunau.edu.cn/cas/next'),
    );
    expect(cas.firstWhere((c) => c.name == 'TGC').path, '/cas');
    expect(cas.firstWhere((c) => c.name == 'TGC').httpOnly, isTrue);
    await dio.get(
      'http://sso.hunau.edu.cn/cas/next',
      options: Options(followRedirects: false, validateStatus: (_) => true),
    );
    expect(
      '${adapter.requests.last.headers['cookie']}',
      isNot(contains('TGC=test')),
    );
  });
}
