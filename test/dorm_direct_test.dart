import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:smart_hunan_agri/models/app_constants.dart';
import 'package:smart_hunan_agri/services/dorm_service.dart';
import 'package:smart_hunan_agri/services/secure_storage_helper.dart';

import 'support/session_http_adapter.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._dir);
  final String _dir;
  @override
  Future<String> getApplicationDocumentsPath() async => _dir;
}

class NoCacheCredentials extends SecureStorageHelper {
  @override
  Future<String?> getUsername() async => null;
}

// 学生公寓平台真实返回的 createRow 结构（与 ChillEast 一致）。
const bedHtml = '''
<html><body><script>
function loadData() {
  view.createRow("ssl", "宿舍楼", "丰泽4北");
  view.createRow("lc", "楼层", "4");
  view.createRow("fj", "寝室房间号", "401");
  view.createRow("cw", "床位", "2");
}
</script></body></html>
''';
const loginHtml = '<HTML>统一身份认证<input type="password"></HTML>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dorm_direct_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('超星 OAuth 直连 gy.hunau.edu.cn 拉取床位，无需 WebVPN/WebView', () async {
    var hitWebVpn = false;
    final adapter = SessionHttpAdapter((request) {
      final uri = request.uri;
      if (uri.host == 'webvpn.hunau.edu.cn') {
        hitWebVpn = true;
        return sessionResponse('', status: 500);
      }
      if (uri.host == 'auth.chaoxing.com') {
        return sessionResponse(
          '',
          status: 302,
          location: 'https://gy.hunau.edu.cn/app/content/main/sitemap?code=abc',
        );
      }
      if (uri.host == 'gy.hunau.edu.cn') {
        if (uri.path.startsWith('/app/content/main/sitemap')) {
          return sessionResponse(
            '',
            status: 302,
            location: 'https://gy.hunau.edu.cn/wap/main/welcome',
            cookies: ['JSESSIONID=GY123; Path=/'],
          );
        }
        if (uri.path.contains('/stu/wyDorm')) {
          final cookie = request.headers['cookie']?.toString() ?? '';
          return cookie.contains('JSESSIONID=GY123')
              ? sessionResponse(bedHtml)
              : sessionResponse(loginHtml);
        }
        return sessionResponse('<html>welcome</html>');
      }
      return sessionResponse('', status: 404);
    });

    final info = await DormService(
      dio: Dio()..httpClientAdapter = adapter,
      credentials: NoCacheCredentials(),
      // Defensive: if the direct path ever returns null the fallback must fail
      // fast instead of hitting the real network.
      ensureWebVpnSession: () async => false,
      reauthenticate: () async => false,
      fetchRenderedInfo: () async => null,
    ).fetchDormInfo();

    expect(info.dormBuilding, '丰泽四北');
    expect(info.floor, '4');
    expect(info.room, '401');
    expect(info.bed, '2');
    expect(hitWebVpn, isFalse);
    // probe(unauthorized) + authorize + sitemap + welcome + bed(authorized)
    expect(
      adapter.requests.where((r) => r.uri.host == 'gy.hunau.edu.cn').length,
      greaterThanOrEqualTo(2),
    );
    expect(AppConstants.dormitoryBedUrl, contains('gy.hunau.edu.cn'));
  });

  test('超星登录态失效时直连放弃并回退（不抛未捕获异常）', () async {
    final adapter = SessionHttpAdapter((request) {
      final uri = request.uri;
      // authorize 回显登录页 -> 直连判定失效返回 null
      if (uri.host == 'auth.chaoxing.com') {
        return sessionResponse('<html>passport2 login</html>');
      }
      if (uri.host == 'gy.hunau.edu.cn' && uri.path.contains('/stu/wyDorm')) {
        return sessionResponse(loginHtml);
      }
      return sessionResponse('', status: 404);
    });

    await expectLater(
      DormService(
        dio: Dio()..httpClientAdapter = adapter,
        credentials: NoCacheCredentials(),
        ensureWebVpnSession: () async => false,
        reauthenticate: () async => false,
        fetchRenderedInfo: () async => null,
      ).fetchDormInfo(),
      throwsA(isA<Exception>()),
    );
  });
}
