import 'package:flutter/material.dart';

import '../services/app_cookie_manager.dart';
import '../services/chaoxing_course_service.dart';
import '../services/chaoxing_messages_service.dart';
import '../services/chaoxing_cache_store.dart';
import 'webview_detail_page.dart';

class ChaoxingMessagesPage extends StatefulWidget {
  const ChaoxingMessagesPage({super.key, this.createService, this.cache});
  final ChaoxingMessagesService Function()? createService;
  final ChaoxingCacheStore? cache;

  @override
  State<ChaoxingMessagesPage> createState() => _ChaoxingMessagesPageState();
}

class _ChaoxingMessagesPageState extends State<ChaoxingMessagesPage> {
  ChaoxingMessagesService? _service;
  final _search = TextEditingController();
  List<ChaoxingConversation>? _conversations;
  String _query = '';
  String? _error;
  bool _loading = true;
  bool _syncing = false;
  int _generation = 0;
  late final ChaoxingCacheStore _cache = widget.cache ?? ChaoxingCacheStore();
  String? _owner;
  Map<String, dynamic> _details = {};
  String? _refreshError;
  String? _syncedAt;

  String _detailKey(ChaoxingConversation c) => '${c.index}:${c.name}';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    _service?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    _owner = await _cache.account();
    final cached = await _cache.read('messages');
    if (!mounted) return;
    if (_owner != await _cache.account()) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '账号已切换，请重新打开消息页面。';
        });
      }
      return;
    }
    if (!mounted) return;
    if (cached != null && cached['conversations'] is List) {
      final conversations = ChaoxingMessagesService.parseConversations(
        cached['conversations'] as List,
      );
      final raw = cached['conversations'] as List;
      if (conversations.isNotEmpty && conversations.length == raw.length) {
        setState(() {
          _conversations = conversations;
          _details = cached['details'] is Map
              ? Map<String, dynamic>.from(cached['details'] as Map)
              : {};
          _syncedAt = cached['updatedAt'] as String?;
          _loading = false;
        });
        return;
      }
    }
    await _load();
  }

  Future<void> _save() => _cache.write(_owner, 'messages', {
    'conversations': (_conversations ?? []).map((c) => c.toJson()).toList(),
    'details': _details,
    'updatedAt': _syncedAt,
  });

  Future<void> _load() async {
    if (_syncing || !mounted) return;
    _syncing = true;
    final generation = ++_generation;
    final old = _service;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _refreshError = null;
      });
    }
    if (!mounted || generation != _generation) return;
    final service =
        old ?? widget.createService?.call() ?? ChaoxingMessagesService();
    _service = service;
    try {
      List<ChaoxingConversation> result;
      if (old == null) {
        await service.start();
        result = await service.conversations();
      } else {
        result = await service.refreshConversations();
      }
      if (result.isEmpty) result = await service.refreshConversations();
      if (result.isEmpty) throw StateError('学习通尚未返回有效会话');
      if (_owner != await _cache.account()) throw StateError('账号已切换');
      if (!mounted || generation != _generation) return;
      final preserved = <String, dynamic>{};
      for (final next in result) {
        final same = (_conversations ?? []).where(
          (old) =>
              old.index == next.index &&
              old.name == next.name &&
              old.preview == next.preview &&
              old.time == next.time,
        );
        final key = _detailKey(next);
        if (same.length == 1 && _details.containsKey(key)) {
          preserved[key] = _details[key];
        }
      }
      setState(() {
        _conversations = result;
        _details = preserved;
        _syncedAt = DateTime.now().toIso8601String();
        _loading = false;
      });
      await _save();
    } catch (_) {
      if (identical(_service, service)) _service = null;
      try {
        await service.dispose();
      } catch (_) {}
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        if (_conversations == null) {
          _error = '消息暂时无法同步，请检查网络或重新登录学习通。';
        } else {
          _refreshError = '刷新失败，正在显示上次的消息。';
        }
      });
    } finally {
      if (generation == _generation) _syncing = false;
    }
  }

  Future<void> _openWeb() async {
    _generation++;
    final previous = _service;
    _service = null;
    if (mounted) setState(() => _loading = _conversations == null);
    await previous?.dispose();
    _syncing = false;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const WebViewDetailPage(
          title: '学习通消息',
          url: ChaoxingMessagesService.url,
          userAgent: ChaoxingCourseService.desktopUserAgent,
          showWebBack: true,
        ),
      ),
    );
    if (!mounted) return;
    await AppCookieManager().syncMultiDomainCookiesFromWebView(null, [
      'https://passport2.chaoxing.com',
      'https://fe.chaoxing.com',
      'https://learn.chaoxing.com',
      'https://im.chaoxing.com',
    ]);
    if (mounted && _conversations == null) await _load();
  }

  Future<List<ChaoxingChatMessage>> _fetchMessages(
    ChaoxingConversation conversation,
  ) async {
    var service = _service;
    if (service == null) {
      service = widget.createService?.call() ?? ChaoxingMessagesService();
      _service = service;
      try {
        await service.start();
      } catch (_) {
        if (identical(_service, service)) _service = null;
        await service.dispose();
        rethrow;
      }
    }
    final live = await service.conversations();
    // Ordering, preview and timestamp can change after receiving new messages.
    // Only resolve an unambiguous name; never select the first duplicate.
    final matches = live.where((c) => c.name == conversation.name);
    if (matches.length != 1) throw StateError('会话已变化，请刷新列表');
    final messages = await service.messages(matches.single);
    if (messages.isEmpty) throw StateError('聊天内容尚未加载完成，请重试');
    if (_owner != await _cache.account()) throw StateError('账号已切换');
    if (mounted && identical(service, _service)) {
      _details[_detailKey(conversation)] = messages
          .map((m) => m.toJson())
          .toList();
      await _save();
    }
    return messages;
  }

  void _openConversation(ChaoxingConversation conversation) {
    final raw = _details[_detailKey(conversation)];
    final parsed = raw is List
        ? ChaoxingMessagesService.parseMessages(raw)
        : null;
    final cached =
        parsed != null &&
            parsed.isNotEmpty &&
            parsed.length == (raw as List).length
        ? parsed
        : null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ConversationPage(
          conversation: conversation,
          cached: cached,
          fetch: () => _fetchMessages(conversation),
        ),
      ),
    );
  }

  String get _syncLabel {
    final date = DateTime.tryParse(_syncedAt ?? '')?.toLocal();
    if (date == null) return '上次同步时间未知';
    String two(int value) => value.toString().padLeft(2, '0');
    return '上次同步 ${date.month}月${date.day}日 ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = (_conversations ?? [])
        .where(
          (c) => '${c.name} ${c.preview}'.toLowerCase().contains(
            _query.trim().toLowerCase(),
          ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习通消息'),
        actions: [
          IconButton(
            tooltip: '刷新消息',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '打开学习通消息网页',
            onPressed: _openWeb,
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading && _conversations == null
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在同步学习通消息…'),
                  ],
                ),
              )
            : _error != null
            ? _MessageRecovery(
                message: _error!,
                onRetry: _load,
                onOpenWeb: _openWeb,
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_loading) ...[
                              const LinearProgressIndicator(minHeight: 2),
                              const SizedBox(height: 12),
                            ],
                            if (_refreshError != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  _refreshError!,
                                  style: TextStyle(color: colors.error),
                                ),
                              ),
                            Row(
                              children: [
                                Text(
                                  '会话 · ${_conversations?.length ?? 0}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            Text(
                              _loading ? '正在同步，先显示上次的会话' : _syncLabel,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _search,
                              onChanged: (value) =>
                                  setState(() => _query = value),
                              decoration: InputDecoration(
                                hintText: '搜索会话或消息摘要',
                                filled: true,
                                fillColor: colors.surfaceContainerHighest
                                    .withValues(alpha: 0.38),
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: '清除搜索',
                                        onPressed: () {
                                          _search.clear();
                                          setState(() => _query = '');
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: colors.primary),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (entries.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            _query.isEmpty ? '会话尚未同步，请下拉重试' : '没有找到匹配的会话',
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        sliver: SliverList.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final c = entries[index];
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _openConversation(c),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _ConversationAvatar(name: c.name),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    c.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                ),
                                                if (c.time.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    c.time,
                                                    maxLines: 1,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: colors
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            if (c.preview.isNotEmpty) ...[
                                              const SizedBox(height: 5),
                                              Text(
                                                c.preview,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: colors
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 20,
                                        color: colors.outline,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initial = name.runes.isEmpty ? '通' : String.fromCharCode(name.runes.first);
    return CircleAvatar(
      radius: 24,
      backgroundColor: colors.secondaryContainer,
      foregroundColor: colors.onSecondaryContainer,
      child: Text(
        initial,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ConversationPage extends StatefulWidget {
  const _ConversationPage({
    required this.conversation,
    required this.cached,
    required this.fetch,
  });
  final ChaoxingConversation conversation;
  final List<ChaoxingChatMessage>? cached;
  final Future<List<ChaoxingChatMessage>> Function() fetch;
  @override
  State<_ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<_ConversationPage> {
  late Future<List<ChaoxingChatMessage>> _messages;
  List<ChaoxingChatMessage>? _last;
  bool _refreshing = false;
  late bool _fromCache = widget.cached != null;
  String? _error;
  @override
  void initState() {
    super.initState();
    _last = widget.cached;
    _messages = widget.cached != null
        ? Future.value(widget.cached)
        : widget.fetch();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final result = await widget.fetch();
      if (result.isEmpty) throw StateError('聊天内容尚未加载完成');
      if (mounted) {
        setState(() {
          _last = result;
          _fromCache = false;
          _messages = Future.value(result);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '消息刷新失败，请返回刷新会话或重试。');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.conversation.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '刷新会话',
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<ChaoxingChatMessage>>(
          future: _messages,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done &&
                _last == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError && _last == null) {
              return _MessageRecovery(
                message: '消息加载失败，请返回刷新会话或重试。',
                onRetry: _refresh,
                retryLabel: '重试',
              );
            }
            final messages = _last ?? snapshot.data ?? [];
            if (snapshot.hasData && _last == null) _last = snapshot.data;
            if (messages.isEmpty) {
              return Center(child: Text(_error ?? '当前没有可显示的消息'));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: messages.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: 0.48,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error ??
                            (_refreshing
                                ? '正在刷新，先显示已有消息…'
                                : _fromCache
                                ? '显示上次保存的消息。更早记录和附件请在网页中查看。'
                                : '更早记录和附件请在网页中查看。'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }
                final message = messages[index - 1];
                return _ChatMessageRow(
                  message: message,
                  maxBubbleWidth: MediaQuery.sizeOf(context).width * 0.76,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ChatMessageRow extends StatelessWidget {
  const _ChatMessageRow({
    required this.message,
    required this.maxBubbleWidth,
  });

  final ChaoxingChatMessage message;
  final double maxBubbleWidth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final incoming = !message.mine;
    final sender = message.sender.trim();
    final initial = sender.runes.isEmpty
        ? '通'
        : String.fromCharCode(sender.runes.first);
    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: incoming ? colors.surface : colors.primaryContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(incoming ? 3 : 12),
            bottomRight: Radius.circular(incoming ? 12 : 3),
          ),
          border: incoming ? Border.all(color: colors.outlineVariant) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: SelectableText(
            message.text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: incoming ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: incoming ? 42 : 0,
              right: incoming ? 0 : 2,
              bottom: 5,
            ),
            child: Wrap(
              spacing: 8,
              children: [
                Text(
                  incoming ? (sender.isEmpty ? '消息' : sender) : '我',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (message.time.isNotEmpty)
                  Text(
                    message.time,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.outline,
                    ),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: incoming
                ? MainAxisAlignment.start
                : MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (incoming) ...[
                CircleAvatar(
                  radius: 15,
                  backgroundColor: colors.secondaryContainer,
                  foregroundColor: colors.onSecondaryContainer,
                  child: Text(initial, style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(child: bubble),
              if (!incoming) const SizedBox(width: 4),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageRecovery extends StatelessWidget {
  const _MessageRecovery({
    required this.message,
    required this.onRetry,
    this.onOpenWeb,
    this.retryLabel = '重新同步',
  });
  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onOpenWeb;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          if (onOpenWeb != null)
            TextButton(onPressed: onOpenWeb, child: const Text('打开学习通 / 登录')),
        ],
      ),
    ),
  );
}
