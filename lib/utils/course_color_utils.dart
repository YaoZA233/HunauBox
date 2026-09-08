import 'package:flutter/material.dart';

class CourseColorUtils {
  static const List<Color> _palette = [
    Color(0xFFB86F62),
    Color(0xFFA85D55),
    Color(0xFF986A72),
    Color(0xFF9B7185),
    Color(0xFF886A7C),
    Color(0xFF766A83),
    Color(0xFF687596),
    Color(0xFF5D7890),
    Color(0xFF587F8A),
    Color(0xFF5C8580),
    Color(0xFF648875),
    Color(0xFF718966),
    Color(0xFF7F8B5D),
    Color(0xFF8E8855),
    Color(0xFF9A814C),
    Color(0xFFA47A4B),
    Color(0xFFAA7252),
    Color(0xFF936B5B),
    Color(0xFF806B62),
    Color(0xFF6F7470),
    Color(0xFF637A78),
    Color(0xFF577F79),
    Color(0xFF5A8770),
    Color(0xFF668B68),
    Color(0xFF78905F),
    Color(0xFF898B5A),
    Color(0xFF9B8055),
    Color(0xFFA77455),
    Color(0xFFB36D5D),
    Color(0xFF9B6570),
    Color(0xFF846A7B),
    Color(0xFF736D87),
    Color(0xFF657B94),
    Color(0xFF5F8490),
    Color(0xFF628982),
    Color(0xFF6D8A73),
    Color(0xFF7D8D67),
    Color(0xFF8D8660),
    Color(0xFF9B7957),
    Color(0xFFA86E57),
  ];

  static Color getColorForCourse(String courseName) {
    if (courseName.isEmpty) return _palette[0];

    final hash = courseName.hashCode.abs();
    final index = (hash + (hash >> 8)) % _palette.length;
    return _palette[index];
  }
}
