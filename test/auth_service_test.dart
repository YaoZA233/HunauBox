import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/app_constants.dart';
import 'package:smart_hunan_agri/services/app_cookie_manager.dart';
import 'package:smart_hunan_agri/services/auth_service.dart';
import 'package:smart_hunan_agri/services/http_login_service.dart';
import 'package:smart_hunan_agri/services/secure_storage_helper.dart';

import 'app_cookie_manager_test.dart' show browserCookies;

class MemoryCredentials extends SecureStorageHelper {
  String? username = 'synthetic-student', password = 'synthetic-password';
  int writes = 0;
  @override
  Future<String?> getUsername() async => username;
  @override
  Future<String?> getPassword() async => password;
  @override
  Future<void> saveUsername(String value) async {
    writes++;
    username = value;
  }

  @override
  Future<void> savePassword(String value) async {
    writes++;
    password = value;
  }

  @override
  Future<void> clearAll() async {
    username = null;
    password = null;
  }
}

class FakeHttpLogin extends HttpLoginService {
  FakeHttpLogin(this.handler);
  final Future<HttpLoginResult> Function() handler;
  int calls = 0;
  @override
  Future<HttpLoginResult> login(String username, String password) async {
    calls++;
    return handler();
  }
}

HttpLoginResult freshResult() => HttpLoginResult(
  cookies: {
    Uri.parse(AppConstants.ssoLoginUrl): [
      Cookie('TGC', 'fresh')
        ..path = '/cas'
        ..secure = true
        ..httpOnly = true,
    ],
    Uri.parse(AppConstants.portalBaseUrl): [
      Cookie('PORTAL_SESSION', 'fresh')..path = '/',
    ],
  },
);

void main() {
  tearDown(AuthService.cancelPendingLogins);

  test('门户有效但 TGC 过期，静默登录仍执行完整 HTTP 认证并发布新会话', () async {
    final jar = CookieJar(), browser = CookieJar();
    for (final store in [jar, browser]) {
      await store.saveFromResponse(Uri.parse(AppConstants.portalBaseUrl), [
        Cookie('PORTAL_SESSION', 'still-valid')..path = '/',
      ]);
      await store.saveFromResponse(Uri.parse(AppConstants.ssoBaseUrl), [
        Cookie('TGC', 'stale')..path = '/',
      ]);
    }
    final cookies = AppCookieManager(
      cookieJar: jar,
      readWebViewCookies: (url) => browserCookies(browser, url),
      deleteWebViewCookie: (url, cookie) async {
        cookie.maxAge = 0;
        await browser.saveFromResponse(Uri.parse(url), [cookie]);
      },
      writeWebViewCookie: (url, cookie) =>
          browser.saveFromResponse(Uri.parse(url), [cookie]),
    );
    final http = FakeHttpLogin(() async => freshResult());
    final storage = MemoryCredentials();
    final auth = AuthService(
      httpLoginService: http,
      storage: storage,
      cookies: cookies,
    );
    expect(await auth.silentLogin(), isTrue);
    expect(http.calls, 1);
    expect(storage.writes, 2);
    for (final store in [jar, browser]) {
      final values = await store.loadForRequest(
        Uri.parse(AppConstants.ssoLoginUrl),
      );
      expect(values.map((c) => c.value), ['fresh']);
      expect(values.single.path, '/cas');
      expect(
        (await store.loadForRequest(
          Uri.parse(AppConstants.portalBaseUrl),
        )).single.value,
        'fresh',
      );
    }
  });

  test('各服务并发静默续登共用一次 HTTP 登录', () async {
    final gate = Completer<HttpLoginResult>();
    final http = FakeHttpLogin(() => gate.future);
    final cookies = AppCookieManager(
      cookieJar: CookieJar(),
      readWebViewCookies: (_) async => [],
      writeWebViewCookie: (_, cookie) async {},
    );
    final storage = MemoryCredentials();
    final results = Future.wait(
      List.generate(
        3,
        (_) => AuthService(
          httpLoginService: http,
          storage: storage,
          cookies: cookies,
        ).silentLogin(),
      ),
    );
    while (http.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    gate.complete(freshResult());
    expect(await results, [true, true, true]);
    expect(http.calls, 1);
    expect(storage.writes, 2);
  });

  test('退出期间网络续登晚到，不能发布 Cookie 或写回凭据', () async {
    final gate = Completer<HttpLoginResult>();
    final http = FakeHttpLogin(() => gate.future);
    final storage = MemoryCredentials();
    var publications = 0;
    final jar = CookieJar();
    final cookies = AppCookieManager(
      cookieJar: jar,
      readWebViewCookies: (_) async => [],
      writeWebViewCookie: (_, cookie) async {
        publications++;
      },
    );
    final result = AuthService(
      httpLoginService: http,
      storage: storage,
      cookies: cookies,
    ).silentLogin();
    while (http.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final logout = AuthService.cancelPendingLogins();
    gate.complete(freshResult());
    await logout;
    await storage.clearAll();
    expect(await result, isFalse);
    expect(publications, 0);
    expect(storage.writes, 0);
    expect(storage.username, isNull);
    expect(
      await jar.loadForRequest(Uri.parse(AppConstants.ssoLoginUrl)),
      isEmpty,
    );
  });

  test('退出等候进行中的 Cookie 发布，清理后不会恢复旧账号', () async {
    final publishing = Completer<void>(), release = Completer<void>();
    final jar = CookieJar();
    final storage = MemoryCredentials();
    var logoutFinished = false;
    final cookies = AppCookieManager(
      cookieJar: jar,
      readWebViewCookies: (_) async => [],
      writeWebViewCookie: (_, cookie) async {
        if (!publishing.isCompleted) publishing.complete();
        await release.future;
      },
    );
    final result = AuthService(
      httpLoginService: FakeHttpLogin(() async => freshResult()),
      storage: storage,
      cookies: cookies,
    ).silentLogin();
    await publishing.future;
    final logout = AuthService.cancelPendingLogins().then((_) {
      logoutFinished = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(logoutFinished, isFalse);
    release.complete();
    await logout;
    await jar.deleteAll();
    await storage.clearAll();
    expect(await result, isFalse);
    expect(storage.writes, 0);
    expect(storage.username, isNull);
    expect(
      await jar.loadForRequest(Uri.parse(AppConstants.ssoLoginUrl)),
      isEmpty,
    );
  });

  test('缺少凭据不执行 HTTP 登录', () async {
    final storage = MemoryCredentials()..username = null;
    final http = FakeHttpLogin(() async => freshResult());
    expect(
      await AuthService(httpLoginService: http, storage: storage).silentLogin(),
      isFalse,
    );
    expect(http.calls, 0);
  });
}
