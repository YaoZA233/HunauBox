import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/app_constants.dart';
import 'package:smart_hunan_agri/services/app_cookie_manager.dart';
import 'package:smart_hunan_agri/services/leave_service.dart';
import 'package:smart_hunan_agri/services/questionnaire_service.dart';
import 'package:smart_hunan_agri/services/xgxt_login_service.dart';

import 'support/session_http_adapter.dart';

ResponseBody ticketResponse({int status = 302}) => sessionResponse(
  '',
  status: status,
  location: '${AppConstants.xgxtCasUrl}?ticket=ST-test',
);

void main() {
  test('请假 JSON 内的登录说明不会触发会话重建', () async {
    final adapter = SessionHttpAdapter(
      (request) => sessionResponse(
        '{"aaData":[{"id":"1","reason":"<html>cas/login 使用说明"}]}',
      ),
    );
    final records = await LeaveService(
      dio: Dio()..httpClientAdapter = adapter,
      reauthenticate: () async => throw StateError('有效 JSON 不应重登'),
    ).fetchList();
    expect(records, hasLength(1));
    expect(adapter.requests, hasLength(1));
  });

  test('问卷和请假保留学工维护错误，不把服务故障改成密码失效', () async {
    final adapter = SessionHttpAdapter(
      (request) =>
          sessionResponse('', status: 302, location: AppConstants.ssoLoginUrl),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    Future<bool> unavailable() async =>
        throw const XgxtSessionException('学工服务正在维护');
    await expectLater(
      QuestionnaireService(dio: dio, reauthenticate: unavailable).fetchList(),
      throwsA(
        isA<QuestionnaireException>().having(
          (e) => e.message,
          'message',
          '学工服务正在维护',
        ),
      ),
    );
    await expectLater(
      LeaveService(dio: dio, reauthenticate: unavailable).fetchList(),
      throwsA(
        isA<LeaveException>().having((e) => e.message, 'message', '学工服务正在维护'),
      ),
    );
    expect(adapter.requests, hasLength(2));
  });

  test('CAS 允许服务器返回的 jsessionid 路径参数并继续逐跳校验', () async {
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.host == 'sso.hunau.edu.cn') {
        return sessionResponse(
          '',
          status: 302,
          location: '${AppConstants.xgxtCasUrl};jsessionid=test?ticket=ST-test',
        );
      }
      if (request.uri.path.startsWith('/cas')) {
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
      return sessionResponse('{"aaData":[]}');
    });
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
    );
    expect(await login.performXgxtCasLogin(), isTrue);
    expect(adapter.requests[1].uri.path, '/cas;jsessionid=test');
  });

  test('问卷中的认证相关文本和 HTML 不会误判为登录页', () async {
    final adapter = SessionHttpAdapter(
      (request) =>
          sessionResponse('{"aaData":[{"MC":"<html>cas/login 使用说明"}]}'),
    );
    expect(
      await XgxtLoginService(
        dio: Dio()..httpClientAdapter = adapter,
        cookieJar: CookieJar(),
      ).ensureSession(),
      isTrue,
    );
    expect(adapter.requests, hasLength(1));
  });

  test('会话检查使用完整 DataTables 参数，不因缺少排序参数得到服务器错误', () async {
    final adapter = SessionHttpAdapter((request) {
      expect(request.uri.queryParameters, containsPair('iSortingCols', '1'));
      expect(request.uri.queryParameters, containsPair('iSortCol_0', '3'));
      expect(request.uri.queryParameters, containsPair('sSortDir_0', 'desc'));
      expect(request.uri.queryParameters, containsPair('bSortable_0', 'false'));
      expect(request.headers['X-Requested-With'], 'XMLHttpRequest');
      expect(request.headers['Cache-Control'], 'no-cache');
      return sessionResponse('{"aaData":[]}');
    });
    expect(
      await XgxtLoginService(
        dio: Dio()..httpClientAdapter = adapter,
        cookieJar: CookieJar(),
      ).ensureSession(),
      isTrue,
    );
    expect(adapter.requests, hasLength(1));
  });

  for (final failure in ['500', '403', 'HTML', 'timeout']) {
    test('问卷接口 $failure 时仍可验证学工会话，不强制重登', () async {
      final adapter = SessionHttpAdapter((request) {
        if (request.uri.path.contains('xs_wjdc')) {
          return switch (failure) {
            '500' => sessionResponse('服务器错误', status: 500),
            '403' => sessionResponse('无问卷权限', status: 403),
            'timeout' => throw DioException(
              requestOptions: request,
              type: DioExceptionType.receiveTimeout,
            ),
            _ => sessionResponse('<html>服务维护</html>'),
          };
        }
        expect(request.uri.toString(), startsWith(AppConstants.leaveListUrl));
        return sessionResponse('{"aaData":[]}');
      });
      final login = XgxtLoginService(
        dio: Dio()..httpClientAdapter = adapter,
        cookieJar: CookieJar(),
        refreshSso: () async => throw StateError('不应重登'),
      );
      expect(await login.ensureSession(), isTrue);
      expect(adapter.requests, hasLength(2));
    });
  }

  test('业务服务均维护时保留会话并报告服务故障，不反复清 Cookie 或重登', () async {
    final jar = CookieJar();
    await jar.saveFromResponse(Uri.parse(AppConstants.xgxtBaseUrl), [
      Cookie('JSESSIONID', 'keep')..path = '/',
    ]);
    final adapter = SessionHttpAdapter(
      (request) => sessionResponse('维护', status: 503),
    );
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: jar,
      refreshSso: () async => throw StateError('服务器故障不应重登'),
    );
    await expectLater(
      login.ensureSession(),
      throwsA(isA<XgxtSessionException>()),
    );
    expect(adapter.requests, hasLength(2));
    expect(
      (await jar.loadForRequest(
        Uri.parse(AppConstants.xgxtBaseUrl),
      )).single.value,
      'keep',
    );
  });

  test('打开主页与原生功能并发恢复时会话检查和发布也只执行一次', () async {
    final gate = Completer<void>();
    var publications = 0;
    final adapter = SessionHttpAdapter((request) async {
      await gate.future;
      return sessionResponse('{"aaData":[]}');
    });
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
      publishSession: () async {
        publications++;
      },
    );
    final home = login.ensureSession();
    final native = login.performXgxtCasLogin();
    final repeatedHome = login.ensureSession();
    gate.complete();
    expect(await Future.wait([home, native, repeatedHome]), [true, true, true]);
    expect(adapter.requests, hasLength(1));
    expect(publications, 1);
  });

  test('交换学工票据不会删除统一认证和阳光服务共用的父域 Cookie', () async {
    final jar = CookieJar();
    await jar.saveFromResponse(Uri.parse(AppConstants.ssoBaseUrl), [
      Cookie('SHARED', 'keep')
        ..domain = '.hunau.edu.cn'
        ..path = '/',
    ]);
    final adapter = SessionHttpAdapter((request) {
      expect(request.headers['cookie'], contains('SHARED=keep'));
      if (request.uri.host == 'sso.hunau.edu.cn') return ticketResponse();
      if (request.uri.path == '/cas') {
        return sessionResponse('首页', cookies: ['JSESSIONID=fresh; Path=/']);
      }
      return sessionResponse('{"aaData":[]}');
    });
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: jar,
    );
    expect(await login.performXgxtCasLogin(), isTrue);
    expect(
      (await jar.loadForRequest(
        Uri.parse(AppConstants.sunshineBaseUrl),
      )).single.value,
      'keep',
    );
  });

  test('Cookie发布失败不会把浏览器准备状态报告为成功', () async {
    final jar = CookieJar();
    await jar.saveFromResponse(Uri.parse(AppConstants.xgxtWapUrl), [
      Cookie('JSESSIONID', 'fresh')..path = '/',
    ]);
    final bridge = AppCookieManager(
      cookieJar: jar,
      readWebViewCookies: (url) async => [],
      writeWebViewCookie: (url, cookie) async => throw StateError('浏览器写入失败'),
    );
    final adapter = SessionHttpAdapter(
      (request) => sessionResponse('{"aaData":[]}'),
    );
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: jar,
      publishSession: () =>
          bridge.replaceWebViewSession(XgxtLoginService.browserSessionUrls),
    );
    await expectLater(
      login.ensureSession(),
      throwsA(isA<XgxtSessionException>()),
    );
  });

  test('首次打开复用有效会话，等待全部路径Cookie发布完成才返回', () async {
    final jar = CookieJar();
    final browser = CookieJar();
    await jar.saveFromResponse(Uri.parse(AppConstants.xgxtWapUrl), [
      Cookie('WAP_SESSION', 'wap')..path = '/wap',
    ]);
    await jar.saveFromResponse(Uri.parse(AppConstants.leaveApplyUrl), [
      Cookie('LEAVE_SESSION', 'leave')..path = '/content/student/leave',
    ]);
    final bridge = AppCookieManager(
      cookieJar: jar,
      writeWebViewCookie: (url, cookie) =>
          browser.saveFromResponse(Uri.parse(url), [cookie]),
      readWebViewCookies: (url) async => [],
      deleteWebViewCookie: (url, cookie) async {},
    );
    var publications = 0;
    final adapter = SessionHttpAdapter(
      (request) => sessionResponse('{"aaData":[]}'),
    );
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: jar,
      refreshSso: () async => throw StateError('有效会话不应重复登录'),
      publishSession: () async {
        await bridge.replaceWebViewSession(XgxtLoginService.browserSessionUrls);
        publications++;
      },
    );
    expect(await login.ensureSession(), isTrue);
    expect(publications, 1);
    expect(adapter.requests.length, 1);
    expect(
      (await browser.loadForRequest(
        Uri.parse(AppConstants.xgxtWapUrl),
      )).any((c) => c.name == 'WAP_SESSION'),
      isTrue,
    );
    expect(
      (await browser.loadForRequest(
        Uri.parse(AppConstants.leaveApplyUrl),
      )).any((c) => c.name == 'LEAVE_SESSION'),
      isTrue,
    );
  });

  test('首次检查失效时自动完成CAS，主页无需手动刷新', () async {
    var loggedIn = false, publications = 0;
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.host == 'sso.hunau.edu.cn') return ticketResponse();
      if (request.uri.path == '/cas') {
        loggedIn = true;
        return sessionResponse('首页', cookies: ['JSESSIONID=fresh; Path=/']);
      }
      return loggedIn
          ? sessionResponse('{"aaData":[]}')
          : sessionResponse(
              '',
              status: 302,
              location: AppConstants.ssoLoginUrl,
            );
    });
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
      publishSession: () async {
        publications++;
      },
    );
    expect(await login.ensureSession(), isTrue);
    expect(publications, 1);
    expect(loggedIn, isTrue);
  });

  test('验证业务接口后把新 HTTP 学工会话回写浏览器', () async {
    final jar = CookieJar();
    await jar.saveFromResponse(Uri.parse(AppConstants.xgxtWapUrl), [
      Cookie('JSESSIONID', 'legacy-domain')
        ..domain = 'xgxt.hunau.edu.cn'
        ..path = '/',
    ]);
    final browser = CookieJar();
    await browser.saveFromResponse(Uri.parse(AppConstants.xgxtWapUrl), [
      Cookie('JSESSIONID', 'stale')..path = '/',
    ]);
    final bridge = AppCookieManager(
      cookieJar: jar,
      writeWebViewCookie: (url, cookie) =>
          browser.saveFromResponse(Uri.parse(url), [cookie]),
    );
    final adapter = SessionHttpAdapter(
      (request) => request.uri.host == 'sso.hunau.edu.cn'
          ? sessionResponse(
              '',
              status: 302,
              location: 'http://xgxt.hunau.edu.cn/cas?ticket=ST-test',
            )
          : sessionResponse(
              request.uri.path.startsWith('/content/') ? '{"aaData":[]}' : '首页',
              cookies: ['JSESSIONID=fresh; Path=/; Secure; HttpOnly'],
            ),
    );
    var publications = 0;
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: jar,
      publishSession: () async {
        publications++;
        await bridge.syncMultiDomainCookiesToWebView(AppConstants.xgxtWapUrl);
      },
    );
    expect(await login.performXgxtCasLogin(), isTrue);
    expect(publications, 1);
    expect(adapter.requests.every((r) => r.uri.scheme == 'https'), isTrue);
    expect(adapter.requests.last.headers['cookie'], 'JSESSIONID=fresh');
    expect(
      (await browser.loadForRequest(
        Uri.parse(AppConstants.xgxtWapUrl),
      )).single.value,
      'fresh',
    );
  });

  test('学工 ticket 后跳转外域不会发送 Cookie 或误判登录', () async {
    final adapter = SessionHttpAdapter(
      (r) => r.uri.host == 'sso.hunau.edu.cn'
          ? ticketResponse()
          : sessionResponse(
              '',
              status: 302,
              location: 'https://example.org/?ticket=ST-test',
            ),
    );
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
      refreshSso: () async => false,
      browserLogin: () async => false,
    );
    expect(await login.performXgxtCasLogin(), isFalse);
    expect(adapter.requests.every((r) => r.uri.host != 'example.org'), isTrue);
  });
  test('每跳保存/发送 Cookie，轮换后的会话同时供请假和问卷使用', () async {
    final jar = CookieJar();
    var imported = 0;
    var renewed = 0;
    final adapter = SessionHttpAdapter((request) {
      expect(request.followRedirects, isFalse);
      if (request.uri.host == 'sso.hunau.edu.cn') {
        expect(request.uri.queryParameters['service'], AppConstants.xgxtCasUrl);
        return ticketResponse(status: 303);
      }
      if (request.uri.path == '/cas') {
        return sessionResponse(
          '',
          status: 302,
          location: '/session/start',
          cookies: ['JSESSIONID=initial; Path=/; HttpOnly'],
        );
      }
      if (request.uri.path == '/session/start') {
        expect(request.headers['cookie'], contains('JSESSIONID=initial'));
        return sessionResponse(
          '',
          status: 307,
          location: '../wap/main/welcome',
          cookies: ['JSESSIONID=authenticated; Path=/; HttpOnly'],
        );
      }
      expect(request.headers['cookie'], contains('JSESSIONID=authenticated'));
      if (request.uri.path.startsWith('/content/')) {
        return sessionResponse('{"aaData":[]}');
      }
      return sessionResponse('<html>学工首页</html>');
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final login = XgxtLoginService(
      dio: dio,
      cookieJar: jar,
      syncSsoCookies: () async {
        imported++;
      },
      refreshSso: () async {
        renewed++;
        return true;
      },
    );
    expect(await login.performXgxtCasLogin(), isTrue);
    expect(imported, 0);
    expect(renewed, 0);
    expect(await LeaveService(dio: dio).fetchList(), isEmpty);
    expect(await QuestionnaireService(dio: dio).fetchList(), isEmpty);
    expect(adapter.requests.length, 7);
  });

  test('统一认证过期时自动刷新，再交换学工会话', () async {
    final jar = CookieJar();
    var imports = 0;
    var renewals = 0;
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.host == 'sso.hunau.edu.cn') {
        return '${request.headers['cookie']}'.contains('TGC=fresh')
            ? ticketResponse()
            : sessionResponse('<html>统一认证登录</html>');
      }
      return sessionResponse(
        request.uri.path.startsWith('/content/')
            ? '{"aaData":[]}'
            : '<html>首页</html>',
        cookies: ['JSESSIONID=valid; Path=/'],
      );
    });
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: jar,
      syncSsoCookies: () async {
        imports++;
      },
      refreshSso: () async {
        renewals++;
        await jar.saveFromResponse(Uri.parse(AppConstants.ssoBaseUrl), [
          Cookie('TGC', 'fresh')..path = '/cas',
        ]);
        return true;
      },
    );
    expect(await login.performXgxtCasLogin(), isTrue);
    expect(imports, 1);
    expect(renewals, 1);
    expect(adapter.requests.length, 5);
  });

  test('只有 WebView 有统一认证 Cookie 时先同步，不重复刷新', () async {
    final jar = CookieJar();
    var imports = 0;
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.host == 'sso.hunau.edu.cn') {
        return '${request.headers['cookie']}'.contains('TGC=browser')
            ? ticketResponse()
            : sessionResponse('登录');
      }
      return sessionResponse(
        request.uri.path.startsWith('/content/') ? '{"aaData":[]}' : '首页',
        cookies: ['JSESSIONID=valid; Path=/'],
      );
    });
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: jar,
      syncSsoCookies: () async {
        imports++;
        await jar.saveFromResponse(Uri.parse(AppConstants.ssoBaseUrl), [
          Cookie('TGC', 'browser')..path = '/cas',
        ]);
      },
      refreshSso: () async => throw StateError('不应重复登录'),
    );
    expect(await login.performXgxtCasLogin(), isTrue);
    expect(imports, 1);
  });

  test('返回统一认证页时即使已有旧 JSESSIONID 也不能算成功', () async {
    final jar = CookieJar();
    await jar.saveFromResponse(Uri.parse(AppConstants.xgxtBaseUrl), [
      Cookie('JSESSIONID', 'stale')..path = '/',
    ]);
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.host == 'sso.hunau.edu.cn' &&
          request.uri.queryParameters.containsKey('service')) {
        return ticketResponse();
      }
      if (request.uri.path == '/cas') {
        return sessionResponse(
          '',
          status: 302,
          location: AppConstants.ssoLoginUrl,
        );
      }
      return sessionResponse('<html>登录</html>');
    });
    expect(
      await XgxtLoginService(
        dio: Dio()..httpClientAdapter = adapter,
        cookieJar: jar,
        refreshSso: () async => false,
        browserLogin: () async => false,
      ).performXgxtCasLogin(),
      isFalse,
    );
  });

  for (final scenario in [
    '无 Cookie',
    'HTTP 403',
    '登录表单',
    '缺少 Location',
    '循环跳转',
  ]) {
    test('$scenario 不会误报登录成功', () async {
      final adapter = SessionHttpAdapter((request) {
        if (request.uri.host == 'sso.hunau.edu.cn') return ticketResponse();
        return switch (scenario) {
          'HTTP 403' => sessionResponse('拒绝访问', status: 403),
          '登录表单' => sessionResponse(
            '<HTML><input TYPE="password"></HTML>',
            cookies: ['JSESSIONID=unauthenticated; Path=/'],
          ),
          '缺少 Location' => sessionResponse('', status: 302),
          '循环跳转' => sessionResponse('', status: 308, location: '/cas'),
          _ => sessionResponse('<html>首页</html>'),
        };
      });
      expect(
        await XgxtLoginService(
          dio: Dio()..httpClientAdapter = adapter,
          cookieJar: CookieJar(),
          refreshSso: () async => false,
          browserLogin: () async => false,
        ).performXgxtCasLogin(),
        isFalse,
      );
      if (scenario == '循环跳转') expect(adapter.requests.length, 11);
    });
  }

  test('并发登录合并为一次，完成后允许下一次刷新', () async {
    final adapter = SessionHttpAdapter(
      (request) => request.uri.host == 'sso.hunau.edu.cn'
          ? ticketResponse()
          : sessionResponse(
              request.uri.path.startsWith('/content/') ? '{"aaData":[]}' : '首页',
              cookies: ['JSESSIONID=valid; Path=/'],
            ),
    );
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
    );
    expect(
      await Future.wait(List.generate(3, (_) => login.performXgxtCasLogin())),
      [true, true, true],
    );
    expect(adapter.requests.length, 3);
    expect(await login.performXgxtCasLogin(), isTrue);
    expect(adapter.requests.length, 6);
    expect(identical(XgxtLoginService(), XgxtLoginService()), isTrue);
  });

  test('统一认证刷新失败有界退出，下一次调用可重新尝试', () async {
    var renewals = 0;
    final adapter = SessionHttpAdapter((_) => sessionResponse('登录'));
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
      syncSsoCookies: () async {},
      refreshSso: () async {
        renewals++;
        return false;
      },
      browserLogin: () async => false,
    );
    expect(await login.performXgxtCasLogin(), isFalse);
    expect(await login.performXgxtCasLogin(), isFalse);
    expect(renewals, 2);
    expect(adapter.requests.length, 4);
  });

  test('请假和问卷同时遇到过期，合并登录后分别恢复业务请求', () async {
    var tickets = 0;
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.host == 'sso.hunau.edu.cn') {
        tickets++;
        return ticketResponse();
      }
      if (request.uri.path == '/cas') {
        return sessionResponse('首页', cookies: ['JSESSIONID=fresh; Path=/']);
      }
      return '${request.headers['cookie']}'.contains('JSESSIONID=fresh')
          ? sessionResponse('{"aaData":[]}')
          : sessionResponse(
              '',
              status: 302,
              location: AppConstants.ssoLoginUrl,
            );
    });
    final jar = CookieJar();
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(CookieManager(jar));
    final login = XgxtLoginService(dio: dio, cookieJar: jar);
    final results = await Future.wait([
      LeaveService(
        dio: dio,
        reauthenticate: login.performXgxtCasLogin,
      ).fetchList(),
      QuestionnaireService(
        dio: dio,
        reauthenticate: login.performXgxtCasLogin,
      ).fetchList(),
    ]);
    expect(results.every((result) => result.isEmpty), isTrue);
    expect(tickets, 1);
    expect(adapter.requests.length, 7);
  });

  test('SSO 中间跳转逐跳保存 Cookie 后取票，不要求首跳直接返回 ticket', () async {
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.host == 'sso.hunau.edu.cn') {
        if (request.uri.path == '/cas/login') {
          return sessionResponse(
            '',
            status: 302,
            location: '/cas/continue',
            cookies: ['SSO_STAGE=ready; Path=/cas'],
          );
        }
        expect(request.headers['cookie'], contains('SSO_STAGE=ready'));
        return ticketResponse();
      }
      return sessionResponse(
        request.uri.path.startsWith('/content/') ? '{"aaData":[]}' : '首页',
        cookies: ['JSESSIONID=valid; Path=/'],
      );
    });
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
      refreshSso: () async => throw StateError('不应刷新'),
      browserLogin: () async => throw StateError('不应兜底'),
    );
    expect(await login.performXgxtCasLogin(), isTrue);
    expect(adapter.requests.length, 4);
  });

  test('HTTP 返回 JavaScript 登录跳转时通过后台浏览器补齐会话', () async {
    final jar = CookieJar();
    var browsers = 0;
    var renewals = 0;
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.host == 'sso.hunau.edu.cn') {
        return sessionResponse(
          '<html><script>location.href="/cas/continue";</script></html>',
        );
      }
      expect(request.headers['cookie'], contains('JSESSIONID=browser-session'));
      return sessionResponse('{"aaData":[]}');
    });
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: jar,
      syncSsoCookies: () async {},
      refreshSso: () async {
        renewals++;
        return false;
      },
      browserLogin: () async {
        browsers++;
        await jar.saveFromResponse(Uri.parse(AppConstants.xgxtWapUrl), [
          Cookie('JSESSIONID', 'browser-session')..path = '/',
        ]);
        return true;
      },
    );
    expect(await login.performXgxtCasLogin(), isTrue);
    expect(browsers, 1);
    expect(renewals, 1);
  });

  test('浏览器返回成功也必须验证原生接口，不把登录页面当成功', () async {
    final adapter = SessionHttpAdapter(
      (request) => request.uri.host == 'sso.hunau.edu.cn'
          ? sessionResponse('登录')
          : sessionResponse(
              '',
              status: 302,
              location: AppConstants.ssoLoginUrl,
            ),
    );
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: CookieJar(),
      syncSsoCookies: () async {},
      refreshSso: () async => false,
      browserLogin: () async => true,
    );
    expect(await login.performXgxtCasLogin(), isFalse);
    expect(adapter.requests.last.uri.path, contains('/xs_wjdc'));
  });

  test('HTTP 200 和旧 JSESSIONID 不能证明成功，业务接口失效会触发浏览器恢复', () async {
    final jar = CookieJar();
    var recovered = false;
    var browsers = 0;
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.host == 'sso.hunau.edu.cn') return ticketResponse();
      if (request.uri.path == '/cas') {
        return sessionResponse(
          '<html>页面外壳</html>',
          cookies: ['JSESSIONID=preauth; Path=/'],
        );
      }
      return recovered
          ? sessionResponse('{"aaData":[]}')
          : sessionResponse(
              '',
              status: 302,
              location: AppConstants.ssoLoginUrl,
            );
    });
    final login = XgxtLoginService(
      dio: Dio()..httpClientAdapter = adapter,
      cookieJar: jar,
      refreshSso: () async => false,
      browserLogin: () async {
        browsers++;
        recovered = true;
        return true;
      },
    );
    expect(await login.performXgxtCasLogin(), isTrue);
    expect(browsers, 1);
    expect(
      adapter.requests.where((r) => r.uri.path.contains('/xs_wjdc')).length,
      2,
    );
  });
}
