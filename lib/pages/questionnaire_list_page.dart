import 'package:flutter/material.dart';

import '../models/questionnaire_models.dart';
import '../services/questionnaire_service.dart';
import '../widgets/login_bottom_sheet.dart';
import '../widgets/questionnaire_widgets.dart';
import 'questionnaire_detail_page.dart';
import 'xgxt_webview_page.dart';

enum QuestionnaireFilter {
  all('全部'),
  pending('待填写'),
  submitted('已提交'),
  closed('已截止');

  const QuestionnaireFilter(this.label);
  final String label;
  bool matches(QuestionnaireItem item) => switch (this) {
    all => true,
    pending => item.isPending,
    submitted => item.isSubmitted,
    closed => !item.isSubmitted && item.isExpired,
  };
}

class QuestionnaireListPage extends StatefulWidget {
  const QuestionnaireListPage({super.key, this.service});
  final QuestionnaireService? service;

  @override
  State<QuestionnaireListPage> createState() => _QuestionnaireListPageState();
}

class _QuestionnaireListPageState extends State<QuestionnaireListPage> {
  late final QuestionnaireService _service;
  List<QuestionnaireItem> _items = [];
  bool _loading = false;
  String? _error;
  QuestionnaireFilter _filter = QuestionnaireFilter.all;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? QuestionnaireService();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.fetchList();
      // 待填写优先，按截止时间排列；其余维持服务端顺序。
      final pending = items.where((e) => e.isPending).toList()
        ..sort(
          (a, b) => (DateTime.tryParse(a.endTime) ?? DateTime(9999)).compareTo(
            DateTime.tryParse(b.endTime) ?? DateTime(9999),
          ),
        );
      if (mounted) {
        setState(
          () => _items = [...pending, ...items.where((e) => !e.isPending)],
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is QuestionnaireException
              ? e.message
              : '暂时无法加载问卷，请检查网络后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(QuestionnaireItem item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QuestionnaireDetailPage(item: item, service: _service),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _login() async {
    final info = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LoginBottomSheet(),
    );
    if (info != null && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filtered = _items.where(_filter.matches).toList();
    final pendingCount = _items.where((e) => e.isPending).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('学工问卷'),
        actions: [
          IconButton(
            tooltip: '刷新问卷',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '打开学工系统',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const XgxtWebViewPage()),
              );
              if (mounted) await _load();
            },
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  Text(
                    '我的问卷',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 30,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: pendingCount == 0
                              ? '暂无待填写问卷'
                              : '$pendingCount 份待填写',
                          style: TextStyle(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: '  /  共 ${_items.length} 份问卷'),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: colors.outlineVariant),
                      ),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: QuestionnaireFilter.values.map((filter) {
                          final count = _items.where(filter.matches).length;
                          final selected = _filter == filter;
                          return Padding(
                            padding: const EdgeInsets.only(right: 24),
                            child: Semantics(
                              selected: selected,
                              button: true,
                              child: InkWell(
                                onTap: () => setState(() => _filter = filter),
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 48,
                                  ),
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        width: 2,
                                        color: selected
                                            ? colors.primary
                                            : Colors.transparent,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    '${filter.label} $count',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: selected
                                          ? colors.primary
                                          : colors.onSurfaceVariant,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  if (_error != null)
                    QuestionnaireStatePanel(
                      icon: Icons.wifi_off_rounded,
                      title: '问卷暂未同步',
                      message: _error!,
                      action: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        children: [
                          FilledButton(
                            onPressed: _load,
                            child: const Text('重新加载'),
                          ),
                          TextButton(
                            onPressed: _login,
                            child: const Text('重新登录'),
                          ),
                        ],
                      ),
                    )
                  else if (filtered.isEmpty)
                    QuestionnaireStatePanel(
                      icon: Icons.task_alt_rounded,
                      title: _filter == QuestionnaireFilter.pending
                          ? '待办已清空'
                          : '暂无问卷',
                      message: _filter == QuestionnaireFilter.pending
                          ? '目前没有需要填写的问卷，稍后可下拉刷新。'
                          : '这里会显示学工系统发布的问卷。',
                    ),
                  ...filtered.map(_itemRow),
                ],
              ),
            ),
    );
  }

  Widget _itemRow(QuestionnaireItem item) {
    final colors = Theme.of(context).colorScheme;
    final color = item.isPending ? colors.primary : colors.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _open(item),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.65),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    item.isPending
                        ? Icons.circle
                        : item.isSubmitted
                        ? Icons.check_rounded
                        : Icons.remove_rounded,
                    size: item.isPending ? 6 : 14,
                    color: color,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    item.statusLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title.isEmpty ? '未命名问卷' : item.title,
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.chevron_right_rounded, size: 22, color: color),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.endTime.isEmpty ? '未设置截止时间' : '截止 ${item.endTime}',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
