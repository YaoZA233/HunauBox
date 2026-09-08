import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/homework_provider.dart';
import '../providers/notice_provider.dart';
import '../providers/background_provider.dart';
import '../services/auth_guard.dart';
import 'function_page.dart';
import 'home_page.dart';
import 'homework_page.dart';
import 'notice_page.dart';
import 'settings_page.dart';

class MainNavigator extends ConsumerWidget {
  const MainNavigator({super.key});

  static const _destinations = [
    (Icons.apps_outlined, Icons.apps_rounded, '功能'),
    (Icons.notifications_none_rounded, Icons.notifications_rounded, '通知'),
    (Icons.assignment_outlined, Icons.assignment_rounded, '作业'),
    (Icons.settings_outlined, Icons.settings_rounded, '设置'),
  ];

  Future<void> _openDestination(
    BuildContext context,
    WidgetRef ref,
    int index,
  ) async {
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
      3 => const SettingsPage(),
      _ => const HomePage(),
    };

    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasBackground = ref.watch(appBackgroundProvider).hasImage;

    return Scaffold(
      backgroundColor: hasBackground
          ? Colors.transparent
          : isDark
          ? const Color(0xFF18221D)
          : const Color(0xFFE2E8E1),
      body: Row(
        children: [
          SizedBox(
            width: 78,
            child: _SideRail(
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

class _SideRail extends StatelessWidget {
  const _SideRail({required this.onChanged});

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark
        ? const Color(0xFFE8EEE8)
        : const Color(0xFF3D5145);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            _TimeAndBatteryStatus(foreground: foreground),
            const Spacer(),
            ...List.generate(MainNavigator._destinations.length, (index) {
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
                            Icon(destination.$1, size: 22, color: foreground),
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
