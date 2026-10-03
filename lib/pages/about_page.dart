import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_update_service.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});
  @override State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static final Uri _repositoryUri = Uri.parse(AppUpdateService.repositoryUrl);
  final _updateService = AppUpdateService();
  String _currentVersion = '1.0.3';
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
      if (mounted && info.version.isNotEmpty) setState(() => _currentVersion = info.version);
    } catch (_) {}
    await _checkForUpdate(silent: true);
  }

  Future<void> _checkForUpdate({required bool silent}) async {
    if (_checking) return;
    setState(() { _checking = true; _error = null; });
    try {
      final release = await _updateService.fetchLatest();
      if (!mounted) return;
      if (_updateService.compareVersions(release.version, _currentVersion) > 0) {
        setState(() => _release = release);
        if (mounted) _showReleaseSheet(release);
      } else {
        setState(() => _release = null);
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('当前已是最新版本 $_currentVersion')));
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _error = '$e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _download(AppRelease release, {VoidCallback? onChanged}) async {
    if (_downloading) return;
    setState(() { _downloading = true; _progress = 0; });
    onChanged?.call();
    try {
      final file = await _updateService.downloadApk(release, onProgress: (received, total) {
        if (mounted && total > 0) {
          setState(() => _progress = received / total);
          onChanged?.call();
        }
      });
      if (!mounted) return;
      setState(() => _downloadedPath = file.path);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('安装包已下载到应用目录')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _downloading = false);
      onChanged?.call();
    }
  }

  Future<void> _openReleasePage(AppRelease release) async {
    final launched = await launchUrl(Uri.parse(release.htmlUrl), mode: LaunchMode.externalApplication);
    if (!launched && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开版本发布页')));
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
                      Row(children: [
                        Expanded(child: Text('发现新版本 ${release.version}', style: Theme.of(sheetContext).textTheme.headlineSmall)),
                        Icon(Icons.auto_awesome_rounded, color: colors.primary),
                      ]),
                      const SizedBox(height: 8),
                      Text(release.name.isEmpty ? 'HunauBox 更新' : release.name, style: TextStyle(fontWeight: FontWeight.w700, color: colors.primary)),
                      if (release.publishedAt != null) ...[
                        const SizedBox(height: 6),
                        Text('发布时间：${_formatDate(release.publishedAt!)}', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                      ],
                      const SizedBox(height: 16),
                      Text(release.body.trim().isEmpty ? '本次更新暂无文字说明。' : release.body.trim(), style: const TextStyle(height: 1.55)),
                      const SizedBox(height: 16),
                      if (release.apk != null)
                        Text('安装包：${release.apk!.name}${release.apk!.size > 0 ? ' · ${_formatBytes(release.apk!.size)}' : ''}', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                      if (_downloadedPath != null)
                        Padding(padding: const EdgeInsets.only(top: 8), child: Text('已下载：$_downloadedPath', style: TextStyle(color: colors.primary, fontSize: 12))),
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(child: OutlinedButton(onPressed: () => _openReleasePage(release), child: const Text('打开发布页'))),
                        const SizedBox(width: 10),
                        Expanded(child: FilledButton.icon(
                          onPressed: _downloading || release.apk == null ? null : () => _download(release, onChanged: () => setSheetState(() {})),
                          icon: _downloading ? SizedBox(width: 17, height: 17, child: CircularProgressIndicator(value: _progress == 0 ? null : _progress, strokeWidth: 2)) : const Icon(Icons.download_rounded),
                          label: Text(_downloading ? '${(_progress * 100).round()}%' : release.apk == null ? '暂无 APK' : '下载 APK'),
                        )),
                      ]),
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

  String _formatBytes(int value) { if (value < 1024 * 1024) return '${(value / 1024).ceil()} KB'; return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB'; }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _openRepository(BuildContext context) async {
    final launched = await launchUrl(
      _repositoryUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开项目仓库链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于应用')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 36),
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.18),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/icon.png',
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'HunauBox',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '湖南农业大学校园生活服务',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '让校园事务更简单',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 10),
                Text('聚合课表、成绩、校园服务和常用工具，让信息随手可得。'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _AboutRow(
            icon: Icons.info_outline_rounded,
            label: '当前版本',
            value: _currentVersion,
          ),
          const SizedBox(height: 10),
          _AboutRow(
            icon: Icons.system_update_rounded,
            label: '检查软件更新',
            value: _checking ? '检查中…' : _release == null ? '点击检查' : '发现 ${_release!.version}',
            onTap: () => _checkForUpdate(silent: false),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: colors.error, fontSize: 12))),
          const SizedBox(height: 10),
          _AboutRow(
            icon: Icons.code_rounded,
            label: '开源项目',
            value: '查看 GitHub',
            onTap: () => _openRepository(context),
          ),
          const SizedBox(height: 32),
          Text(
            'HunauBox',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _AboutRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: colors.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(value, style: TextStyle(color: colors.onSurfaceVariant)),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
