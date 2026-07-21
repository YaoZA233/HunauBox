import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;

import '../models/app_constants.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';
import 'secure_storage_helper.dart';

class WebVpnAuthService {
  final _logger = AppLogger.instance;

  Future<bool> ensureSession() async {
    try {
      await AppCookieManager().initialize();
      await AppCookieManager().syncMultiDomainCookiesToWebView(
        AppConstants.webvpnBaseUrl,
      );

      if (await _hasWebVpnSession()) return true;

      final storage = SecureStorageHelper();
      final username = await storage.getUsername();
      final password = await storage.getPassword();
      if (username == null || password == null) {
        _logger.w('WebVPN auto login skipped: missing saved credentials');
        return false;
      }

      final completer = Completer<bool>();
      var loginInjected = false;
      var completed = false;

      Future<void> injectLoginIfNeeded(
        webview.InAppWebViewController controller,
        String urlString,
      ) async {
        final isCasLoginPage =
            urlString.contains('/cas/login') ||
            urlString.contains('/authn/login.html') ||
            urlString.contains('sso.hunau.edu.cn');
        if (!isCasLoginPage || loginInjected || completed) return;

        final jsUsername = jsonEncode(username);
        final jsPassword = jsonEncode(password);
        final result = await controller.evaluateJavascript(
          source: '''
            (async function() {
              const sleep = (ms) => new Promise(r => setTimeout(r, ms));
              for (let i = 0; i < 20; i++) {
                const queryInFrames = (selector) => {
                  let el = document.querySelector(selector);
                  if (el) return el;
                  const frames = document.querySelectorAll('iframe');
                  for (const frame of frames) {
                    try {
                      const doc = frame.contentDocument || frame.contentWindow.document;
                      const inner = doc.querySelector(selector);
                      if (inner) return inner;
                    } catch (e) {}
                  }
                  return null;
                };

                const userInput = queryInFrames('input.email-username') || queryInFrames('input[name="username"]');
                const passInput = queryInFrames('input[name="authcode"]') || queryInFrames('input[type="password"]');
                const loginButton = queryInFrames('button.exeActionBtn') ||
                    queryInFrames('input[type="submit"]') ||
                    queryInFrames('button[type="submit"]') ||
                    queryInFrames('.login-btn');

                if (userInput && passInput && loginButton) {
                  userInput.value = $jsUsername;
                  passInput.value = $jsPassword;
                  userInput.dispatchEvent(new Event('input', {bubbles: true}));
                  passInput.dispatchEvent(new Event('input', {bubbles: true}));
                  loginButton.click();
                  return 'INJECTED_AND_CLICKED';
                }
                await sleep(500);
              }
              return 'NOT_FOUND';
            })();
          ''',
        );
        if (result?.toString().contains('INJECTED_AND_CLICKED') == true) {
          loginInjected = true;
        }
      }

      final webView = webview.HeadlessInAppWebView(
        initialSize: const Size(1080, 1920),
        initialUrlRequest: webview.URLRequest(
          url: webview.WebUri(AppConstants.webvpnLoginUrl),
        ),
        initialSettings: webview.InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          sharedCookiesEnabled: true,
          thirdPartyCookiesEnabled: true,
          mixedContentMode: webview.MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          userAgent:
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        ),
        onLoadStart: (controller, url) async {
          await injectLoginIfNeeded(controller, url?.toString() ?? '');
        },
        onLoadStop: (controller, url) async {
          if (completed) return;
          final urlString = url?.toString() ?? '';
          await AppCookieManager().syncMultiDomainCookiesFromWebView(urlString);

          if (await _hasWebVpnSession()) {
            completed = true;
            if (!completer.isCompleted) completer.complete(true);
            return;
          }

          await injectLoginIfNeeded(controller, urlString);
        },
      );

      await webView.run();
      try {
        return await completer.future.timeout(
          const Duration(seconds: 45),
          onTimeout: () => false,
        );
      } finally {
        await AppCookieManager().syncMultiDomainCookiesFromWebView(
          AppConstants.webvpnBaseUrl,
        );
        webView.dispose();
      }
    } catch (e) {
      _logger.e('WebVPN auto login failed: $e');
      return false;
    }
  }

  Future<bool> _hasWebVpnSession() async {
    final cookieManager = webview.CookieManager.instance();
    final webCookies = await cookieManager.getCookies(
      url: webview.WebUri(AppConstants.webvpnBaseUrl),
    );
    if (_containsWebVpnSessionCookie(webCookies.map((cookie) => cookie.name))) {
      return true;
    }

    final dioCookies = await AppCookieManager().dioCookieJar.loadForRequest(
      Uri.parse(AppConstants.webvpnBaseUrl),
    );
    return _containsWebVpnSessionCookie(
      dioCookies.map((cookie) => cookie.name),
    );
  }

  bool _containsWebVpnSessionCookie(Iterable<String> names) {
    return names.any(
      (name) => name.contains('vpn_ticket') || name.contains('webvpn_key'),
    );
  }
}
