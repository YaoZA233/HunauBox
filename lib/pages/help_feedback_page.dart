import 'package:flutter/material.dart';

class HelpFeedbackPage extends StatelessWidget {
  const HelpFeedbackPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('帮助与反馈'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          _buildIntro(context),
          const SizedBox(height: 24),
          _sectionTitle(context, '快速上手'),
          const SizedBox(height: 10),
          _buildGuideCard(context, [
            _GuideItem(Icons.login_rounded, '先登录校园账号', '点击首页右上角头像完成登录。课表、成绩、作业、通知和校园服务需要登录后才能同步。'),
            _GuideItem(Icons.sync_rounded, '需要更新时下拉刷新', '进入课表、作业或通知页面后下拉即可刷新。教务系统繁忙时，等待一会儿再重试比连续点击更稳定。'),
            _GuideItem(Icons.dashboard_customize_rounded, '把常用功能放到顺手的位置', '首页卡片支持进入对应功能；设置中的快捷入口可以调整常用服务，减少重复查找。'),
          ]),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Agent 使用说明'),
          const SizedBox(height: 10),
          _buildAgentCard(context),
          const SizedBox(height: 24),
          _sectionTitle(context, '课表与临时调课'),
          const SizedBox(height: 10),
          _buildGuideCard(context, [
            _GuideItem(Icons.calendar_month_rounded, '同步本学期课表', '在功能 → 课程表中打开课表，点击右上角同步按钮。首次同步会自动识别当前学期和开学日期。'),
            _GuideItem(Icons.touch_app_rounded, '长按课程卡片调课', '长按某节课可以直接进入临时调课；也可以点击右上角的调课按钮，选择日期时间、单周次、批量周次或批量课程调课。'),
            _GuideItem(Icons.event_busy_rounded, '设置本次不上课', '在调课表单中打开“本次不上课”，这只会隐藏对应周次的课程，不会删除原始课表。重新同步新课表时，旧的临时安排会自动清理。'),
          ]),
          const SizedBox(height: 24),
          _sectionTitle(context, '作业、通知与提醒'),
          const SizedBox(height: 10),
          _buildGuideCard(context, [
            _GuideItem(Icons.assignment_rounded, '作业页面怎么用', '顶部进度卡展示完成比例；搜索框可以按课程、标题和备注筛选；待处理与已完成可以分别查看。点击学习通作业会打开详情页，手动作业会保留在本地。'),
            _GuideItem(Icons.notifications_active_rounded, '开启课程提醒', '在通知或设置中打开提醒后，应用会根据当前课表安排通知。修改临时调课后，提醒会按新的时间重新安排。'),
            _GuideItem(Icons.refresh_rounded, '同步异常怎么办', '先确认登录状态，再下拉刷新；如果只显示旧数据，退出页面后重新进入。网络不稳定时不要重复提交充值、评价或其他可能产生实际操作的请求。'),
          ]),
          const SizedBox(height: 24),
          _sectionTitle(context, '常见问题'),
          const SizedBox(height: 10),
          _buildFaqCard(context),
          const SizedBox(height: 24),
          _sectionTitle(context, '反馈与联系'),
          const SizedBox(height: 10),
          _buildContactCard(context),
        ],
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [colors.primary, Color.lerp(colors.primary, colors.tertiary, .55)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: colors.onPrimary.withValues(alpha: .16), shape: BoxShape.circle),
            child: Icon(Icons.support_agent_rounded, color: colors.onPrimary, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('需要帮助？先看这里', style: TextStyle(color: colors.onPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('从登录、Agent 到课表和提醒，常用操作都整理在下面。', style: TextStyle(color: colors.onPrimary.withValues(alpha: .82), height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800));
  }

  Widget _buildGuideCard(BuildContext context, List<_GuideItem> items) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        children: items.asMap().entries.map((entry) {
          final item = entry.value;
          return Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                leading: _iconBox(context, item.icon),
                title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(item.description, style: TextStyle(color: colors.onSurfaceVariant, height: 1.45))),
              ),
              if (entry.key != items.length - 1) const Divider(height: 1, indent: 76),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAgentCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _iconBox(context, Icons.auto_awesome_rounded),
              const SizedBox(width: 12),
              const Expanded(child: Text('把 Agent 当成校园助手来问', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 14),
            Text('开启方式：设置 → Agent → 开启校园 Agent，并填写兼容 Chat Completions 的模型地址、API Key 和模型名称。配置只保存在本机安全存储中。', style: TextStyle(color: colors.onSurfaceVariant, height: 1.5)),
            const SizedBox(height: 14),
            Text('可以这样提问', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _examplePrompt(context, '“查一下我今天还有几节课，告诉我教室。”'),
            _examplePrompt(context, '“找出本周三之前截止的作业。”'),
            _examplePrompt(context, '“打开空教室功能，我想查明天下午的空教室。”'),
            _examplePrompt(context, '“帮我创建一个下周五 18:00 截止的手动作业：复习高等数学。”'),
            const SizedBox(height: 10),
            Text('涉及跳转、创建或可能改变数据的操作时，Agent 会先展示操作内容并请求确认。它不会代替你完成支付、提交问卷或在学习通中交作业。', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.45)),
          ],
        ),
      ),
    );
  }

  Widget _examplePrompt(BuildContext context, String text) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(11)),
      child: Text(text, style: TextStyle(color: colors.onSurface, fontSize: 13, height: 1.35)),
    );
  }

  Widget _buildFaqCard(BuildContext context) {
    final items = [
      ('为什么课表同步失败？', '请先确认校园账号可以正常登录，再检查网络。教务系统维护或访问繁忙时可能暂时无法返回数据，稍后重新同步即可。'),
      ('Agent 没有回复或提示配置错误？', '检查 API 地址是否包含正确的协议和路径，确认模型名称与服务商控制台一致，并确认 Key 仍然有效。修改配置后重新进入 Agent 页面再试。'),
      ('为什么首页和课表显示的课程不一样？', '首页只展示当前时间附近的课程，课表页面展示整周。临时调课保存后，两处都会按新的安排计算；如果页面停留太久，可以退出后重新进入。'),
      ('刷新后数据仍然没有变化？', '部分服务会优先展示本地缓存。保持登录状态后再次下拉刷新，必要时完全退出当前页面再打开。不要在网络不稳定时反复触发会产生实际操作的按钮。'),
      ('如何反馈问题？', '请提供问题发生的页面、操作步骤、预期结果和实际结果；如果有错误提示请完整复制。不要发送密码、API Key、验证码或完整 Cookie。'),
    ];
    return Card(
      child: Column(
        children: items.asMap().entries.map((entry) => _buildFaqItem(context, entry.value.$1, entry.value.$2, entry.key != items.length - 1)).toList(),
      ),
    );
  }

  Widget _buildFaqItem(BuildContext context, String question, String answer, bool showDivider) {
    return Column(children: [
      ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(question, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        children: [Align(alignment: Alignment.centerLeft, child: Text(answer, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5)))],
      ),
      if (showDivider) const Divider(height: 1, indent: 16, endIndent: 16),
    ]);
  }

  Widget _buildContactCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.person_outline_rounded, color: colors.primary), const SizedBox(width: 10), const Text('开发者：钟会 ZhongHui.', style: TextStyle(fontWeight: FontWeight.w700))]),
          const SizedBox(height: 12),
          Row(children: [Icon(Icons.email_outlined, color: colors.primary), const SizedBox(width: 10), const SelectableText('yaozhengan7@gmail.com')]),
          const SizedBox(height: 12),
          Text('反馈时请尽量说明设备型号、应用版本、页面名称和复现步骤。当前版本为 1.0.2。', style: TextStyle(color: colors.onSurfaceVariant, height: 1.5)),
        ]),
      ),
    );
  }

  Widget _iconBox(BuildContext context, IconData icon) {
    final colors = Theme.of(context).colorScheme;
    return Container(width: 42, height: 42, decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: colors.onPrimaryContainer));
  }
}

class _GuideItem {
  const _GuideItem(this.icon, this.title, this.description);

  final IconData icon;
  final String title;
  final String description;
}
