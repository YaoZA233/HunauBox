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
  int _selectedFilter = 0;

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

    final unread = noticeState.messages.where(_isUnread).toList();
    final visibleMessages = _selectedFilter == 0
        ? noticeState.messages
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
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
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
              child: _buildEmptyState(showUnreadOnly: _selectedFilter == 1),
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

  Widget _buildOverview({required int unreadCount, required int totalCount}) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          unreadCount == 0 ? '消息已全部查看' : '有 $unreadCount 条消息未读',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          totalCount == 0 ? '下拉刷新以同步校园通知' : '最近共收到 $totalCount 条通知',
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

  Widget _buildEmptyState({required bool showUnreadOnly}) {
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
              showUnreadOnly ? '暂时没有未读通知' : '暂无通知',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '下拉即可同步最新消息',
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
