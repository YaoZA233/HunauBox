import 'package:flutter/material.dart';

import '../services/onboarding_store.dart';
import '../widgets/campus_loading_mark.dart';

/// Keeps the home page unmounted until the first-run choice has been made.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    super.key,
    required this.child,
    this.store = const OnboardingStore(),
    this.onReady,
  });
  final Widget child;
  final OnboardingStore store;
  final VoidCallback? onReady;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  bool? _complete;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    bool complete;
    try {
      complete = await widget.store.isComplete();
    } catch (_) {
      complete = false;
    }
    if (!mounted) return;
    setState(() => _complete = complete);
    if (complete) _notifyReady();
  }

  void _notifyReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call();
    });
  }

  Future<void> _finish() async {
    var saved = true;
    try {
      await widget.store.complete();
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    setState(() => _complete = true);
    _notifyReady();
    if (!saved) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('未能记住引导状态，下次打开时可能再次显示')));
    }
  }

  @override
  Widget build(BuildContext context) => switch (_complete) {
    null => const Scaffold(body: Center(child: CampusLoadingMark(size: 36))),
    false => OnboardingPage(firstRun: true, onFinish: _finish),
    true => widget.child,
  };
}

class _GuideStep {
  const _GuideStep(
    this.section,
    this.title,
    this.description,
    this.path,
    this.icon,
    this.actions,
    this.tip,
  );
  final String section;
  final String title;
  final String description;
  final String path;
  final IconData icon;
  final List<(String, String)> actions;
  final String tip;
}

const _steps = <_GuideStep>[
  _GuideStep(
    '认识界面',
    '先看看功能在哪里',
    '主界面由左侧导航和右侧内容区组成。常用入口集中在这里，想了解某一部分时也可以从目录直接跳转。',
    '首页 · 左侧导航与右侧页面',
    Icons.space_dashboard_outlined,
    [
      ('打开功能', '点击左侧“功能”，查找学习、校园卡和生活服务。'),
      ('查看消息和作业', '左侧“通知”与“作业”分别进入对应列表。'),
      ('切换到概览', '在右侧首页向左滑动，可查看概览；向右滑动返回首页。'),
    ],
    '暂时不用记住所有入口，稍后可在设置中重看。',
  ),
  _GuideStep(
    '登录账号',
    '登录后同步校园信息',
    '课表、成绩、学习通和多数校园服务需要先登录校园账号；设置页面可以不登录直接使用。',
    '首页右上角头像 → 个人中心 → 登录校园账号',
    Icons.person_outline_rounded,
    [
      ('进入个人中心', '点击首页右上角头像，选择“登录校园账号”。'),
      ('按提示完成登录', '使用学校提供的账号完成认证，遇到验证时按页面提示操作。'),
      ('同步需要的数据', '登录后打开相应功能；如果数据未更新，可在该页面手动刷新。'),
    ],
    '登录失效或同步失败时，可重新登录后再试。',
  ),
  _GuideStep(
    '课表',
    '导入课表，查看每天安排',
    '首次使用课表时先导入本学期课程，之后可以按周或按天查看。',
    '左侧功能 → 课表查询 → 导入课表',
    Icons.calendar_month_outlined,
    [
      ('导入课程', '在空课表点击“导入课表”，或在右上角“课表功能”中选择导入。'),
      ('切换视图', '周视图可左右切换周次，顶部按钮可以切换日视图。'),
      ('临时调整', '长按课程或在“课表功能”中选择“临时调课”，按提示保存。'),
    ],
    '临时调课只改变本机显示，不会修改教务系统的原始课表。',
  ),
  _GuideStep(
    '学习通',
    '课程与消息分开查看',
    '学习通课程和消息都有独立入口。课程可查看任务点，会话可查看已获取的聊天内容。',
    '左侧功能 → 学习通课程 / 学习通消息',
    Icons.school_outlined,
    [
      ('查找课程', '在“学习通课程”按课程、教师或学校搜索，也可以按文件夹筛选。'),
      ('查看会话', '在“学习通消息”搜索名称或摘要，点击会话查看消息；更早记录和附件可在网页中查看。'),
      ('获取最新内容', '页面默认保留上次成功获取的结果，下拉或点击右上角刷新。'),
    ],
    '同步或打开会话可能将消息标记为已读；显示缓存时内容可能不是最新的。',
  ),
  _GuideStep(
    '待办与通知',
    '把学习事项找出来',
    '左侧“作业”和“通知”各自有列表和搜索，适合查看需要处理的事情。',
    '左侧作业 / 左侧通知',
    Icons.assignment_outlined,
    [
      ('查看作业', '在作业页切换待处理和已完成，可搜索课程名、标题或备注。'),
      ('打开学习通作业', '点击学习通作业进入对应页面，提交仍需在学习通中完成。'),
      ('查看通知', '从左侧打开通知；需要更新时在对应页面下拉刷新。'),
    ],
    '课程提醒和作业截止提醒可在设置中调整，按需开启系统通知权限。',
  ),
  _GuideStep(
    '概览',
    '把常用信息放在一页',
    '概览汇集余额、待办、学习通等信息，项目和顺序可以按自己的习惯调整。',
    '首页内容区向左滑动 → 概览',
    Icons.dashboard_outlined,
    [
      ('添加信息', '点击概览右上角“添加卡片”，选择想查看的内容和样式。'),
      ('调整顺序', '点击右上角“排序”，在管理页面长按并拖动卡片。'),
      ('刷新数据', '点击概览右上角“刷新”，查看各项服务的更新结果。'),
    ],
    '需要登录或授权的项目，会在对应服务可用后显示数据。',
  ),
  _GuideStep(
    'Agent 与设置',
    '按需要开启，再随时回来',
    'Agent 是可选功能；设置中还可以调整主题、通知和常用服务。',
    '首页右上角头像 → 设置',
    Icons.tune_rounded,
    [
      ('配置 Agent', '在设置中开启 Agent，并在“模型服务配置”填写服务地址、API Key 和模型名称。'),
      ('从侧栏提问', '开启后，左侧出现 Agent。可以询问课表、作业或已缓存的学习通课程和消息。'),
      ('再次查看教程', '进入“设置 → 使用引导”，可随时从目录选择主题重看。'),
    ],
    '向 Agent 发送消息后，回答所需的校园数据会发送给你配置的模型服务；请使用可信的服务。',
  ),
];

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.firstRun = false, this.onFinish});
  final bool firstRun;
  final Future<void> Function()? onFinish;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      if (widget.onFinish != null) {
        await widget.onFinish!();
      } else if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  void _go(int target) {
    if (!_controller.hasClients || target < 0 || target >= _steps.length) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(target);
    } else {
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _showContents() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Row(
                  children: [
                    Text('引导目录', style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _steps.length,
                  itemBuilder: (context, index) => ListTile(
                    leading: ExcludeSemantics(child: Icon(_steps[index].icon)),
                    title: Text(_steps[index].section),
                    subtitle: Text(_steps[index].title),
                    selected: index == _index,
                    onTap: () => Navigator.pop(context, index),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && selected != null) _go(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !widget.firstRun,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.firstRun) _finish();
      },
      child: Scaffold(
        backgroundColor: colors.surface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '使用引导',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: '教程目录',
                          onPressed: _finishing ? null : _showContents,
                          icon: const Icon(Icons.format_list_bulleted_rounded),
                        ),
                        TextButton(
                          onPressed: _finishing ? null : _finish,
                          child: Text(widget.firstRun ? '跳过' : '关闭'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: Semantics(
                      label: '引导进度，第 ${_index + 1} 页，共 ${_steps.length} 页',
                      child: ExcludeSemantics(
                        child: Row(
                          children: [
                            for (var i = 0; i < _steps.length; i++)
                              Expanded(
                                child: Container(
                                  height: 3,
                                  margin: EdgeInsets.only(
                                    right: i == _steps.length - 1 ? 0 : 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: i <= _index
                                        ? colors.primary
                                        : colors.outlineVariant,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _steps.length,
                      onPageChanged: (value) => setState(() => _index = value),
                      itemBuilder: (context, index) =>
                          _GuideContent(step: _steps[index]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                    child: Row(
                      children: [
                        if (_index > 0) ...[
                          Expanded(
                            child: TextButton(
                              onPressed: _finishing
                                  ? null
                                  : () => _go(_index - 1),
                              child: const Text('上一步'),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: FilledButton(
                            onPressed: _finishing
                                ? null
                                : _index == _steps.length - 1
                                ? _finish
                                : () => _go(_index + 1),
                            child: Text(
                              _index == _steps.length - 1
                                  ? (widget.firstRun ? '开始使用' : '完成')
                                  : '下一步',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideContent extends StatelessWidget {
  const _GuideContent({required this.step});
  final _GuideStep step;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: PageStorageKey('guide-${step.section}'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(step.icon, size: 20, color: colors.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  step.section,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            step.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            step.description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            '从这里进入',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.path,
            style: theme.textTheme.titleSmall?.copyWith(
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          Divider(height: 1, color: colors.outlineVariant),
          const SizedBox(height: 24),
          Text(
            '怎么用',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < step.actions.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${index + 1}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.actions[index].$1,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          step.actions[index].$2,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '使用时留意',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.tip,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
