import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' as dio_cookie;

import '../models/app_constants.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';

class DioClient {
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;

  DioClient._internal();

  late final Dio _dio;
  final _logger = AppLogger.instance;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    await AppCookieManager().initialize();

    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.portalBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 Edg/147.0.0.0',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
        followRedirects: true,
        maxRedirects: 10,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    _dio.interceptors.add(
      dio_cookie.CookieManager(AppCookieManager().dioCookieJar),
    );

    _dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestHeader: false,
        requestBody: false,
        responseHeader: false,
        responseBody: false,
        error: true,
        logPrint: (obj) => _logger.d(obj.toString()),
      ),
    );

    _initialized = true;
  }

  Dio get dio {
    if (!_initialized) {
      throw Exception('DioClient 未初始化,请先调用 initialize()');
    }
    return _dio;
  }

  static Options getOptions({String? referer, bool isXmlHttpRequest = false}) {
    final headers = <String, dynamic>{};
    if (referer != null) {
      headers['Referer'] = referer;
    }
    if (isXmlHttpRequest) {
      headers['X-Requested-With'] = 'XMLHttpRequest';
    }
    return Options(headers: headers);
  }
}
