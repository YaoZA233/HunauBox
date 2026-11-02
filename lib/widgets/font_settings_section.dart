import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/font_provider.dart';

class FontSettingsSection extends ConsumerStatefulWidget {
  const FontSettingsSection({super.key});

  @override
  ConsumerState<FontSettingsSection> createState() =>
      _FontSettingsSectionState();
}

class _FontSettingsSectionState extends ConsumerState<FontSettingsSection> {
  bool _picking = false;

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is FontImportException ? error.message : '无法选择字体，请重试';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _choose() async {
    if (_picking) return;
    final picker = ref.read(fontFilePickerProvider);
    setState(() => _picking = true);
    try {
      final file = await picker();
      if (file == null || !mounted) return;
      await ref.read(appFontProvider.notifier).importFont(file);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('字体已应用')));
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _reset() async {
    try {
      await ref.read(appFontProvider.notifier).reset();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已恢复默认字体')));
      }
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final font = ref.watch(appFontProvider);
    final colors = Theme.of(context).colorScheme;
    final busy = _picking || font.loading || !font.ready;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('应用字体', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        Text(
          font.loading ? '正在加载字体…' : font.name ?? '当前使用系统默认字体',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          '支持导入 .ttf 字体；字体不包含的文字会使用系统字体。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (font.error != null) ...[
          const SizedBox(height: 8),
          Text(
            font.error!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.error),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : _choose,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(font.isCustom ? '更换字体' : '导入字体'),
            ),
            if (font.isCustom || font.error != null)
              TextButton(
                onPressed: busy ? null : _reset,
                child: const Text('恢复默认字体'),
              ),
          ],
        ),
      ],
    );
  }
}
