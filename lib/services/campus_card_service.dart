import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' as dio_cookie;
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/app_constants.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';
import '../utils/dkyw_crypto.dart';

enum PaymentMethod { wechat, alipay }

class WeChatRechargeOrder {
  const WeChatRechargeOrder({
    required this.partnerjourno,
    required this.mwebUrl,
    required this.returnurl,
    this.redirectUrl,
    this.prepayId,
  });

  final String partnerjourno;
  final String mwebUrl;
  final String returnurl;
  final String? redirectUrl;
  final String? prepayId;
}

class WeChatPayStatusResult {
  const WeChatPayStatusResult({
    required this.isSuccess,
    required this.isPending,
    this.message,
  });

  final bool isSuccess;
  final bool isPending;
  final String? message;
}

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
  String toString() =>
      'CampusCardInfo(name: $name, idserial: $idserial, balance: $balance)';
}

class CampusCardService {
  /// 使用隔离的 HTTP 客户端验证支付协议，不访问原生 WebView 或真实账户。
  @visibleForTesting
  CampusCardService.forTesting({
    required Dio dio,
    String? openid,
    CampusCardInfo? cachedInfo,
    required Future<String?> Function() authorize,
    required Future<void> Function() clearSession,
  }) : _authorizeOverride = authorize,
       _clearSessionOverride = clearSession {
    _dio = dio;
    _openid = openid;
    _cachedInfo = cachedInfo;
  }

  CampusCardService._internal() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        followRedirects: true,
        maxRedirects: 10,
        validateStatus: (status) => status != null && status < 500,
        headers: {
          'User-Agent': AppConstants.campusCardUA,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      ),
    );
  }

  static final CampusCardService instance = CampusCardService._internal();

  final _logger = AppLogger.instance;
  late final Dio _dio;
  Future<String?> Function()? _authorizeOverride;
  Future<void> Function()? _clearSessionOverride;
  bool _creatingWeChatOrder = false;

  bool _cookiesReady = false;

  String? _openid;
  String? get openid => _openid;

  CampusCardInfo? _cachedInfo;
  CampusCardInfo? get cachedInfo => _cachedInfo;

  /// 清除失效的财务平台会话，保留超星登录态供下一次 OAuth 重新授权。
  Future<void> invalidateSession() async {
    _openid = null;
    _cachedInfo = null;
    if (_clearSessionOverride != null) {
      await _clearSessionOverride!();
      return;
    }
    await AppCookieManager().initialize();
    await AppCookieManager().dioCookieJar.delete(
      Uri.parse('https://fin-serv.hunau.edu.cn'),
    );
  }

  Future<String?> authenticate() async {
    if (_authorizeOverride != null) {
      return _openid = await _authorizeOverride!();
    }
    if (!_cookiesReady) {
      await AppCookieManager().initialize();
      if (_dio.interceptors.whereType<dio_cookie.CookieManager>().isEmpty) {
        _dio.interceptors.add(
          dio_cookie.CookieManager(AppCookieManager().dioCookieJar),
        );
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

          // 不能在导航开始时完成授权：目标页的会话 Cookie 尚未写入。
        },
        onLoadStop: (controller, url) async {
          final urlString = url?.toString() ?? '';
          _logger.d('🏁 OAuth LoadStop: $urlString');

          final uri = Uri.tryParse(urlString);
          if (uri?.host == 'fin-serv.hunau.edu.cn' &&
              uri?.path == '/homeCX/openHomePage') {
            final id = uri!.queryParameters['openid'];
            if (id != null && id.isNotEmpty && !completer.isCompleted) {
              await AppCookieManager().syncMultiDomainCookiesFromWebView(
                urlString,
              );
              if (!completer.isCompleted) {
                _openid = id;
                completer.complete(id);
              }
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

    final url =
        'https://fin-serv.hunau.edu.cn/virtualcard/openVirtualcard?openid=$_openid&displayflag=1&id=27';

    _logger.i('📡 Fetching payment code from: $url (Retry: $isRetry)');

    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'Referer':
                'https://fin-serv.hunau.edu.cn/homeCX/openHomePage?openid=$_openid&usertype=2',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final html = response.data.toString();

        if ((html.contains('cas/login') || html.contains('统一身份认证')) &&
            !html.contains('id="qrcode"')) {
          _logger.w('⚠️ Session expired detected in fetchPaymentCode');
          if (!isRetry) {
            _openid = null;
            return fetchPaymentCode(isRetry: true);
          }
        }

        final qrMatch = RegExp(
          r'id="qrcode".*?src="data:image/png;base64,(.*?)"',
          dotAll: true,
        ).firstMatch(html);
        final qrBase64 = qrMatch
            ?.group(1)
            ?.replaceAll('\n', '')
            .replaceAll('\r', '')
            .trim();

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

    final url =
        'https://fin-serv.hunau.edu.cn/cardpay/openCardPay?openid=$_openid&displayflag=1&id=28';

    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'Referer':
                'https://fin-serv.hunau.edu.cn/homeCX/openHomePage?openid=$_openid&usertype=2',
          },
        ),
      );

      if (_isInvalidSessionPage(response)) {
        _logger.w('⚠️ Session expired detected in fetchRechargeInfo');
        if (!isRetry) {
          await invalidateSession();
          return fetchRechargeInfo(isRetry: true);
        }
        await invalidateSession();
        throw Exception('财务平台会话失效，请重新登录后重试');
      }

      if (response.statusCode == 200 && response.data != null) {
        final html = response.data.toString();

        // 只接受本次页面中的卡片信息，不能用旧缓存掩盖失效页面。
        _cachedInfo = null;
        final infoMatch = RegExp(r'<p class="bdb">(.*?)<\/p>').firstMatch(html);
        final infoText = infoMatch?.group(1);

        if (infoText != null) {
          _parseAndCacheInfo(infoText);
        }

        if (_cachedInfo == null) {
          _logger.d('📡 Performing deep scan for balance...');
          _deepScanInfo(html);
        }

        if (_cachedInfo == null) {
          _logger.w('⚠️ Balance still missing, trying openHomePage...');
          final homeResponse = await _dio.get(
            'https://fin-serv.hunau.edu.cn/homeCX/openHomePage?openid=$_openid&usertype=2',
            options: Options(
              headers: {'User-Agent': AppConstants.campusCardUA},
            ),
          );
          if (homeResponse.data != null) {
            _deepScanInfo(homeResponse.data.toString());
          }
        }

        if (_cachedInfo == null) {
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
    if (amount < 1 || amount > 1000 || amount != amount.roundToDouble()) {
      throw Exception('充值金额必须是 1–1000 元的整数');
    }
    if (_openid == null || _cachedInfo == null) {
      await fetchRechargeInfo();
    }

    const url = 'https://fin-serv.hunau.edu.cn/alipay/transferFromAlipay2Card';
    _logger.i(
      '📡 [校园卡支付] 请求支付宝表单，amount=${amount.toStringAsFixed(0)}, openid=$_openid, idserial=${_cachedInfo?.idserial}',
    );

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
            'Referer':
                'https://fin-serv.hunau.edu.cn/cardpay/openCardPay?openid=$_openid&displayflag=1&id=28',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final html = response.data.toString();
        _logger.i(
          '📄 [校园卡支付] 表单响应长度=${html.length}, containsAlipayScheme=${html.contains('alipays://') || html.contains('alipay://')}',
        );
        return html;
      }
      throw Exception('充值请求失败: ${response.statusCode}');
    } catch (e) {
      _logger.e('❌ getAlipayForm error: $e');
      rethrow;
    }
  }

  /// 创建校园卡微信 H5 充值订单。
  Future<WeChatRechargeOrder> createWeChatOrder(double amount) async {
    if (!amount.isFinite ||
        amount < 1 ||
        amount > 1000 ||
        amount != amount.roundToDouble()) {
      throw Exception('充值金额必须是 1–1000 元的整数');
    }
    if (_creatingWeChatOrder) {
      throw Exception('微信充值订单正在创建，请勿重复提交');
    }
    _creatingWeChatOrder = true;
    try {
      // 即使已有 OpenID，也必须用只读请求确认会话仍有效再发起订单。
      final info = await fetchRechargeInfo();
      if (_openid == null || _openid!.isEmpty || info.idserial.isEmpty) {
        throw Exception('无法获取有效的校园卡充值信息');
      }
      // 记录本次支付方式；此接口失败不影响后续下单。
      try {
        await _postWeChatJson('/myaccount/userlastbind', {
          'payinfo': {'cardpayWay': '1'},
          'idserial': info.idserial,
        });
      } on _CampusCardSessionExpired {
        rethrow;
      } catch (e) {
        _logger.w('记录微信支付方式失败（不影响下单）: $e');
      }

      // 下单 POST 不自动重试：超时可能发生在服务端已创建订单之后。
      final data = await _postWeChatJson('/wxpay/transferFromWx2Card', {
        'txamt': amount.toStringAsFixed(0),
        'payWay': '1',
        'openid': _openid,
        'idserial': info.idserial,
        'tradetype': 'WAP',
      });

      if (data['success'] != true) {
        final message = data['message']?.toString().trim();
        throw Exception(
          message == null || message.isEmpty
              ? '财务平台拒绝创建微信充值订单'
              : '创建微信充值订单失败：$message',
        );
      }
      final result = data['resultData'];
      if (result is! Map) {
        throw Exception('微信订单响应缺少订单信息，请先确认充值记录再重试');
      }
      final journo = result['partnerjourno']?.toString().trim() ?? '';
      final mwebUrl = result['mweb_url']?.toString().trim() ?? '';
      final returnurl = _normalizeWeChatReturnUrl(
        result['returnurl']?.toString() ?? '',
      );
      final paymentUri = Uri.tryParse(mwebUrl);
      final returnUri = Uri.tryParse(returnurl);
      if (journo.isEmpty ||
          paymentUri?.scheme != 'https' ||
          paymentUri?.host != 'wx.tenpay.com' ||
          returnUri?.scheme != 'https' ||
          returnUri?.host != 'fin-serv.hunau.edu.cn') {
        throw Exception('微信订单响应不完整或支付地址异常，请先确认充值记录再重试');
      }
      return WeChatRechargeOrder(
        partnerjourno: journo,
        mwebUrl: mwebUrl,
        returnurl: returnurl,
        redirectUrl: result['redirect_url']?.toString(),
        prepayId: result['prepay_id']?.toString(),
      );
    } on DioException catch (e) {
      _logger.e('微信充值请求网络异常: ${e.type}');
      throw Exception('微信充值请求未能确认，请先查看充值记录，勿重复支付');
    } catch (e) {
      _logger.e('创建微信充值订单失败: $e');
      rethrow;
    } finally {
      _creatingWeChatOrder = false;
    }
  }

  Future<Map<String, dynamic>> _postWeChatJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post(
      'https://fin-serv.hunau.edu.cn$path',
      queryParameters: {'openid': _openid, 'connect_redirect': '1'},
      // 与当前 dkyw.request.ajax 一致，JSON 请求也需要 datajson 封装。
      data: {'datajson': DkywCrypto.encryptPayload(payload)},
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': AppConstants.campusCardUA,
          'Referer':
              'https://fin-serv.hunau.edu.cn/cardpay/openCardPay?openid=$_openid&displayflag=1&id=28',
          'Accept': 'application/json, text/javascript, */*; q=0.01',
          'X-Requested-With': 'XMLHttpRequest',
        },
      ),
    );
    if (_isInvalidSessionPage(response)) {
      await invalidateSession();
      throw _CampusCardSessionExpired();
    }
    if (response.statusCode != 200) {
      throw Exception('微信充值接口请求失败（HTTP ${response.statusCode}），请先确认充值记录');
    }
    dynamic decoded;
    try {
      decoded = DkywCrypto.decryptServerResponse(response.data);
    } catch (_) {
      throw Exception('微信充值接口响应解密失败，请先确认充值记录再重试');
    }
    if (decoded is! Map) {
      throw Exception('微信充值接口返回格式异常，请先确认充值记录再重试');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static bool _isInvalidSessionPage(Response<dynamic> response) {
    final html = response.data?.toString() ?? '';
    return response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.realUri.path.contains('errorPage') ||
        response.realUri.path.contains('/login') ||
        html.contains('资源受限') ||
        html.contains('页面丢失') ||
        ((html.contains('cas/login') || html.contains('统一身份认证')) &&
            !html.contains('idserial'));
  }

  static String _normalizeWeChatReturnUrl(String value) {
    var url = value.trim();
    // 平台会返回一次或两次编码；已是 URL 时不再解码其查询参数。
    for (
      var i = 0;
      i < 3 && !url.startsWith('http://') && !url.startsWith('https://');
      i++
    ) {
      try {
        final decoded = Uri.decodeComponent(url);
        if (decoded == url) break;
        url = decoded;
      } catch (_) {
        break;
      }
    }
    return url.startsWith('http://')
        ? url.replaceFirst('http://', 'https://')
        : url;
  }

  /// 从微信 H5 支付页提取用于唤起客户端的 weixin:// 地址。
  Future<String?> getWeChatDeepLink(String mwebUrl) async {
    try {
      final response = await _dio.get(
        mwebUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Referer': 'https://fin-serv.hunau.edu.cn/',
            'User-Agent': AppConstants.campusCardUA,
          },
        ),
      );
      final html = response.data?.toString() ?? '';
      return RegExp(
        r'''(weixin://wap/pay\?[^"'\s<>\)]+)''',
      ).firstMatch(html)?.group(1);
    } catch (e) {
      _logger.w('提取微信唤起链接失败，将使用 H5 兜底: $e');
      return null;
    }
  }

  Future<WeChatPayStatusResult> queryWeChatPayStatus({
    required String partnerjourno,
    required String returnurl,
  }) async {
    if (_openid == null) throw Exception('未授权 (OpenID 为空)');
    try {
      final response = await _dio.get(
        'https://fin-serv.hunau.edu.cn/wxpay/queryWxWapPayStatus',
        queryParameters: {
          'partnerjourno': partnerjourno,
          'openid': _openid,
          'returnurl': returnurl,
        },
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'Referer':
                'https://fin-serv.hunau.edu.cn/cardpay/openCardPay?openid=$_openid',
          },
        ),
      );
      return parseWeChatPayStatusResponse(
        location: response.headers.value('location') ?? '',
        realPath: response.realUri.path,
        body: response.data?.toString() ?? '',
      );
    } catch (e) {
      _logger.w('查询微信支付状态失败，将保持待确认状态: $e');
      return WeChatPayStatusResult(
        isSuccess: false,
        isPending: true,
        message: e.toString(),
      );
    }
  }

  /// 将查询页严格分类，避免把“订单查询中”误判为支付成功。
  static WeChatPayStatusResult parseWeChatPayStatusResponse({
    required String location,
    required String realPath,
    required String body,
  }) {
    if (location.contains('paySuccess') || realPath.contains('paySuccess')) {
      return const WeChatPayStatusResult(isSuccess: true, isPending: false);
    }
    if (body.contains('微信支付订单查询中') || body.contains('icon-wait.png')) {
      return const WeChatPayStatusResult(isSuccess: false, isPending: true);
    }
    final explicitSuccess =
        (body.contains('支付成功') || body.contains('充值成功')) &&
        !body.contains('失败原因') &&
        !body.contains('static.css');
    if (explicitSuccess) {
      return const WeChatPayStatusResult(isSuccess: true, isPending: false);
    }

    final reason = RegExp(
      r'id="message"[^>]*>([^<]+)</p>',
    ).firstMatch(body)?.group(1)?.trim();
    if (reason != null && reason.isNotEmpty && reason != '微信支付订单查询中') {
      return WeChatPayStatusResult(
        isSuccess: false,
        isPending: false,
        message: reason,
      );
    }
    return const WeChatPayStatusResult(isSuccess: false, isPending: true);
  }

  Future<Map<String, dynamic>> queryOrderStatus(String paycode) async {
    if (_openid == null) throw Exception('未授权 (OpenID 为空)');

    const url = 'https://fin-serv.hunau.edu.cn/virtualcard/queryOrderStatus';
    final payload = {'paycode': paycode, 'openid': _openid};

    try {
      final response = await _dio.get(
        url,
        queryParameters: {
          'openid': _openid,
          'connect_redirect': '1',
          'datajson': DkywCrypto.encryptPayload(payload),
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                'https://fin-serv.hunau.edu.cn/virtualcard/openVirtualcard?openid=$_openid&displayflag=1&id=27',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = DkywCrypto.decryptServerResponse(response.data);
        if (data is Map) return Map<String, dynamic>.from(data);
        throw Exception('查询状态失败：响应格式异常');
      }

      throw Exception('查询状态失败: ${response.statusCode}');
    } catch (e) {
      _logger.e('❌ queryOrderStatus error: $e');
      rethrow;
    }
  }

  String getCampusCardHomeUrl() {
    if (_openid == null) return AppConstants.campusCardUrl;
    return 'https://fin-serv.hunau.edu.cn/homeCX/openHomePage?openid=$_openid&usertype=2';
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
      final nameMatch =
          RegExp(r'id="username"\s+value="([^"]+)"').firstMatch(html) ??
          RegExp(r'name="username"\s+value="([^"]+)"').firstMatch(html);
      final idMatch =
          RegExp(r'id="idserial"\s+value="([^"]+)"').firstMatch(html) ??
          RegExp(r'name="idserial"\s+value="([^"]+)"').firstMatch(html);

      final balanceDeepMatch =
          RegExp(
            r'余额(?:<\/?[^>]+>|[：:\s])*([0-9]+\.[0-9]+)',
          ).firstMatch(html) ??
          RegExp(r'([0-9]+\.[0-9]+)元').firstMatch(html);

      if (nameMatch != null && idMatch != null) {
        final name = nameMatch.group(1)!.trim();
        final idserial = idMatch.group(1)!.trim();
        final balance =
            balanceDeepMatch?.group(1) ?? _cachedInfo?.balance ?? '0.00';

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

class _CampusCardSessionExpired implements Exception {
  @override
  String toString() => 'Exception: 财务平台会话失效，请重新登录后重试';
}
