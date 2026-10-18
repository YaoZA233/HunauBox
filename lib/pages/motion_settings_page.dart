import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/motion_settings.dart';
import '../providers/motion_provider.dart';
import '../widgets/app_motion.dart';

class MotionSettingsPage extends ConsumerStatefulWidget {
  const MotionSettingsPage({super.key});

  @override
  ConsumerState<MotionSettingsPage> createState() => _MotionSettingsPageState();
}

class _MotionSettingsPageState extends ConsumerState<MotionSettingsPage> {
  final _pages = PageController();
  final _scroll = ScrollController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _save(MotionSettings settings) async {
    try {
      await ref.read(motionSettingsProvider.notifier).update(settings);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('动画设置暂未保存，请重试')));
      }
    }
  }

  Future<void> _preview(MotionSettings settings) async {
    await _scroll.animateTo(
      0,
      duration: settings.reduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || !_pages.hasClients) return;
    final next = _page == 0 ? 1 : 0;
    if (settings.transition == AppTransition.none ||
        settings.reduced(context)) {
      _pages.jumpToPage(next);
    } else {
      _pages.animateToPage(
        next,
        duration: settings.duration(context),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(motionSettingsProvider);
    final colors = Theme.of(context).colorScheme;
    // Keep the preview correct even when this page is hosted by a test/theme
    // that does not install the application-wide extension.
    return Theme(
      data: Theme.of(context).copyWith(
        extensions: [
          ...Theme.of(
            context,
          ).extensions.values.where((e) => e is! MotionSettings),
          settings,
        ],
      ),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('动画与交互'),
            actions: [
              IconButton(
                tooltip: '播放预览',
                onPressed: () => _preview(settings),
                icon: const Icon(Icons.play_circle_outline_rounded),
              ),
            ],
          ),
          body: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('转场预览', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '左右滑动或点击预览。所选效果也会应用于页面打开、返回和周课表切换。',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: ColoredBox(
                        color: colors.surfaceContainerHighest,
                        child: PageView.builder(
                          key: const ValueKey('motion-preview'),
                          controller: _pages,
                          itemCount: 2,
                          onPageChanged: (index) =>
                              setState(() => _page = index),
                          itemBuilder: (context, index) => AppMotionPage(
                            controller: _pages,
                            index: index,
                            child: ColoredBox(
                              color: index == 0
                                  ? colors.primaryContainer
                                  : colors.secondaryContainer,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      index == 0
                                          ? Icons.calendar_month_outlined
                                          : Icons.view_agenda_outlined,
                                      color: index == 0
                                          ? colors.onPrimaryContainer
                                          : colors.onSecondaryContainer,
                                      size: 32,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      index == 0 ? '课程安排' : '今日课程',
                                      style: TextStyle(
                                        color: index == 0
                                            ? colors.onPrimaryContainer
                                            : colors.onSecondaryContainer,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '${_page + 1} / 2',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _preview(settings),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('预览转场'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('页面转场', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              RadioGroup<AppTransition>(
                groupValue: settings.transition,
                onChanged: (value) {
                  if (value != null) {
                    _save(settings.copyWith(transition: value));
                  }
                },
                child: Column(
                  children: [
                    for (final style in AppTransition.values)
                      RadioListTile<AppTransition>(
                        key: ValueKey('transition-${style.name}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        value: style,
                        title: Text(style.label),
                        subtitle: Text(style.description),
                        secondary: Icon(style.icon),
                      ),
                  ],
                ),
              ),
              const Divider(height: 32),
              Text('动画速度', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final speed in MotionSpeed.values)
                    ChoiceChip(
                      label: Text(speed.label),
                      selected: settings.speed == speed,
                      onSelected: (_) => _save(settings.copyWith(speed: speed)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('按压反馈'),
                subtitle: const Text('按住按钮和常用入口时轻微缩放，松开后回弹'),
                value: settings.pressFeedback,
                onChanged: (value) =>
                    _save(settings.copyWith(pressFeedback: value)),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('滑动边缘回弹'),
                subtitle: const Text('上下、左右滑动到边缘时提供柔和阻尼'),
                value: settings.bouncyScroll,
                onChanged: (value) =>
                    _save(settings.copyWith(bouncyScroll: value)),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('减少动态效果'),
                subtitle: Text(
                  MediaQuery.disableAnimationsOf(context)
                      ? '系统已开启减少动态效果，当前自动使用简化动画'
                      : '使用短淡入淡出，关闭透视、旋转、按压缩放和边缘回弹',
                ),
                value: settings.reduceMotion,
                onChanged: (value) =>
                    _save(settings.copyWith(reduceMotion: value)),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => _save(const MotionSettings()),
                icon: const Icon(Icons.restore_rounded),
                label: const Text('恢复默认动画'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
