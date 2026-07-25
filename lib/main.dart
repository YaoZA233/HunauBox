import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, 
        colorSchemeSeed: themeColor,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA), // Google Light Gray background
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8F9FA),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Color(0xFF202124)),
          titleTextStyle: TextStyle(color: Color(0xFF202124), fontSize: 18, fontWeight: FontWeight.w500),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE8EAED), width: 1),
          ),
          margin: EdgeInsets.zero,
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF5F6368),
          textColor: Color(0xFF202124),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 64,
          indicatorColor: themeColor.withOpacity(0.1),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IconThemeData(color: themeColor);
            }
            return const IconThemeData(color: Color(0xFF5F6368));
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: themeColor);
            }
            return const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF5F6368));
          }),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: themeColor,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFF3C4043)),
          ),
          margin: EdgeInsets.zero,
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 64,
          indicatorColor: themeColor.withValues(alpha: 0.24),
        ),
      ),
      themeMode: themeMode,
      home: const MainNavigator(),
    );
  }
}

