import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UpdateSource {
  gitee('Gitee', '国内高速节点 (默认推荐)'),
  github('GitHub', '国际源 (可能需代理)');

  const UpdateSource(this.label, this.description);
  final String label;
  final String description;
}

class AppReleaseAsset {
  const AppReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });
  final String name;
  final String downloadUrl;
  final int size;
}

class AppRelease {
  const AppRelease({
    required this.tag,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.assets,
    required this.prerelease,
    this.source = UpdateSource.gitee,
  });

  final String tag;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime? publishedAt;
  final List<AppReleaseAsset> assets;
  final bool prerelease;
  final UpdateSource source;

  /// 统一返回纯语义版本，例如从 `v1.0.6` 中解析出 `1.0.6`
  String get version {
    final match = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(tag);
    if (match == null) return tag.trim();
    return [
      match.group(1),
      match.group(2) ?? '0',
      match.group(3) ?? '0',
    ].join('.');
  }

  /// 优先选取正式版 APK 安装包
  AppReleaseAsset? get apk {
    final candidates = assets
        .where((asset) => asset.name.toLowerCase().endsWith('.apk'))
        .toList();
    int rank(AppReleaseAsset asset) {
      final name = asset.name.toLowerCase();
      if (RegExp(r'(^|[._-])debug([._-]|$)').hasMatch(name)) return 4;
      if (name == 'app-release.apk') return 0;
      if (RegExp(r'(^|[._-])release([._-]|$)').hasMatch(name)) {
        return name.contains('universal') ? 1 : 2;
      }
      return 3;
    }

    candidates.sort((a, b) {
      final priority = rank(a).compareTo(rank(b));
      return priority != 0
          ? priority
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return candidates.firstOrNull;
  }

  factory AppRelease.fromJson(
    Map<String, dynamic> json, {
    UpdateSource source = UpdateSource.gitee,
  }) {
    final assets = (json['assets'] is List ? json['assets'] as List : const [])
        .whereType<Map>()
        .map(
          (item) => AppReleaseAsset(
            name: '${item['name'] ?? ''}',
            downloadUrl: '${item['browser_download_url'] ?? ''}',
            size: int.tryParse('${item['size'] ?? 0}') ?? 0,
          ),
        )
        .where((asset) => asset.name.isNotEmpty && asset.downloadUrl.isNotEmpty)
        .toList();

    final tag = '${json['tag_name'] ?? ''}';
    var htmlUrl = '${json['html_url'] ?? ''}';
    if (htmlUrl.isEmpty) {
      htmlUrl = source == UpdateSource.gitee
          ? '${AppUpdateService.giteeRepositoryUrl}/releases'
          : '${AppUpdateService.githubRepositoryUrl}/releases';
    }

    return AppRelease(
      tag: tag,
      name: '${json['name'] ?? ''}',
      body: '${json['body'] ?? ''}',
      htmlUrl: htmlUrl,
      publishedAt: DateTime.tryParse(
        '${json['published_at'] ?? json['created_at'] ?? ''}',
      ),
      assets: assets,
      prerelease: json['prerelease'] == true,
      source: source,
    );
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AppUpdateService {
  AppUpdateService({Dio? dio, Future<Directory> Function()? documentsDirectory})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              followRedirects: false,
              validateStatus: (status) => status != null && status < 500,
            ),
          ),
      _documentsDirectory =
          documentsDirectory ?? getApplicationDocumentsDirectory;

  // Gitee 相关常量 (默认源)
  static const giteeRepositoryUrl = 'https://gitee.com/YaoZA233/HunauBox';
  static const giteeReleasesUrl =
      'https://gitee.com/YaoZA233/HunauBox/releases';
  static const giteeLatestReleaseUrl =
      'https://gitee.com/api/v5/repos/YaoZA233/HunauBox/releases/latest';
  static const giteeReleasesListUrl =
      'https://gitee.com/api/v5/repos/YaoZA233/HunauBox/releases?page=1&per_page=1';

  // GitHub 相关常量
  static const githubRepositoryUrl = 'https://github.com/YaoZA233/HunauBox';
  static const githubReleasesUrl =
      'https://github.com/YaoZA233/HunauBox/releases';
  static const githubLatestReleaseUrl =
      'https://api.github.com/repos/YaoZA233/HunauBox/releases/latest';

  // 兼容旧引用的 repositoryUrl 与 latestReleaseUrl
  static const repositoryUrl = githubRepositoryUrl;
  static const latestReleaseUrl = githubLatestReleaseUrl;

  static const _sourcePrefKey = 'app_update_channel_source';

  final Dio _dio;
  final Future<Directory> Function() _documentsDirectory;

  /// 获取用户设置的更新源，默认是 Gitee
  static Future<UpdateSource> getPreferredSource() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 1),
      );
      final val = prefs.getString(_sourcePrefKey);
      if (val == UpdateSource.github.name) {
        return UpdateSource.github;
      }
      return UpdateSource.gitee;
    } catch (_) {
      return UpdateSource.gitee;
    }
  }

  /// 保存用户选择的更新源
  static Future<void> setPreferredSource(UpdateSource source) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sourcePrefKey, source.name);
    } catch (_) {}
  }

  /// 检查最新版本 (支持可选位置参数以兼容子类重写)
  Future<AppRelease> fetchLatest([UpdateSource? source]) async {
    final effectiveSource = source ?? await getPreferredSource();

    if (effectiveSource == UpdateSource.gitee) {
      return _fetchLatestFromGitee();
    } else {
      return _fetchLatestFromGitHub();
    }
  }

  Future<AppRelease> _fetchLatestFromGitee() async {
    try {
      // 先尝试调用 Gitee 的 latest 接口
      final response = await _dio.get(
        giteeLatestReleaseUrl,
        options: Options(
          validateStatus: (status) => status == 200 || status == 404,
          headers: {'Accept': 'application/json', 'User-Agent': 'HunauBox-App'},
        ),
      );

      dynamic data = response.statusCode == 200 ? response.data : null;
      if (data is String) data = jsonDecode(data);

      // 如果 latest 返回 404 或无数据，尝试拉取 releases 列表
      if (data is! Map || '${data['tag_name'] ?? ''}'.trim().isEmpty) {
        final listResponse = await _dio.get(
          giteeReleasesListUrl,
          options: Options(
            validateStatus: (status) => status == 200,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'HunauBox-App',
            },
          ),
        );
        dynamic listData = listResponse.data;
        if (listData is String) listData = jsonDecode(listData);
        if (listData is! List) {
          throw const AppUpdateException('Gitee 返回的数据格式异常');
        }
        if (listData.isNotEmpty && listData.first is Map) {
          data = listData.first;
        } else {
          throw const AppUpdateException('Gitee 暂未发布版本，可在设置中切换为 GitHub 源');
        }
      }

      if (data is! Map) {
        throw const AppUpdateException('Gitee 返回的数据格式异常');
      }

      final release = AppRelease.fromJson(
        data.cast<String, dynamic>(),
        source: UpdateSource.gitee,
      );
      if (release.tag.isEmpty) {
        throw const AppUpdateException('没有在 Gitee 找到可用版本');
      }
      return release;
    } on AppUpdateException {
      rethrow;
    } catch (e) {
      throw AppUpdateException('无法从 Gitee 获取版本信息：$e');
    }
  }

  Future<AppRelease> _fetchLatestFromGitHub() async {
    try {
      final response = await _dio.get(
        githubLatestReleaseUrl,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'HunauBox-App',
          },
        ),
      );
      if (response.statusCode != 200) {
        throw AppUpdateException('GitHub 请求返回 HTTP ${response.statusCode}');
      }
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      if (data is! Map) throw const AppUpdateException('GitHub 返回的数据格式异常');
      final release = AppRelease.fromJson(
        data.cast<String, dynamic>(),
        source: UpdateSource.github,
      );
      if (release.tag.isEmpty) {
        throw const AppUpdateException('没有在 GitHub 找到可用版本');
      }
      return release;
    } on AppUpdateException {
      rethrow;
    } catch (_) {
      throw const AppUpdateException('暂时无法获取 GitHub 版本信息，请检查网络或切换为 Gitee 源');
    }
  }

  int compareVersions(String left, String right) {
    List<int> parts(String value) {
      final match = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(value);
      if (match == null) return const [0, 0, 0];
      return [
        int.tryParse(match.group(1) ?? '') ?? 0,
        int.tryParse(match.group(2) ?? '') ?? 0,
        int.tryParse(match.group(3) ?? '') ?? 0,
      ];
    }

    final a = parts(left), b = parts(right);
    for (var i = 0; i < 3; i++) {
      final result = (a.length > i ? a[i] : 0).compareTo(
        b.length > i ? b[i] : 0,
      );
      if (result != 0) return result;
    }
    return 0;
  }

  Future<File> downloadApk(
    AppRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    final asset = release.apk;
    if (asset == null) {
      throw AppUpdateException(
        '该版本尚未上传 APK 安装包，请前往 ${release.source.label} 发布页下载',
      );
    }
    final directory = await _documentsDirectory();
    final updateDirectory = Directory('${directory.path}/updates');
    await updateDirectory.create(recursive: true);
    final safeName = asset.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File('${updateDirectory.path}/$safeName');
    try {
      await _dio.download(
        asset.downloadUrl,
        file.path,
        onReceiveProgress: onProgress,
        options: Options(
          followRedirects: true,
          maxRedirects: 8,
          validateStatus: (status) => status == 200,
          headers: {
            'Accept': 'application/octet-stream',
            'User-Agent': 'HunauBox-App',
          },
        ),
      );
      if (!await file.exists() || await file.length() == 0) {
        throw const AppUpdateException('下载结果为空，请稍后重试');
      }
      return file;
    } catch (error) {
      if (error is AppUpdateException) rethrow;
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      throw const AppUpdateException('安装包下载失败，请稍后重试');
    }
  }
}
