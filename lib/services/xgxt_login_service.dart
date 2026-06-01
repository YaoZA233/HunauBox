import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' as dio_cookie;

import '../models/app_constants.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';

class XgxtLoginService {
  final _logger = AppLogger.instance;
  final Dio _dio = Dio();
  bool _cookiesReady = false;

  Future<void> _ensureCookieJar() async {
    if (_cookiesReady) return;
    await AppCookieManager().initialize();
    if (_dio.interceptors.whereType<dio_cookie.CookieManager>().isEmpty) {
      _dio.interceptors.add(dio_cookie.CookieManager(AppCookieManager().dioCookieJar));
    }
    _cookiesReady = true;
  }

  Future<bool> performXgxtCasLogin() async {
    try {
      await _ensureCookieJar();

      await AppCookieManager().syncMultiDomainCookiesFromWebView(AppConstants.ssoBaseUrl);

      String? ticket;
      for (int attempt = 0; attempt < 2 && (ticket == null || ticket.isEmpty); attempt++) {
        final ssoResponse = await _dio.get(
          '${AppConstants.ssoBaseUrl}/cas/login',
          queryParameters: {
            'service': AppConstants.xgxtCasUrl,
          },
          options: Options(
            followRedirects: false,
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        if (ssoResponse.statusCode == 302 || ssoResponse.statusCode == 301) {
          final location = ssoResponse.headers.value('location');
          if (location != null) {
            final uri = Uri.parse(location);
            ticket = uri.queryParameters['ticket'];
          }
        }

        if (ticket == null || ticket.isEmpty) {
          await AppCookieManager().syncMultiDomainCookiesFromWebView(AppConstants.ssoBaseUrl);
        }
      }

      if (ticket == null || ticket.isEmpty) {
        _logger.w('⚠️ Unable to obtain Service Ticket, fallback to WebView SSO flow');
        return false;
      }

      final casResponse = await _dio.get(
        AppConstants.xgxtCasUrl,
        queryParameters: {
          'ticket': ticket,
        },
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (casResponse.statusCode != 200 && casResponse.statusCode != 302) {
        _logger.w('⚠️ XGXT CAS validation returned unexpected status: ${casResponse.statusCode}');
        return false;
      }
      return true;
    } catch (e) {
      _logger.e('❌ XGXT CAS login failed: $e');
      return false;
    }
  }
}