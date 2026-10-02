import 'package:flutter/material.dart';

import '../models/questionnaire_models.dart';
import '../services/auth_service.dart';
import '../services/questionnaire_service.dart';
import '../services/secure_storage_helper.dart';
import '../services/xgxt_login_service.dart';
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
    _service =
        widget.service ?? QuestionnaireService(reauthenticate: _renewSession);
    _load();
  }

  Future<bool> _renewSession() async {
    final login = XgxtLoginService();
    if (await login.performXgxtCasLogin()) return true;
    final storage = SecureStorageHelper();
    final username = await storage.getUsername();
    final password = await storage.getPassword();
    if (!mounted || username == null || password == null) return false;
    await AuthService().login(username, password, context);
    if (!mounted) return false;
    return login.performXgxtCasLogin();
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '问卷待办',
                                style: TextStyle(
                                  color: colors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                pendingCount == 0
                                    ? '暂无待填写问卷'
                                    : '还有 $pendingCount 份等待填写',
                                style: const TextStyle(
                                  fontSize: 21,
                                  height: 1.3,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '查看通知问卷，按时完成信息登记',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.fact_check_outlined,
                          color: colors.primary,
                          size: 44,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: QuestionnaireFilter.values.map((filter) {
                        final count = _items.where(filter.matches).length;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('${filter.label} $count'),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                            showCheckmark: false,
                            visualDensity: VisualDensity.comfortable,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                  ...filtered.map(_itemCard),
                ],
              ),
            ),
    );
  }

  Widget _itemCard(QuestionnaireItem item) {
    final colors = Theme.of(context).colorScheme;
    final color = item.isPending
        ? colors.primary
        : item.isSubmitted
        ? colors.tertiary
        : colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(item),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 4,
                  color: color.withValues(alpha: item.isPending ? 1 : 0.35),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            QuestionnaireBadge(
                              label: item.statusLabel,
                              color: color,
                            ),
                            const Spacer(),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 19,
                              color: color,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          item.title.isEmpty ? '未命名问卷' : item.title,
                          style: const TextStyle(
                            fontSize: 17,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.endTime.isEmpty
                                    ? '未设置截止时间'
                                    : '截止 ${item.endTime}',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
