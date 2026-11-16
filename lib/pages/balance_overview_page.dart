import 'dart:async';
import '../services/finance_cache_store.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/electricity_model.dart';
import '../models/homework_model.dart';
import '../models/campus_card_bill.dart';
import '../models/exam_schedule_model.dart';
import '../providers/homework_provider.dart';
import '../providers/notice_provider.dart';
import '../providers/exam_provider.dart';
import '../providers/chaoxing_course_provider.dart';
import '../services/auth_guard.dart';
import '../services/campus_card_bill_service.dart';
import '../services/campus_card_service.dart';
import '../services/electricity_service.dart';
import '../services/overview_card_layout_store.dart';
import '../widgets/app_ui_kit.dart';
import 'campus_card_bill_page.dart';
import 'campus_card_recharge_page.dart';
import 'electricity_recharge_page.dart';
import 'exam_page.dart';
import 'homework_page.dart';
import 'notice_page.dart';
import 'chaoxing_courses_page.dart';
import 'chaoxing_messages_page.dart';

const _cardLabels = {
  'notice': '未读消息',
  'homework': '待完成作业',
  'chaoxing_messages': '学习通消息',
  'chaoxing_courses': '学习通课程',
  'upcoming_homework': '即将截止作业',
  'exam': '最近考试',
  'campus_card': '校园卡',
  'recent_bill': '校园卡最近消费',
  'electricity_1': '宿舍电费1',
  'electricity_2': '宿舍电费2',
};

const _taskCardIds = {
  'notice',
  'homework',
  'upcoming_homework',
  'exam',
  'chaoxing_messages',
  'chaoxing_courses',
};
const _slotKeySeparator = '·';

/// 同一内容在布局中的唯一实例键：首次出现用卡片 id，重复出现追加序号。
String _slotKeyAt(List<OverviewCardSlot> layout, int index) {
  final cardId = layout[index].cardId;
  var occurrence = 0;
  for (var i = 0; i <= index; i++) {
    if (layout[i].cardId == cardId) occurrence++;
  }
  return occurrence == 1 ? cardId : '$cardId$_slotKeySeparator$occurrence';
}

/// 弹层与提示用语：重复实例带上序号，避免同名的两张卡无法区分。
String _slotLabelAt(List<OverviewCardSlot> layout, int index) {
  final label = _cardLabels[layout[index].cardId]!;
  final key = _slotKeyAt(layout, index);
  final separator = key.indexOf(_slotKeySeparator);
  return separator < 0 ? label : '$label ${key.substring(separator + 1)}';
}

String _sizeLabel(OverviewCardSize size) =>
    size == OverviewCardSize.large ? '标准视图' : '紧凑视图';

/// 账户余额与待办概览页 (参考 TDesign & Forui 极简规范)
class BalanceOverviewPage extends ConsumerStatefulWidget {
  const BalanceOverviewPage({
    super.key,
    this.isActive = true,
    this.loadCardInfo,
    this.loadElectricityBalance,
    this.loadRecentBills,
    this.loadExams,
  });

  final bool isActive;
  final Future<CampusCardInfo> Function()? loadCardInfo;
  final Future<ElectricityBalanceInfo> Function(SavedElectricityRoom)?
  loadElectricityBalance;
  final Future<List<CampusCardBill>> Function(CampusCardBillQuery)?
  loadRecentBills;
  final Future<List<ExamScheduleModel>> Function()? loadExams;

  @override
  ConsumerState<BalanceOverviewPage> createState() =>
      _BalanceOverviewPageState();
}

/// 默认查询近 7 天的校园卡消费记录（复用现有账单服务与授权会话）。
Future<List<CampusCardBill>> _defaultLoadRecentBills(
  CampusCardBillQuery query,
) => CampusCardBillService.instance.query(query);

class _BalanceOverviewPageState extends ConsumerState<BalanceOverviewPage>
    with AutomaticKeepAliveClientMixin<BalanceOverviewPage> {
  @override
  bool get wantKeepAlive => true;

  Future<void>? _refreshInProgress;
  final _scrollController = ScrollController();
  final _viewportKey = GlobalKey();
  Timer? _dragScrollTimer;
  double _dragScrollStep = 0;

  @override
  void dispose() {
    _stopDragScroll();
    _scrollController.dispose();
    super.dispose();
  }

  void _stopDragScroll() {
    _dragScrollTimer?.cancel();
    _dragScrollTimer = null;
    _dragScrollStep = 0;
  }

  void _updateDragScroll(DragUpdateDetails details) {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_scrollController.hasClients) return;
    final y = box.globalToLocal(details.globalPosition).dy;
    _dragScrollStep = y < 72
        ? -10
        : y > box.size.height - 72
        ? 10
        : 0;
    if (_dragScrollStep == 0) {
      _stopDragScroll();
      return;
    }
    _dragScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      _scrollController.jumpTo(
        (position.pixels + _dragScrollStep).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  // ── 校园卡 ──────────────────────────────────────────────────────────────
  CampusCardInfo? _cardInfo;
  bool _cardLoading = false;
  String? _cardError;

  final _elecBalances = List<ElectricityBalanceInfo?>.filled(2, null);
  final _savedRooms = List<SavedElectricityRoom?>.filled(2, null);
  final _elecLoading = List<bool>.filled(2, false);
  final _elecErrors = List<String?>.filled(2, null);
  final _elecRequestIds = List<int>.filled(2, 0);

  // ── 校园卡最近消费 ────────────────────────────────────────────────────────
  CampusCardBill? _recentBill;
  bool _billLoading = false;
  String? _billError;
  int _billRequestId = 0;

  // ── 最近考试 ──────────────────────────────────────────────────────────────
  ExamScheduleModel? _nextExam;
  bool _examLoading = false;
  int _examRequestId = 0;
  int? _chaoxingConversationCount;
  int? _chaoxingCourseCount;
  int _chaoxingSnapshotRequestId = 0;

  final _layoutStore = const OverviewCardLayoutStore();
  List<OverviewCardSlot> _layout = OverviewCardLayoutStore.defaultLayout;
  bool _layoutLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCardLayout();
    if (widget.isActive) _loadAll();
  }

  @override
  void didUpdateWidget(covariant BalanceOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive && _refreshInProgress == null) {
      _loadAll();
    }
  }

  // Keep page state across swipes; activation refreshes data using the shared
  // service sessions. Rapid swipes share the same pending refresh.
  Future<void> _loadAll() {
    // Explicit refreshes after editing a room must supersede old room reads.
    final request = _refreshAll();
    _refreshInProgress = request;
    return request.whenComplete(() {
      if (identical(_refreshInProgress, request)) _refreshInProgress = null;
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadCard(),
      _loadElec(0),
      _loadElec(1),
      _loadRecentBill(),
      _loadExams(),
      _loadChaoxingSnapshots(),
    ]);
  }

  Future<void> _loadChaoxingSnapshots() async {
    final requestId = ++_chaoxingSnapshotRequestId;
    final cache = ref.read(chaoxingCacheProvider);
    final snapshots = await Future.wait([
      cache.read('messages'),
      cache.read('courses'),
    ]);
    if (!mounted || requestId != _chaoxingSnapshotRequestId) return;
    final conversations = snapshots[0]?['conversations'];
    final courses = snapshots[1]?['items'];
    setState(() {
      _chaoxingConversationCount = conversations is List
          ? conversations.length
          : null;
      _chaoxingCourseCount = courses is List ? courses.length : null;
    });
  }

  Future<void> _openChaoxing({required bool messages}) async {
    final result = await AuthGuard.ensureLoggedIn(context);
    if (!result.allowed || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => messages
            ? const ChaoxingMessagesPage()
            : const ChaoxingCoursesPage(),
      ),
    );
    if (mounted) await _loadChaoxingSnapshots();
  }

  Future<void> _loadCardLayout() async {
    try {
      final layout = await _layoutStore.load();
      if (mounted) setState(() => _layout = layout);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法读取卡片布局，暂用默认顺序')));
      }
    } finally {
      if (mounted) setState(() => _layoutLoading = false);
    }
  }

  /// 布局变更即时生效并落盘；落盘失败回滚，避免界面与持久化不一致。
  Future<void> _applyLayout(List<OverviewCardSlot> next) async {
    final previous = _layout;
    setState(() => _layout = next);
    try {
      await _layoutStore.save(next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _layout = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存卡片布局失败，请重试')));
    }
  }

  int _indexOfSlotKey(String slotKey) {
    for (var i = 0; i < _layout.length; i++) {
      if (_slotKeyAt(_layout, i) == slotKey) return i;
    }
    return -1;
  }

  Future<void> _moveSlot(String draggedKey, int targetIndex) async {
    if (draggedKey == _slotKeyAt(_layout, targetIndex)) return;
    final from = _indexOfSlotKey(draggedKey);
    if (from < 0) return;
    final next = List<OverviewCardSlot>.of(_layout);
    final moved = next.removeAt(from);
    next.insert(targetIndex.clamp(0, next.length), moved);
    await _applyLayout(next);
  }

  Future<void> _manageCards({bool openSort = false}) async {
    if (_layoutLoading) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _OverviewManageSheet(
        layout: _layout,
        onSave: _applyLayout,
        initialTab: openSort ? 1 : 0,
      ),
    );
  }

  Future<void> _openElectricity(int slot) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ElectricityRechargePage(roomSlot: slot),
      ),
    );
    if (mounted) await _loadAll();
  }

  Future<void> _loadCard() async {
    if (_cardLoading) return;
    setState(() {
      _cardLoading = true;
      _cardError = null;
    });
    try {
      if (_cardInfo == null && widget.loadCardInfo == null) {
        final cached = await CampusCardService.instance.getStoredCardInfo();
        if (!mounted) return;
        if (cached != null) {
          setState(
            () => _cardInfo = CampusCardInfo(
              name: cached.data['name'] as String,
              idserial: cached.data['idserial'] as String,
              balance: cached.data['balance'] as String,
            ),
          );
        }
      }
      final info =
          await (widget.loadCardInfo ??
              CampusCardService.instance.fetchRechargeInfo)();
      if (mounted) setState(() => _cardInfo = info);
    } catch (e) {
      if (mounted) setState(() => _cardError = '获取失败');
    } finally {
      if (mounted) setState(() => _cardLoading = false);
    }
  }

  Future<void> _loadElec(int slot) async {
    final requestId = ++_elecRequestIds[slot];
    setState(() {
      _elecLoading[slot] = true;
      _elecErrors[slot] = null;
    });
    try {
      final service = ElectricityService.instance;
      final saved = await service.getSavedRoom(slot: slot);
      if (!mounted || requestId != _elecRequestIds[slot]) return;
      setState(() {
        if (saved == null ||
            _savedRooms[slot] == null ||
            ElectricityService.balanceCacheKey(saved) !=
                ElectricityService.balanceCacheKey(_savedRooms[slot]!)) {
          _elecBalances[slot] = null;
        }
        _savedRooms[slot] = saved;
      });
      if (saved == null) return;
      if (_elecBalances[slot] == null &&
          widget.loadElectricityBalance == null) {
        final cached = await FinanceCacheStore.read(
          ElectricityService.balanceCacheKey(saved),
        );
        if (!mounted || requestId != _elecRequestIds[slot]) return;
        if (cached != null) {
          setState(
            () => _elecBalances[slot] = ElectricityBalanceInfo.fromJson(
              cached.data,
            ),
          );
        }
      }
      final balance =
          await (widget.loadElectricityBalance?.call(saved) ??
              service.getBalance(
                areaName: saved.areaName,
                buildingName: saved.buildingName,
                roomId: saved.roomId,
                mertype: saved.mertype,
              ));
      if (mounted && requestId == _elecRequestIds[slot]) {
        setState(() => _elecBalances[slot] = balance);
      }
    } catch (e) {
      if (mounted && requestId == _elecRequestIds[slot]) {
        setState(() => _elecErrors[slot] = '获取失败');
      }
    } finally {
      if (mounted && requestId == _elecRequestIds[slot]) {
        setState(() => _elecLoading[slot] = false);
      }
    }
  }

  Future<void> _loadRecentBill() async {
    final requestId = ++_billRequestId;
    setState(() {
      _billLoading = true;
      _billError = null;
    });
    try {
      final end = DateUtils.dateOnly(DateTime.now());
      final begin = DateTime(end.year, end.month, end.day - 6);
      final query = CampusCardBillQuery(
        beginDate: begin,
        endDate: end,
        type: CampusCardTradeType.consume,
      );
      final bills = await (widget.loadRecentBills ?? _defaultLoadRecentBills)(
        query,
      );
      if (!mounted || requestId != _billRequestId) return;
      setState(() => _recentBill = bills.isEmpty ? null : bills.first);
    } catch (_) {
      if (mounted && requestId == _billRequestId) {
        setState(() {
          _recentBill = null;
          _billError = '获取失败';
        });
      }
    } finally {
      if (mounted && requestId == _billRequestId) {
        setState(() => _billLoading = false);
      }
    }
  }

  Future<void> _loadExams() async {
    final requestId = ++_examRequestId;
    setState(() => _examLoading = true);
    try {
      final loader = widget.loadExams;
      final List<ExamScheduleModel> exams;
      if (loader != null) {
        exams = await loader();
      } else {
        // 生产环境复用实时考试 provider：先返回本地缓存，后台静默同步超星数据。
        exams =
            ref.read(currentSemesterExamsProvider).valueOrNull ??
            await ref.read(examStorageProvider).readExamList();
      }
      if (!mounted || requestId != _examRequestId) return;
      final sorted = List<ExamScheduleModel>.of(exams)
        ..sort((a, b) => a.time.compareTo(b.time));
      setState(() => _nextExam = sorted.isEmpty ? null : sorted.first);
    } catch (_) {
      if (mounted && requestId == _examRequestId) {
        setState(() => _nextExam = null);
      }
    } finally {
      if (mounted && requestId == _examRequestId) {
        setState(() => _examLoading = false);
      }
    }
  }

  Future<void> _openBill() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const CampusCardBillPage()),
    );
    if (mounted) await _loadRecentBill();
  }

  Future<void> _openExam() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ExamPage()),
    );
    if (mounted) await _loadExams();
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
    super.build(context);
    final colors = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.paddingOf(context).top;

    final noticeState = ref.watch(noticeProvider);
    final homeworkAsync = ref.watch(homeworkProvider);

    final unreadCount = noticeState.messages.where((m) => m.hasRedDot).length;

    final pendingHomework =
        homeworkAsync.valueOrNull
            ?.where((h) => h.status == HomeworkStatus.pending)
            .toList() ??
        [];
    final pendingCount = pendingHomework.length;

    final nextHomework = pendingHomework.isEmpty
        ? null
        : (pendingHomework..sort((a, b) {
                if (a.endTime == null && b.endTime == null) return 0;
                if (a.endTime == null) return 1;
                if (b.endTime == null) return -1;
                return a.endTime!.compareTo(b.endTime!);
              }))
              .first;

    final recentBillMerchant =
        _recentBill == null || _recentBill!.merchantName.trim().isEmpty
        ? (_recentBill == null ? '暂无消费' : '校园卡消费')
        : _recentBill!.merchantName;

    final variants = <String, _OverviewCardVariants>{
      for (final messages in [true, false])
        messages
            ? 'chaoxing_messages'
            : 'chaoxing_courses': _OverviewCardVariants(
          large: _BalanceItemCard(
            icon: messages ? Icons.forum_outlined : Icons.school_outlined,
            title: messages ? '学习通消息' : '学习通课程',
            subtitle:
                (messages
                        ? _chaoxingConversationCount
                        : _chaoxingCourseCount) ==
                    null
                ? '打开后同步'
                : '上次同步的结果',
            value:
                (messages ? _chaoxingConversationCount : _chaoxingCourseCount)
                    ?.toString(),
            symbol: '',
            unit: messages ? '个会话' : '门课程',
            isLoading: false,
            tagText: '查看',
            onTap: () => _openChaoxing(messages: messages),
          ),
          small: _CompactCard(
            icon: messages ? Icons.forum_outlined : Icons.school_outlined,
            title: messages ? '学习通消息' : '学习通课程',
            detail:
                (messages ? _chaoxingConversationCount : _chaoxingCourseCount)
                    ?.toString() ??
                '未同步',
            badgeLabel:
                (messages
                        ? _chaoxingConversationCount
                        : _chaoxingCourseCount) ==
                    null
                ? '去同步'
                : '上次同步',
            badgeVariant: AppBadgeVariant.primary,
            isLoading: false,
            onTap: () => _openChaoxing(messages: messages),
          ),
        ),
      'notice': _OverviewCardVariants(
        large: _MetricCard(
          label: '未读消息',
          count: unreadCount,
          icon: Icons.notifications_none_rounded,
          activeColor: colors.primary,
          isLoading: noticeState.isLoading,
          onTap: _openNotice,
        ),
        small: _CompactCard(
          icon: Icons.notifications_none_rounded,
          title: '未读消息',
          detail: '$unreadCount',
          detailColor: unreadCount > 0 ? colors.primary : null,
          badgeLabel: unreadCount > 0 ? '$unreadCount 待处理' : '已清空',
          badgeVariant: unreadCount > 0
              ? AppBadgeVariant.warning
              : AppBadgeVariant.neutral,
          isLoading: noticeState.isLoading,
          onTap: _openNotice,
        ),
      ),
      'homework': _OverviewCardVariants(
        large: _MetricCard(
          label: '待完成作业',
          count: pendingCount,
          icon: Icons.assignment_outlined,
          activeColor: const Color(0xFFE88A1A),
          isLoading: homeworkAsync.isLoading,
          onTap: _openHomework,
        ),
        small: _CompactCard(
          icon: Icons.assignment_outlined,
          title: '待完成作业',
          detail: '$pendingCount',
          detailColor: pendingCount > 0 ? const Color(0xFFE88A1A) : null,
          badgeLabel: pendingCount > 0 ? '$pendingCount 待处理' : '已清空',
          badgeVariant: pendingCount > 0
              ? AppBadgeVariant.warning
              : AppBadgeVariant.neutral,
          isLoading: homeworkAsync.isLoading,
          onTap: _openHomework,
        ),
      ),
      if (nextHomework != null)
        'upcoming_homework': _OverviewCardVariants(
          large: _UpcomingHomeworkCard(
            homework: nextHomework,
            onTap: _openHomework,
          ),
          small: _CompactCard(
            icon: Icons.event_available_outlined,
            title: '即将截止',
            detail: nextHomework.title,
            badgeLabel: _formatDeadline(nextHomework.endTime),
            badgeVariant: _isWithinDay(nextHomework.endTime)
                ? AppBadgeVariant.warning
                : AppBadgeVariant.neutral,
            isLoading: false,
            onTap: _openHomework,
          ),
        ),
      if (_nextExam != null)
        'exam': _OverviewCardVariants(
          large: _UpcomingExamCard(exam: _nextExam!, onTap: _openExam),
          small: _CompactCard(
            icon: Icons.event_note_outlined,
            title: '最近考试',
            detail: _nextExam!.title,
            badgeLabel: _formatExamTime(_nextExam!.time),
            badgeVariant: _isWithinDay(_nextExam!.time)
                ? AppBadgeVariant.warning
                : AppBadgeVariant.neutral,
            isLoading: false,
            onTap: _openExam,
          ),
        ),
      'campus_card': _OverviewCardVariants(
        large: _BalanceItemCard(
          icon: Icons.credit_card_rounded,
          title: '校园卡',
          subtitle: _cardError != null && _cardInfo != null
              ? '更新失败，显示上次余额'
              : _cardInfo != null
              ? '持卡人：${_cardInfo!.name}'
              : '一卡通服务',
          value: _cardInfo?.balance,
          symbol: '¥',
          unit: '',
          isLoading: _cardLoading && _cardInfo == null,
          errorText: _cardInfo == null ? _cardError : null,
          tagText: '去充值',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CampusCardRechargePage()),
          ),
        ),
        small: _CompactCard(
          icon: Icons.credit_card_rounded,
          title: '校园卡',
          detail: _cardError != null && _cardInfo == null
              ? _cardError!
              : '¥${_cardInfo?.balance ?? '--'}',
          isError: _cardError != null,
          badgeLabel: _cardError != null && _cardInfo != null ? '上次余额' : '去充值',
          badgeVariant: AppBadgeVariant.primary,
          isLoading: _cardLoading && _cardInfo == null,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CampusCardRechargePage()),
          ),
        ),
      ),
      'recent_bill': _OverviewCardVariants(
        large: _BalanceItemCard(
          icon: Icons.receipt_long_rounded,
          title: '最近消费',
          subtitle: _billError != null ? '校园卡消费记录' : recentBillMerchant,
          value: _recentBill?.amount,
          symbol: _recentBill != null ? '¥' : '',
          unit: '',
          isLoading: _billLoading,
          errorText: _billError,
          tagText: '查账单',
          onTap: _openBill,
        ),
        small: _CompactCard(
          icon: Icons.receipt_long_rounded,
          title: '最近消费',
          detail: _billError != null
              ? _billError!
              : _recentBill != null
              ? '¥${_recentBill!.amount}'
              : recentBillMerchant,
          isError: _billError != null,
          badgeLabel: '查账单',
          badgeVariant: AppBadgeVariant.primary,
          isLoading: _billLoading,
          onTap: _openBill,
        ),
      ),
      for (var slot = 0; slot < 2; slot++)
        'electricity_${slot + 1}': _OverviewCardVariants(
          large: _BalanceItemCard(
            icon: Icons.bolt_rounded,
            title: '宿舍电费${slot + 1}',
            subtitle: _elecErrors[slot] != null && _elecBalances[slot] != null
                ? '更新失败，显示上次余额'
                : _savedRooms[slot] != null
                ? '${_savedRooms[slot]!.areaName} · ${_savedRooms[slot]!.buildingName} · ${_savedRooms[slot]!.roomName}'
                : '尚未关联宿舍房间',
            value: _elecBalances[slot]?.balance,
            symbol: '',
            unit: '度/元',
            isLoading: _elecLoading[slot] && _elecBalances[slot] == null,
            errorText: _elecBalances[slot] == null ? _elecErrors[slot] : null,
            tagText: _savedRooms[slot] == null ? '去选择房间' : '购电充值',
            onTap: () => _openElectricity(slot),
          ),
          small: _CompactCard(
            icon: Icons.bolt_rounded,
            title: '宿舍电费${slot + 1}',
            detail: _elecErrors[slot] != null && _elecBalances[slot] == null
                ? _elecErrors[slot]!
                : '${_elecBalances[slot]?.balance ?? '--'} 度/元',
            isError: _elecErrors[slot] != null,
            badgeLabel: _elecErrors[slot] != null && _elecBalances[slot] != null
                ? '上次余额'
                : _savedRooms[slot] == null
                ? '去选择房间'
                : '购电充值',
            badgeVariant: AppBadgeVariant.primary,
            isLoading: _elecLoading[slot] && _elecBalances[slot] == null,
            onTap: () => _openElectricity(slot),
          ),
        ),
    };

    final isRefreshing =
        _cardLoading ||
        _billLoading ||
        _examLoading ||
        _elecLoading.any((loading) => loading);

    return CustomScrollView(
      key: _viewportKey,
      controller: _scrollController,
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
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 24,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '添加卡片',
                    onPressed: _layoutLoading ? null : _manageCards,
                    icon: Icon(
                      Icons.add_card_rounded,
                      size: 22,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    tooltip: '排序',
                    onPressed: _layoutLoading
                        ? null
                        : () => _manageCards(openSort: true),
                    icon: Icon(
                      Icons.swap_vert_rounded,
                      size: 22,
                      color: colors.onSurfaceVariant,
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

              LayoutBuilder(
                builder: (context, constraints) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildLayoutRows(variants, constraints.maxWidth),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ],
    );
  }

  /// 大卡独占整行，两个小卡自动并排；分组标题仍按顺序里第一个分组插入。
  List<Widget> _buildLayoutRows(
    Map<String, _OverviewCardVariants> variants,
    double width,
  ) {
    final cells = <_LayoutCell>[];
    for (var index = 0; index < _layout.length; index++) {
      final slot = _layout[index];
      final variant = variants[slot.cardId];
      if (variant == null) continue;
      final isHalf = slot.size == OverviewCardSize.small;
      final cellWidth = isHalf ? (width - AppSpacing.md) / 2 : width;
      cells.add(
        _LayoutCell(
          slotKey: _slotKeyAt(_layout, index),
          layoutIndex: index,
          section: _taskCardIds.contains(slot.cardId) ? '待处理事项' : '校园账户余额',
          cellWidth: cellWidth,
          card: slot.size == OverviewCardSize.large
              ? variant.large
              : _squareCard(variant.small, cellWidth),
        ),
      );
    }

    final result = <Widget>[];
    var pending = <_LayoutCell>[];
    String? previousSection;

    void addSection(String section) {
      if (section == previousSection) {
        if (result.isNotEmpty) {
          result.add(const SizedBox(height: AppSpacing.md));
        }
        return;
      }
      if (result.isNotEmpty) result.add(const SizedBox(height: AppSpacing.xl));
      result.add(_buildSectionHeader(section));
      result.add(const SizedBox(height: AppSpacing.sm));
      previousSection = section;
    }

    void flush() {
      if (pending.isEmpty) return;
      addSection(pending.first.section);
      result.add(_buildRow(pending, width));
      pending = [];
    }

    for (final cell in cells) {
      if (cell.cellWidth >= width) {
        flush();
        pending = [cell];
        flush();
        continue;
      }
      pending.add(cell);
      if (pending.length == 2) flush();
    }
    flush();
    return result;
  }

  Widget _buildRow(List<_LayoutCell> row, double width) {
    if (row.length == 2) {
      return Row(
        children: [
          Expanded(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: _draggableSlot(row[0]),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: _draggableSlot(row[1]),
            ),
          ),
        ],
      );
    }
    final cell = row.single;
    final slot = _draggableSlot(cell);
    if (cell.cellWidth >= width) return slot;
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(width: cell.cellWidth, child: slot),
    );
  }

  /// 大小只决定占用的网格宽度，不能因字体大小或侧栏而退化成整行。
  Widget _squareCard(Widget card, double side) {
    return SizedBox(width: side, height: side, child: card);
  }

  Widget _draggableSlot(_LayoutCell cell) {
    final card = KeyedSubtree(key: ValueKey(cell.slotKey), child: cell.card);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != cell.slotKey,
      onAcceptWithDetails: (details) =>
          _moveSlot(details.data, cell.layoutIndex),
      builder: (context, candidates, rejects) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        transform: candidates.isNotEmpty
            ? (Matrix4.identity()..scale(1.02, 1.02, 1.0))
            : Matrix4.identity(),
        child: LongPressDraggable<String>(
          data: cell.slotKey,
          maxSimultaneousDrags: 1,
          onDragUpdate: _updateDragScroll,
          onDragEnd: (_) => _stopDragScroll(),
          feedback: Material(
            elevation: 8,
            borderRadius: AppRadius.roundedLg,
            child: SizedBox(width: cell.cellWidth, child: cell.card),
          ),
          childWhenDragging: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: 0.3,
            child: card,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: AppRadius.roundedLg,
              border: candidates.isEmpty
                  ? null
                  : Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
            ),
            child: card,
          ),
        ),
      ),
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

/// 一个待排版卡片：布局下标用于拖动落点，cellWidth 决定是否与下一张小卡并排。
class _LayoutCell {
  const _LayoutCell({
    required this.slotKey,
    required this.layoutIndex,
    required this.section,
    required this.cellWidth,
    required this.card,
  });

  final String slotKey;
  final int layoutIndex;
  final String section;
  final double cellWidth;
  final Widget card;
}

/// 同一内容卡片的大/小两种形态。
class _OverviewCardVariants {
  const _OverviewCardVariants({required this.large, required this.small});

  final Widget large;
  final Widget small;
}

class _OverviewManageSheet extends StatefulWidget {
  const _OverviewManageSheet({
    required this.layout,
    required this.onSave,
    this.initialTab = 0,
  });

  final List<OverviewCardSlot> layout;
  final void Function(List<OverviewCardSlot> layout) onSave;
  final int initialTab;

  @override
  State<_OverviewManageSheet> createState() => _OverviewManageSheetState();
}

class _OverviewManageSheetState extends State<_OverviewManageSheet>
    with SingleTickerProviderStateMixin {
  late final _slots = <OverviewCardSlot>[...widget.layout];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _add(String cardId, OverviewCardSize size) {
    setState(() => _slots.add(OverviewCardSlot(cardId: cardId, size: size)));
    widget.onSave(List.of(_slots));
    // 添加后切换到"已添加"标签
    _tabController.animateTo(1);
  }

  void _remove(String slotKey) {
    var index = -1;
    for (var i = 0; i < _slots.length; i++) {
      if (_slotKeyAt(_slots, i) == slotKey) {
        index = i;
        break;
      }
    }
    if (index < 0) return;
    setState(() => _slots.removeAt(index));
    widget.onSave(List.of(_slots));
  }

  void _move(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      _slots.insert(newIndex, _slots.removeAt(oldIndex));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.sm,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '管理卡片',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '自定义你的概览界面',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const CloseButton(),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: colors.onPrimary,
                unselectedLabelColor: colors.onSurfaceVariant,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: '添加卡片'),
                  Tab(text: '卡片排序'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildAddTab(colors), _buildManageTab(colors)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddTab(ColorScheme colors) {
    return ListView(
      key: const ValueKey('manage_list'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.primary.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 20, color: colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '选择要添加的卡片类型和显示样式',
                  style: TextStyle(fontSize: 13, color: colors.onSurface),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final cardId in OverviewCardLayoutStore.knownCardIds) ...[
          _buildCardOption(cardId, colors),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  Widget _buildCardOption(String cardId, ColorScheme colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.5)),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _cardLabels[cardId]!,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _buildSizeButton(
                  cardId: cardId,
                  size: OverviewCardSize.large,
                  icon: Icons.crop_16_9_rounded,
                  label: '标准视图',
                  description: '占满整行',
                  colors: colors,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildSizeButton(
                  cardId: cardId,
                  size: OverviewCardSize.small,
                  icon: Icons.crop_portrait_rounded,
                  label: '紧凑视图',
                  description: '每行两个',
                  colors: colors,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSizeButton({
    required String cardId,
    required OverviewCardSize size,
    required IconData icon,
    required String label,
    required String description,
    required ColorScheme colors,
  }) {
    return Tooltip(
      message:
          '添加${_cardLabels[cardId]}${size == OverviewCardSize.large ? '大卡' : '小卡'}',
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _add(cardId, size),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: colors.outline.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(icon, size: 32, color: colors.primary),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManageTab(ColorScheme colors) {
    if (_slots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dashboard_outlined,
              size: 64,
              color: colors.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '还没有添加卡片',
              style: TextStyle(fontSize: 16, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => _tabController.animateTo(0),
              icon: const Icon(Icons.add_rounded),
              label: const Text('去添加'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.tertiaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.tertiary.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.touch_app_rounded, size: 20, color: colors.tertiary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '长按卡片拖动调整位置',
                  style: TextStyle(fontSize: 13, color: colors.onSurface),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            cacheExtent: 2400,
            buildDefaultDragHandles: false,
            itemCount: _slots.length,
            onReorder: _move,
            itemBuilder: (context, index) {
              final slot = _slots[index];
              final key = _slotKeyAt(_slots, index);
              final label = _slotLabelAt(_slots, index);

              return Container(
                key: ValueKey('manage_$key'),
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colors.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  title: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Wrap(
                    spacing: 4,
                    children: [
                      Icon(
                        slot.size == OverviewCardSize.large
                            ? Icons.crop_16_9_rounded
                            : Icons.crop_portrait_rounded,
                        size: 14,
                        color: colors.onSurfaceVariant,
                      ),
                      Text(
                        _sizeLabel(slot.size),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  trailing: Wrap(
                    spacing: -8,
                    children: [
                      IconButton(
                        tooltip: '上移$label',
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        onPressed: index == 0
                            ? null
                            : () => _move(index, index - 1),
                      ),
                      IconButton(
                        tooltip: '下移$label',
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        onPressed: index == _slots.length - 1
                            ? null
                            : () => _move(index, index + 1),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: colors.error,
                        ),
                        onPressed: () => _remove(key),
                        tooltip: '移除$label',
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, child) => _tabController.index == 1
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: FilledButton(
                    onPressed: () {
                      widget.onSave(List.of(_slots));
                      Navigator.of(context).pop();
                    },
                    child: const Text('保存'),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── 指标大卡 (Forui Metric 风格) ──────────────────────────────────────────────

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
                AppBadge(label: '$count 待处理', variant: AppBadgeVariant.warning)
              else
                const AppBadge(label: '已清空', variant: AppBadgeVariant.neutral),
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
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── 小卡：正方形形态，沿用同一套卡片与徽章令牌，只保留单行主值 ────────────────

class _CompactCard extends StatelessWidget {
  const _CompactCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.badgeLabel,
    required this.badgeVariant,
    required this.isLoading,
    required this.onTap,
    this.detailColor,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String badgeLabel;
  final AppBadgeVariant badgeVariant;
  final bool isLoading;
  final VoidCallback onTap;
  final Color? detailColor;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      label: '$title，$detail，$badgeLabel',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tight = constraints.maxWidth < 140;
          return AppCard(
            onTap: onTap,
            padding: EdgeInsets.all(tight ? AppSpacing.sm : AppSpacing.md),
            child: LayoutBuilder(
              builder: (context, inner) {
                // Preserve square geometry at large text sizes. Content may scroll
                // vertically inside exceptionally small cells instead of overflowing.
                return SingleChildScrollView(
                  primary: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: inner.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              icon,
                              size: 18,
                              color: colors.onSurfaceVariant,
                            ),
                            if (!tight) ...[
                              const SizedBox(width: 4),
                              Flexible(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: AppBadge(
                                      label: badgeLabel,
                                      variant: badgeVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (isLoading)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Text(
                            detail,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color:
                                  detailColor ??
                                  (isError ? colors.error : colors.onSurface),
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ── 即将截止作业横幅 ─────────────────────────────────────────────────────────

class _UpcomingHomeworkCard extends StatelessWidget {
  const _UpcomingHomeworkCard({required this.homework, required this.onTap});

  final HomeworkModel homework;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isUrgent =
        _isWithinDay(homework.endTime) &&
        homework.endTime != null &&
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
            variant: isUrgent
                ? AppBadgeVariant.warning
                : AppBadgeVariant.neutral,
          ),
        ],
      ),
    );
  }
}

// ── 最近考试横幅 ───────────────────────────────────────────────────────────────

class _UpcomingExamCard extends StatelessWidget {
  const _UpcomingExamCard({required this.exam, required this.onTap});

  final ExamScheduleModel exam;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isUrgent = _isWithinDay(exam.time) && !exam.time.isBefore(now);
    final details = <String>[
      if (exam.courseName.trim().isNotEmpty) exam.courseName.trim(),
      if (exam.location != null && exam.location!.trim().isNotEmpty)
        exam.location!.trim(),
    ];
    final subtitle = details.isEmpty
        ? (exam.status.trim().isNotEmpty ? exam.status.trim() : '考试安排')
        : details.join(' · ');

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
                  exam.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
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
          const SizedBox(width: AppSpacing.sm),
          AppBadge(
            label: _formatExamTime(exam.time),
            variant: isUrgent
                ? AppBadgeVariant.warning
                : AppBadgeVariant.neutral,
          ),
        ],
      ),
    );
  }
}

// ── 现代余额大卡 (TDesign 金额排版规范) ─────────────────────────────────────────

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
                Flexible(
                  child: Text(
                    value ?? '--',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: colors.onSurface,
                    ),
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

/// 截止时间距今不足一天（用于紧急配色与徽章）。
bool _isWithinDay(DateTime? endTime) =>
    endTime != null && endTime.difference(DateTime.now()).inHours < 24;

String _formatDeadline(DateTime? dt) {
  if (dt == null) return '无截止时间';
  final now = DateTime.now();
  final diff = dt.difference(now);
  if (diff.isNegative) return '已逾期';
  if (diff.inHours < 24) return '${diff.inHours} 小时后截止';
  if (diff.inDays <= 7) return '${diff.inDays} 天后截止';
  return '${dt.month}月${dt.day}日 截止';
}

String _formatExamTime(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final examDay = DateTime(dt.year, dt.month, dt.day);
  final dayDiff = examDay.difference(today).inDays;
  if (dayDiff <= 0) return dt.isBefore(now) ? '进行中' : '今天';
  if (dayDiff == 1) return '明天';
  if (dayDiff <= 7) return '$dayDiff 天后';
  return '${dt.month}月${dt.day}日';
}
