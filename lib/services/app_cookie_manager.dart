import 'dart:io' as io;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import 'package:path_provider/path_provider.dart';

import '../models/app_constants.dart';
import 'app_logger.dart';

class AppCookieManager {
  static final AppCookieManager _instance = AppCookieManager._internal();
  factory AppCookieManager() => _instance;
  AppCookieManager._internal();

  late final PersistCookieJar dioCookieJar;
  final webview.CookieManager _webViewCookieManager =
      webview.CookieManager.instance();
  bool _initialized = false;
  final _logger = AppLogger.instance;

  Future<void> initialize() async {
    if (_initialized) return;
    final appDocDir = await getApplicationDocumentsDirectory();
    dioCookieJar = PersistCookieJar(
      storage: FileStorage('${appDocDir.path}/.cookies'),
    );
    _initialized = true;
  }

  // 同步 WebView 的 Cookie 到 Dio
  Future<void> syncMultiDomainCookiesFromWebView([String? currentUrl]) async {
    await initialize();
    final domains = <String>[
      AppConstants.ssoBaseUrl,
      AppConstants.portalBaseUrl,
      AppConstants.webvpnBaseUrl,
      'https://bxpt.hunau.edu.cn',
      'https://bxpt.hunau.edu.cn/relax/',
      'https://passport2.chaoxing.com',
      'https://auth.chaoxing.com',
      'https://notice.chaoxing.com',
      'https://hd.chaoxing.com',
      'https://office.chaoxing.com',
      'https://mooc1.chaoxing.com',
      'https://mooc1-api.chaoxing.com',
      'https://mooc-res2.chaoxing.com',
      'https://reserve.chaoxing.com',
      'https://v1.chaoxing.com',
      'https://photo.chaoxing.com',
      'https://p.cldisk.com',
      'https://ananas.chaoxing.com',
      'https://fin-serv.hunau.edu.cn',
    ];

    if (currentUrl != null &&
        currentUrl.isNotEmpty &&
        !domains.contains(currentUrl)) {
      domains.add(currentUrl);
    }

    for (final domain in domains) {
      try {
        final cookies = await _webViewCookieManager.getCookies(
          url: webview.WebUri(domain),
        );
        for (final cookie in cookies) {
          final dioCookie = io.Cookie(cookie.name, cookie.value);
          dioCookie.domain = cookie.domain ?? Uri.parse(domain).host;
          dioCookie.path = cookie.path ?? '/';
          await dioCookieJar.saveFromResponse(Uri.parse(domain), [dioCookie]);

          if (domain.contains('webvpn.hunau.edu.cn') &&
              (cookie.name.contains('vpn_ticket') ||
                  cookie.name.contains('webvpn_key'))) {
            final mirroredCookie = io.Cookie(cookie.name, cookie.value)
              ..domain = 'portal.hunau.edu.cn'
              ..path = '/'
              ..httpOnly = true;
            await dioCookieJar.saveFromResponse(
              Uri.parse(AppConstants.portalBaseUrl),
              [mirroredCookie],
            );
          }
        }
      } catch (e) {
        _logger.w('Failed to sync cookies from $domain: $e');
      }
    }
  }

  Future<void> syncMultiDomainCookiesToWebView(String url) async {
    await initialize();
    try {
      final uri = Uri.parse(url);
      final cookies = await dioCookieJar.loadForRequest(uri);
      for (final cookie in cookies) {
        final targetDomain = cookie.domain ?? uri.host;
        await _webViewCookieManager.setCookie(
          url: webview.WebUri(url),
          name: cookie.name,
          value: cookie.value,
          domain: targetDomain,
          path: cookie.path ?? '/',
          isSecure: false,
          isHttpOnly: cookie.httpOnly,
        );
      }
    } catch (e) {
      _logger.w('Failed to sync cookies to WebView for $url: $e');
    }
  }

  Future<void> injectAllChaoxingCookies() async {
    await initialize();
    final domains = [
      'http://chaoxing.com',
      'https://chaoxing.com',
      'https://passport2.chaoxing.com',
      'https://auth.chaoxing.com',
      'https://notice.chaoxing.com',
      'http://notice.chaoxing.com',
      'https://hd.chaoxing.com',
      'http://hd.chaoxing.com',
      'https://office.chaoxing.com',
      'http://office.chaoxing.com',
      'https://mooc1.chaoxing.com',
      'http://mooc1.chaoxing.com',
      'https://mooc1-api.chaoxing.com',
      'https://mooc-res2.chaoxing.com',
      'https://photo.chaoxing.com',
      'https://p.cldisk.com',
      'https://ananas.chaoxing.com',
      'https://fin-serv.hunau.edu.cn',
    ];

    for (final domain in domains) {
      await syncMultiDomainCookiesToWebView(domain);
    }

    _logger.i('Injected Chaoxing cookies to WebView');
  }

  Future<void> clearAllCookies() async {
    await initialize();
    await dioCookieJar.deleteAll();
    await _webViewCookieManager.deleteAllCookies();
  }

  Future<String?> getCookieValue(String url, String name) async {
    try {
      final cookies = await dioCookieJar.loadForRequest(Uri.parse(url));
      for (final cookie in cookies) {
        if (cookie.name == name) {
          return cookie.value;
        }
      }
    } catch (e) {
      _logger.w('⚠️ Failed to get cookie $name for $url: $e');
    }
    return null;
  }
}
