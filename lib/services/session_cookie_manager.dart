import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

/// Redirect cookies belong to the response origin, never to Location's host.
/// dio_cookie_manager 3.4 also saves them against Location when redirects are
/// handled manually; CAS/OAuth cross-origin handoffs must avoid that behavior.
class SessionCookieManager extends CookieManager {
  SessionCookieManager(super.cookieJar);

  static void install(Dio dio, CookieJar jar) {
    dio.interceptors.removeWhere((interceptor) => interceptor is CookieManager);
    dio.interceptors.add(SessionCookieManager(jar));
  }

  @override
  Future<String> loadCookies(RequestOptions options) async {
    final saved = await cookieJar.loadForRequest(options.uri);
    final previous = options.headers[HttpHeaders.cookieHeader] as String?;
    return CookieManager.getCookies([
      if (previous != null)
        ...previous
            .split(';')
            .where((part) => part.trim().isNotEmpty)
            .map((part) => Cookie.fromSetCookieValue(part.trim())),
      ...saved.where(
        (cookie) => !cookie.secure || options.uri.scheme == 'https',
      ),
    ]);
  }

  @override
  Future<void> saveCookies(Response response) async {
    final headers = response.headers[HttpHeaders.setCookieHeader] ?? const [];
    if (headers.isEmpty) return;
    final origin = response.realUri;
    final cookies = <Cookie>[];
    for (final header in headers) {
      for (final part in header.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
        final cookie = Cookie.fromSetCookieValue(part.trim());
        final domain = cookie.domain?.replaceFirst(RegExp(r'^\.'), '');
        if (domain != null &&
            origin.host != domain &&
            !origin.host.endsWith('.$domain')) {
          throw const HttpException(
            'Cookie domain does not match response origin',
          );
        }
        if (cookie.path == null || !cookie.path!.startsWith('/')) {
          final slash = origin.path.lastIndexOf('/');
          cookie.path = slash <= 0 ? '/' : origin.path.substring(0, slash);
        }
        cookies.add(cookie);
      }
    }
    await cookieJar.saveFromResponse(origin, cookies);
  }
}
