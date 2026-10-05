import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/agent_models.dart';
import '../services/agent_conversation_store.dart';

class AgentHistorySheet extends ConsumerStatefulWidget {
  const AgentHistorySheet({super.key});
  @override
  ConsumerState<AgentHistorySheet> createState() => _AgentHistorySheetState();
}

class _AgentHistorySheetState extends ConsumerState<AgentHistorySheet> {
  String _query = '';

  Future<void> _action(String action, AgentConversation? conversation) async {
    final store = ref.read(agentConversationsProvider);
    try {
      if (action == 'rename' && conversation != null) {
        final title = await showDialog<String>(
          context: context,
          builder: (_) => _RenameConversationDialog(title: conversation.title),
        );
        if (title != null) await store.rename(conversation.id, title);
      } else {
        final all = action == 'clear';
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(all ? '删除全部会话？' : '删除此会话？'),
            content: const Text('删除设备上的聊天记录，已经完成的校园操作不会撤销。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        if (all) {
          await store.clear();
        } else if (conversation != null) {
          await store.delete(conversation.id);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is AgentException ? e.message : '聊天记录操作失败，请重试'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(agentConversationsProvider);
    final query = _query.toLowerCase();
    final rows = store.conversations
        .where(
          (c) =>
              c.title.toLowerCase().contains(query) ||
              c.messages.any((m) => m.text.toLowerCase().contains(query)),
        )
        .toList();
    return SafeArea(
      child: SizedBox(
        height:
            (MediaQuery.sizeOf(context).height * .82 -
                    MediaQuery.viewInsetsOf(context).bottom)
                .clamp(180, MediaQuery.sizeOf(context).height * .82),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '聊天记录',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '删除全部会话',
                    onPressed: store.conversations.isEmpty
                        ? null
                        : () => _action('clear', null),
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                  IconButton(
                    tooltip: '关闭聊天记录',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  hintText: '搜索标题或消息',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(query.isEmpty ? '还没有保存的会话' : '没有匹配的会话'),
                      )
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final c = rows[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            selected: c.id == store.activeId,
                            title: Text(
                              c.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${DateFormat('MM-dd HH:mm').format(c.updatedAt)} · ${c.messages.where((m) => m.role == 'user').length} 轮',
                              maxLines: 2,
                            ),
                            onTap: () => Navigator.pop(context, c.id),
                            trailing: PopupMenuButton<String>(
                              tooltip: '会话操作',
                              onSelected: (value) => _action(value, c),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('重命名'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const Text(
                '记录仅保存在本机，新建会话会保留已有对话。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameConversationDialog extends StatefulWidget {
  const _RenameConversationDialog({required this.title});
  final String title;
  @override
  State<_RenameConversationDialog> createState() =>
      _RenameConversationDialogState();
}

class _RenameConversationDialogState extends State<_RenameConversationDialog> {
  late final _controller = TextEditingController(text: widget.title);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('重命名会话'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: '会话标题'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('保存'),
      ),
    ],
  );
}
