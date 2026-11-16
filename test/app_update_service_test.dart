import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/services/app_update_service.dart';

import 'support/session_http_adapter.dart';

AppRelease releaseWith(List<String> names, {String body = '## 更新\n\n修复问题'}) =>
    AppRelease.fromJson({
      'tag_name': 'v1.0.6',
      'name': '1.0.6',
      'body': body,
      'html_url': 'https://github.com/YaoZA233/HunauBox/releases/tag/v1.0.6',
      'assets': [
        for (final name in names)
          {
            'name': name,
            'browser_download_url': 'https://example.com/$name',
            'size': 4,
          },
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final source in UpdateSource.values) {
    test('${source.label} 跳过预发布、草稿和 beta 标签', () async {
      final adapter = SessionHttpAdapter((request) {
        final latest = source == UpdateSource.github
            ? AppUpdateService.githubLatestReleaseUrl
            : AppUpdateService.giteeLatestReleaseUrl;
        if (request.uri.toString() == latest) {
          return sessionResponse('{"tag_name":"v2.0.0-beta"}');
        }
        return sessionResponse(
          '[{"tag_name":"v2.0.0-beta"},{"tag_name":"v1.9.0","draft":true},{"tag_name":"v1.8.0","prerelease":true},{"tag_name":"v1.7.0"},{"tag_name":"v1.6.0"}]',
        );
      });
      final service = AppUpdateService(dio: Dio()..httpClientAdapter = adapter);
      expect((await service.fetchLatest(source)).version, '1.7.0');
      await expectLater(
        service.downloadApk(AppRelease.fromJson({'tag_name': 'v2.0.0-beta'})),
        throwsA(isA<AppUpdateException>()),
      );
    });
  }

  test('保留预发布版本并正确比较正式版和 beta', () {
    final release = AppRelease.fromJson({'tag_name': 'v1.0.8-beta.2'});
    final service = AppUpdateService();
    expect(release.version, '1.0.8-beta.2');
    expect(service.compareVersions('1.0.8', '1.0.8-beta'), greaterThan(0));
    expect(
      service.compareVersions('1.0.8-beta.10', '1.0.8-beta.2'),
      greaterThan(0),
    );
    expect(service.compareVersions('1.0.8-beta', '1.0.7'), greaterThan(0));
    expect(service.compareVersions('1.0.8-beta', '1.0.8-beta'), 0);
  });

  test('默认使用 Gitee，更新源选择持久化且可切回', () async {
    expect(await AppUpdateService.getPreferredSource(), UpdateSource.gitee);
    await AppUpdateService.setPreferredSource(UpdateSource.github);
    expect(await AppUpdateService.getPreferredSource(), UpdateSource.github);
    await AppUpdateService.setPreferredSource(UpdateSource.gitee);
    expect(await AppUpdateService.getPreferredSource(), UpdateSource.gitee);
  });

  for (final source in UpdateSource.values) {
    test('检查版本使用已保存的 ${source.label} 源，保留附件下载地址', () async {
      await AppUpdateService.setPreferredSource(source);
      final adapter = SessionHttpAdapter((request) {
        expect(
          request.uri.toString(),
          source == UpdateSource.gitee
              ? AppUpdateService.giteeLatestReleaseUrl
              : AppUpdateService.githubLatestReleaseUrl,
        );
        return sessionResponse(
          jsonEncode({
            'tag_name': 'v1.0.6',
            'assets': [
              {
                'name': 'app-release.apk',
                'browser_download_url':
                    'https://example.com/${source.name}.apk',
              },
            ],
          }),
        );
      });
      final service = AppUpdateService(dio: Dio()..httpClientAdapter = adapter);
      final release = await service.fetchLatest();
      expect(release.source, source);
      expect(
        release.apk!.downloadUrl,
        'https://example.com/${source.name}.apk',
      );
      expect(
        release.htmlUrl,
        source == UpdateSource.gitee
            ? AppUpdateService.giteeReleasesUrl
            : AppUpdateService.githubReleasesUrl,
      );
      expect(adapter.requests, hasLength(1));
    });
  }

  for (final latestBody in ['<html>Not Found</html>', '{}']) {
    test('Gitee latest 不可用时回退发布列表：$latestBody', () async {
      final adapter = SessionHttpAdapter((request) {
        if (request.uri.toString() == AppUpdateService.giteeLatestReleaseUrl) {
          return sessionResponse(
            latestBody,
            status: latestBody == '{}' ? 200 : 404,
          );
        }
        expect(request.uri.toString(), AppUpdateService.giteeReleasesListUrl);
        return sessionResponse('[{"tag_name":"v1.0.6"}]');
      });
      final release = await AppUpdateService(
        dio: Dio()..httpClientAdapter = adapter,
      ).fetchLatest();
      expect(release.version, '1.0.6');
      expect(release.source, UpdateSource.gitee);
      expect(adapter.requests, hasLength(2));
    });
  }

  test('Gitee 无发布版本时提示切换 GitHub，不静默跨源', () async {
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.toString() == AppUpdateService.giteeLatestReleaseUrl) {
        return sessionResponse('Not Found', status: 404);
      }
      expect(request.uri.toString(), AppUpdateService.giteeReleasesListUrl);
      return sessionResponse('[]');
    });
    await expectLater(
      AppUpdateService(dio: Dio()..httpClientAdapter = adapter).fetchLatest(),
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.message,
          'message',
          contains('切换为 GitHub'),
        ),
      ),
    );
    expect(adapter.requests, hasLength(2));
  });

  test('Gitee HTTP 错误不能当作有效版本', () async {
    final adapter = SessionHttpAdapter(
      (request) => sessionResponse('{"tag_name":"v9.9.9"}', status: 403),
    );
    await expectLater(
      AppUpdateService(dio: Dio()..httpClientAdapter = adapter).fetchLatest(),
      throwsA(isA<AppUpdateException>()),
    );
    expect(adapter.requests, hasLength(1));
  });

  for (final names in [
    ['app-debug.apk', 'app-release.apk'],
    ['app-release.apk', 'app-debug.apk'],
    ['app-arm64-v8a-release.apk', 'app-debug.apk', 'app-release.apk'],
  ]) {
    test('正式通用包优先，不依赖附件顺序 $names', () {
      final release = releaseWith(names);
      expect(release.apk!.name, 'app-release.apk');
      expect(release.assets.map((a) => a.name), names);
    });
  }

  test('支持大小写和自定义正式包名称，保留仅调试包、无安装包时的行为', () {
    expect(
      releaseWith(['app-debug.apk', 'APP-RELEASE.APK']).apk!.name,
      'APP-RELEASE.APK',
    );
    expect(
      releaseWith(['app-debug.apk', 'HunauBox-1.0.6-release.apk']).apk!.name,
      'HunauBox-1.0.6-release.apk',
    );
    expect(
      releaseWith(['app-debug.apk', 'HunauBox.apk']).apk!.name,
      'HunauBox.apk',
    );
    expect(
      releaseWith([
        'app-arm64-release.apk',
        'app-universal-release.apk',
      ]).apk!.name,
      'app-universal-release.apk',
    );
    expect(releaseWith(['app-debug.apk', 'app-beta.apk']).apk, isNull);
    expect(releaseWith(['notes.md', 'app-release.apk.sha256']).apk, isNull);
  });

  test('更新 API 保留 Markdown 原文，并且实际下载请求和落盘文件都为 release 包', () async {
    final directory = await Directory.systemTemp.createTemp(
      'hunau_update_test_',
    );
    // Only this test's freshly created temporary directory may be removed.
    addTearDown(() async {
      expect(
        directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
        isTrue,
      );
      expect(
        directory.uri.pathSegments.where((s) => s.isNotEmpty).last,
        startsWith('hunau_update_test_'),
      );
      await directory.delete(recursive: true);
    });
    const markdown = '# 1.0.6\n\n- **修复** 更新\n- 支持 `Markdown`';
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.toString() == AppUpdateService.latestReleaseUrl ||
          request.uri.toString() == AppUpdateService.giteeLatestReleaseUrl) {
        return sessionResponse(
          jsonEncode({
            'tag_name': 'v1.0.6',
            'body': markdown,
            'assets': [
              for (final name in ['app-debug.apk', 'app-release.apk'])
                {
                  'name': name,
                  'browser_download_url': 'https://example.com/$name',
                },
            ],
          }),
        );
      }
      expect(request.uri.path, '/app-release.apk');
      return ResponseBody.fromBytes(
        [1, 2, 3, 4],
        200,
        headers: {
          Headers.contentLengthHeader: ['4'],
        },
      );
    });
    final service = AppUpdateService(
      dio: Dio()..httpClientAdapter = adapter,
      documentsDirectory: () async => directory,
    );
    final release = await service.fetchLatest();
    expect(release.body, markdown);
    final file = await service.downloadApk(release);
    expect(file.uri.pathSegments.last, 'app-release.apk');
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect(adapter.requests, hasLength(2));
  });

  test('APK 优先写入公共 Download 目录，未提供时才回退应用目录', () async {
    final publicDir = await Directory.systemTemp.createTemp(
      'hunau_public_download_',
    );
    final docsDir = await Directory.systemTemp.createTemp('hunau_docs_');
    addTearDown(() async {
      for (final dir in [publicDir, docsDir]) {
        expect(
          dir.absolute.path.startsWith(Directory.systemTemp.absolute.path),
          isTrue,
        );
        await dir.delete(recursive: true);
      }
    });
    final adapter = SessionHttpAdapter((request) {
      if (request.uri.toString() == AppUpdateService.giteeLatestReleaseUrl) {
        return sessionResponse(
          jsonEncode({
            'tag_name': 'v1.0.6',
            'assets': [
              {
                'name': 'app-release.apk',
                'browser_download_url': 'https://example.com/app-release.apk',
              },
            ],
          }),
        );
      }
      return ResponseBody.fromBytes(
        [1, 2, 3, 4],
        200,
        headers: {
          Headers.contentLengthHeader: ['4'],
        },
      );
    });
    final service = AppUpdateService(
      dio: Dio()..httpClientAdapter = adapter,
      documentsDirectory: () async => docsDir,
      publicDownloadsDirectory: () async => publicDir,
    );
    final file = await service.downloadApk(await service.fetchLatest());
    expect(file.parent.path, publicDir.path);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
  });
}
