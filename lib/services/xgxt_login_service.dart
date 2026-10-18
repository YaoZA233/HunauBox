import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import 'package:flutter/widgets.dart';

import '../models/app_constants.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';
import 'auth_service.dart';
import 'session_cookie_manager.dart';

class XgxtSessionException implements Exception {
  const XgxtSessionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class XgxtLoginService {
  // Share one login across features to avoid competing CAS tickets/sessions.
  static final _shared = XgxtLoginService._();

  factory XgxtLoginService({
    Dio? dio,
    CookieJar? cookieJar,
    Future<void> Function()? syncSsoCookies,
    Future<bool> Function()? refreshSso,
    Future<bool> Function()? browserLogin,
    Future<void> Function()? publishSession,
  }) {
    if (dio == null &&
        cookieJar == null &&
        syncSsoCookies == null &&
        refreshSso == null &&
        browserLogin == null &&
        publishSession == null) {
      return _shared;
    }
    return XgxtLoginService._(
      dio: dio,
      cookieJar: cookieJar,
      syncSsoCookies: syncSsoCookies,
      refreshSso: refreshSso,
      browserLogin: browserLogin,
      publishSession: publishSession,
    );
  }

  XgxtLoginService._({
    Dio? dio,
    CookieJar? cookieJar,
    Future<void> Function()? syncSsoCookies,
    Future<bool> Function()? refreshSso,
    Future<bool> Function()? browserLogin,
    Future<void> Function()? publishSession,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 15),
             ),
           ),
       _cookieJar = cookieJar,
       _syncSsoCookies = syncSsoCookies,
       _refreshSso = refreshSso,
       _browserLogin = browserLogin,
       _publishSession = publishSession,
       _usesSharedJar = cookieJar == null;

  static const _maxRedirects = 10;
  static const browserSessionUrls = [
    AppConstants.xgxtBaseUrl,
    AppConstants.xgxtWapUrl,
    AppConstants.xgxtQuestionnaireListUrl,
    AppConstants.leaveApplyUrl,
    AppConstants.leaveListUrl,
    '${AppConstants.xgxtBaseUrl}/wap/menu/student/leave/qjsq',
  ];
  final _logger = AppLogger.instance;
  final Dio _dio;
  CookieJar? _cookieJar;
  final Future<void> Function()? _syncSsoCookies;
  final Future<bool> Function()? _refreshSso;
  final Future<bool> Function()? _browserLogin;
  final Future<void> Function()? _publishSession;
  final bool _usesSharedJar;
  bool _cookiesReady = false;
  Future<bool>? _loginInProgress;

  Future<void> _ensureCookieJar() async {
    if (_cookiesReady) return;
    if (_cookieJar == null) {
      await AppCookieManager().initialize();
      _cookieJar = AppCookieManager().dioCookieJar;
    }
    SessionCookieManager.install(_dio, _cookieJar!);
    _cookiesReady = true;
  }

  Options get _options => Options(
    followRedirects: false,
    responseType: ResponseType.plain,
    validateStatus: (status) => status != null && status < 500,
    headers: {
      'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 10; Mobile) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/147.0.0.0 Mobile Safari/537.36',
    },
  );

  bool _isRedirect(int? status) =>
      const [301, 302, 303, 307, 308].contains(status);

  Future<bool> performXgxtCasLogin() {
    return _loginInProgress ??= _login().whenComplete(() {
      _loginInProgress = null;
    });
  }

  /// Verify the HTTP session and publish every business cookie scope before
  /// constructing the visible browser, including when reusing a session.
  Future<bool> ensureSession() => _loginInProgress ??= _ensureSession()
      .whenComplete(() => _loginInProgress = null);

  Future<bool> _ensureSession() async {
    await _ensureCookieJar();
    if (await _probeSession()) {
      await _publishValidSession();
      return true;
    }
    return _login();
  }

  Future<bool> hasValidSession() async {
    try {
      await _ensureCookieJar();
      return await _probeSession();
    } catch (_) {
      return false;
    }
  }

  Future<void> publishBrowserSession() => _publishValidSession();

  Future<Uri?> _requestTicket() async {
    var current = Uri.parse(
      AppConstants.ssoLoginUrl,
    ).replace(queryParameters: {'service': AppConstants.xgxtCasUrl});
    final service = Uri.parse(AppConstants.xgxtCasUrl);
    for (var hop = 0; hop < _maxRedirects; hop++) {
      final response = await _dio.getUri(current, options: _options);
      if (!_isRedirect(response.statusCode)) return null;
      final location = response.headers.value('location');
      if (location == null || location.isEmpty) return null;
      final next = _trustedRedirect(current.resolve(location));
      if (next == null) return null;
      if (next.host == service.host &&
          next.path.split(';').first == service.path &&
          (next.queryParameters['ticket'] ?? '').isNotEmpty) {
        return next;
      }
      if (next.host != Uri.parse(AppConstants.ssoBaseUrl).host) return null;
      current = next;
    }
    return null;
  }

  Future<bool> _login() async {
    try {
      await _ensureCookieJar();

      // Import WebView cookies only if the HTTP jar cannot obtain a ticket;
      // otherwise stale browser cookies could overwrite a newer SSO session.
      var ticketUri = await _requestTicket();
      if (ticketUri == null) {
        await (_syncSsoCookies?.call() ??
            AppCookieManager().syncMultiDomainCookiesFromWebView(
              AppConstants.ssoBaseUrl,
            ));
        ticketUri = await _requestTicket();
      }
      var refreshed = false;
      if (ticketUri == null) {
        final renewed =
            await (_refreshSso?.call() ?? AuthService().silentLogin());
        refreshed = true;
        if (renewed) ticketUri = await _requestTicket();
      }
      if (ticketUri != null && await _exchangeTicket(ticketUri)) {
        await _publishValidSession();
        return true;
      }
      if (!refreshed) {
        final renewed =
            await (_refreshSso?.call() ?? AuthService().silentLogin());
        if (renewed) {
          ticketUri = await _requestTicket();
          if (ticketUri != null && await _exchangeTicket(ticketUri)) {
            await _publishValidSession();
            return true;
          }
        }
      }
      // Reproduce the browser flow which succeeds when the user opens XGXT:
      // it also executes any HTML/JavaScript CAS transitions.
      final browserOk = await (_browserLogin?.call() ?? _loginWithBrowser());
      if (!browserOk || !await _probeSession()) return false;
      await _publishValidSession();
      return true;
    } on XgxtSessionException {
      rethrow;
    } on DioException catch (e) {
      _logger.w('学工 CAS 连接失败（${e.type}）');
      throw const XgxtSessionException('学工或统一认证服务暂时无法连接，请稍后重试');
    } catch (e) {
      _logger.w('学工 CAS 登录失败（${e.runtimeType}）');
      return false;
    }
  }

  Uri? _trustedRedirect(Uri uri) {
    final xgxtHost = Uri.parse(AppConstants.xgxtBaseUrl).host;
    if (uri.scheme == 'http' && uri.host == xgxtHost && uri.port == 80) {
      uri = uri.replace(scheme: 'https', port: 443);
    }
    return uri.scheme == 'https' &&
            uri.port == 443 &&
            uri.userInfo.isEmpty &&
            [
              xgxtHost,
              Uri.parse(AppConstants.ssoBaseUrl).host,
            ].contains(uri.host)
        ? uri
        : null;
  }

  Future<void> _publishValidSession() async {
    try {
      if (_publishSession != null) {
        await _publishSession();
      } else if (_usesSharedJar) {
        await AppCookieManager().replaceWebViewSession(browserSessionUrls);
      }
    } catch (_) {
      throw const XgxtSessionException('学工会话未能同步到浏览器，请重试');
    }
  }

  Future<bool> _exchangeTicket(Uri ticketUri) async {
    // Discard legacy Domain/path shadows before installing the new session.
    await SessionCookieManager.clearHostCookies(
      _cookieJar!,
      browserSessionUrls.map(Uri.parse),
    );
    // As in ChillEast, each hop passes through CookieManager. Adapter-level
    // redirects lose intermediate Set-Cookie headers before the next hop.
    var currentUri = ticketUri;
    for (var hop = 0; hop < _maxRedirects; hop++) {
      final response = await _dio.getUri(currentUri, options: _options);
      if (_isRedirect(response.statusCode)) {
        final location = response.headers.value('location');
        if (location == null || location.isEmpty) return false;
        final next = _trustedRedirect(currentUri.resolve(location));
        if (next == null) return false;
        currentUri = next;
        continue;
      }

      final body = '${response.data}'.toLowerCase();
      if (response.statusCode != 200 ||
          currentUri.host != Uri.parse(AppConstants.xgxtBaseUrl).host ||
          currentUri.path.contains('/login') ||
          body.contains('cas/login') ||
          RegExp(r'<input\b[^>]*type\s*=\s*["\x27]?password').hasMatch(body)) {
        return false;
      }
      final cookies = await _cookieJar!.loadForRequest(
        Uri.parse(AppConstants.xgxtWapUrl),
      );
      final hasSessionCookie = cookies.any(
        (cookie) => cookie.name == 'JSESSIONID' && cookie.value.isNotEmpty,
      );
      // A pre-authentication JSESSIONID and an HTTP 200 page are insufficient.
      return hasSessionCookie && await _probeSession();
    }
    _logger.w('学工 CAS 重定向次数超限，会话未建立');
    return false;
  }

  Future<bool> _probeSession() async {
    // A questionnaire outage or permission failure does not invalidate the
    // whole student system. Verify a second authenticated, read-only endpoint.
    for (final url in [
      AppConstants.xgxtQuestionnaireListUrl,
      AppConstants.leaveListUrl,
    ]) {
      try {
        final response = await _dio.get(
          url,
          queryParameters: {
            'bSortable_0': 'false',
            'bSortable_1': 'false',
            'iSortingCols': '1',
            'iDisplayStart': '0',
            'iDisplayLength': '1',
            'iSortCol_0': '3',
            'sSortDir_0': 'desc',
            '_t_s_': DateTime.now().millisecondsSinceEpoch,
          },
          options: _options.copyWith(
            headers: {
              ...?_options.headers,
              'Cache-Control': 'no-cache',
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': AppConstants.xgxtWapUrl,
            },
          ),
        );
        if (_isRedirect(response.statusCode) || response.statusCode == 401) {
          return false;
        }
        if (response.statusCode == 200) {
          try {
            final data = response.data is String
                ? jsonDecode(response.data)
                : response.data;
            if (data is Map && data['aaData'] is List) return true;
          } on FormatException {
            // Try the other service; an HTML error page is not proof of logout.
          }
        }
        final body = '${response.data}'.trimLeft().toLowerCase();
        if (!body.startsWith('{') &&
            !body.startsWith('[') &&
            (body.contains('cas/login') ||
                RegExp(
                  r'<input\b[^>]*type\s*=\s*["\x27]?password',
                ).hasMatch(body) ||
                RegExp(
                  r'<form\b[^>]*\bid\s*=\s*["\x27]cims_form',
                ).hasMatch(body))) {
          return false;
        }
      } on DioException {
        // The second endpoint can still be available.
      }
    }
    throw const XgxtSessionException('学工服务暂时无法验证会话，请稍后重试');
  }

  Future<bool> _loginWithBrowser() async {
    final cookies = AppCookieManager();
    await cookies.syncMultiDomainCookiesToWebView(AppConstants.ssoLoginUrl);
    await cookies.syncMultiDomainCookiesToWebView(AppConstants.xgxtWapUrl);
    final done = Completer<bool>();
    var stopped = false;
    var checking = false;
    final browser = webview.HeadlessInAppWebView(
      initialSize: const Size(1080, 1920),
      initialUrlRequest: webview.URLRequest(
        url: webview.WebUri(
          Uri.parse(AppConstants.ssoLoginUrl)
              .replace(queryParameters: {'service': AppConstants.xgxtCasUrl})
              .toString(),
        ),
      ),
      initialSettings: webview.InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        sharedCookiesEnabled: true,
        thirdPartyCookiesEnabled: true,
        mixedContentMode: webview.MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        userAgent: _options.headers!['User-Agent'] as String,
      ),
      onLoadStop: (controller, url) async {
        if (stopped || checking || done.isCompleted || url == null) return;
        if (Uri.tryParse(url.toString())?.host !=
            Uri.parse(AppConstants.xgxtBaseUrl).host) {
          return;
        }
        checking = true;
        try {
          for (var attempt = 0; attempt < 8; attempt++) {
            if (stopped || done.isCompleted) return;
            await cookies.syncMultiDomainCookiesFromWebView(url.toString());
            final valid = await _probeSession();
            if (stopped || done.isCompleted) return;
            if (valid) {
              done.complete(true);
              return;
            }
            // Some WAP pages finish their AJAX authentication after load-stop.
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        } catch (e) {
          _logger.w('学工浏览器会话校验失败（${e.runtimeType}）');
        } finally {
          checking = false;
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame == true && !done.isCompleted) {
          done.complete(false);
        }
      },
    );
    try {
      await browser.run();
      return await done.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
    } finally {
      stopped = true;
      await browser.dispose();
    }
  }
}
