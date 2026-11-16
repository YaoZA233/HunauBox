import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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

  bool get isStable =>
      !prerelease &&
      RegExp(
        r'^v?\d+(?:\.\d+){0,2}(?:\+[0-9A-Za-z.-]+)?$',
        caseSensitive: false,
      ).hasMatch(tag.trim());

  /// 提取版本号并保留预发布后缀，例如 `v1.0.8-beta`。
  String get version {
    final match = RegExp(
      r'(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?',
    ).firstMatch(tag);
    if (match == null) return tag.trim();
    final base = [
      match.group(1),
      match.group(2) ?? '0',
      match.group(3) ?? '0',
    ].join('.');
    return match.group(4) == null ? base : '$base-${match.group(4)}';
  }

  /// 优先选取正式版 APK 安装包
  AppReleaseAsset? get apk {
    final candidates = assets
        .where(
          (asset) =>
              asset.name.toLowerCase().endsWith('.apk') &&
              !RegExp(
                r'(^|[._-])(debug|beta|alpha|rc)([._-]|$)',
                caseSensitive: false,
              ).hasMatch(asset.name),
        )
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
      prerelease: json['prerelease'] == true || json['draft'] == true,
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
  AppUpdateService({
    Dio? dio,
    Future<Directory> Function()? documentsDirectory,
    Future<Directory?> Function()? publicDownloadsDirectory,
  }) : _dio =
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
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _publicDownloadsDirectory =
           publicDownloadsDirectory ?? defaultPublicDownloadsDirectory;

  // Gitee 相关常量 (默认源)
  static const giteeRepositoryUrl = 'https://gitee.com/YaoZA233/HunauBox';
  static const giteeReleasesUrl =
      'https://gitee.com/YaoZA233/HunauBox/releases';
  static const giteeLatestReleaseUrl =
      'https://gitee.com/api/v5/repos/YaoZA233/HunauBox/releases/latest';
  static const giteeReleasesListUrl =
      'https://gitee.com/api/v5/repos/YaoZA233/HunauBox/releases?page=1&per_page=100';

  // GitHub 相关常量
  static const githubRepositoryUrl = 'https://github.com/YaoZA233/HunauBox';
  static const githubReleasesUrl =
      'https://github.com/YaoZA233/HunauBox/releases';
  static const githubLatestReleaseUrl =
      'https://api.github.com/repos/YaoZA233/HunauBox/releases/latest';
  static const githubReleasesListUrl =
      'https://api.github.com/repos/YaoZA233/HunauBox/releases?per_page=100&page=1';
  static const _downloadsChannel = MethodChannel('hunaubox/update_download');

  // 兼容旧引用的 repositoryUrl 与 latestReleaseUrl
  static const repositoryUrl = githubRepositoryUrl;
  static const latestReleaseUrl = githubLatestReleaseUrl;

  static const _sourcePrefKey = 'app_update_channel_source';

  /// Android 公共下载目录，用户可在文件管理器 Download 中找到安装包
  static const androidPublicDownloadPath = '/storage/emulated/0/Download';

  final Dio _dio;
  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory?> Function() _publicDownloadsDirectory;

  /// 返回可写的公共 Download 目录；不可用（非 Android / 无权限）时返回 null
  static Future<Directory?> defaultPublicDownloadsDirectory() async {
    if (!Platform.isAndroid) return null;
    final directory = Directory(androidPublicDownloadPath);
    if (await _isWritable(directory)) return directory;
    try {
      // Android 10 及以下写入公共目录需要存储权限，Android 11+ 探测已直接成功
      final status = await Permission.storage.request();
      if (status.isGranted && await _isWritable(directory)) return directory;
    } catch (_) {}
    return null;
  }

  static Future<bool> _isWritable(Directory directory) async {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final probe = File('${directory.path}/.hunau_box_write_probe');
      await probe.writeAsString('probe');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

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
      if (data is! Map ||
          '${data['tag_name'] ?? ''}'.trim().isEmpty ||
          !AppRelease.fromJson(data.cast<String, dynamic>()).isStable) {
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
        final candidates = listData
            .whereType<Map>()
            .map(
              (item) => AppRelease.fromJson(
                item.cast<String, dynamic>(),
                source: UpdateSource.gitee,
              ),
            )
            .where(
              (release) => release.tag.trim().isNotEmpty && release.isStable,
            )
            .toList();
        if (candidates.isNotEmpty) {
          candidates.sort((a, b) => compareVersions(b.version, a.version));
          return candidates.first;
        } else {
          throw const AppUpdateException('Gitee 暂未发布版本，可在设置中切换为 GitHub 源');
        }
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
      if (!release.isStable) {
        final list = await _dio.get(
          githubReleasesListUrl,
          options: Options(
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'HunauBox-App',
            },
          ),
        );
        dynamic data = list.data;
        if (data is String) data = jsonDecode(data);
        if (list.statusCode != 200 || data is! List) {
          throw const AppUpdateException('GitHub 发布列表不可用');
        }
        final candidates = data
            .whereType<Map>()
            .map(
              (item) => AppRelease.fromJson(
                item.cast<String, dynamic>(),
                source: UpdateSource.github,
              ),
            )
            .where((item) => item.tag.trim().isNotEmpty && item.isStable)
            .toList();
        if (candidates.isEmpty) throw const AppUpdateException('GitHub 暂无正式版本');
        candidates.sort((a, b) => compareVersions(b.version, a.version));
        return candidates.first;
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
    String? prerelease(String value) => RegExp(
      r'\d+(?:\.\d+)?(?:\.\d+)?-([0-9A-Za-z.-]+)',
    ).firstMatch(value)?.group(1);
    final first = prerelease(left), second = prerelease(right);
    if (first == null || second == null) {
      return first == second ? 0 : (first == null ? 1 : -1);
    }
    final aIds = first.split('.'), bIds = second.split('.');
    for (var i = 0; i < aIds.length && i < bIds.length; i++) {
      final aNum = int.tryParse(aIds[i]), bNum = int.tryParse(bIds[i]);
      final result = aNum != null && bNum != null
          ? aNum.compareTo(bNum)
          : aNum != null
          ? -1
          : bNum != null
          ? 1
          : aIds[i].compareTo(bIds[i]);
      if (result != 0) return result;
    }
    return aIds.length.compareTo(bIds.length);
  }

  Future<File> downloadApk(
    AppRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!release.isStable) throw const AppUpdateException('自动更新仅支持正式版本');
    final asset = release.apk;
    if (asset == null) {
      throw AppUpdateException(
        '该版本尚未上传 APK 安装包，请前往 ${release.source.label} 发布页下载',
      );
    }
    final publicDirectory = await _publicDownloadsDirectory();
    final useMediaStore = Platform.isAndroid && publicDirectory == null;
    final directory = publicDirectory ?? await _fallbackUpdateDirectory();
    final safeName = asset.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File('${directory.path}/$safeName');
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
      if (useMediaStore) {
        final path = await _downloadsChannel.invokeMethod<String>('saveApk', {
          'path': file.path,
          'name': safeName,
        });
        if (path == null || path.isEmpty) {
          throw const AppUpdateException('无法保存到 Download 目录');
        }
        await file.delete();
        return File(path);
      }
      return file;
    } catch (error) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      if (error is AppUpdateException) rethrow;
      throw const AppUpdateException('安装包下载失败，请稍后重试');
    }
  }

  Future<Directory> _fallbackUpdateDirectory() async {
    final directory = await _documentsDirectory();
    final updateDirectory = Directory('${directory.path}/updates');
    await updateDirectory.create(recursive: true);
    return updateDirectory;
  }
}
