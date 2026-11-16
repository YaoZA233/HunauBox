import 'package:flutter/material.dart';

import '../services/course_notification_service.dart';
import '../services/course_notification_settings_store.dart';
import '../services/enhanced_live_course_service.dart';

class EnhancedLiveCoursePage extends StatefulWidget {
  const EnhancedLiveCoursePage({super.key});

  @override
  State<EnhancedLiveCoursePage> createState() => _EnhancedLiveCoursePageState();
}

class _EnhancedLiveCoursePageState extends State<EnhancedLiveCoursePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _store = CourseNotificationSettingsStore.instance;
  Map<String, dynamic>? _device;
  bool _busy = false;
  bool _upcoming = false;
  String? _error;
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Pulse animation for active state indicators
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Progress animation for demo
    _progressController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: 0.28).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
    );

    _load();
    _progressController.forward();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      await _store.load();
      final device = await EnhancedLiveCourseService.instance.deviceInfo();
      if (mounted) {
        setState(() {
          _device = device;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取设备信息，请稍后重试');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (_) {
      if (mounted) _message('操作失败，请检查通知权限后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<bool> _permission() async {
    final granted = await CourseNotificationService.instance
        .requestPermission();
    if (!granted && mounted) _message('请先在系统设置中允许通知');
    return granted;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final supported = _device?['supported'] == true;
    final hasDynamicIsland = EnhancedLiveCourseService.instance
        .supportsDynamicIsland(_device ?? {});

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Animated App Bar
          SliverAppBar.large(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('增强课程实况'),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.primaryContainer,
                      colors.secondaryContainer,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.lens_blur_rounded,
                    size: 80,
                    color: colors.primary.withOpacity(0.3),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Hero section
                _buildHeroSection(theme, colors),
                const SizedBox(height: 32),

                // Dynamic Island Support Badge
                if (hasDynamicIsland) ...[
                  _buildDynamicIslandBadge(theme, colors),
                  const SizedBox(height: 24),
                ],

                // Preview Toggle
                _buildPreviewToggle(theme, colors),
                const SizedBox(height: 20),

                // Enhanced Preview Card
                _buildEnhancedPreviewCard(theme, colors),
                const SizedBox(height: 12),

                // Description
                _buildDescription(theme, colors),
                const SizedBox(height: 32),

                // Main Toggle
                _buildMainToggle(theme, colors, supported),
                const SizedBox(height: 16),

                // Action Buttons
                _buildActionButtons(theme, colors, supported),
                const SizedBox(height: 32),

                // Device Info Card
                _buildDeviceInfoCard(theme, colors, supported),
                const SizedBox(height: 20),

                // Capsule Style Info
                if (hasDynamicIsland) ...[
                  _buildCapsuleStyleInfo(theme, colors),
                  const SizedBox(height: 20),
                ],

                // Settings Button
                _buildSettingsButton(theme, colors, supported),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(ThemeData theme, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: colors.primary,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '智能课程展示',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '灵动岛级别的体验',
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
          '将课程信息以最优雅的方式呈现在通知栏。支持各大厂商的灵动岛、胶囊展示，实时同步上课进度，无需频繁打开课表。',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicIslandBadge(ThemeData theme, ColorScheme colors) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.primary, colors.secondary],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stars_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  '🎉 您的设备支持灵动岛',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(
    ThemeData theme,
    ColorScheme colors,
    bool supported,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Start Current Class
        FilledButton.icon(
          onPressed: !supported || _busy
              ? null
              : () => _run(() async {
                  if (!await _permission()) return;
                  if (!_store.settings.value.liveActivityEnabled) {
                    await _store.save(
                      _store.settings.value.copyWith(liveActivityEnabled: true),
                    );
                  }
                  final started = await EnhancedLiveCourseService.instance
                      .startCurrent();
                  if (mounted) {
                    _message(
                      started
                          ? '✅ 本节课程实况已启动！下拉通知栏查看精美展示'
                          : '⏰ 当前没有进行中的课程\n请确认已导入课表',
                    );
                  }
                }),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.play_circle_filled_rounded),
          label: const Text(
            '开始本节课程',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),

        // Show Sample
        OutlinedButton.icon(
          onPressed: !supported || _busy
              ? null
              : () => _run(() async {
                  if (!await _permission()) return;
                  await EnhancedLiveCourseService.instance.showSample(
                    upcoming: _upcoming,
                  );
                  if (mounted) {
                    _message('📱 示例通知已发送到通知栏\n2 分钟后将自动消失');
                  }
                }),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: BorderSide(color: colors.primary, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.phonelink_ring_rounded),
          label: const Text(
            '发送预览到通知栏',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),

        // Stop Sample
        TextButton.icon(
          onPressed: !supported || _busy
              ? null
              : () => _run(EnhancedLiveCourseService.instance.stopSample),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('收起预览'),
        ),
      ],
    );
  }

  Widget _buildDeviceInfoCard(
    ThemeData theme,
    ColorScheme colors,
    bool supported,
  ) {
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
              Icon(Icons.devices_rounded, color: colors.primary, size: 24),
              const SizedBox(width: 12),
              Text(
                '设备兼容性',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_device == null)
            Text(
              _error ?? '正在检查设备信息...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else if (!supported)
            _buildInfoRow(
              theme,
              colors,
              Icons.phone_android,
              '当前仅支持 Android 设备',
              null,
            )
          else ...[
            _buildInfoRow(
              theme,
              colors,
              Icons.smartphone_rounded,
              '设备型号',
              '${_device!['manufacturer']} ${_device!['model']}',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              theme,
              colors,
              Icons.android_rounded,
              'Android 版本',
              'API ${_device!['sdk']}',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              theme,
              colors,
              Icons.notifications_active_rounded,
              '通知权限',
              _device!['notificationsEnabled'] == true ? '✅ 已允许' : '❌ 未允许',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              theme,
              colors,
              Icons.alarm_rounded,
              '精确调度',
              _device!['exactAlarms'] == true ? '✅ 已允许' : '⚠️ 可能延迟',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              theme,
              colors,
              Icons.auto_awesome_rounded,
              '灵动岛支持',
              _device!['dynamicIslandSupport'] == true ||
                      _device!['liveUpdates'] == true
                  ? '✅ 支持'
                  : '📱 标准模式',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    ColorScheme colors,
    IconData icon,
    String label,
    String? value,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: colors.primary),
        const SizedBox(width: 12),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        if (value != null)
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _buildCapsuleStyleInfo(ThemeData theme, ColorScheme colors) {
    final service = EnhancedLiveCourseService.instance;
    final description = service.getCapsuleStyleDescription(_device ?? {});

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.tertiaryContainer, colors.secondaryContainer],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '胶囊展示样式',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.6,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsButton(
    ThemeData theme,
    ColorScheme colors,
    bool supported,
  ) {
    return OutlinedButton.icon(
      onPressed: !supported || _busy
          ? null
          : () => _run(
              EnhancedLiveCourseService.instance.openNotificationSettings,
            ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: colors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(Icons.settings_outlined, size: 20, color: colors.onSurface),
      label: Text('打开系统通知设置', style: TextStyle(color: colors.onSurface)),
    );
  }

  Widget _buildPreviewToggle(ThemeData theme, ColorScheme colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      padding: const EdgeInsets.all(4),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: true,
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 18),
                SizedBox(width: 6),
                Text('课前提醒'),
              ],
            ),
          ),
          ButtonSegment(
            value: false,
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.school, size: 18),
                SizedBox(width: 6),
                Text('上课中'),
              ],
            ),
          ),
        ],
        selected: {_upcoming},
        onSelectionChanged: (values) {
          setState(() => _upcoming = values.single);
          _progressController.reset();
          _progressController.forward();
        },
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.primary;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.onPrimary;
            }
            return colors.onSurfaceVariant;
          }),
        ),
      ),
    );
  }

  Widget _buildEnhancedPreviewCard(ThemeData theme, ColorScheme colors) {
    final service = EnhancedLiveCourseService.instance;
    final hasDynamicIsland = service.supportsDynamicIsland(_device ?? {});

    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.surfaceContainer, colors.surfaceContainerHigh],
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              // Capsule Header (simulating dynamic island)
              if (hasDynamicIsland)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withOpacity(0.4),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _upcoming ? Colors.blue : Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _upcoming ? '12 分钟后' : '72 分钟剩余',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.school, color: Colors.white70, size: 16),
                    ],
                  ),
                ),

              // Main Content
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  hasDynamicIsland ? 8 : 20,
                  20,
                  20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _upcoming
                                ? colors.primaryContainer
                                : colors.tertiaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _upcoming
                                    ? Icons.access_time_rounded
                                    : Icons.play_circle_rounded,
                                size: 16,
                                color: _upcoming
                                    ? colors.onPrimaryContainer
                                    : colors.onTertiaryContainer,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _upcoming ? '即将上课' : '进行中',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: _upcoming
                                      ? colors.onPrimaryContainer
                                      : colors.onTertiaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '示例',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Course Name
                    Text(
                      '植物生理学',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Location with icon
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 20,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '文渊馆 B203',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Time Info
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '09:50–11:30',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.onSurfaceVariant,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.timer_outlined,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '第 3–4 节',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),

                    // Progress Bar (only for ongoing)
                    if (!_upcoming) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _progressAnimation.value,
                                minHeight: 8,
                                backgroundColor: colors.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colors.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${(_progressAnimation.value * 100).toInt()}%',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: colors.tertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '距下课还有 72 分钟',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.tertiary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.notifications_active_rounded,
                              size: 20,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '12 分钟后开始上课',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDescription(ThemeData theme, ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_rounded, size: 20, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '这是信息展示示意图。实际通知外观和胶囊样式由您的手机系统和厂商定制界面呈现，效果会更加精美。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainToggle(ThemeData theme, ColorScheme colors, bool supported) {
    return ValueListenableBuilder<CourseNotificationSettings>(
      valueListenable: _store.settings,
      builder: (context, settings, _) {
        return Container(
          decoration: BoxDecoration(
            color: settings.liveActivityEnabled
                ? colors.primaryContainer
                : colors.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: settings.liveActivityEnabled
                  ? colors.primary
                  : colors.outlineVariant,
              width: 2,
            ),
          ),
          child: SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            title: Text(
              '启用课程实况',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '提前 ${settings.minutesBefore} 分钟自动展示，下课后自动收起',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            value: settings.liveActivityEnabled,
            activeColor: colors.primary,
            onChanged: !supported || _busy
                ? null
                : (value) => _run(() async {
                    if (value && !await _permission()) return;
                    final previous = _store.settings.value;
                    await _store.save(
                      previous.copyWith(liveActivityEnabled: value),
                    );
                    try {
                      await EnhancedLiveCourseService.instance.sync();
                    } catch (_) {
                      await _store.save(previous);
                      rethrow;
                    }
                  }),
          ),
        );
      },
    );
  }
}
