import 'package:flutter/material.dart';

import '../services/app_cookie_manager.dart';
import '../services/chaoxing_course_service.dart';
import '../services/chaoxing_messages_service.dart';
import 'webview_detail_page.dart';

class ChaoxingMessagesPage extends StatefulWidget {
  const ChaoxingMessagesPage({super.key, this.createService});
  final ChaoxingMessagesService Function()? createService;

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
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    _service?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final old = _service;
    _service = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    await old?.dispose();
    if (!mounted || generation != _generation) return;
    final service = widget.createService?.call() ?? ChaoxingMessagesService();
    _service = service;
    try {
      await service.start();
      final result = await service.conversations();
      if (!mounted || generation != _generation) return;
      setState(() {
        _conversations = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = '消息暂时无法同步，请检查网络或重新登录学习通。';
      });
    }
  }

  Future<void> _openWeb() async {
    _generation++;
    final previous = _service;
    _service = null;
    if (mounted) setState(() => _loading = true);
    await previous?.dispose();
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
    if (mounted) await _load();
  }

  void _openConversation(ChaoxingConversation conversation) {
    final service = _service;
    if (service == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                _ConversationPage(conversation: conversation, service: service),
          ),
        )
        .then((_) {
          if (mounted) _load();
        });
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
        child: _loading
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
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 44,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _load, child: const Text('重新同步')),
                      TextButton(
                        onPressed: _openWeb,
                        child: const Text('打开学习通 / 登录'),
                      ),
                    ],
                  ),
                ),
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
                            Text(
                              '会话 · ${_conversations?.length ?? 0}',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '同步或打开会话可能会将消息标记为已读。',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _search,
                              onChanged: (value) =>
                                  setState(() => _query = value),
                              decoration: InputDecoration(
                                labelText: '搜索会话或消息摘要',
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
                                  borderRadius: BorderRadius.circular(16),
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
                            _query.isEmpty ? '暂无会话，下拉刷新' : '没有找到匹配的会话',
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        sliver: SliverList.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final c = entries[index];
                            return Card(
                              margin: EdgeInsets.zero,
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: colors.primaryContainer,
                                  child: Icon(
                                    Icons.forum_outlined,
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                                title: Text(
                                  c.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: c.preview.isEmpty
                                    ? null
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          c.preview,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                trailing: c.time.isEmpty
                                    ? const Icon(Icons.chevron_right_rounded)
                                    : Text(
                                        c.time,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                onTap: () => _openConversation(c),
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

class _ConversationPage extends StatefulWidget {
  const _ConversationPage({required this.conversation, required this.service});
  final ChaoxingConversation conversation;
  final ChaoxingMessagesService service;
  @override
  State<_ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<_ConversationPage> {
  late Future<List<ChaoxingChatMessage>> _messages;
  @override
  void initState() {
    super.initState();
    _messages = widget.service.messages(widget.conversation);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.conversation.name)),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<ChaoxingChatMessage>>(
          future: _messages,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('消息加载失败，请返回刷新会话或重试。'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(
                        () => _messages = widget.service.messages(
                          widget.conversation,
                        ),
                      ),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }
            final messages = snapshot.data ?? [];
            if (messages.isEmpty) {
              return const Center(child: Text('当前没有可显示的消息'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: messages.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      '显示学习通当前加载的消息；更早记录和附件请在网页中查看。',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  );
                }
                final message = messages[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          message.sender,
                          message.time,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: message.mine
                              ? colors.primaryContainer
                              : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SelectableText(message.text),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
