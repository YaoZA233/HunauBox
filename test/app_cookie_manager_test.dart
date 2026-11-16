import 'dart:io' show SameSite;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/app_constants.dart';
import 'package:smart_hunan_agri/services/app_cookie_manager.dart';
import 'package:smart_hunan_agri/services/leave_service.dart';
import 'package:smart_hunan_agri/services/questionnaire_service.dart';
import 'package:smart_hunan_agri/services/xgxt_login_service.dart';

import 'support/session_http_adapter.dart';

// Model native CookieManager URL filtering, including Path=/cas. Returning
// every browser cookie for a root URL would hide the production failure.
Future<List<webview.Cookie>> browserCookies(
  CookieJar browser,
  String url,
) async => (await browser.loadForRequest(Uri.parse(url)))
    .map(
      (cookie) => webview.Cookie(
        name: cookie.name,
        value: cookie.value,
        path: cookie.path,
        domain: cookie.domain,
        isSecure: cookie.secure,
        isHttpOnly: cookie.httpOnly,
        expiresDate: cookie.expires?.millisecondsSinceEpoch,
      ),
    )
    .toList();

void main() {
  test('指定当前系统时只导入该域，旧浏览器 Cookie 不覆盖其他业务新会话', () async {
    final browser = CookieJar();
    final jar = CookieJar();
    for (final url in [
      AppConstants.xgxtBaseUrl,
      AppConstants.sunshineBaseUrl,
      AppConstants.ssoBaseUrl,
    ]) {
      await browser.saveFromResponse(Uri.parse(url), [
        Cookie('session', 'stale')..path = '/',
      ]);
      await jar.saveFromResponse(Uri.parse(url), [
        Cookie('session', 'fresh')..path = '/',
      ]);
    }
    final visited = <String>[];
    final manager = AppCookieManager(
      cookieJar: jar,
      readWebViewCookies: (url) {
        visited.add(url);
        return browserCookies(browser, url);
      },
    );
    await manager.syncMultiDomainCookiesFromWebView(AppConstants.ssoBaseUrl);
    expect(
      visited.every((url) => Uri.parse(url).host == 'sso.hunau.edu.cn'),
      isTrue,
    );
    for (final url in [
      AppConstants.xgxtBaseUrl,
      AppConstants.sunshineBaseUrl,
    ]) {
      expect((await jar.loadForRequest(Uri.parse(url))).single.value, 'fresh');
    }
  });

  test('完整 HTTP 登录清除原门户和重复 TGC，并保留新 Cookie 原始属性', () async {
    final jar = CookieJar();
    final browser = CookieJar();
    final sso = Uri.parse(AppConstants.ssoLoginUrl);
    for (final store in [jar, browser]) {
      await store.saveFromResponse(sso, [
        Cookie('TGC', 'old-root')
          ..domain = sso.host
          ..path = '/',
        Cookie('TGC', 'old-cas')..path = '/cas/',
      ]);
      await store.saveFromResponse(Uri.parse(AppConstants.portalBaseUrl), [
        Cookie('portal', 'old')..path = '/',
      ]);
    }
    final deletes = <Cookie>[];
    final expiration = DateTime.now().toUtc().add(const Duration(hours: 2));
    final manager = AppCookieManager(
      cookieJar: jar,
      readWebViewCookies: (url) => browserCookies(browser, url),
      deleteWebViewCookie: (url, cookie) async {
        deletes.add(cookie);
        cookie.maxAge = 0;
        await browser.saveFromResponse(Uri.parse(url), [cookie]);
      },
      writeWebViewCookie: (url, cookie) =>
          browser.saveFromResponse(Uri.parse(url), [cookie]),
    );
    await manager.saveHttpLoginCookies({
      sso: [
        Cookie('TGC', 'verified')
          ..path = '/cas'
          ..secure = true
          ..httpOnly = true
          ..sameSite = SameSite.lax
          ..expires = expiration,
      ],
    });
    expect(
      deletes.where((c) => c.name == 'TGC').map((c) => c.path),
      containsAll(['/', '/cas', '/cas/']),
    );
    for (final store in [jar, browser]) {
      expect(
        await store.loadForRequest(Uri.parse(AppConstants.portalBaseUrl)),
        isEmpty,
      );
      expect(
        await store.loadForRequest(Uri.parse(AppConstants.ssoBaseUrl)),
        isEmpty,
      );
      final cookie = (await store.loadForRequest(sso)).single;
      expect(cookie.value, 'verified');
      expect(cookie.path, '/cas');
      expect(cookie.domain, isNull);
      expect(cookie.secure, isTrue);
      expect(cookie.httpOnly, isTrue);
      expect(cookie.sameSite, SameSite.lax);
      expect(
        cookie.expires?.millisecondsSinceEpoch,
        expiration.millisecondsSinceEpoch,
      );
    }
  });

  test('Android 缺少作用域时清理 host-only、Domain 和路径 TGC 阴影', () async {
    final deleted = <Cookie>[];
    final manager = AppCookieManager(
      cookieJar: CookieJar(),
      readWebViewCookies: (url) async =>
          Uri.parse(url).host == 'sso.hunau.edu.cn'
          ? [webview.Cookie(name: 'TGC', value: 'old')]
          : [],
      deleteWebViewCookie: (_, cookie) async {
        deleted.add(cookie);
      },
      writeWebViewCookie: (_, cookie) async {},
    );
    await manager.saveHttpLoginCookies({
      Uri.parse(AppConstants.ssoLoginUrl): [
        Cookie('TGC', 'fresh')..path = '/cas',
      ],
    });
    expect(deleted.length, 9);
    expect(deleted.map((c) => c.domain).toSet(), {
      null,
      'sso.hunau.edu.cn',
      '.sso.hunau.edu.cn',
    });
    expect(deleted.map((c) => c.path).toSet(), {'/', '/cas', '/cas/'});
  });
  test('域名根路径不含 TGC，CAS 路径同步后可获取它且保留作用域', () async {
    final browser = CookieJar();
    final jar = CookieJar();
    await browser.saveFromResponse(Uri.parse(AppConstants.ssoLoginUrl), [
      Cookie('TGC', 'browser-session')
        ..path = '/cas'
        ..secure = true
        ..httpOnly = true,
    ]);
    expect(
      await browser.loadForRequest(Uri.parse(AppConstants.ssoBaseUrl)),
      isEmpty,
    );
    final visited = <String>[];
    final manager = AppCookieManager(
      cookieJar: jar,
      readWebViewCookies: (url) {
        visited.add(url);
        return browserCookies(browser, url);
      },
    );
    await manager.syncMultiDomainCookiesFromWebView();
    final cookies = await jar.loadForRequest(
      Uri.parse(AppConstants.ssoLoginUrl),
    );
    expect(cookies.single.name, 'TGC');
    expect(cookies.single.path, '/cas');
    expect(cookies.single.domain, isNull);
    expect(cookies.single.secure, isTrue);
    expect(cookies.single.httpOnly, isTrue);
    expect(visited, contains('${AppConstants.ssoBaseUrl}/cas/'));
    expect(
      await jar.loadForRequest(Uri.parse(AppConstants.ssoBaseUrl)),
      isEmpty,
    );
    expect(
      await jar.loadForRequest(Uri.parse(AppConstants.xgxtCasUrl)),
      isEmpty,
    );
  });

  test('同步至 SSO 根路径时仍恢复 CAS 路径 TGC，不改成根 Cookie', () async {
    final jar = CookieJar();
    final expiration = DateTime.now().toUtc().add(const Duration(hours: 1));
    await jar.saveFromResponse(Uri.parse(AppConstants.ssoLoginUrl), [
      Cookie('TGC', 'session')
        ..path = '/cas'
        ..secure = true
        ..httpOnly = true
        ..expires = expiration,
    ]);
    final writes = <MapEntry<String, Cookie>>[];
    final manager = AppCookieManager(
      cookieJar: jar,
      writeWebViewCookie: (url, cookie) async {
        writes.add(MapEntry(url, cookie));
      },
    );
    await manager.syncMultiDomainCookiesToWebView(AppConstants.ssoBaseUrl);
    expect(writes.length, 1);
    expect(Uri.parse(writes.single.key).path, startsWith('/cas'));
    final cookie = writes.single.value;
    expect(cookie.path, '/cas');
    expect(cookie.domain, isNull);
    expect(cookie.secure, isTrue);
    expect(cookie.httpOnly, isTrue);
    expect(
      cookie.expires?.millisecondsSinceEpoch,
      expiration.millisecondsSinceEpoch,
    );
  });

  test('Android 只返回 Cookie 名和值时，TGC 仍按 CAS 路径同步', () async {
    final jar = CookieJar();
    final manager = AppCookieManager(
      cookieJar: jar,
      readWebViewCookies: (url) async => Uri.parse(url).path.startsWith('/cas')
          ? [webview.Cookie(name: 'TGC', value: 'android-session')]
          : [],
    );
    await manager.syncMultiDomainCookiesFromWebView();
    expect(
      (await jar.loadForRequest(
        Uri.parse(AppConstants.ssoLoginUrl),
      )).single.path,
      '/cas',
    );
    expect(
      await jar.loadForRequest(Uri.parse(AppConstants.ssoBaseUrl)),
      isEmpty,
    );
  });

  test('浏览器的过期 Cookie 不会被同步成无限期有效会话', () async {
    final jar = CookieJar();
    final manager = AppCookieManager(
      cookieJar: jar,
      readWebViewCookies: (url) async => Uri.parse(url).path.startsWith('/cas')
          ? [
              webview.Cookie(
                name: 'TGC',
                value: 'expired',
                path: '/cas',
                expiresDate: DateTime.now()
                    .subtract(const Duration(hours: 1))
                    .millisecondsSinceEpoch,
              ),
            ]
          : [],
    );
    await manager.syncMultiDomainCookiesFromWebView();
    expect(
      await jar.loadForRequest(Uri.parse(AppConstants.ssoLoginUrl)),
      isEmpty,
    );
  });

  test('复现仅浏览器有 Path=/cas TGC：直接进入请假/问卷自动恢复', () async {
    final browser = CookieJar();
    final jar = CookieJar();
    await browser.saveFromResponse(Uri.parse(AppConstants.ssoLoginUrl), [
      Cookie('TGC', 'browser-only')..path = '/cas',
    ]);
    final bridge = AppCookieManager(
      cookieJar: jar,
      readWebViewCookies: (url) => browserCookies(browser, url),
    );
    var renewals = 0;
    var browserLogins = 0;
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.host == 'sso.hunau.edu.cn') {
        if (!'${request.headers['cookie']}'.contains('TGC=browser-only')) {
          return sessionResponse('<html>统一认证登录</html>');
        }
        return sessionResponse(
          '',
          status: 302,
          location: '${AppConstants.xgxtCasUrl}?ticket=ST-test',
        );
      }
      if (request.uri.path == '/cas') {
        return sessionResponse(
          '',
          status: 302,
          location: AppConstants.xgxtWapUrl,
          cookies: ['JSESSIONID=authenticated; Path=/'],
        );
      }
      if (request.uri.path == '/wap/main/welcome') {
        return sessionResponse('<html>首页</html>');
      }
      return '${request.headers['cookie']}'.contains('JSESSIONID=authenticated')
          ? sessionResponse('{"aaData":[]}')
          : sessionResponse(
              '',
              status: 302,
              location: AppConstants.ssoLoginUrl,
            );
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final login = XgxtLoginService(
      dio: dio,
      cookieJar: jar,
      syncSsoCookies: bridge.syncMultiDomainCookiesFromWebView,
      refreshSso: () async {
        renewals++;
        return false;
      },
      browserLogin: () async {
        browserLogins++;
        return false;
      },
    );
    expect(
      await LeaveService(
        dio: dio,
        reauthenticate: login.performXgxtCasLogin,
      ).fetchList(),
      isEmpty,
    );
    expect(
      await QuestionnaireService(
        dio: dio,
        reauthenticate: login.performXgxtCasLogin,
      ).fetchList(),
      isEmpty,
    );
    expect(renewals, 0);
    expect(browserLogins, 0);
  });

  test('升级时清理旧根路径/Domain TGC，CAS 请求只携带新的单个 TGC', () async {
    final jar = CookieJar();
    final host = Uri.parse(AppConstants.ssoBaseUrl).host;
    await jar.saveFromResponse(Uri.parse(AppConstants.ssoLoginUrl), [
      Cookie('TGC', 'legacy-root')
        ..domain = host
        ..path = '/',
      Cookie('TGC', 'legacy-cas')
        ..domain = host
        ..path = '/cas',
    ]);
    final bridge = AppCookieManager(
      cookieJar: jar,
      readWebViewCookies: (url) async =>
          Uri.parse(url).host == host && Uri.parse(url).path.startsWith('/cas')
          ? [webview.Cookie(name: 'TGC', value: 'fresh-cas', path: '/cas')]
          : [],
    );
    await bridge.syncMultiDomainCookiesFromWebView();
    final cookies = await jar.loadForRequest(
      Uri.parse(AppConstants.ssoLoginUrl),
    );
    expect(
      cookies
          .where((cookie) => cookie.name == 'TGC')
          .map((cookie) => cookie.value),
      ['fresh-cas'],
    );
    expect(
      await jar.loadForRequest(Uri.parse(AppConstants.ssoBaseUrl)),
      isEmpty,
    );
    final adapter = SessionHttpAdapter((request) {
      return sessionResponse(
        '',
        status: 302,
        location: '${AppConstants.xgxtCasUrl}?ticket=ST-test',
      );
    });
    final dio = Dio()..httpClientAdapter = adapter;
    // An actual request through CookieManager confirms no duplicate header.
    dio.interceptors.add(CookieManager(jar));
    final response = await dio.get(
      AppConstants.ssoLoginUrl,
      options: Options(
        followRedirects: false,
        validateStatus: (status) => status == 302,
      ),
    );
    expect(response.statusCode, 302);
    expect(adapter.requests.first.headers['cookie'], 'TGC=fresh-cas');
    expect(adapter.requests.first.uri.host, host);
  });
}
