import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message_model.dart';
import '../providers/notice_provider.dart';
import 'notice_detail_screen.dart';

class NoticePage extends ConsumerStatefulWidget {
  const NoticePage({super.key});

  @override
  ConsumerState<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends ConsumerState<NoticePage>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  int _selectedFilter = 0;
  String _searchQuery = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.pixels <
            _scrollController.position.maxScrollExtent - 200) {
      return;
    }
    final noticeState = ref.read(noticeProvider);
    if (!noticeState.isLoading &&
        !noticeState.isLoadingMore &&
        noticeState.hasMore) {
      ref.read(noticeProvider.notifier).loadMore();
    }
  }

  Future<void> _refresh() => ref.read(noticeProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final noticeState = ref.watch(noticeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('通知')),
      body: _buildBody(noticeState),
    );
  }

  Widget _buildBody(NoticeState noticeState) {
    if (noticeState.isLoading && noticeState.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (noticeState.errorMessage != null && noticeState.messages.isEmpty) {
      return _buildErrorState();
    }

    final filteredMessages = _filterMessages(noticeState.messages);
    final unread = filteredMessages.where(_isUnread).toList();
    final visibleMessages = _selectedFilter == 0
        ? filteredMessages
        : unread;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _buildOverview(
                unreadCount: unread.length,
                totalCount: noticeState.messages.length,
                matchingCount: filteredMessages.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            sliver: SliverToBoxAdapter(child: _buildSearchField()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            sliver: SliverToBoxAdapter(child: _buildFilterControl()),
          ),
          if (noticeState.isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            ),
          if (visibleMessages.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(
                showUnreadOnly: _selectedFilter == 1,
                hasSearch: _searchQuery.trim().isNotEmpty,
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _NoticeItem(
                      message: visibleMessages[index],
                      onTap: () => _openNotice(visibleMessages[index]),
                    ),
                  ),
                  childCount: visibleMessages.length,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildLoadMoreState(noticeState)),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 92)),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final colors = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '搜索通知标题、正文或发布人',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: .7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.outlineVariant.withValues(alpha: .65)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.primary, width: 1.4),
        ),
      ),
    );
  }

  List<MessageModel> _filterMessages(List<MessageModel> messages) {
    final terms = _normalize(_searchQuery)
        .split(' ')
        .where((term) => term.isNotEmpty)
        .toList();
    if (terms.isEmpty) return messages;

    return messages.where((message) {
      final searchable = _normalize([
        message.title,
        message.content,
        message.createrName,
        message.sendTime,
        message.idCode,
      ].join(' '));
      return terms.every((term) => _fuzzyContains(searchable, term));
    }).toList();
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s,.;:!?，。；：！？、]+'), ' ')
        .trim();
  }

  bool _fuzzyContains(String source, String term) {
    if (source.contains(term)) return true;
    var index = 0;
    for (final character in source.split('')) {
      if (index < term.length && character == term[index]) index++;
    }
    return index == term.length;
  }

  Widget _buildOverview({
    required int unreadCount,
    required int totalCount,
    required int matchingCount,
  }) {
    final colors = Theme.of(context).colorScheme;
    final hasSearch = _searchQuery.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasSearch
              ? '找到 $matchingCount 条相关通知'
              : unreadCount == 0
              ? '消息已全部查看'
              : '有 $unreadCount 条消息未读',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          hasSearch
              ? '支持标题、正文、发布人和时间的模糊搜索'
              : totalCount == 0
              ? '下拉刷新以同步校园通知'
              : '最近共收到 $totalCount 条通知',
          style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildFilterControl() {
    final colors = Theme.of(context).colorScheme;
    const labels = ['全部', '未读'];
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = (constraints.maxWidth - 6) / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: _selectedFilter * segmentWidth,
                top: 0,
                width: segmentWidth,
                height: 38,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: List.generate(labels.length, (index) {
                  final selected = _selectedFilter == index;
                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => setState(() => _selectedFilter = index),
                      child: Center(
                        child: Text(
                          labels[index],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required bool showUnreadOnly,
    required bool hasSearch,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              showUnreadOnly
                  ? Icons.mark_email_read_outlined
                  : Icons.notifications_none_rounded,
              size: 44,
              color: colors.secondary,
            ),
            const SizedBox(height: 14),
            Text(
              hasSearch
                  ? '没有找到匹配的通知'
                  : showUnreadOnly
                  ? '暂时没有未读通知'
                  : '暂无通知',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              hasSearch ? '换个关键词或缩短搜索词试试' : '下拉即可同步最新消息',
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded, size: 44, color: colors.error),
                  const SizedBox(height: 14),
                  const Text(
                    '通知暂时无法同步',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '请检查登录状态后下拉重试',
                    style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreState(NoticeState state) {
    final colors = Theme.of(context).colorScheme;
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (state.hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          '已查看全部通知',
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      ),
    );
  }

  Future<void> _openNotice(MessageModel message) async {
    final targetId = message.uuid.isNotEmpty ? message.uuid : message.idCode;
    if (targetId.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoticeDetailScreen(noticeId: targetId)),
    );
  }

  bool _isUnread(MessageModel message) => !message.isRead || message.hasRedDot;
}

class _NoticeItem extends StatelessWidget {
  final MessageModel message;
  final VoidCallback onTap;

  const _NoticeItem({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unread = !message.isRead || message.hasRedDot;
    final accent = unread ? colors.primary : colors.outlineVariant;
    final sender = message.createrName.isEmpty ? '系统' : message.createrName;

    return Material(
      color: unread
          ? colors.surfaceContainerLowest
          : colors.surfaceContainerHighest.withValues(alpha: 0.26),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: unread
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  sender[0],
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: unread
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            message.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.3,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: unread
                                  ? colors.onSurface
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      message.content.replaceAll(RegExp(r'[\r\n]+'), ' '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        Icon(
                          Icons.account_circle_outlined,
                          size: 15,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            sender,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _formatTime(message.sendTime),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(String rawTime) {
    try {
      final parts = rawTime.split(' ');
      if (parts.length < 2) return rawTime;
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      return parts.first == today ? parts[1].substring(0, 5) : parts.first.substring(5);
    } catch (_) {
      return rawTime;
    }
  }
}
