import 'package:flutter/material.dart';

class CourseColorUtils {
  static const List<Color> _palette = [
    Color(0xFFEF5350),
    Color(0xFFE53935),
    Color(0xFFD32F2F),
    Color(0xFFEC407A),
    Color(0xFFD81B60),
    Color(0xFFC2185B),
    Color(0xFFAB47BC),
    Color(0xFF8E24AA),
    Color(0xFF7B1FA2),
    Color(0xFF7E57C2),
    Color(0xFF5E35B1),
    Color(0xFF512DA8),
    Color(0xFF5C6BC0),
    Color(0xFF3949AB),
    Color(0xFF303F9F),
    Color(0xFF42A5F5),
    Color(0xFF1E88E5),
    Color(0xFF1976D2),
    Color(0xFF03A9F4),
    Color(0xFF0288D1),
    Color(0xFF00BCD4),
    Color(0xFF0097A7),
    Color(0xFF26A69A),
    Color(0xFF00897B),
    Color(0xFF00796B),
    Color(0xFF66BB6A),
    Color(0xFF43A047),
    Color(0xFF388E3C),
    Color(0xFF8BC34A),
    Color(0xFF689F38),
    Color(0xFFC0CA33),
    Color(0xFF9E9D24),
    Color(0xFFFFA000),
    Color(0xFFFF9800),
    Color(0xFFFB8C00),
    Color(0xFFF57C00),
    Color(0xFFFF7043),
    Color(0xFFF4511E),
    Color(0xFFE64A19),
    Color(0xFF8D6E63),
  ];

  static Color getColorForCourse(String courseName) {
    if (courseName.isEmpty) return _palette[0];

    final hash = courseName.hashCode.abs();
    final index = (hash + (hash >> 8)) % _palette.length;
    return _palette[index];
  }
}
