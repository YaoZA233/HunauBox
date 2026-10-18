import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

import '../models/app_constants.dart';
import '../models/campus_card_bill.dart';
import '../utils/dkyw_crypto.dart';
import 'app_cookie_manager.dart';
import 'campus_card_service.dart';
import 'session_cookie_manager.dart';

class CampusCardBillException implements Exception {
  const CampusCardBillException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Financial platform selftrade protocol, matching ChillEast/querytrace.js.
/// This service only reads transactions and shares the existing card session.
class CampusCardBillService {
  CampusCardBillService({
    Dio? dio,
    CookieJar? cookieJar,
    Future<String> Function(bool force)? authorize,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 20),
             ),
           ),
       _cookieJar = cookieJar,
       _authorize = authorize;

  static final instance = CampusCardBillService();
  static const _base = 'https://fin-serv.hunau.edu.cn/selftrade';
  final Dio _dio;
  final CookieJar? _cookieJar;
  final Future<String> Function(bool force)? _authorize;
  bool _ready = false;

  Future<void> _initialize() async {
    if (_ready) return;
    var jar = _cookieJar;
    if (jar == null) {
      await AppCookieManager().initialize();
      jar = AppCookieManager().dioCookieJar;
    }
    SessionCookieManager.install(_dio, jar);
    _ready = true;
  }

  Future<String> _getOpenid(bool force) async {
    if (_authorize != null) return _authorize(force);
    final card = CampusCardService.instance;
    if (force) await card.invalidateSession();
    if (card.openid == null || card.cachedInfo == null) {
      await card.fetchRechargeInfo(isRetry: force);
    }
    final openid = card.openid;
    if (openid == null || openid.isEmpty) {
      throw const CampusCardBillException('校园卡授权失败，请重新登录后重试');
    }
    return openid;
  }

  Options _options(Map<String, String> headers) => Options(
    followRedirects: false,
    validateStatus: (status) => status != null && status < 500,
    responseType: ResponseType.plain,
    headers: {'User-Agent': AppConstants.campusCardUA, ...headers},
  );

  Future<List<CampusCardBill>> query(CampusCardBillQuery query) async {
    final error = query.validate();
    if (error != null) throw CampusCardBillException(error);
    try {
      await _initialize();
      for (var attempt = 0; attempt < 2; attempt++) {
        final openid = await _getOpenid(attempt > 0);
        if (openid.isEmpty) {
          throw const CampusCardBillException('校园卡授权失败，请重新登录后重试');
        }
        final page = Uri.parse('$_base/openQueryCardSelfTrade')
            .replace(
              queryParameters: {
                'openid': openid,
                'displayflag': '1',
                'id': '4',
              },
            )
            .toString();
        final landing = await _dio.get(page, options: _options({}));
        if (_expired(landing, landing.data)) {
          if (attempt == 0) continue;
          throw const CampusCardBillException('校园卡会话已失效，请重新登录后重试');
        }
        _checkStatus(landing);
        final response = await _dio.post(
          '$_base/queryCardSelfTradeList',
          queryParameters: {'openid': openid, 'connect_redirect': '1'},
          data: {
            'datajson': DkywCrypto.encryptPayload({
              'beginDate': CampusCardBillQuery.formatDate(query.beginDate),
              'endDate': CampusCardBillQuery.formatDate(query.endDate),
              'tradeType': query.type.value,
              'openid': openid,
            }),
          },
          options: _options({
            'Referer': page,
            'X-Requested-With': 'XMLHttpRequest',
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/javascript, */*; q=0.01',
          }),
        );
        final data = DkywCrypto.decryptServerResponse(response.data);
        if (_expired(response, data)) {
          if (attempt == 0) continue;
          throw const CampusCardBillException('校园卡会话已失效，请重新登录后重试');
        }
        _checkStatus(response);
        if (data is! Map) {
          throw const CampusCardBillException('账单响应格式异常，请稍后重试');
        }
        if (data['success'] != true && data['success'] != 'true') {
          throw CampusCardBillException(
            (data['message'] ?? data['msg'] ?? '查询账单失败，请稍后重试').toString(),
          );
        }
        final result = data['resultData'];
        final List<dynamic>? rows = result is List
            ? result
            : result is Map
            ? result.values.whereType<List>().firstOrNull
            : result == null
            ? const []
            : null;
        if (rows == null || rows.any((row) => row is! Map)) {
          throw const CampusCardBillException('账单响应格式异常，请稍后重试');
        }
        return rows
            .map(
              (row) => CampusCardBill.fromJson(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList();
      }
      throw const CampusCardBillException('校园卡会话已失效，请重新登录后重试');
    } on CampusCardBillException {
      rethrow;
    } on DioException {
      throw const CampusCardBillException('校园卡账单服务暂时无法连接，请稍后重试');
    } catch (_) {
      throw const CampusCardBillException('校园卡账单加载失败，请稍后重试');
    }
  }

  void _checkStatus(Response<dynamic> response) {
    if (response.statusCode != 200) {
      throw CampusCardBillException('账单服务请求失败：HTTP ${response.statusCode}');
    }
  }

  bool _expired(Response<dynamic> response, dynamic data) {
    if (response.statusCode == 401 ||
        const [301, 302, 303, 307, 308].contains(response.statusCode)) {
      return true;
    }
    // A merchant's name is content, never evidence that the session expired.
    if (data is Map && (data['success'] == true || data['success'] == 'true')) {
      return false;
    }
    final message = data is Map
        ? '${data['message'] ?? data['msg'] ?? ''}'
        : '$data';
    return [
      'openid无效',
      '页面丢失',
      '未登录',
      '会话过期',
      '资源受限',
      'cas/login',
      '统一身份认证',
    ].any(message.contains);
  }
}
