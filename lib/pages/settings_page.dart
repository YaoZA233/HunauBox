import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/quick_action_item.dart';
import '../services/navigation_settings_store.dart';
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
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                  Text('${selected.length}/$_maxSelected', style: const TextStyle(color: Colors.black54)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('最多选择 8 个功能显示在首页。', style: TextStyle(color: Colors.black54)),
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
