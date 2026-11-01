import 'package:flutter/material.dart';
import 'pages/capsule_notifications_settings_page.dart';

void main() {
  runApp(const TestCapsuleSettingsApp());
}

class TestCapsuleSettingsApp extends StatelessWidget {
  const TestCapsuleSettingsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '胶囊通知设置测试',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const CapsuleNotificationsSettingsPage(),
    );
  }
}
