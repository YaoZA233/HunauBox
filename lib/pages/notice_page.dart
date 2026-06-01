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

class _NoticePageState extends ConsumerState<NoticePage> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  
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
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final noticeState = ref.read(noticeProvider);
      if (!noticeState.isLoading && !noticeState.isLoadingMore && noticeState.hasMore) {
        ref.read(noticeProvider.notifier).loadMore();
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final noticeState = ref.watch(noticeProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _buildBody(noticeState),
    );
  }
  
  Widget _buildBody(NoticeState noticeState) {
    if (noticeState.isLoading && noticeState.messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载通知...'),
          ],
        ),
      );
    }
    
    if (noticeState.errorMessage != null && noticeState.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                noticeState.errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.read(noticeProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    
    if (noticeState.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '暂无通知',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '有新消息时会在这里显示',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark ? Colors.white38 : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      backgroundColor: Theme.of(context).cardColor,
      color: Theme.of(context).primaryColor,
      onRefresh: () => ref.read(noticeProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: noticeState.messages.length + (noticeState.hasMore ? 1 : 0),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), // 为悬浮导航栏留出空间
        itemBuilder: (context, index) {
          if (index == noticeState.messages.length) {
            return _buildLoadMoreIndicator(noticeState);
          }
          final message = noticeState.messages[index];
          return _buildMessageCard(message);
        },
      ),
    );
  }

  Widget _buildLoadMoreIndicator(NoticeState noticeState) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: noticeState.isLoadingMore
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('正在加载更多...', style: TextStyle(color: Colors.grey)),
                ],
              )
            : noticeState.hasMore 
                ? const SizedBox.shrink()
                : const Text('没有更多通知了', style: TextStyle(color: Colors.grey)),
      ),
    );
  }
  
  Widget _buildMessageCard(MessageModel message) {
    String timeDisplay = message.sendTime;
    try {
      final parts = message.sendTime.split(' ');
      if (parts.length > 1) {
        final date = parts[0];
        final time = parts[1];
        final now = DateTime.now();
        final String today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        timeDisplay = (date == today) ? time.substring(0, 5) : date.substring(5);
      }
    } catch (_) {}

    String initial = '通';
    if (message.createrName.isNotEmpty) {
      initial = message.createrName[0];
    }

    final isUnread = !message.isRead || message.hasRedDot;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          final targetId = message.uuid.isNotEmpty ? message.uuid : message.idCode;
          if (targetId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NoticeDetailScreen(noticeId: targetId),
              ),
            );
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.01),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            message.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                              color: isUnread ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 6),
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ]
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message.content.replaceAll('\r\n', ' ').replaceAll('\n', ' '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.person_outline, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8)),
                        const SizedBox(width: 4),
                        Text(
                          message.createrName,
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const Spacer(),
                        Icon(Icons.access_time_rounded, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.8)),
                        const SizedBox(width: 4),
                        Text(
                          timeDisplay,
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
}