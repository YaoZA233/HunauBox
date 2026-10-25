import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/electricity_model.dart';
import '../models/homework_model.dart';
import '../providers/homework_provider.dart';
import '../providers/notice_provider.dart';
import '../services/auth_guard.dart';
import '../services/campus_card_service.dart';
import '../services/electricity_service.dart';
import '../widgets/app_ui_kit.dart';
import 'campus_card_recharge_page.dart';
import 'electricity_recharge_page.dart';
import 'homework_page.dart';
import 'notice_page.dart';

/// 账户余额与待办概览页 (参考 TDesign & Forui 极简规范)
class BalanceOverviewPage extends ConsumerStatefulWidget {
  const BalanceOverviewPage({super.key});

  @override
  ConsumerState<BalanceOverviewPage> createState() =>
      _BalanceOverviewPageState();
}

class _BalanceOverviewPageState extends ConsumerState<BalanceOverviewPage> {
  // ── 校园卡 ──────────────────────────────────────────────────────────────
  CampusCardInfo? _cardInfo;
  bool _cardLoading = false;
  String? _cardError;

  // ── 电费 ────────────────────────────────────────────────────────────────
  ElectricityBalanceInfo? _elecBalance;
  SavedElectricityRoom? _savedRoom;
  bool _elecLoading = false;
  String? _elecError;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadCard(), _loadElec()]);
  }

  Future<void> _loadCard() async {
    if (_cardLoading) return;
    setState(() {
      _cardLoading = true;
      _cardError = null;
    });
    try {
      final info = await CampusCardService.instance.fetchRechargeInfo();
      if (mounted) setState(() => _cardInfo = info);
    } catch (e) {
      if (mounted) setState(() => _cardError = '获取失败');
    } finally {
      if (mounted) setState(() => _cardLoading = false);
    }
  }

  Future<void> _loadElec() async {
    if (_elecLoading) return;
    setState(() {
      _elecLoading = true;
      _elecError = null;
    });
    try {
      final service = ElectricityService.instance;
      final saved = await service.getSavedRoom();
      if (saved == null) {
        if (mounted) {
          setState(() {
            _savedRoom = null;
            _elecBalance = null;
            _elecLoading = false;
          });
        }
        return;
      }
      _savedRoom = saved;
      final balance = await service.getBalance(
        areaName: saved.areaName,
        buildingName: saved.buildingName,
        roomId: saved.roomId,
        mertype: saved.mertype,
      );
      if (mounted) setState(() => _elecBalance = balance);
    } catch (e) {
      if (mounted) setState(() => _elecError = '获取失败');
    } finally {
      if (mounted) setState(() => _elecLoading = false);
    }
  }

  Future<void> _openNotice() async {
    final result = await AuthGuard.ensureLoggedIn(context);
    if (!result.allowed || !mounted) return;
    ref.read(noticeProvider.notifier).refresh();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const NoticePage()),
    );
  }

  Future<void> _openHomework() async {
    final result = await AuthGuard.ensureLoggedIn(context);
    if (!result.allowed || !mounted) return;
    ref.read(homeworkProvider.notifier).refresh();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const HomeworkPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.paddingOf(context).top;

    final noticeState = ref.watch(noticeProvider);
    final homeworkAsync = ref.watch(homeworkProvider);

    final unreadCount =
        noticeState.messages.where((m) => m.hasRedDot).length;

    final pendingHomework = homeworkAsync.valueOrNull
            ?.where((h) => h.status == HomeworkStatus.pending)
            .toList() ??
        [];
    final pendingCount = pendingHomework.length;

    final nextHomework = pendingHomework.isEmpty
        ? null
        : (pendingHomework
              ..sort((a, b) {
                if (a.endTime == null && b.endTime == null) return 0;
                if (a.endTime == null) return 1;
                if (b.endTime == null) return -1;
                return a.endTime!.compareTo(b.endTime!);
              }))
            .first;

    final bool isRefreshing = _cardLoading || _elecLoading;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            topPadding + AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          sliver: SliverList.list(
            children: [
              // ── 顶部 Header ──────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '资产与代办',
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '概览',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 24,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: isRefreshing ? null : _loadAll,
                    icon: isRefreshing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.primary,
                            ),
                          )
                        : Icon(
                            Icons.refresh_rounded,
                            size: 22,
                            color: colors.onSurfaceVariant,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── 待处理区域 (TDesign Tag + Forui 简洁双列 Metric) ───────────
              _buildSectionHeader('待处理事项'),
              const SizedBox(height: AppSpacing.sm),

              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: '未读消息',
                      count: unreadCount,
                      icon: Icons.notifications_none_rounded,
                      activeColor: colors.primary,
                      isLoading: noticeState.isLoading,
                      onTap: _openNotice,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _MetricCard(
                      label: '待完成作业',
                      count: pendingCount,
                      icon: Icons.assignment_outlined,
                      activeColor: const Color(0xFFE88A1A),
                      isLoading: homeworkAsync.isLoading,
                      onTap: _openHomework,
                    ),
                  ),
                ],
              ),

              if (nextHomework != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _UpcomingHomeworkCard(
                  homework: nextHomework,
                  onTap: _openHomework,
                ),
              ],

              const SizedBox(height: AppSpacing.xl),

              // ── 账户余额区域 (Forui 结构化 Card) ──────────────────────────
              _buildSectionHeader('校园账户余额'),
              const SizedBox(height: AppSpacing.sm),

              // 校园卡余额卡片
              _BalanceItemCard(
                icon: Icons.credit_card_rounded,
                title: '校园卡',
                subtitle: _cardInfo?.name != null ? '持卡人：${_cardInfo!.name}' : '一卡通服务',
                value: _cardInfo?.balance,
                symbol: '¥',
                unit: '',
                isLoading: _cardLoading,
                errorText: _cardError,
                tagText: '去充值',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CampusCardRechargePage()),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // 电费余额卡片
              _BalanceItemCard(
                icon: Icons.bolt_rounded,
                title: '宿舍电费',
                subtitle: _savedRoom != null
                    ? '${_savedRoom!.areaName} · ${_savedRoom!.buildingName} · ${_savedRoom!.roomName}'
                    : '尚未关联宿舍房间',
                value: _elecBalance?.balance,
                symbol: '',
                unit: '度/元',
                isLoading: _elecLoading,
                errorText: _elecError,
                tagText: _savedRoom == null ? '去选择房间' : '购电充值',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ElectricityRechargePage()),
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xxs),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ── 指标小卡 (Forui Metric 风格) ──────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.activeColor,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color activeColor;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.onSurfaceVariant),
              const Spacer(),
              if (count > 0)
                AppBadge(
                  label: '$count 待处理',
                  variant: AppBadgeVariant.warning,
                )
              else
                const AppBadge(
                  label: '已清空',
                  variant: AppBadgeVariant.neutral,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (isLoading)
            const SizedBox(
              height: 28,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Text(
              '$count',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: count > 0 ? activeColor : colors.onSurface,
                height: 1.1,
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 即将截止作业横幅 ─────────────────────────────────────────────────────────

class _UpcomingHomeworkCard extends StatelessWidget {
  const _UpcomingHomeworkCard({
    required this.homework,
    required this.onTap,
  });

  final HomeworkModel homework;
  final VoidCallback onTap;

  String _formatDeadline(DateTime? dt) {
    if (dt == null) return '无截止时间';
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.isNegative) return '已逾期';
    if (diff.inHours < 24) return '${diff.inHours} 小时后截止';
    if (diff.inDays <= 7) return '${diff.inDays} 天后截止';
    return '${dt.month}月${dt.day}日 截止';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isUrgent = homework.endTime != null &&
        homework.endTime!.difference(DateTime.now()).inHours < 24 &&
        !homework.endTime!.isBefore(DateTime.now());

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: isUrgent ? const Color(0xFFE88A1A) : colors.primary,
              borderRadius: AppRadius.roundedSm,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  homework.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  homework.courseName,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppBadge(
            label: _formatDeadline(homework.endTime),
            variant: isUrgent ? AppBadgeVariant.warning : AppBadgeVariant.neutral,
          ),
        ],
      ),
    );
  }
}

// ── 现代余额卡片 (TDesign 金额排版规范) ─────────────────────────────────────────

class _BalanceItemCard extends StatelessWidget {
  const _BalanceItemCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.symbol,
    required this.unit,
    required this.isLoading,
    this.errorText,
    required this.tagText,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final String symbol;
  final String unit;
  final bool isLoading;
  final String? errorText;
  final String tagText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: AppRadius.roundedSm,
                ),
                child: Icon(icon, size: 18, color: colors.onSurface),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AppBadge(
                label: tagText,
                variant: AppBadgeVariant.primary,
                icon: Icons.chevron_right_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (isLoading)
            const SizedBox(
              height: 36,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (errorText != null)
            Text(
              errorText!,
              style: TextStyle(
                fontSize: 18,
                color: colors.error,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (symbol.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Text(
                      symbol,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                Text(
                  value ?? '--',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: colors.onSurface,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
