import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_hunan_agri/models/app_constants.dart';
import 'package:smart_hunan_agri/services/app_cookie_manager.dart';
import 'package:smart_hunan_agri/services/dorm_service.dart';
import 'package:smart_hunan_agri/services/secure_storage_helper.dart';
import 'package:smart_hunan_agri/services/webvpn_url_converter.dart';

import 'support/session_http_adapter.dart';

const dormHtml = '''
<html><body><table>
<tr><th>宿舍楼</th><th>楼层</th><th>房间</th><th>床号</th></tr>
<tr><td>丰泽四北</td><td>4</td><td>401</td><td>2</td></tr>
</table></body></html>
''';
const loginHtml = '<HTML>统一身份认证<input type="password"></HTML>';

class NoCacheCredentials extends SecureStorageHelper {
  @override
  Future<String?> getUsername() async => null;
}

void main() {
  for (final succeeds in [true, false]) {
    test('WebVPN 准备失败也能刷新 SSO，且只恢复一次：$succeeds', () async {
      var preparations = 0, renewals = 0;
      final service = DormService(
        dio: Dio()
          ..httpClientAdapter = SessionHttpAdapter(
            (_) => sessionResponse(dormHtml),
          ),
        credentials: NoCacheCredentials(),
        ensureWebVpnSession: () async {
          preparations++;
          return preparations > 1 && succeeds;
        },
        reauthenticate: () async {
          renewals++;
          return true;
        },
        fetchDirectInfo: () async => null,
        fetchRenderedInfo: () async => null,
      );
      if (succeeds) {
        expect((await service.fetchDormInfo()).hasCoreInfo, isTrue);
      } else {
        await expectLater(
          service.fetchDormInfo(),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('登录已失效'),
            ),
          ),
        );
      }
      expect(preparations, 2);
      expect(renewals, 1);
    });
  }
  test('公寓登录页自动刷新统一认证，重新准备 WebVPN 后读取', () async {
    var renewed = false;
    var renewals = 0;
    var preparations = 0;
    var renderings = 0;
    final adapter = SessionHttpAdapter(
      (_) => sessionResponse(renewed ? dormHtml : loginHtml),
    );
    final service = DormService(
      dio: Dio()..httpClientAdapter = adapter,
      credentials: NoCacheCredentials(),
      prepareSession: () async {
        preparations++;
      },
      fetchDirectInfo: () async => null,
      fetchRenderedInfo: () async {
        renderings++;
        return null;
      },
      reauthenticate: () async {
        renewals++;
        renewed = true;
        return true;
      },
    );
    final info = await service.fetchDormInfo();
    expect(info.dormBuilding, '丰泽四北');
    expect(info.bed, '2');
    expect(renewals, 1);
    expect(preparations, 2);
    expect(renderings, 2);
    expect(adapter.requests.length, 2);
  });

  test('部分渲染数据不能遮盖登录过期，恢复后再读取完整信息', () async {
    var renderings = 0;
    var renewed = false;
    final adapter = SessionHttpAdapter(
      (_) => sessionResponse(renewed ? dormHtml : loginHtml),
    );
    final service = DormService(
      dio: Dio()..httpClientAdapter = adapter,
      credentials: NoCacheCredentials(),
      prepareSession: () async {},
      fetchDirectInfo: () async => null,
      fetchRenderedInfo: () async {
        renderings++;
        return DormInfo(
          dormBuilding: '',
          floor: '4',
          room: '',
          bed: '',
          fetchedAt: DateTime.now(),
        );
      },
      reauthenticate: () async {
        renewed = true;
        return true;
      },
    );
    expect((await service.fetchDormInfo()).hasCoreInfo, isTrue);
    expect(renderings, 2);
  });

  for (final renewSucceeds in [true, false]) {
    test('公寓认证恢复结果 $renewSucceeds：持续失效有界退出', () async {
      var renewals = 0;
      final adapter = SessionHttpAdapter((_) => sessionResponse(loginHtml));
      final service = DormService(
        dio: Dio()..httpClientAdapter = adapter,
        credentials: NoCacheCredentials(),
        prepareSession: () async {},
        fetchDirectInfo: () async => null,
        fetchRenderedInfo: () async => null,
        reauthenticate: () async {
          renewals++;
          return renewSucceeds;
        },
      );
      await expectLater(
        service.fetchDormInfo(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('公寓系统登录已失效'),
          ),
        ),
      );
      expect(renewals, 1);
      expect(adapter.requests.length, renewSucceeds ? 2 : 1);
    });
  }

  test('公寓逐跳保存 Cookie，相对/上游绝对跳转均保留 WebVPN 路径', () async {
    final entry = Uri.parse(AppConstants.dormServiceUrl);
    final sessionUrl = WebVpnUrlConverter.convert(
      'http://gy.hunau.edu.cn/session',
    );
    final homeUrl = WebVpnUrlConverter.convert('http://gy.hunau.edu.cn/home');
    var renewals = 0;
    final adapter = SessionHttpAdapter((request) {
      expect(request.followRedirects, isFalse);
      if (request.uri.path == entry.path) {
        return sessionResponse(
          '',
          status: 302,
          location: '/session',
          cookies: ['JSESSIONID=initial; Path=/'],
        );
      }
      expect(request.headers['cookie'], contains('JSESSIONID=initial'));
      if (request.uri.toString() == sessionUrl) {
        return sessionResponse(
          '',
          status: 303,
          location: 'http://gy.hunau.edu.cn/home',
        );
      }
      expect(request.uri.toString(), homeUrl);
      return sessionResponse(dormHtml);
    });
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(CookieManager(CookieJar()));
    final info = await DormService(
      dio: dio,
      credentials: NoCacheCredentials(),
      prepareSession: () async {},
      fetchDirectInfo: () async => null,
      fetchRenderedInfo: () async => null,
      reauthenticate: () async {
        renewals++;
        return true;
      },
    ).fetchDormInfo();
    expect(info.bed, '2');
    expect(adapter.requests.length, 3);
    expect(renewals, 0);
  });

  test('已经由 WebVPN 改写的相对 Location 不重复添加代理前缀', () async {
    final entry = Uri.parse(AppConstants.dormServiceUrl);
    final home = Uri.parse(
      WebVpnUrlConverter.convert('http://gy.hunau.edu.cn/home'),
    );
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.path == entry.path) {
        return sessionResponse('', status: 302, location: home.path);
      }
      expect(request.uri, home);
      return sessionResponse(dormHtml);
    });
    final info = await DormService(
      dio: Dio()..httpClientAdapter = adapter,
      credentials: NoCacheCredentials(),
      prepareSession: () async {},
      fetchDirectInfo: () async => null,
      fetchRenderedInfo: () async => null,
      reauthenticate: () async => throw StateError('不应刷新登录'),
    ).fetchDormInfo();
    expect(info.hasCoreInfo, isTrue);
    expect(adapter.requests.length, 2);
  });

  test('公寓刷新后 Path=/cas 的新 TGC 能从 Dio 回流到浏览器', () async {
    final jar = CookieJar();
    final browser = CookieJar();
    final bridge = AppCookieManager(
      cookieJar: jar,
      writeWebViewCookie: (url, cookie) =>
          browser.saveFromResponse(Uri.parse(url), [cookie]),
    );
    var renewals = 0;
    final adapter = SessionHttpAdapter((_) => sessionResponse(loginHtml));
    final service = DormService(
      dio: Dio()..httpClientAdapter = adapter,
      credentials: NoCacheCredentials(),
      prepareSession: () =>
          bridge.syncMultiDomainCookiesToWebView(AppConstants.ssoBaseUrl),
      fetchDirectInfo: () async => null,
      fetchRenderedInfo: () async {
        final cookies = await browser.loadForRequest(
          Uri.parse(AppConstants.ssoLoginUrl),
        );
        if (!cookies.any((c) => c.name == 'TGC' && c.value == 'renewed')) {
          return null;
        }
        return DormInfo(
          dormBuilding: '丰泽四北',
          floor: '4',
          room: '401',
          bed: '2',
          fetchedAt: DateTime.now(),
        );
      },
      reauthenticate: () async {
        renewals++;
        await jar.saveFromResponse(Uri.parse(AppConstants.ssoLoginUrl), [
          Cookie('TGC', 'renewed')..path = '/cas',
        ]);
        return true;
      },
    );
    expect((await service.fetchDormInfo()).bed, '2');
    expect(renewals, 1);
    expect(adapter.requests.length, 1);
  });
}
