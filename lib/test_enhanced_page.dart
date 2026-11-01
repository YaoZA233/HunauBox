import 'package:flutter/material.dart';
import 'pages/enhanced_live_course_page.dart';

void main() {
  runApp(const TestEnhancedApp());
}

class TestEnhancedApp extends StatelessWidget {
  const TestEnhancedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '增强课程实况测试',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const EnhancedLiveCoursePage(),
    );
  }
}
