import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/agent_settings_page.dart';
import '../services/agent_settings_store.dart';
import '../models/agent_models.dart';

class AgentSettingsSection extends ConsumerWidget {
  const AgentSettingsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(agentSettingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Agent',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('开启 Agent'),
                subtitle: const Text('开启后在左侧显示 Agent；关闭时仅保留功能、通知和作业'),
                value: store.config.enabled,
                onChanged: !store.loaded || store.saving || store.error != null
                    ? null
                    : (value) async {
                        if (value) {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('开启校园 Agent？'),
                              content: const Text(
                                '只有你主动发送消息后才调用模型。对话和查询所需的校园数据会发送到你配置的服务，请选择可信的服务商。充值和问卷提交仍由你手动确认操作。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('暂不开启'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('开启'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                        }
                        try {
                          await store.setEnabled(value);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e is AgentException ? e.message : '开关未保存，请重试',
                                ),
                              ),
                            );
                          }
                        }
                      },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('模型服务配置'),
                subtitle: Text(
                  store.config.isConfigured
                      ? '已配置 · ${store.config.model}'
                      : '填写服务 URL、API Key 和模型名称',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AgentSettingsPage(),
                  ),
                ),
              ),
              if (store.error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(store.error!),
                      TextButton(
                        onPressed: store.retryLoad,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}
