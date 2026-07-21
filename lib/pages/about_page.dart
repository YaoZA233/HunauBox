import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static final Uri _repositoryUri = Uri.parse(
    'https://github.com/YaoZA233/HunauSmartCompusLife',
  );

  Future<void> _openRepository(BuildContext context) async {
    final launched = await launchUrl(
      _repositoryUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开项目仓库链接')),
      );
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
              child: Icon(Icons.school_rounded, size: 48, color: colors.primary),
            ),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'Life@HUNAU',
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
                Text('让校园事务更简单', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                SizedBox(height: 10),
                Text('聚合课表、成绩、校园服务和常用工具，让信息随手可得。'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _AboutRow(
            icon: Icons.info_outline_rounded,
            label: '当前版本',
            value: '1.0.0',
          ),
          const SizedBox(height: 10),
          _AboutRow(
            icon: Icons.code_rounded,
            label: '开源项目',
            value: '查看 GitHub',
            onTap: () => _openRepository(context),
          ),
          const SizedBox(height: 32),
          Text(
            'Life@HUNAU',
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
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(value, style: TextStyle(color: colors.onSurfaceVariant)),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.open_in_new_rounded, size: 18, color: colors.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
