import 'dart:async';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/homework_provider.dart';
import '../providers/notice_provider.dart';
import '../providers/background_provider.dart';
import '../services/auth_guard.dart';
import '../services/agent_settings_store.dart';
import 'agent_page.dart';
import 'function_page.dart';
import 'home_page.dart';
import 'homework_page.dart';
import 'notice_page.dart';

class MainNavigator extends ConsumerWidget {
  const MainNavigator({super.key});

  static const _destinations = [
    (Icons.apps_outlined, Icons.apps_rounded, '功能'),
    (Icons.notifications_none_rounded, Icons.notifications_rounded, '通知'),
    (Icons.assignment_outlined, Icons.assignment_rounded, '作业'),
    (Icons.smart_toy_outlined, Icons.smart_toy_rounded, 'Agent'),
  ];

  Future<void> _openDestination(
    BuildContext context,
    WidgetRef ref,
    int index,
  ) async {
    if (index == 3 && !ref.read(agentSettingsProvider).config.enabled) return;
    if (index != 3) {
      final result = await AuthGuard.ensureLoggedIn(context);
      if (!result.allowed || !context.mounted) return;

      if (index == 1) {
        ref.read(noticeProvider.notifier).refresh();
      } else if (index == 2) {
        ref.read(homeworkProvider.notifier).refresh();
      }
    }

    if (!context.mounted) return;
    final Widget page = switch (index) {
      0 => const FunctionPage(),
      1 => const NoticePage(),
      2 => const HomeworkPage(),
      3 => const AgentPage(),
      _ => const HomePage(),
    };

    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final hasBackground = ref.watch(appBackgroundProvider).hasImage;
    final agentEnabled = ref.watch(agentSettingsProvider).config.enabled;

    return Scaffold(
      // Keep a muted surface behind the rail so its translucent material has
      // something to separate from the white content panel.
      backgroundColor: hasBackground
          ? Colors.transparent
          : colors.surfaceContainerHighest,
      body: Row(
        children: [
          SizedBox(
            width: 78,
            child: CampusNavigationRail(
              agentEnabled: agentEnabled,
              onChanged: (index) => _openDestination(context, ref, index),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(34),
              ),
              child: ColoredBox(
                color: hasBackground
                    ? colors.surface.withValues(alpha: 0.72)
                    : colors.surface,
                child: const HomePage(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CampusNavigationRail extends StatelessWidget {
  const CampusNavigationRail({
    super.key,
    required this.onChanged,
    required this.agentEnabled,
    this.showSystemStatus = true,
  });

  final ValueChanged<int> onChanged;
  final bool agentEnabled;
  final bool showSystemStatus;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = colors.onSurfaceVariant;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.78),
            border: Border(
              right: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.9),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(2, 0),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                children: [
                  if (showSystemStatus)
                    _TimeAndBatteryStatus(foreground: foreground),
                  const Spacer(),
                  ...List.generate(agentEnabled ? 4 : 3, (index) {
                    final destination = MainNavigator._destinations[index];

                    return Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Tooltip(
                        message: destination.$3,
                        child: Semantics(
                          button: true,
                          label: destination.$3,
                          child: InkResponse(
                            onTap: () => onChanged(index),
                            radius: 27,
                            customBorder: const CircleBorder(),
                            child: SizedBox(
                              width: 54,
                              height: 54,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    destination.$1,
                                    size: 22,
                                    color: foreground,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    destination.$3,
                                    style: TextStyle(
                                      color: foreground,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeAndBatteryStatus extends StatefulWidget {
  const _TimeAndBatteryStatus({required this.foreground});

  final Color foreground;

  @override
  State<_TimeAndBatteryStatus> createState() => _TimeAndBatteryStatusState();
}

class _TimeAndBatteryStatusState extends State<_TimeAndBatteryStatus> {
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batterySubscription;
  Timer? _refreshTimer;
  int? _batteryLevel;
  BatteryState _batteryState = BatteryState.unknown;

  @override
  void initState() {
    super.initState();
    _refreshBattery();
    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _batteryState = state);
      _refreshBattery();
    });
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _refreshBattery();
    });
  }

  Future<void> _refreshBattery() async {
    try {
      final level = await _battery.batteryLevel;
      if (!mounted) return;
      setState(() => _batteryLevel = level.clamp(0, 100));
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _batterySubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final level = _batteryLevel;
    final charging =
        _batteryState == BatteryState.charging ||
        _batteryState == BatteryState.full;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        label: level == null ? '电池电量未知' : '电池电量 $level%',
        child: Column(
          children: [
            Text(
              now.hour.toString().padLeft(2, '0'),
              style: TextStyle(
                color: widget.foreground,
                fontSize: 27,
                height: 1,
                fontWeight: FontWeight.w300,
              ),
            ),
            Container(
              width: 22,
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: 7),
              color: widget.foreground.withValues(alpha: 0.45),
            ),
            Text(
              now.minute.toString().padLeft(2, '0'),
              style: TextStyle(
                color: widget.foreground,
                fontSize: 27,
                height: 1,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 17,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.foreground.withValues(alpha: 0.7),
                      width: 1.4,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: (level ?? 0) / 100,
                            child: ColoredBox(
                              color: widget.foreground.withValues(alpha: 0.82),
                            ),
                          ),
                        ),
                        if (charging)
                          Icon(
                            Icons.bolt_rounded,
                            size: 11,
                            color: level != null && level > 48
                                ? Theme.of(context).colorScheme.surface
                                : widget.foreground,
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 3,
                  height: 7,
                  decoration: BoxDecoration(
                    color: widget.foreground.withValues(alpha: 0.7),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              level == null ? '--%' : '$level%',
              style: TextStyle(
                color: widget.foreground.withValues(alpha: 0.78),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
