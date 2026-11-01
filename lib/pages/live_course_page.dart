import 'package:flutter/material.dart';

import '../services/course_notification_service.dart';
import '../services/course_notification_settings_store.dart';
import '../services/live_course_service.dart';

class LiveCoursePage extends StatefulWidget {
  const LiveCoursePage({super.key});

  @override
  State<LiveCoursePage> createState() => _LiveCoursePageState();
}

class _LiveCoursePageState extends State<LiveCoursePage>
    with WidgetsBindingObserver {
  final _store = CourseNotificationSettingsStore.instance;
  Map<String, dynamic>? _device;
  bool _busy = false;
  bool _upcoming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      await _store.load();
      final device = await LiveCourseService.instance.deviceInfo();
      if (mounted) {
        setState(() {
          _device = device;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取通知状态，请稍后重试');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (_) {
      if (mounted) _message('未能更新课程实况，请检查通知权限后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
    final liveUpdates = _device?['liveUpdates'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('课程实况')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          Text(
            '下一站，教室。',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '把上课地点和剩余时间留在通知栏。\n不用反复打开课表。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('课前')),
              ButtonSegment(value: false, label: Text('上课中')),
            ],
            selected: {_upcoming},
            onSelectionChanged: (values) =>
                setState(() => _upcoming = values.single),
          ),
          const SizedBox(height: 20),
          Semantics(
            label: '课程信息示例，并非当前课表',
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(16),
                color: colors.surfaceContainerLow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _upcoming ? '12 分钟后上课' : '上课中 · 距下课 72 分钟',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      Text(
                        '示例',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '植物生理学',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '文渊馆 B203',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '09:50–11:30   ·   第 3–4 节',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (!_upcoming) ...[
                    const SizedBox(height: 20),
                    const LinearProgressIndicator(
                      value: .28,
                      minHeight: 3,
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '信息示意。实际通知与胶囊外观由手机系统呈现。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          ValueListenableBuilder<CourseNotificationSettings>(
            valueListenable: _store.settings,
            builder: (context, settings, _) => SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动展示课程通知'),
              subtitle: Text('提前 ${settings.minutesBefore} 分钟出现，下课后自动收起'),
              value: settings.liveActivityEnabled,
              onChanged: !supported || _busy
                  ? null
                  : (value) => _run(() async {
                      if (value && !await _permission()) return;
                      final previous = _store.settings.value;
                      await _store.save(
                        previous.copyWith(liveActivityEnabled: value),
                      );
                      try {
                        await LiveCourseService.instance.sync();
                      } catch (_) {
                        await _store.save(previous);
                        rethrow;
                      }
                    }),
            ),
          ),
          const Divider(height: 28),
          FilledButton.icon(
            onPressed: !supported || _busy
                ? null
                : () => _run(() async {
                    if (!await _permission()) return;
                    if (!_store.settings.value.liveActivityEnabled) {
                      await _store.save(
                        _store.settings.value.copyWith(
                          liveActivityEnabled: true,
                        ),
                      );
                    }
                    final started = await LiveCourseService.instance
                        .startCurrent();
                    if (mounted) {
                      _message(
                        started
                            ? '本节课程实况已开始，拉下通知栏即可查看'
                            : '现在没有正在进行的课程，请先确认已导入课表',
                      );
                    }
                  }),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('开始本节课程'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: !supported || _busy
                ? null
                : () => _run(() async {
                    if (!await _permission()) return;
                    await LiveCourseService.instance.showSample(
                      upcoming: _upcoming,
                    );
                    if (mounted) _message('示例通知已发送，拉下通知栏查看；2 分钟后自动收起');
                  }),
            icon: const Icon(Icons.notifications_none_rounded),
            label: const Text('发送示例到通知栏'),
          ),
          TextButton(
            onPressed: !supported || _busy
                ? null
                : () => _run(LiveCourseService.instance.stopSample),
            child: const Text('收起示例'),
          ),
          const SizedBox(height: 20),
          Text('本机支持', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            _device == null
                ? (_error ?? '正在检查…')
                : !supported
                ? '课程实况目前支持 Android 手机。'
                : '${_device!['manufacturer']} ${_device!['model']} · Android API ${_device!['sdk']}\n'
                      '${_device!['notificationsEnabled'] == true ? '通知已允许' : '通知未允许'} · ${_device!['exactAlarms'] == true ? '准时调度已允许' : '调度可能被系统延后'}\n'
                      '${liveUpdates
                          ? _device!['promoted'] == true
                                ? '系统已展示实时活动'
                                : '支持原生实时活动，胶囊展示由系统决定'
                          : '当前使用原生通知栏展示'}',
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.6,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '荣耀 Android 16 可通过原生实时活动接入灵动胶囊。其他品牌与旧版系统取决于厂商支持；无法展示胶囊时，仍可在通知栏查看完整课程。',
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.6,
              color: colors.onSurfaceVariant,
            ),
          ),
          TextButton.icon(
            onPressed: !supported
                ? null
                : () =>
                      _run(LiveCourseService.instance.openNotificationSettings),
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('系统通知设置'),
          ),
        ],
      ),
    );
  }
}
