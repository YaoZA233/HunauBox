import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/background_provider.dart';
import 'services/app_cookie_manager.dart';
import 'services/course_notification_service.dart';
import 'pages/main_navigator.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await CourseNotificationService.instance.initialize();
    await CourseNotificationService.instance.rescheduleIfEnabled();
  } catch (_) {
    // Notifications are optional; never prevent the main UI from starting.
  }
  await AppCookieManager().initialize(); // 初始化 Cookie 库
  runApp(const ProviderScope(child: SmartHunanAgriApp()));
}

class SmartHunanAgriApp extends ConsumerWidget {
  const SmartHunanAgriApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeColor = ref.watch(themeColorProvider);
    final themeMode = ref.watch(themeModeProvider);
    final background = ref.watch(appBackgroundProvider);

    ThemeData buildTheme(Brightness brightness) {
      final isDark = brightness == Brightness.dark;
      final scheme = ColorScheme.fromSeed(
        seedColor: themeColor,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
      );
      final surface = isDark
          ? const Color(0xFF101412)
          : const Color(0xFFF5F7F4);
      final card = isDark ? const Color(0xFF1A201C) : const Color(0xFFFFFFFF);
      final outline = isDark
          ? const Color(0xFF3E4941)
          : const Color(0xFFDCE4DD);
      final textTheme = ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
        fontFamily: 'sans-serif',
      );

      return ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorScheme: scheme,
        scaffoldBackgroundColor: background.hasImage
            ? Colors.transparent
            : surface,
        textTheme: textTheme.copyWith(
          headlineSmall: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.16,
          ),
          titleLarge: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
          titleMedium: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
          bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.45),
          bodySmall: textTheme.bodySmall?.copyWith(height: 1.38),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: surface.withValues(
            alpha: background.hasImage ? 0.82 : 0.94,
          ),
          foregroundColor: scheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: textTheme.titleLarge?.copyWith(
            color: scheme.onSurface,
            fontSize: 20,
          ),
        ),
        cardTheme: CardThemeData(
          color: card,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: outline),
          ),
          margin: EdgeInsets.zero,
        ),
        dividerTheme: DividerThemeData(color: outline, thickness: 0.8),
        listTileTheme: ListTileThemeData(
          iconColor: scheme.onSurfaceVariant,
          textColor: scheme.onSurface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDark ? const Color(0xFF202720) : const Color(0xFFF0F3F0),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.primary, width: 1.5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isDark
              ? const Color(0xFF283129)
              : const Color(0xFF253127),
          contentTextStyle: TextStyle(
            color: isDark ? scheme.onSurface : Colors.white,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        if (!background.hasImage) return child;
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
      home: const MainNavigator(),
    );
  }
}
