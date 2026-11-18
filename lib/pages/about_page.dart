import 'package:flutter/material.dart';
import '../models/app_version.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_update_notifier.dart';
import '../services/app_update_service.dart';
import '../widgets/app_markdown.dart';
import '../widgets/app_ui_kit.dart';
import '../widgets/campus_loading_mark.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    this.updateService,
    this.updateNotifier,
    this.openInstaller,
  });
  final AppUpdateService? updateService;
  final AppUpdateNotifier? updateNotifier;
  final Future<bool> Function(String path)? openInstaller;
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static final Uri _githubRepositoryUri = Uri.parse(
    AppUpdateService.githubRepositoryUrl,
  );
  static final Uri _giteeRepositoryUri = Uri.parse(
    AppUpdateService.giteeRepositoryUrl,
  );

  late final _updateService = widget.updateService ?? AppUpdateService();
  late final _updateNotifier = widget.updateNotifier ?? AppUpdateNotifier();
  String _currentVersion = fallbackAppVersion;
  UpdateSource _currentSource = UpdateSource.gitee;
  AppRelease? _release;
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  String? _downloadedPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVersionAndCheck();
  }

  Future<void> _loadVersionAndCheck() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted && info.version.isNotEmpty) {
        setState(() => _currentVersion = info.version);
      }
    } catch (_) {}

    try {
      final source = await AppUpdateService.getPreferredSource();
      if (mounted) setState(() => _currentSource = source);
    } catch (_) {}

    await _checkForUpdate(silent: true);
  }

  Future<void> _checkForUpdate({required bool silent}) async {
    if (!mounted || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      try {
        final source = await AppUpdateService.getPreferredSource();
        if (mounted) setState(() => _currentSource = source);
      } catch (_) {}
      final release = await _updateService.fetchLatest(_currentSource);
      if (!mounted) return;
      if (_updateService.compareVersions(release.version, _currentVersion) >
          0) {
        setState(() => _release = release);
        if (mounted) _showReleaseSheet(release);
      } else {
        setState(() => _release = null);
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '当前已是最新版本 $_currentVersion (${_currentSource.label} 源)',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _error = '$e');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _download(AppRelease release, {VoidCallback? onChanged}) async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    onChanged?.call();
    await _updateNotifier.requestPermission();
    Future<void> notification = Future.value();
    try {
      await _updateNotifier.showProgress(received: 0, total: 0);
      final file = await _updateService.downloadApk(
        release,
        onProgress: (received, total) {
          notification = notification.then(
            (_) =>
                _updateNotifier.showProgress(received: received, total: total),
          );
          if (mounted && total > 0) {
            setState(() => _progress = received / total);
            onChanged?.call();
          }
        },
      );
      await notification;
      await _updateNotifier.showCompleted(file.uri.pathSegments.last);
      if (!mounted) return;
      setState(() => _downloadedPath = file.path);
      final installResult = await (widget.openInstaller ?? _openInstaller)(
        file.path,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            installResult
                ? '安装包已保存到 Download 目录，正在打开安装界面'
                : '安装包已保存到 ${file.path}，请手动点击安装',
          ),
        ),
      );
    } catch (e) {
      await notification;
      await _updateNotifier.showFailed('$e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
      onChanged?.call();
    }
  }

  /// 调用系统安装器打开 APK；返回是否成功拉起安装界面
  Future<bool> _openInstaller(String path) async {
    try {
      final result = await OpenFilex.open(path);
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openReleasePage(AppRelease release) async {
    final launched = await launchUrl(
      Uri.parse(release.htmlUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开版本发布页')));
    }
  }

  void _showReleaseSheet(AppRelease release) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '发现新版本 ${release.version}',
                              style: Theme.of(
                                sheetContext,
                              ).textTheme.headlineSmall,
                            ),
                          ),
                          AppBadge(
                            label: '${release.source.label} 源',
                            variant: AppBadgeVariant.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        release.name.isEmpty ? 'HunauBox 更新' : release.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                        ),
                      ),
                      if (release.publishedAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '发布时间：${_formatDate(release.publishedAt!)}',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      AppMarkdown(
                        data: release.body.trim().isEmpty
                            ? '本次更新暂无文字说明。'
                            : release.body.trim(),
                        baseUri: Uri.tryParse(release.htmlUrl),
                      ),
                      const SizedBox(height: 16),
                      if (release.apk != null)
                        Text(
                          '安装包：${release.apk!.name}${release.apk!.size > 0 ? ' · ${_formatBytes(release.apk!.size)}' : ''}',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      if (_downloadedPath != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '已下载：$_downloadedPath',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _openReleasePage(release),
                              child: const Text('打开发布页'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _downloading || release.apk == null
                                  ? null
                                  : () => _download(
                                      release,
                                      onChanged: () {
                                        if (sheetContext.mounted) {
                                          setSheetState(() {});
                                        }
                                      },
                                    ),
                              icon: _downloading
                                  ? SizedBox(
                                      width: 17,
                                      height: 17,
                                      child: CircularProgressIndicator(
                                        value: _progress == 0
                                            ? null
                                            : _progress,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.download_rounded),
                              label: Text(
                                _downloading
                                    ? '${(_progress * 100).round()}%'
                                    : release.apk == null
                                    ? '前往网页下载'
                                    : '下载 APK',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatBytes(int value) {
    if (value < 1024 * 1024) return '${(value / 1024).ceil()} KB';
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _openUrl(BuildContext context, Uri uri, String label) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开 $label 链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于应用')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'HunauBox',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '湖南农业大学校园生活服务',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  '课表、成绩、学习通与校园服务，集中在一个地方。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                _AboutSectionLabel('软件信息'),
                const SizedBox(height: 4),
                _AboutRow(label: '当前版本', detail: _currentVersion),
                const Divider(height: 1),
                _AboutRow(
                  label: '检查软件更新',
                  detail: _checking
                      ? '正在检查…'
                      : _release == null
                      ? '更新源：${_currentSource.label}'
                      : '发现新版本 ${_release!.version} · ${_currentSource.label}',
                  onTap: _checking
                      ? null
                      : () => _checkForUpdate(silent: false),
                  showProgress: _checking,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 32),
                _AboutSectionLabel('项目仓库'),
                const SizedBox(height: 4),
                _AboutRow(
                  label: 'Gitee 仓库',
                  detail: '国内访问推荐',
                  external: true,
                  onTap: () =>
                      _openUrl(context, _giteeRepositoryUri, 'Gitee 仓库'),
                ),
                const Divider(height: 1),
                _AboutRow(
                  label: 'GitHub 仓库',
                  detail: '查看源代码与版本发布',
                  external: true,
                  onTap: () =>
                      _openUrl(context, _githubRepositoryUri, 'GitHub 仓库'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutSectionLabel extends StatelessWidget {
  const _AboutSectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String detail;
  final VoidCallback? onTap;
  final bool external;
  final bool showProgress;

  const _AboutRow({
    required this.label,
    required this.detail,
    this.onTap,
    this.external = false,
    this.showProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 14,
      title: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          detail,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ),
      trailing: showProgress
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CampusLoadingMark(size: 18),
            )
          : onTap == null
          ? null
          : Icon(
              external
                  ? Icons.open_in_new_rounded
                  : Icons.chevron_right_rounded,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
      onTap: onTap,
    );
  }
}
