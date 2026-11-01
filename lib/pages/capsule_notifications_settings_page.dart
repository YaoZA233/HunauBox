import 'package:flutter/material.dart';

import '../services/unified_capsule_service.dart';
import '../services/course_notification_service.dart';
import '../services/course_notification_settings_store.dart';
import '../services/enhanced_live_course_service.dart';

/// 胶囊通知设置页面
///
/// 统一管理所有类型的胶囊通知：
/// - 课程提醒
/// - 作业提醒
/// - 校园通知
/// - 考试提醒
/// - 活动提醒
class CapsuleNotificationsSettingsPage extends StatefulWidget {
  const CapsuleNotificationsSettingsPage({super.key});

  @override
  State<CapsuleNotificationsSettingsPage> createState() =>
      _CapsuleNotificationsSettingsPageState();
}

class _CapsuleNotificationsSettingsPageState
    extends State<CapsuleNotificationsSettingsPage> {
  final _service = UnifiedCapsuleService.instance;

  Map<String, dynamic>? _deviceInfo;
  Set<String> _enabledTypes = {};
  bool _loading = true;
  bool _busy = false;
  CourseNotificationSettings _courseSettings = const CourseNotificationSettings(
    enabled: false,
    minutesBefore: 15,
  );

  // 所有支持的通知类型
  static const _allTypes = [
    UnifiedCapsuleService.typesCourse,
    UnifiedCapsuleService.typesHomework,
    UnifiedCapsuleService.typesMessage,
    UnifiedCapsuleService.typesExam,
    UnifiedCapsuleService.typesActivity,
  ];

  @override
  void initState() {
    super.initState();

    _loadSettings();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final deviceInfo = await _service.capabilities();
      final enabledTypes = await _service.loadEnabledTypes();
      final courseStore = CourseNotificationSettingsStore.instance;
      await courseStore.load();

      if (mounted) {
        setState(() {
          _deviceInfo = deviceInfo;
          _enabledTypes = enabledTypes;
          _courseSettings = courseStore.settings.value;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showMessage('加载设置失败：$e');
      }
    }
  }

  Future<void> _toggleCourseLive(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _requestPermission();
      final next = _courseSettings.copyWith(
        liveActivityEnabled: enabled,
        enabled: enabled || _courseSettings.enabled,
      );
      await CourseNotificationSettingsStore.instance.save(next);
      await EnhancedLiveCourseService.instance.sync();
      if (mounted) setState(() => _courseSettings = next);
      _showMessage(enabled ? '课程实况已启用' : '课程实况已关闭');
    } catch (e) {
      _showMessage('课程实况设置失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCourseSample() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _requestPermission();
      await EnhancedLiveCourseService.instance.showSample(upcoming: false);
      _showMessage('课程实况示例已发送，请下拉通知栏查看');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPermission() async {
    final granted = await CourseNotificationService.instance
        .requestPermission();
    if (!granted && mounted) {
      _showMessage('请在系统设置中允许通知权限');
    }
  }

  Future<void> _toggleType(String type) async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      final newTypes = Set<String>.from(_enabledTypes);
      if (newTypes.contains(type)) {
        newTypes.remove(type);
      } else {
        newTypes.add(type);
        // 首次启用时请求权限
        await _requestPermission();
      }

      await _service.saveEnabledTypes(newTypes);
      // Rebuild from the local timetable/homework cache. Passing empty lists
      // here used to erase the payload and made the capsule appear broken.
      await _service.syncLocal();

      if (mounted) {
        setState(() {
          _enabledTypes = newTypes;
          _busy = false;
        });

        _showMessage(
          newTypes.contains(type)
              ? '已启用${_service.getTypeName(type)}'
              : '已关闭${_service.getTypeName(type)}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _showMessage('操作失败：$e');
      }
    }
  }

  Future<void> _sendTestNotification(String type) async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await _requestPermission();

      // 创建测试数据
      final now = DateTime.now();
      final testData = _createTestData(type, now);

      await _service.configure(
        enabledTypes: {type},
        courses: type == UnifiedCapsuleService.typesCourse
            ? testData as List<CourseData>
            : [],
        homework: type == UnifiedCapsuleService.typesHomework
            ? testData as List<HomeworkData>
            : [],
        messages: type == UnifiedCapsuleService.typesMessage
            ? testData as List<MessageData>
            : [],
        exams: type == UnifiedCapsuleService.typesExam
            ? testData as List<ExamData>
            : [],
        activities: type == UnifiedCapsuleService.typesActivity
            ? testData as List<ActivityData>
            : [],
      );

      if (mounted) {
        setState(() => _busy = false);
        _showMessage('测试通知已发送！\n请下拉通知栏查看效果');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _showMessage('发送失败：$e');
      }
    }
  }

  List<dynamic> _createTestData(String type, DateTime now) {
    switch (type) {
      case UnifiedCapsuleService.typesCourse:
        return [
          CourseData(
            id: 'test_course',
            name: '植物生理学',
            room: '文渊馆 B203',
            start: now
                .subtract(const Duration(minutes: 28))
                .millisecondsSinceEpoch,
            end: now.add(const Duration(minutes: 72)).millisecondsSinceEpoch,
            periods: '第 3-4 节',
          ),
        ];

      case UnifiedCapsuleService.typesHomework:
        return [
          HomeworkData(
            id: 'test_hw',
            title: '植物生理学实验报告',
            course: '植物生理学',
            deadline: now.add(const Duration(hours: 18)).millisecondsSinceEpoch,
          ),
        ];

      case UnifiedCapsuleService.typesMessage:
        return [
          MessageData(
            id: 'test_msg',
            title: '关于2024春季学期选课的通知',
            sender: '教务处',
            content: '各位同学，春季学期选课将于本周五开始，请及时登录教务系统进行选课。',
            time: now.millisecondsSinceEpoch,
            priority: 'important',
            read: false,
          ),
        ];

      case UnifiedCapsuleService.typesExam:
        return [
          ExamData(
            id: 'test_exam',
            subject: '高等数学',
            location: '第一教学楼 301',
            time: now.add(const Duration(days: 3)).millisecondsSinceEpoch,
            important: true,
          ),
        ];

      case UnifiedCapsuleService.typesActivity:
        return [
          ActivityData(
            id: 'test_activity',
            name: '农业科技创新讲座',
            location: '学术报告厅',
            time: now.add(const Duration(hours: 5)).millisecondsSinceEpoch,
            important: false,
          ),
        ];

      default:
        return [];
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supported = _deviceInfo?['supported'] == true;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('通知与课程实况')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('通知与课程实况')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '需要提醒的内容会出现在系统通知栏。课程进行中时，会显示教室、时间和倒计时。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          _buildCourseLiveCard(
            Theme.of(context),
            Theme.of(context).colorScheme,
            supported,
          ),
          const SizedBox(height: 24),
          Text('通知类型', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < _allTypes.length; index++) ...[
                  _buildSimpleTypeTile(_allTypes[index], supported),
                  if (index != _allTypes.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
          if (!supported) ...[
            const SizedBox(height: 12),
            Text(
              '当前设备不支持 Android 胶囊展示，但普通通知仍可使用。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSimpleTypeTile(String type, bool supported) {
    final enabled = _enabledTypes.contains(type);
    return SwitchListTile.adaptive(
      value: enabled,
      onChanged: supported && !_busy ? (_) => _toggleType(type) : null,
      title: Text(_service.getTypeName(type)),
      subtitle: Text(_typeShortDescription(type)),
      secondary: Icon(_typeIcon(type)),
    );
  }

  String _typeShortDescription(String type) {
    switch (type) {
      case UnifiedCapsuleService.typesCourse:
        return '上课前和上课中显示课程、教室与倒计时';
      case UnifiedCapsuleService.typesHomework:
        return '显示待完成作业和截止时间';
      case UnifiedCapsuleService.typesMessage:
        return '显示新的校园通知';
      case UnifiedCapsuleService.typesExam:
        return '显示近期考试时间与地点';
      case UnifiedCapsuleService.typesActivity:
        return '显示近期校园活动';
      default:
        return '';
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case UnifiedCapsuleService.typesCourse:
        return Icons.menu_book_outlined;
      case UnifiedCapsuleService.typesHomework:
        return Icons.assignment_outlined;
      case UnifiedCapsuleService.typesMessage:
        return Icons.notifications_none_rounded;
      case UnifiedCapsuleService.typesExam:
        return Icons.event_note_outlined;
      case UnifiedCapsuleService.typesActivity:
        return Icons.campaign_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Widget _buildCourseLiveCard(
    ThemeData theme,
    ColorScheme colors,
    bool supported,
  ) {
    final enabled = _courseSettings.liveActivityEnabled;
    return Card(
      margin: EdgeInsets.zero,
      color: enabled
          ? colors.primaryContainer.withOpacity(0.55)
          : colors.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.view_agenda_outlined, color: colors.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '课程实况',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 3),
                      Text('教室、时间、倒计时与课程胶囊使用同一套设置'),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: enabled,
                  onChanged: supported && !_busy ? _toggleCourseLive : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: supported && enabled && !_busy
                    ? _showCourseSample
                    : null,
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('发送课程实况示例'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme, ColorScheme colors) {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildHeroSection(ThemeData theme, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors.primary, colors.secondary],
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '智能胶囊通知',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '一目了然的信息展示',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '在通知栏和灵动岛以优雅的方式展示课程、作业、消息等重要信息，'
          '支持荣耀、华为、小米等厂商的胶囊特效。',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicIslandBadge(ThemeData theme, ColorScheme colors) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.notifications_active_outlined, color: colors.primary),
      title: const Text('系统支持胶囊展示'),
      subtitle: const Text('是否显示由系统通知权限和厂商策略决定'),
    );
  }

  Widget _buildUnsupportedCard(ThemeData theme, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_rounded, color: colors.error, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '设备不支持',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '胶囊通知目前仅支持 Android 设备',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  List<Widget> _buildTypeCards(
    ThemeData theme,
    ColorScheme colors,
    bool supported,
  ) {
    return _allTypes.map((type) {
      final enabled = _enabledTypes.contains(type);
      final icon = _service.getTypeIcon(type);
      final name = _service.getTypeName(type);
      final description = _service.getTypeDescription(type);

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          elevation: enabled ? 4 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: enabled ? colors.primary : colors.outlineVariant,
              width: enabled ? 2 : 1,
            ),
          ),
          color: enabled
              ? colors.primaryContainer.withOpacity(0.5)
              : colors.surfaceContainer,
          child: InkWell(
            onTap: supported && !_busy ? () => _toggleType(type) : null,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Icon
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: enabled
                              ? colors.primary.withOpacity(0.2)
                              : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(icon, style: const TextStyle(fontSize: 24)),
                      ),
                      const SizedBox(width: 16),

                      // Name & Description
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: enabled
                                    ? colors.onPrimaryContainer
                                    : colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: enabled
                                    ? colors.onPrimaryContainer.withOpacity(0.8)
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Switch
                      Switch.adaptive(
                        value: enabled,
                        onChanged: supported && !_busy
                            ? (_) => _toggleType(type)
                            : null,
                        activeColor: colors.primary,
                      ),
                    ],
                  ),

                  // Test Button
                  if (enabled) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: supported && !_busy
                            ? () => _sendTestNotification(type)
                            : null,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: colors.primary),
                        ),
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('发送测试通知'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildQuickActions(
    ThemeData theme,
    ColorScheme colors,
    bool supported,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: supported && !_busy && _enabledTypes.isNotEmpty
              ? () async {
                  setState(() => _busy = true);
                  try {
                    await _service.refresh();
                    if (mounted) {
                      setState(() => _busy = false);
                      _showMessage('已刷新所有胶囊通知');
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() => _busy = false);
                      _showMessage('刷新失败：$e');
                    }
                  }
                }
              : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text(
            '刷新所有通知',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: supported && !_busy
              ? () async {
                  setState(() => _busy = true);
                  try {
                    await _service.cancelAll();
                    if (mounted) {
                      setState(() => _busy = false);
                      _showMessage('已清除所有胶囊通知');
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() => _busy = false);
                      _showMessage('清除失败：$e');
                    }
                  }
                }
              : null,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: BorderSide(color: colors.error, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: Icon(Icons.clear_all_rounded, color: colors.error),
          label: Text(
            '清除所有通知',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceInfoCard(ThemeData theme, ColorScheme colors) {
    if (_deviceInfo == null) {
      return const SizedBox.shrink();
    }

    final capsuleStyle = _deviceInfo!['capsuleStyle'] as String?;
    final styleDescription = _getCapsuleStyleDescription(capsuleStyle);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_android_rounded, color: colors.primary),
              const SizedBox(width: 12),
              Text(
                '设备兼容性',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            theme,
            colors,
            '制造商',
            _deviceInfo!['manufacturer']?.toString() ?? '未知',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            theme,
            colors,
            '型号',
            _deviceInfo!['model']?.toString() ?? '未知',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(theme, colors, '胶囊样式', styleDescription),
          const SizedBox(height: 8),
          _buildInfoRow(
            theme,
            colors,
            '通知权限',
            _deviceInfo!['notificationsEnabled'] == true ? '✅ 已允许' : '❌ 未允许',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    ColorScheme colors,
    String label,
    String value,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTipsCard(ThemeData theme, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.tertiaryContainer, colors.secondaryContainer],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_rounded, color: colors.tertiary),
              const SizedBox(width: 12),
              Text(
                '使用提示',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '• 启用对应类型后，相关通知会自动展示在通知栏\n'
            '• 支持灵动岛的设备会以胶囊形式显示（由系统决定）\n'
            '• 点击"发送测试通知"可预览效果\n'
            '• 课程通知会显示实时进度，作业通知会显示倒计时\n'
            '• 通知会根据紧急程度自动调整颜色和优先级',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }

  String _getCapsuleStyleDescription(String? style) {
    switch (style) {
      case 'honor_magic_capsule':
        return '荣耀灵动胶囊';
      case 'huawei_live_window':
        return '华为实时窗口';
      case 'xiaomi_notification_capsule':
        return '小米通知胶囊';
      case 'oppo_sidebar':
        return 'OPPO 侧边栏';
      case 'vivo_notification_style':
        return 'vivo 通知样式';
      default:
        return '标准通知';
    }
  }
}
