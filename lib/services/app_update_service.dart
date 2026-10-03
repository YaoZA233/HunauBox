import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class AppReleaseAsset {
  const AppReleaseAsset({required this.name, required this.downloadUrl, required this.size});
  final String name;
  final String downloadUrl;
  final int size;
}

class AppRelease {
  const AppRelease({required this.tag, required this.name, required this.body, required this.htmlUrl, required this.publishedAt, required this.assets, required this.prerelease});
  final String tag;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime? publishedAt;
  final List<AppReleaseAsset> assets;
  final bool prerelease;

  /// GitHub 标签可能是 `v1.0.4`、`release-1.0.4` 或 `1.0.4+4`。
  /// 对外统一返回纯语义版本，避免标签前缀影响比较结果。
  String get version {
    final match = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(tag);
    if (match == null) return tag.trim();
    return [match.group(1), match.group(2) ?? '0', match.group(3) ?? '0'].join('.');
  }
  AppReleaseAsset? get apk => assets.where((asset) => asset.name.toLowerCase().endsWith('.apk')).firstOrNull;

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final assets = (json['assets'] is List ? json['assets'] as List : const [])
        .whereType<Map>()
        .map((item) => AppReleaseAsset(name: '${item['name'] ?? ''}', downloadUrl: '${item['browser_download_url'] ?? ''}', size: int.tryParse('${item['size'] ?? 0}') ?? 0))
        .where((asset) => asset.name.isNotEmpty && asset.downloadUrl.isNotEmpty)
        .toList();
    return AppRelease(tag: '${json['tag_name'] ?? ''}', name: '${json['name'] ?? ''}', body: '${json['body'] ?? ''}', htmlUrl: '${json['html_url'] ?? ''}', publishedAt: DateTime.tryParse('${json['published_at'] ?? ''}'), assets: assets, prerelease: json['prerelease'] == true);
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;
  @override String toString() => message;
}

class AppUpdateService {
  AppUpdateService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 12), receiveTimeout: const Duration(seconds: 20), followRedirects: false, validateStatus: (status) => status == 200));
  static const repositoryUrl = 'https://github.com/YaoZA233/HunauBox';
  static const latestReleaseUrl = 'https://api.github.com/repos/YaoZA233/HunauBox/releases/latest';
  final Dio _dio;

  Future<AppRelease> fetchLatest() async {
    try {
      final response = await _dio.get(latestReleaseUrl, options: Options(headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'HunauBox-App'}));
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      if (data is! Map) throw const AppUpdateException('GitHub 返回的数据格式异常');
      final release = AppRelease.fromJson(data.cast<String, dynamic>());
      if (release.tag.isEmpty) throw const AppUpdateException('没有找到可用版本');
      return release;
    } on AppUpdateException {
      rethrow;
    } catch (_) {
      throw const AppUpdateException('暂时无法获取 GitHub 版本信息，请检查网络后重试');
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
    for (var i = 0; i < 3; i++) { final result = (a.length > i ? a[i] : 0).compareTo(b.length > i ? b[i] : 0); if (result != 0) return result; }
    return 0;
  }

  Future<File> downloadApk(AppRelease release, {void Function(int received, int total)? onProgress}) async {
    final asset = release.apk;
    if (asset == null) throw const AppUpdateException('该版本没有可下载的 APK 安装包');
    final directory = await getApplicationDocumentsDirectory();
    final updateDirectory = Directory('${directory.path}/updates');
    await updateDirectory.create(recursive: true);
    final safeName = asset.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File('${updateDirectory.path}/$safeName');
    try {
      await _dio.download(asset.downloadUrl, file.path, onReceiveProgress: onProgress, options: Options(followRedirects: true, maxRedirects: 5, headers: {'Accept': 'application/octet-stream', 'User-Agent': 'HunauBox-App'}));
      if (!await file.exists() || await file.length() == 0) throw const AppUpdateException('下载结果为空，请稍后重试');
      return file;
    } catch (error) {
      if (error is AppUpdateException) rethrow;
      try { if (await file.exists()) await file.delete(); } catch (_) {}
      throw const AppUpdateException('安装包下载失败，请稍后重试');
    }
  }
}
