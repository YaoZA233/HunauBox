import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/app_constants.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';

/// 获取移动教务系统 API 所需的 token。
///
/// token 由超星 OAuth 回调后的移动教务页面写入 localStorage，不能用门户
/// 页面 Cookie 直接替代，因此通过无界面 WebView 完成一次授权并读取它。
class YdjwxtAuthService {
  static final YdjwxtAuthService _instance = YdjwxtAuthService._internal();
  factory YdjwxtAuthService() => _instance;
  YdjwxtAuthService._internal();

  final _logger = AppLogger.instance;
  String? _cachedToken;
  DateTime? _tokenExpiry;
  Future<String>? _ongoingAuthFuture;

  Future<String> getToken({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedToken != null && _isTokenValid()) {
      return _cachedToken!;
    }

    final ongoing = _ongoingAuthFuture;
    if (ongoing != null) return ongoing;

    final future = _authenticate();
    _ongoingAuthFuture = future;
    try {
      final token = await future;
      _cachedToken = token;
      _tokenExpiry =
          _extractTokenExpiry(token) ??
          DateTime.now().add(const Duration(hours: 3));
      return token;
    } finally {
      if (identical(_ongoingAuthFuture, future)) _ongoingAuthFuture = null;
    }
  }

  void clearToken() {
    _cachedToken = null;
    _tokenExpiry = null;
  }

  bool _isTokenValid() =>
      _tokenExpiry == null ||
      DateTime.now().isBefore(
        _tokenExpiry!.subtract(const Duration(minutes: 5)),
      );

  DateTime? _extractTokenExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is num) {
        final milliseconds = exp > 1000000000000
            ? exp.toInt()
            : exp.toInt() * 1000;
        return DateTime.fromMillisecondsSinceEpoch(milliseconds);
      }
    } catch (e) {
      _logger.d('Unable to parse YDJWXT token expiry: $e');
    }
    return null;
  }

  Future<String> _authenticate() async {
    await AppCookieManager().initialize();
    // OAuth 页面依赖超星登录 Cookie；先把持久化 Cookie 注入 WebView。
    await AppCookieManager().injectAllChaoxingCookies();

    final completer = Completer<String>();
    HeadlessInAppWebView? webView;
    Timer? timeoutTimer;

    String? normalizeToken(dynamic value) {
      if (value == null) return null;
      var token = value.toString().trim();
      // evaluateJavascript 在部分平台会返回 JSON 字符串（包含引号）。
      if (token.length >= 2 && token.startsWith('"') && token.endsWith('"')) {
        try {
          token = jsonDecode(token) as String;
        } catch (_) {
          token = token.substring(1, token.length - 1);
        }
      }
      if (token.startsWith('Bearer ')) token = token.substring(7);
      if (token.startsWith('Basic ')) return null;
      if (token.isEmpty || token == 'null' || token == 'undefined') return null;
      return token;
    }

    void completeWith(dynamic value) {
      final token = normalizeToken(value);
      if (token != null && token.length > 20 && !completer.isCompleted) {
        completer.complete(token);
      }
    }

    try {
      webView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(AppConstants.ydjwxtOAuthUrl)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          userAgent: AppConstants.ydjwxtUA,
          useShouldInterceptRequest: true,
        ),
        onLoadStop: (controller, url) async {
          final token = await controller.evaluateJavascript(
            source: '''
            (function() {
              return localStorage.getItem('token') ||
                     sessionStorage.getItem('token') ||
                     localStorage.getItem('access_token') || '';
            })()
          ''',
          );
          completeWith(token);
        },
        shouldInterceptRequest: (controller, request) async {
          final headers = request.headers;
          if (headers != null) {
            completeWith(
              headers['token'] ??
                  headers['Token'] ??
                  headers['authorization'] ??
                  headers['Authorization'],
            );
          }
          return null;
        },
      );

      await webView.run();
      timeoutTimer = Timer(const Duration(seconds: 45), () {
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException('移动教务系统身份验证超时，请重新登录后重试'));
        }
      });
      return await completer.future;
    } catch (e) {
      _logger.e('YDJWXT authentication failed: $e');
      rethrow;
    } finally {
      timeoutTimer?.cancel();
      webView?.dispose();
    }
  }
}
