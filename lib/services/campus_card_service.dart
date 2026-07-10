import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' as dio_cookie;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/app_constants.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';

class CampusCardInfo {
  final String name;
  final String idserial;
  final String balance;
  final String? openid;

  CampusCardInfo({
    required this.name,
    required this.idserial,
    required this.balance,
    this.openid,
  });

  @override
  String toString() => 'CampusCardInfo(name: $name, idserial: $idserial, balance: $balance)';
}

class CampusCardService {
  CampusCardService._internal() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: true,
      maxRedirects: 10,
      validateStatus: (status) => status != null && status < 500,
      headers: {
        'User-Agent': AppConstants.campusCardUA,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      },
    ));
  }

  static final CampusCardService instance = CampusCardService._internal();

  final _logger = AppLogger.instance;
  late final Dio _dio;

  bool _cookiesReady = false;

  String? _openid;
  String? get openid => _openid;

  CampusCardInfo? _cachedInfo;
  CampusCardInfo? get cachedInfo => _cachedInfo;

  Future<String?> authenticate() async {
    if (!_cookiesReady) {
      await AppCookieManager().initialize();
      if (_dio.interceptors.whereType<dio_cookie.CookieManager>().isEmpty) {
        _dio.interceptors.add(dio_cookie.CookieManager(AppCookieManager().dioCookieJar));
      }
      _cookiesReady = true;
    }
    _logger.i('🚀 Starting background authentication for Campus Card...');

    final completer = Completer<String?>();
    HeadlessInAppWebView? webView;

    try {
      webView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(AppConstants.campusCardUrl)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          userAgent: AppConstants.campusCardUA,
          loadsImagesAutomatically: false,
        ),
        onLoadStart: (controller, url) async {
          final urlString = url?.toString() ?? '';
          _logger.d('🔗 OAuth LoadStart: $urlString');

          if (urlString.contains('fin-serv.hunau.edu.cn/home/openHomePage')) {
            final uri = Uri.parse(urlString);
            final id = uri.queryParameters['openid'];
            if (id != null) {
              _openid = id;
              _logger.i('✅ Extracted OpenID: $_openid');

              await AppCookieManager().syncMultiDomainCookiesFromWebView(urlString);
              if (!completer.isCompleted) completer.complete(_openid);
            }
          }
        },
        onLoadStop: (controller, url) async {
          final urlString = url?.toString() ?? '';
          _logger.d('🏁 OAuth LoadStop: $urlString');

          if (urlString.contains('openid=')) {
            final uri = Uri.parse(urlString);
            final id = uri.queryParameters['openid'];
            if (id != null && !completer.isCompleted) {
              _openid = id;
              _logger.i('✅ Extracted OpenID (onLoadStop): $_openid');
              await AppCookieManager().syncMultiDomainCookiesFromWebView(urlString);
              completer.complete(_openid);
            }
          }
        },
      );

      await webView.run();

      final result = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _logger.e('❌ Campus Card Authentication timeout');
          return null;
        },
      );

      return result;
    } catch (e) {
      _logger.e('❌ Campus Card Authentication failed: $e');
      return null;
    } finally {
      webView?.dispose();
    }
  }

  Future<Map<String, dynamic>> fetchPaymentCode({bool isRetry = false}) async {
    if (_openid == null) {
      final authResult = await authenticate();
      if (authResult == null) throw Exception('授权失败，无法获取付款码');
    }

    final url = 'https://fin-serv.hunau.edu.cn/virtualcard/openVirtualcard?openid=$_openid&displayflag=1&id=27';

    _logger.i('📡 Fetching payment code from: $url (Retry: $isRetry)');

    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'Referer': 'https://fin-serv.hunau.edu.cn/home/openHomePage?openid=$_openid',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final html = response.data.toString();

        if ((html.contains('cas/login') || html.contains('统一身份认证')) && !html.contains('id="qrcode"')) {
          _logger.w('⚠️ Session expired detected in fetchPaymentCode');
          if (!isRetry) {
            _openid = null;
            return fetchPaymentCode(isRetry: true);
          }
        }

        final qrMatch = RegExp(r'id="qrcode".*?src="data:image/png;base64,(.*?)"', dotAll: true).firstMatch(html);
        final qrBase64 = qrMatch?.group(1)?.replaceAll('\n', '').replaceAll('\r', '').trim();

        final codeMatch = RegExp(r'id="code"\s+value="(.*?)"').firstMatch(html);
        final paycode = codeMatch?.group(1);

        final infoMatch = RegExp(r'<p class="bdb">(.*?)<\/p>').firstMatch(html);
        final infoText = infoMatch?.group(1);

        if (infoText != null) {
          _parseAndCacheInfo(infoText);
        } else {
          _logger.d('🔍 Standard info text not found, trying deep scan...');
          _deepScanInfo(html);
        }

        if (qrBase64 == null || paycode == null) {
          _logger.e('❌ Failed to parse QR code or paycode from HTML');
          if (!isRetry) {
            _openid = null;
            return fetchPaymentCode(isRetry: true);
          }
          throw Exception('解析付款码页面失败');
        }

        return {
          'qrBase64': qrBase64,
          'paycode': paycode,
          'info': infoText ?? _cachedInfo?.toString(),
          'openid': _openid,
        };
      }

      throw Exception('网络请求失败: ${response.statusCode}');
    } catch (e) {
      _logger.e('❌ fetchPaymentCode error: $e');
      if (!isRetry && e.toString().contains('Exception')) {
        _logger.i('🔄 Retrying fetchPaymentCode due to error...');
        _openid = null;
        return fetchPaymentCode(isRetry: true);
      }
      rethrow;
    }
  }

  Future<CampusCardInfo> fetchRechargeInfo({bool isRetry = false}) async {
    if (_openid == null) {
      final authResult = await authenticate();
      if (authResult == null) throw Exception('授权失败');
    }

    final url = 'https://fin-serv.hunau.edu.cn/cardpay/openCardPay?openid=$_openid&displayflag=1&id=28';

    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'Referer': 'https://fin-serv.hunau.edu.cn/home/openHomePage?openid=$_openid',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final html = response.data.toString();

        if ((html.contains('cas/login') || html.contains('统一身份认证')) && !html.contains('idserial')) {
          _logger.w('⚠️ Session expired detected in fetchRechargeInfo');
          if (!isRetry) {
            _openid = null;
            return fetchRechargeInfo(isRetry: true);
          }
        }

        final infoMatch = RegExp(r'<p class="bdb">(.*?)<\/p>').firstMatch(html);
        final infoText = infoMatch?.group(1);

        if (infoText != null) {
          _parseAndCacheInfo(infoText);
        }

        if (_cachedInfo == null || _cachedInfo!.balance == '0.00' || _cachedInfo!.balance.isEmpty) {
          _logger.d('📡 Performing deep scan for balance...');
          _deepScanInfo(html);
        }

        if (_cachedInfo == null || _cachedInfo!.balance == '0.00' || _cachedInfo!.balance.isEmpty) {
          _logger.w('⚠️ Balance still missing, trying openHomePage...');
          final homeResponse = await _dio.get(
            'https://fin-serv.hunau.edu.cn/home/openHomePage?openid=$_openid',
            options: Options(headers: {'User-Agent': AppConstants.campusCardUA}),
          );
          if (homeResponse.data != null) {
            _deepScanInfo(homeResponse.data.toString());
          }
        }

        if (_cachedInfo == null || _cachedInfo!.balance == '0.00' || _cachedInfo!.balance.isEmpty) {
          _logger.w('⚠️ Trying openVirtualcard as last resort...');
          await fetchPaymentCode(isRetry: isRetry);
        }

        if (_cachedInfo == null) {
          if (!isRetry) {
            _openid = null;
            return fetchRechargeInfo(isRetry: true);
          }
          throw Exception('无法获取卡片信息');
        }

        return _cachedInfo!;
      }
      throw Exception('网络请求失败: ${response.statusCode}');
    } catch (e) {
      _logger.e('❌ fetchRechargeInfo error: $e');
      if (!isRetry) {
        _openid = null;
        return fetchRechargeInfo(isRetry: true);
      }
      rethrow;
    }
  }

  Future<String> getAlipayForm(double amount) async {
    if (_openid == null || _cachedInfo == null) {
      await fetchRechargeInfo();
    }

    const url = 'https://fin-serv.hunau.edu.cn/alipay/transferFromAlipay2Card';
    _logger.i('📡 [校园卡支付] 请求支付宝表单，amount=${amount.toStringAsFixed(0)}, openid=$_openid, idserial=${_cachedInfo?.idserial}');

    try {
      final response = await _dio.post(
        url,
        data: {
          'txamt': amount.toStringAsFixed(0),
          'payWay': '4',
          'openid': _openid,
          'idserial': _cachedInfo!.idserial,
          'username': _cachedInfo!.name,
          'disableidserialstart': '88,89',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'Referer': 'https://fin-serv.hunau.edu.cn/cardpay/openCardPay?openid=$_openid&displayflag=1&id=28',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final html = response.data.toString();
        _logger.i('📄 [校园卡支付] 表单响应长度=${html.length}, containsAlipayScheme=${html.contains('alipays://') || html.contains('alipay://')}');
        return html;
      }
      throw Exception('充值请求失败: ${response.statusCode}');
    } catch (e) {
      _logger.e('❌ getAlipayForm error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> queryOrderStatus(String paycode) async {
    if (_openid == null) throw Exception('未授权 (OpenID 为空)');

    const url = 'https://fin-serv.hunau.edu.cn/virtualcard/queryOrderStatus';

    try {
      final response = await _dio.get(
        url,
        queryParameters: {
          'openid': _openid,
          'paycode': paycode,
          'connect_redirect': '1',
        },
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': 'https://fin-serv.hunau.edu.cn/virtualcard/openVirtualcard?openid=$_openid&displayflag=1&id=27',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        if (response.data is String) {
          return jsonDecode(response.data as String) as Map<String, dynamic>;
        }
        return response.data as Map<String, dynamic>;
      }

      throw Exception('查询状态失败: ${response.statusCode}');
    } catch (e) {
      _logger.e('❌ queryOrderStatus error: $e');
      rethrow;
    }
  }

  String getCampusCardHomeUrl() {
    if (_openid == null) return AppConstants.campusCardUrl;
    return 'https://fin-serv.hunau.edu.cn/home/openHomePage?openid=$_openid';
  }

  void _parseAndCacheInfo(String infoText) {
    try {
      _logger.d('🔍 Parsing info text: $infoText');
      final regExp = RegExp(r'([^：:\s]+)[：:]([0-9]+).*?余额[：:]([0-9.]+)');
      final match = regExp.firstMatch(infoText);

      if (match != null) {
        _cachedInfo = CampusCardInfo(
          name: match.group(1)!.trim(),
          idserial: match.group(2)!.trim(),
          balance: match.group(3)!.trim(),
          openid: _openid,
        );
        _logger.i('✅ Parsed Card Info: $_cachedInfo');
      } else {
        _logger.w('⚠️ Regex did not match info text: $infoText');
      }
    } catch (e) {
      _logger.w('⚠️ Error parsing info text: $e');
    }
  }

  void _deepScanInfo(String html) {
    try {
      final nameMatch = RegExp(r'id="username"\s+value="([^"]+)"').firstMatch(html) ??
          RegExp(r'name="username"\s+value="([^"]+)"').firstMatch(html);
      final idMatch = RegExp(r'id="idserial"\s+value="([^"]+)"').firstMatch(html) ??
          RegExp(r'name="idserial"\s+value="([^"]+)"').firstMatch(html);

      final balanceDeepMatch = RegExp(r'余额(?:<\/?[^>]+>|[：:\s])*([0-9]+\.[0-9]+)').firstMatch(html) ??
          RegExp(r'([0-9]+\.[0-9]+)元').firstMatch(html);

      if (nameMatch != null && idMatch != null) {
        final name = nameMatch.group(1)!.trim();
        final idserial = idMatch.group(1)!.trim();
        final balance = balanceDeepMatch?.group(1) ?? _cachedInfo?.balance ?? '0.00';

        _cachedInfo = CampusCardInfo(
          name: name,
          idserial: idserial,
          balance: balance,
          openid: _openid,
        );
        _logger.i('✅ Deep scan success: $_cachedInfo');
      }
    } catch (e) {
      _logger.w('⚠️ Deep scan error: $e');
    }
  }
}
