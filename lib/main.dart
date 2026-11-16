import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/background_provider.dart';
import 'services/app_cookie_manager.dart';
import 'services/course_notification_service.dart';
import 'pages/main_navigator.dart';
import 'pages/onboarding_page.dart';
import 'providers/theme_provider.dart';
import 'providers/motion_provider.dart';
import 'providers/app_theme_provider.dart';
import 'widgets/app_motion.dart';
import 'pages/timetable_page.dart';
import 'pages/live_course_page.dart';
import 'services/live_course_service.dart';
import 'services/unified_capsule_service.dart';

final _navigatorKey = GlobalKey<NavigatorState>();
bool _homeReady = false;
bool _pendingCourseTimetable = false;

void _openCourseTimetable() {
  if (!_homeReady || _navigatorKey.currentState == null) {
    _pendingCourseTimetable = true;
    return;
  }
  _navigatorKey.currentState?.push(
    MaterialPageRoute<void>(builder: (_) => const TimetablePage()),
  );
}

void _onHomeReady() {
  _homeReady = true;
  if (_pendingCourseTimetable) {
    _pendingCourseTimetable = false;
    _openCourseTimetable();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await CourseNotificationService.instance.initialize();
    await CourseNotificationService.instance.rescheduleIfEnabled();
    await UnifiedCapsuleService.instance.syncLocal();
  } catch (_) {
    // Notifications are optional; never prevent the main UI from starting.
  }
  await AppCookieManager().initialize(); // 初始化 Cookie 库
  runApp(const ProviderScope(child: SmartHunanAgriApp()));
  if (LiveCourseService.instance.supported) {
    LiveCourseService.channel.setMethodCallHandler((call) async {
      if (call.method == 'openTimetable') _openCourseTimetable();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final open = await LiveCourseService.channel.invokeMethod<bool>(
        'consumeOpen',
      );
      if (open == true) _openCourseTimetable();
    });
  }
}

class SmartHunanAgriApp extends ConsumerStatefulWidget {
  const SmartHunanAgriApp({super.key});

  @override
  ConsumerState<SmartHunanAgriApp> createState() => _SmartHunanAgriAppState();
}

class _SmartHunanAgriAppState extends ConsumerState<SmartHunanAgriApp> {
  // Track the visual theme inputs so we only pay for MaterialApp's 200ms
  // AnimatedTheme crossfade when colors/background/mode actually change.
  // Motion-only changes snap instantly (Duration.zero) instead of lerping
  // the whole ThemeData every frame for 200ms — the source of the jank when
  // picking a transition in settings.
  Color? _lastColor;
  AppBackgroundSettings? _lastBackground;
  ThemeMode? _lastMode;

  @override
  Widget build(BuildContext context) {
    final themeColor = ref.watch(themeColorProvider);
    final themeMode = ref.watch(themeModeProvider);
    final background = ref.watch(appBackgroundProvider);
    final motion = ref.watch(motionSettingsProvider);

    final visualChanged =
        _lastColor != themeColor ||
        _lastBackground?.hasImage != background.hasImage ||
        _lastBackground?.imagePath != background.imagePath ||
        _lastBackground?.blurSigma != background.blurSigma ||
        _lastMode != themeMode;
    _lastColor = themeColor;
    _lastBackground = background;
    _lastMode = themeMode;

    final baseLight = ref.watch(baseAppThemeProvider(Brightness.light));
    final baseDark = ref.watch(baseAppThemeProvider(Brightness.dark));

    return MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      debugShowCheckedModeBanner: false,
      theme: applyMotionToTheme(baseLight, motion),
      darkTheme: applyMotionToTheme(baseDark, motion),
      themeMode: themeMode,
      themeAnimationDuration: visualChanged
          ? kThemeAnimationDuration
          : Duration.zero,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        if (!background.hasImage) {
          return ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: child,
          );
        }
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: background.blurSigma,
                sigmaY: background.blurSigma,
              ),
              child: Transform.scale(
                scale: 1.04,
                child: Image.file(
                  File(background.imagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
            ColoredBox(
              color: (isDark ? Colors.black : Colors.white).withValues(
                alpha: isDark ? 0.24 : 0.14,
              ),
            ),
            child,
          ],
        );
      },
      navigatorKey: _navigatorKey,
      routes: {'/course-live': (_) => const LiveCoursePage()},
      home: OnboardingGate(onReady: _onHomeReady, child: const MainNavigator()),
    );
  }
}
