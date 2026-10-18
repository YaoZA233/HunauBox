import 'dart:io' as io;
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import 'package:path_provider/path_provider.dart';

import '../models/app_constants.dart';
import 'app_logger.dart';

class AppCookieManager {
  static final AppCookieManager _instance = AppCookieManager._internal();
  factory AppCookieManager({
    CookieJar? cookieJar,
    Future<List<webview.Cookie>> Function(String)? readWebViewCookies,
    Future<void> Function(String, io.Cookie)? writeWebViewCookie,
    Future<void> Function(String, io.Cookie)? deleteWebViewCookie,
  }) {
    if (cookieJar == null &&
        readWebViewCookies == null &&
        writeWebViewCookie == null &&
        deleteWebViewCookie == null) {
      return _instance;
    }
    return AppCookieManager._internal(
      cookieJar: cookieJar,
      readWebViewCookies: readWebViewCookies,
      writeWebViewCookie: writeWebViewCookie,
      deleteWebViewCookie: deleteWebViewCookie,
    );
  }
  AppCookieManager._internal({
    CookieJar? cookieJar,
    Future<List<webview.Cookie>> Function(String)? readWebViewCookies,
    Future<void> Function(String, io.Cookie)? writeWebViewCookie,
    Future<void> Function(String, io.Cookie)? deleteWebViewCookie,
  }) : _readWebViewCookies = readWebViewCookies,
       _writeWebViewCookie = writeWebViewCookie,
       _deleteWebViewCookie = deleteWebViewCookie {
    if (cookieJar != null) {
      dioCookieJar = cookieJar;
      _initialized = true;
    }
  }

  late final CookieJar dioCookieJar;
  webview.CookieManager get _webViewCookieManager =>
      webview.CookieManager.instance();
  final Future<List<webview.Cookie>> Function(String)? _readWebViewCookies;
  final Future<void> Function(String, io.Cookie)? _writeWebViewCookie;
  final Future<void> Function(String, io.Cookie)? _deleteWebViewCookie;
  bool _initialized = false;
  Future<void>? _initializing;
  final _logger = AppLogger.instance;

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _initialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _initialize() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    dioCookieJar = PersistCookieJar(
      storage: FileStorage('${appDocDir.path}/.cookies'),
    );
    _initialized = true;
  }

  /// Publish a verified fresh HTTP login. Never infer TGC scope from Android's
  /// metadata-free cookie strings, or let an old root TGC shadow the new one.
  Future<void> saveHttpLoginCookies(Map<Uri, List<io.Cookie>> cookies) async {
    await clearAuthenticationCookies();
    for (final entry in cookies.entries) {
      await dioCookieJar.saveFromResponse(entry.key, entry.value);
    }
    for (final entry in cookies.entries) {
      for (final cookie in entry.value) {
        await _publishWebViewCookie(entry.key.toString(), cookie);
      }
    }
  }

  Future<void> clearAuthenticationCookies() async {
    await initialize();
    final origins = [
      AppConstants.ssoBaseUrl,
      AppConstants.portalBaseUrl,
      'https://passport2.chaoxing.com',
      'https://passport2-api.chaoxing.com',
    ];
    for (final origin in origins) {
      await dioCookieJar.delete(Uri.parse(origin), true);
      final urls = <String>{origin};
      if (origin == AppConstants.ssoBaseUrl) {
        urls.addAll(['$origin/cas/', '$origin/authn/', '$origin/portal/']);
      }
      await _clearWebViewCookies(urls);
    }
  }

  Future<void> replaceWebViewSession(List<String> urls) async {
    await initialize();
    await _clearWebViewCookies(urls);
    for (final url in urls) {
      await syncMultiDomainCookiesToWebView(url, throwOnFailure: true);
    }
  }

  Future<void> _clearWebViewCookies(Iterable<String> urls) async {
    final deleted = <String>{};
    for (final url in urls) {
      final host = Uri.parse(url).host;
      final nativeCookies =
          await (_readWebViewCookies?.call(url) ??
              _webViewCookieManager.getCookies(url: webview.WebUri(url)));
      for (final native in nativeCookies) {
        final paths = <String>{native.path ?? '/'};
        if (native.name == 'TGC') paths.addAll(['/', '/cas', '/cas/']);
        final scopes = <String?>{native.domain};
        if (native.domain == null) {
          scopes.addAll([host, '.$host']);
        }
        for (final path in paths) {
          for (final scope in scopes) {
            final key = '$host|$scope|$path|${native.name}';
            if (!deleted.add(key)) continue;
            final old = io.Cookie(native.name, '')
              ..domain = scope
              ..path = path;
            if (_deleteWebViewCookie != null) {
              await _deleteWebViewCookie(url, old);
            } else {
              await _webViewCookieManager.deleteCookie(
                url: webview.WebUri(url),
                name: native.name,
                domain: scope,
                path: path,
              );
            }
          }
        }
      }
    }
  }

  Future<void> _publishWebViewCookie(String url, io.Cookie cookie) async {
    if (_writeWebViewCookie != null) {
      await _writeWebViewCookie(url, cookie);
      return;
    }
    final saved = await _webViewCookieManager.setCookie(
      url: webview.WebUri(url),
      name: cookie.name,
      value: cookie.value,
      domain: cookie.domain,
      path: cookie.path ?? '/',
      isSecure: cookie.secure,
      isHttpOnly: cookie.httpOnly,
      expiresDate: cookie.expires?.millisecondsSinceEpoch,
      sameSite: const {
        io.SameSite.lax: webview.HTTPCookieSameSitePolicy.LAX,
        io.SameSite.strict: webview.HTTPCookieSameSitePolicy.STRICT,
        io.SameSite.none: webview.HTTPCookieSameSitePolicy.NONE,
      }[cookie.sameSite],
    );
    if (!saved) throw StateError('认证 Cookie 未能同步到 WebView');
  }

  // 同步 WebView 的 Cookie 到 Dio
  Future<void> syncMultiDomainCookiesFromWebView([
    String? currentUrl,
    List<String>? onlyUrls,
  ]) async {
    await initialize();
    final domains =
        onlyUrls?.toList() ??
        <String>[
          AppConstants.ssoBaseUrl,
          '${AppConstants.ssoBaseUrl}/cas/',
          AppConstants.ssoLoginUrl,
          '${AppConstants.ssoBaseUrl}/authn/',
          AppConstants.ssoMainPage,
          AppConstants.xgxtBaseUrl,
          AppConstants.xgxtWapUrl,
          AppConstants.xgxtQuestionnaireListUrl,
          AppConstants.portalBaseUrl,
          AppConstants.webvpnBaseUrl,
          AppConstants.sunshineBaseUrl,
          '${AppConstants.sunshineBaseUrl}/form.aspx',
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

    // A page can only refresh cookies for its own origin. Importing unrelated
    // WebView sessions here used to replace newer HTTP sessions with stale ones.
    if (onlyUrls == null && currentUrl != null && currentUrl.isNotEmpty) {
      final host = Uri.parse(currentUrl).host;
      domains.removeWhere((url) => Uri.parse(url).host != host);
    }

    if (currentUrl != null &&
        currentUrl.isNotEmpty &&
        !domains.contains(currentUrl)) {
      domains.add(currentUrl);
    }

    for (final domain in domains) {
      try {
        final cookies =
            await (_readWebViewCookies?.call(domain) ??
                _webViewCookieManager.getCookies(url: webview.WebUri(domain)));
        for (final cookie in cookies) {
          final dioCookie = io.Cookie(cookie.name, cookie.value);
          // A null Domain is host-only; adding Domain changes its scope.
          dioCookie.domain = cookie.domain;
          dioCookie.path = cookie.path ?? (cookie.name == 'TGC' ? '/cas' : '/');
          dioCookie.secure = cookie.isSecure ?? false;
          dioCookie.httpOnly = cookie.isHttpOnly ?? false;
          if (cookie.expiresDate != null) {
            dioCookie.expires = DateTime.fromMillisecondsSinceEpoch(
              cookie.expiresDate!,
              isUtc: true,
            );
          }
          if (Uri.parse(domain).host ==
                  Uri.parse(AppConstants.ssoBaseUrl).host &&
              dioCookie.name == 'TGC' &&
              dioCookie.path!.startsWith('/cas')) {
            // Earlier versions imported Android's metadata-free TGC as a
            // Domain cookie at /. Expire those shadows before publishing the
            // real CAS cookie, otherwise both values go into one Cookie header.
            final previous = await dioCookieJar.loadForRequest(
              Uri.parse(AppConstants.ssoLoginUrl),
            );
            for (final old in previous) {
              if (old.name != 'TGC' ||
                  (old.path == dioCookie.path &&
                      old.domain == dioCookie.domain)) {
                continue;
              }
              final expired = io.Cookie(old.name, '')
                ..domain = old.domain
                ..path = old.path ?? '/'
                ..maxAge = 0
                ..expires = DateTime.utc(1970);
              await dioCookieJar.saveFromResponse(
                Uri.parse(AppConstants.ssoLoginUrl),
                [expired],
              );
            }
          }
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

  Future<void> syncMultiDomainCookiesToWebView(
    String url, {
    bool throwOnFailure = false,
  }) async {
    await initialize();
    try {
      final requestedUri = Uri.parse(url);
      final urls = <String>{url};
      if (requestedUri.host == Uri.parse(AppConstants.ssoBaseUrl).host) {
        // Root URL lookups exclude TGC(Path=/cas), in both directions.
        urls.addAll([
          '${AppConstants.ssoBaseUrl}/cas/',
          AppConstants.ssoLoginUrl,
          '${AppConstants.ssoBaseUrl}/authn/',
          AppConstants.ssoMainPage,
        ]);
      }
      final written = <String>{};
      for (final targetUrl in urls) {
        final cookies = await dioCookieJar.loadForRequest(Uri.parse(targetUrl));
        for (final cookie in cookies) {
          final key = '${cookie.domain}|${cookie.path}|${cookie.name}';
          if (!written.add(key)) continue;
          if (_writeWebViewCookie != null) {
            await _writeWebViewCookie(targetUrl, cookie);
            continue;
          }
          await _publishWebViewCookie(targetUrl, cookie);
        }
      }
    } catch (e) {
      _logger.w('Failed to sync cookies to WebView for $url: $e');
      if (throwOnFailure) rethrow;
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
