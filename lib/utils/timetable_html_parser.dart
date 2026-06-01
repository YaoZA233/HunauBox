import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

import '../models/course_model.dart';
import '../services/app_logger.dart';

class TimetableHtmlParser {
  static final _logger = AppLogger.instance;

  static List<CourseModel> parseTimetable(String htmlContent) {
    try {
      final document = html_parser.parse(htmlContent);
      final courses = <CourseModel>[];

      dom.Element? table = document.querySelector('table#timetable');
      table ??= document.querySelector('table') ??
          document.querySelector('.kbtable') ??
          document.querySelector('[class*="timetable"]');

      if (table == null) {
        throw Exception('未找到课表表格');
      }

      final rows = table.querySelectorAll('tr');
      for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        final cells = row.querySelectorAll('td');

        for (var dayIndex = 0; dayIndex < cells.length; dayIndex++) {
          final cell = cells[dayIndex];
          final dayOfWeek = dayIndex + 1;

          final hiddenDivs = cell.querySelectorAll('div.kbcontent');
          for (final div in hiddenDivs) {
            final courseId = div.id;
            if (courseId.isEmpty) continue;

            final idParts = courseId.split('-');
            if (idParts.length < 3) continue;

            final slot = int.tryParse(idParts.last);
            if (slot == null) continue;

            final divHtml = div.innerHtml;
            final courseBlocks = divHtml.split(RegExp(r'-{5,}<br>'));

            for (int blockIndex = 0; blockIndex < courseBlocks.length; blockIndex++) {
              final blockHtml = courseBlocks[blockIndex].trim();
              if (blockHtml.isEmpty || blockHtml == '&nbsp;') continue;

              final blockId = courseBlocks.length > 1
                  ? '${courseId}_block${blockIndex + 1}'
                  : courseId;

              final tempDiv = dom.Element.html('<div>$blockHtml</div>');

              final courseName = _extractCourseName(tempDiv);
              if (courseName.isEmpty || courseName == '\u00a0') continue;

              final teacher = _extractFontText(tempDiv, '教师');
              final weekPeriodText = _extractFontText(tempDiv, '周次(节次)');
              final (weeks, periods) = _parseWeeksAndPeriods(weekPeriodText);
              final classroom = _extractFontText(tempDiv, '教室');
              final (startPeriod, endPeriod) = _calculatePeriods(slot, periods);

              courses.add(CourseModel(
                id: blockId,
                name: courseName,
                teacher: teacher,
                classroom: classroom,
                weeks: weeks,
                periods: periods,
                dayOfWeek: dayOfWeek,
                startPeriod: startPeriod,
                endPeriod: endPeriod,
              ));
            }
          }
        }
      }

      return courses;
    } catch (e) {
      _logger.e('❌ Timetable parse failed: $e');
      rethrow;
    }
  }

  static String _extractCourseName(dom.Element div) {
    final innerHtml = div.innerHtml;
    final brSlashIndex = innerHtml.indexOf('<br/>');
    final brIndex = innerHtml.indexOf('<br>');

    int firstBrIndex = -1;
    if (brSlashIndex >= 0 && brIndex >= 0) {
      firstBrIndex = brSlashIndex < brIndex ? brSlashIndex : brIndex;
    } else if (brSlashIndex >= 0) {
      firstBrIndex = brSlashIndex;
    } else if (brIndex >= 0) {
      firstBrIndex = brIndex;
    }

    if (firstBrIndex > 0) {
      return innerHtml.substring(0, firstBrIndex).trim();
    }

    return div.text.trim();
  }

  static String _extractFontText(dom.Element div, String title) {
    final fonts = div.querySelectorAll('font');
    for (final font in fonts) {
      if (font.attributes['title'] == title) {
        return font.text.trim();
      }
    }
    return '';
  }

  static (String, String) _parseWeeksAndPeriods(String text) {
    final weekMatch = RegExp(r'([\d,\-]+)\(周\)').firstMatch(text);
    final periodMatch = RegExp(r'\[(\d+(?:-\d+)?(?:-\d+)*(?:-\d+)*)节\]').firstMatch(text);

    String weeks = '';
    if (weekMatch != null) {
      weeks = '${weekMatch.group(1)}(周)';
    }

    String periods = '';
    if (periodMatch != null) {
      periods = periodMatch.group(1)!;
    }

    return (weeks, periods);
  }

  static (int, int) _calculatePeriods(int slot, String periods) {
    if (periods.isNotEmpty) {
      final parts = periods.split('-');
      if (parts.length >= 2) {
        final start = int.tryParse(parts.first) ?? 1;
        final end = int.tryParse(parts.last) ?? 2;
        return (start, end);
      }
    }

    final start = (slot - 1) * 2 + 1;
    return (start, start + 1);
  }
}
