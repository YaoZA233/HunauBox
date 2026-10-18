import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/agent_models.dart';
import 'app_markdown.dart';

class AgentMessageBubble extends StatelessWidget {
  const AgentMessageBubble({super.key, required this.message});
  final AgentDisplayMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final user = message.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .86,
        ),
        decoration: BoxDecoration(
          color: user
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    user ? '你' : 'Agent',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: user ? colors.onPrimaryContainer : colors.primary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '复制消息',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: message.text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('消息已复制')));
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
            if (message.reasoning.isNotEmpty)
              ExpansionTile(
                key: ValueKey('reasoning-${message.hashCode}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 16),
                title: const Text('思考内容', style: TextStyle(fontSize: 13)),
                subtitle: const Text('由模型服务返回', style: TextStyle(fontSize: 11)),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppMarkdown(
                      data: message.reasoning,
                      fontSize: 13,
                      textColor: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            AppMarkdown(
              data: message.text,
              textColor: message.incomplete
                  ? colors.error
                  : user
                  ? colors.onPrimaryContainer
                  : colors.onSurface,
            ),
            if (!user && !message.incomplete) ...[
              const SizedBox(height: 12),
              AgentUsageLine(
                usage: message.usage,
                model: message.model,
                durationMs: message.durationMs,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AgentUsageLine extends StatelessWidget {
  const AgentUsageLine({
    super.key,
    this.usage,
    this.model = '',
    this.durationMs,
  });
  final AgentTokenUsage? usage;
  final String model;
  final int? durationMs;

  @override
  Widget build(BuildContext context) {
    final stats = usage;
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodySmall!.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          if (model.isNotEmpty) Text(model),
          Text('输入 ${stats?.inputTokens ?? '未返回'} Token'),
          Text('输出 ${stats?.outputTokens ?? '未返回'} Token'),
          if (stats?.cachedTokens != null)
            Text('缓存 ${stats!.cachedTokens} Token'),
          if (stats?.reasoningTokens != null)
            Text('思考 ${stats!.reasoningTokens} Token'),
          if (durationMs != null)
            Text('本轮耗时 ${(durationMs! / 1000).toStringAsFixed(1)} 秒'),
          if (stats != null && stats.requests > 1)
            Text('含 ${stats.requests} 次模型请求'),
          if (stats != null && stats.reportedRequests < stats.requests)
            Text(
              stats.reportedRequests == 0
                  ? '服务商未返回完整用量'
                  : '用量不完整（${stats.reportedRequests}/${stats.requests} 次请求）',
            ),
        ],
      ),
    );
  }
}
