import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/quick_action_item.dart';
import '../providers/background_provider.dart';
import '../services/app_update_service.dart';
import '../services/course_notification_service.dart';
import '../services/course_notification_settings_store.dart';
import '../services/quick_action_store.dart';
import '../providers/theme_provider.dart';
import '../utils/notification_debug_helper.dart';
import '../widgets/agent_settings_section.dart';
import '../providers/motion_provider.dart';
import 'motion_settings_page.dart';
import '../providers/weather_provider.dart';
import 'weather_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _store = QuickActionStore.instance;
  final _courseNotificationStore = CourseNotificationSettingsStore.instance;
  final _imagePicker = ImagePicker();
  static const int _maxSelected = 8;
  UpdateSource _updateSource = UpdateSource.gitee;

  final List<Color> _themeColors = [
    const Color(0xFF09C489), // ChillEast green
    const Color(0xFF7A5C46), // Cedar
    const Color(0xFFB05C4D), // Brick
    const Color(0xFF9A6A3A), // Ochre
    const Color(0xFF7A667C), // Plum
    const Color(0xFF536C7A), // Slate blue
    const Color(0xFF6F7B59), // Olive
    const Color(0xFF8A5363), // Berry
    const Color(0xFF4D7071), // Mineral
    const Color(0xFF6C6A62), // Graphite
  ];

  @override
  void initState() {
    super.initState();
    _store.load();
    _courseNotificationStore.load();
    _loadUpdateSource();
  }

  Future<void> _loadUpdateSource() async {
    final source = await AppUpdateService.getPreferredSource();
    if (mounted) setState(() => _updateSource = source);
  }

  Future<void> _selectUpdateSource() async {
    final selected = await showModalBottomSheet<UpdateSource>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '选择更新下载渠道',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.speed_rounded),
                  title: const Text('Gitee (默认推荐)'),
                  subtitle: const Text('国内高速线路，下载速度稳定迅速'),
                  trailing: _updateSource == UpdateSource.gitee
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, UpdateSource.gitee),
                ),
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: const Text('GitHub (国际线路)'),
                  subtitle: const Text('官方开源仓库，部分网络环境可能较慢'),
                  trailing: _updateSource == UpdateSource.github
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, UpdateSource.github),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && selected != _updateSource) {
      await AppUpdateService.setPreferredSource(selected);
      if (mounted) {
        setState(() => _updateSource = selected);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已将更新渠道切换为 ${selected.label}')));
      }
    }
  }

  Future<void> _pickBackground(WidgetRef ref) async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (image == null) return;
      await ref.read(appBackgroundProvider.notifier).importImage(image.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法读取所选图片，请检查相册权限')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Consumer(
        builder: (context, ref, _) {
          final hasBackground = ref.watch(appBackgroundProvider).hasImage;
          return ValueListenableBuilder<List<String>>(
            valueListenable: _store.selectedIds,
            builder: (context, selectedIds, _) {
              final selected = selectedIds.toSet();
              final children = [
                const AgentSettingsSection(),
                Consumer(
                  builder: (context, ref, _) {
                    final weather = ref.watch(weatherProvider);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.wb_sunny_outlined),
                      title: const Text('天气与位置'),
                      subtitle: Text(
                        !weather.settings.enabled
                            ? '天气已关闭'
                            : weather.settings.useDeviceLocation
                            ? '使用设备当前位置'
                            : weather.settings.manualLocation?.description ??
                                  '手动选择城市',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const WeatherSettingsPage(),
                        ),
                      ),
                    );
                  },
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final motion = ref.watch(motionSettingsProvider);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.animation_rounded),
                      title: const Text('动画与交互'),
                      subtitle: Text(
                        '${motion.transition.label} · ${motion.speed.label}${motion.reduceMotion ? ' · 减少动态效果' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const MotionSettingsPage(),
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 32),
                const Text(
                  '主题设置',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Consumer(
                  builder: (context, ref, child) {
                    final currentColor = ref.watch(themeColorProvider);
                    final currentMode = ref.watch(themeModeProvider);
                    final background = ref.watch(appBackgroundProvider);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('显示模式', style: TextStyle(fontSize: 16)),
                        ),
                        SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('白天'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('黑夜'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_outlined),
                              label: Text('跟随系统'),
                            ),
                          ],
                          selected: {currentMode},
                          onSelectionChanged: (selection) {
                            ref
                                .read(themeModeProvider.notifier)
                                .updateThemeMode(selection.first);
                          },
                        ),
                        const SizedBox(height: 24),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12.0),
                          child: Text('主题配色', style: TextStyle(fontSize: 16)),
                        ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _themeColors.map((color) {
                            final isSelected =
                                currentColor.toARGB32() == color.toARGB32();
                            return GestureDetector(
                              onTap: () {
                                ref
                                    .read(themeColorProvider.notifier)
                                    .updateThemeColor(color);
                              },
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: Colors.black87,
                                          width: 3,
                                        )
                                      : Border.all(
                                          color: Colors.transparent,
                                          width: 0,
                                        ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.4),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        const Text('自定义背景', style: TextStyle(fontSize: 16)),
                        const SizedBox(height: 12),
                        if (background.hasImage) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: double.infinity,
                              height: 150,
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: background.blurSigma,
                                  sigmaY: background.blurSigma,
                                ),
                                child: Transform.scale(
                                  scale: 1.04,
                                  child: Image.file(
                                    File(background.imagePath!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => ColoredBox(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      child: const Center(
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickBackground(ref),
                                icon: const Icon(Icons.image_outlined),
                                label: Text(
                                  background.hasImage ? '更换图片' : '选择图片',
                                ),
                              ),
                            ),
                            if (background.hasImage) ...[
                              const SizedBox(width: 10),
                              IconButton.outlined(
                                onPressed: () => ref
                                    .read(appBackgroundProvider.notifier)
                                    .clear(),
                                tooltip: '清除背景',
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ],
                        ),
                        if (background.hasImage) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Expanded(child: Text('高斯模糊')),
                              Text(
                                background.blurSigma.toStringAsFixed(0),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: background.blurSigma,
                            min: 0,
                            max: 30,
                            divisions: 30,
                            label: background.blurSigma.toStringAsFixed(0),
                            onChanged: (value) => ref
                                .read(appBackgroundProvider.notifier)
                                .updateBlur(value),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                const Text(
                  '通知设置',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<CourseNotificationSettings>(
                  valueListenable: _courseNotificationStore.settings,
                  builder: (context, settings, _) {
                    return Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('下一节课提醒'),
                          subtitle: Text(
                            settings.enabled
                                ? '将在上课前${settings.minutesBefore}分钟通知你'
                                : '开启后将按已导入课表发送提醒',
                          ),
                          value: settings.enabled,
                          onChanged: (enabled) async {
                            if (enabled) {
                              final granted = await CourseNotificationService
                                  .instance
                                  .requestPermission();
                              if (!granted) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('请在系统设置中允许通知权限'),
                                    ),
                                  );
                                }
                                return;
                              }
                            }

                            final updated = settings.copyWith(enabled: enabled);
                            await _courseNotificationStore.save(updated);
                            if (enabled) {
                              await CourseNotificationService.instance
                                  .reschedule(
                                    minutesBefore: updated.minutesBefore,
                                  );
                            } else {
                              await CourseNotificationService.instance
                                  .rescheduleIfEnabled();
                            }
                          },
                        ),
                        if (settings.enabled)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: DropdownButtonFormField<int>(
                              initialValue: settings.minutesBefore,
                              decoration: const InputDecoration(
                                labelText: '提前通知时间',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [10, 15, 20, 30]
                                  .map(
                                    (minutes) => DropdownMenuItem(
                                      value: minutes,
                                      child: Text('提前$minutes分钟'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (minutes) async {
                                if (minutes == null) return;
                                final updated = settings.copyWith(
                                  minutesBefore: minutes,
                                );
                                await _courseNotificationStore.save(updated);
                                await CourseNotificationService.instance
                                    .reschedule(minutesBefore: minutes);
                              },
                            ),
                          ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('新消息通知'),
                          subtitle: const Text('有新的校园通知时提醒你'),
                          value: settings.messageEnabled,
                          onChanged: (enabled) async {
                            if (enabled) {
                              final granted = await CourseNotificationService
                                  .instance
                                  .requestPermission();
                              if (!granted) return;
                            }
                            await _courseNotificationStore.save(
                              settings.copyWith(messageEnabled: enabled),
                            );
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('新作业通知'),
                          subtitle: const Text('有新的待完成作业时提醒你'),
                          value: settings.homeworkEnabled,
                          onChanged: (enabled) async {
                            if (enabled) {
                              final granted = await CourseNotificationService
                                  .instance
                                  .requestPermission();
                              if (!granted) return;
                            }
                            await _courseNotificationStore.save(
                              settings.copyWith(homeworkEnabled: enabled),
                            );
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('作业截止提醒'),
                          subtitle: Text(
                            settings.homeworkDeadlineEnabled
                                ? '将在截止前${settings.homeworkMinutesBefore}分钟通知你'
                                : '开启后提醒待完成作业的截止时间',
                          ),
                          value: settings.homeworkDeadlineEnabled,
                          onChanged: (enabled) async {
                            if (enabled) {
                              final granted = await CourseNotificationService
                                  .instance
                                  .requestPermission();
                              if (!granted) return;
                            }
                            await _courseNotificationStore.save(
                              settings.copyWith(
                                homeworkDeadlineEnabled: enabled,
                              ),
                            );
                            await CourseNotificationService.instance
                                .rescheduleIfEnabled();
                          },
                        ),
                        if (settings.homeworkDeadlineEnabled)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: DropdownButtonFormField<int>(
                              initialValue: settings.homeworkMinutesBefore,
                              decoration: const InputDecoration(
                                labelText: '作业截止提前提醒时间',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [10, 15, 20, 30]
                                  .map(
                                    (minutes) => DropdownMenuItem(
                                      value: minutes,
                                      child: Text('提前$minutes分钟'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (minutes) async {
                                if (minutes == null) return;
                                await _courseNotificationStore.save(
                                  settings.copyWith(
                                    homeworkMinutesBefore: minutes,
                                  ),
                                );
                                await CourseNotificationService.instance
                                    .rescheduleIfEnabled();
                              },
                            ),
                          ),
                        if (kDebugMode)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('正在检查通知状态...')),
                                );
                                await NotificationDebugHelper.printDiagnostics();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('通知诊断已输出到日志')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.bug_report_outlined),
                              label: const Text('诊断通知状态'),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                const Text(
                  '主页设置',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('常用服务'),
                  subtitle: Text(
                    '已选择 ${selected.length} 个服务，最多 $_maxSelected 个',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const CommonServicesSettingsPage(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                const Text(
                  '软件更新',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: const Text('更新下载渠道'),
                  subtitle: Text(
                    '${_updateSource.label} (${_updateSource == UpdateSource.gitee ? '国内高速推荐' : '国际源'})',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _selectUpdateSource,
                ),
              ];

              // Wrap content with semi-transparent background for better readability
              if (!hasBackground) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: children,
                );
              }

              return Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: children,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class CommonServicesSettingsPage extends StatelessWidget {
  const CommonServicesSettingsPage({super.key});

  static const int _maxSelected = 8;

  @override
  Widget build(BuildContext context) {
    final store = QuickActionStore.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('常用服务设置')),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: store.selectedIds,
        builder: (context, selectedIds, _) {
          final selected = selectedIds.toSet();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选择常用服务',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${selected.length}/$_maxSelected',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '最多选择 8 个功能显示在首页。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              ...QuickActionCatalog.items.map((item) {
                final isChecked = selected.contains(item.id);
                return CheckboxListTile(
                  value: isChecked,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.label),
                  secondary: Icon(item.icon),
                  onChanged: (value) async {
                    if (value == null) return;
                    final ids = List<String>.from(selected);
                    if (value) {
                      if (ids.length >= _maxSelected) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('最多只能选择 8 个')),
                        );
                        return;
                      }
                      ids.add(item.id);
                    } else {
                      ids.remove(item.id);
                    }
                    await store.save(ids);
                  },
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
