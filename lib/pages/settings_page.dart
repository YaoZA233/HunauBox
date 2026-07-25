import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/quick_action_item.dart';
import '../services/navigation_settings_store.dart';
import '../services/course_notification_service.dart';
import '../services/course_notification_settings_store.dart';
import '../services/quick_action_store.dart';
import '../providers/theme_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _store = QuickActionStore.instance;
  final _navStore = NavigationSettingsStore.instance;
  final _courseNotificationStore = CourseNotificationSettingsStore.instance;
  static const int _maxSelected = 8;
  
  final List<Color> _themeColors = [
    const Color(0xFF1A73E8), // Google Blue (Default)
    const Color(0xFFE53935), // Google Red
    const Color(0xFF43A047), // Google Green
    const Color(0xFFFB8C00), // Google Orange
    const Color(0xFFD81B60), // Pink
    const Color(0xFF8E24AA), // Purple
    const Color(0xFF3949AB), // Deep Purple
    const Color(0xFF039BE5), // Indigo
    const Color(0xFF00ACC1), // Light Blue
    const Color(0xFF00897B), // Teal
  ];

  @override
  void initState() {
    super.initState();
    _store.load();
    _navStore.load();
    _courseNotificationStore.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: _store.selectedIds,
        builder: (context, selectedIds, _) {
          final selected = selectedIds.toSet();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('主题设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Consumer(
                builder: (context, ref, child) {
                  final currentColor = ref.watch(themeColorProvider);
                  final currentMode = ref.watch(themeModeProvider);
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
                          final isSelected = currentColor.value == color.value;
                          return GestureDetector(
                            onTap: () {
                              ref.read(themeColorProvider.notifier).updateThemeColor(color);
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: isSelected 
                                    ? Border.all(color: Colors.black87, width: 3)
                                    : Border.all(color: Colors.transparent, width: 0),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withOpacity(0.4),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              const Text('上课通知', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                            final granted = await CourseNotificationService.instance
                                .requestPermission();
                            if (!granted) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('请在系统设置中允许通知权限')),
                                );
                              }
                              return;
                            }
                          }

                          final updated = settings.copyWith(enabled: enabled);
                          await _courseNotificationStore.save(updated);
                          if (enabled) {
                            await CourseNotificationService.instance.reschedule(
                              minutesBefore: updated.minutesBefore,
                            );
                          } else {
                            await CourseNotificationService.instance.cancelAll();
                          }
                        },
                      ),
                      if (settings.enabled)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: DropdownButtonFormField<int>(
                            value: settings.minutesBefore,
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
                              final updated =
                                  settings.copyWith(minutesBefore: minutes);
                              await _courseNotificationStore.save(updated);
                              await CourseNotificationService.instance.reschedule(
                                minutesBefore: minutes,
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              const Text('导航栏', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ValueListenableBuilder<bool>(
                valueListenable: _navStore.useFloatingNav,
                builder: (context, useFloatingNav, __) {
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('使用悬浮导航栏'),
                    subtitle: const Text('仿 Telegram 的悬浮样式'),
                    value: useFloatingNav,
                    onChanged: (value) async {
                      await _navStore.save(value);
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              const Text('主页设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('常用服务'),
                subtitle: Text('已选择 ${selected.length} 个服务，最多 $_maxSelected 个'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CommonServicesSettingsPage(),
                    ),
                  );
                },
              ),
            ],
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
                  const Text('选择常用服务', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    '${selected.length}/$_maxSelected',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '最多选择 8 个功能显示在首页。',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
