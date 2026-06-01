import 'package:flutter/material.dart';

import '../models/course_model.dart';
import '../utils/date_calculator.dart';
import '../utils/week_parser.dart';
import '../utils/course_color_utils.dart';

class WeeklyCalendarView extends StatefulWidget {
  final List<CourseModel> courses;
  final DateTime firstWeekMonday;

  const WeeklyCalendarView({
    super.key,
    required this.courses,
    required this.firstWeekMonday,
  });

  @override
  WeeklyCalendarViewState createState() => WeeklyCalendarViewState();
}

class WeeklyCalendarViewState extends State<WeeklyCalendarView> {
  late PageController _pageController;
  int _currentWeekNumber = 1;

  @override
  void initState() {
    super.initState();
    final initialWeek = DateCalculator.getCurrentWeekNumber(widget.firstWeekMonday);
    _currentWeekNumber = initialWeek.clamp(1, 20);
    _pageController = PageController(initialPage: _currentWeekNumber - 1);
  }

  void jumpToToday() {
    final nowWeek = DateCalculator.getCurrentWeekNumber(widget.firstWeekMonday);
    _pageController.animateToPage(
      nowWeek.clamp(1, 20) - 1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weekMonday = DateCalculator.getWeekMonday(
      widget.firstWeekMonday,
      _currentWeekNumber,
    );
    final weekSunday = DateCalculator.getWeekSunday(
      widget.firstWeekMonday,
      _currentWeekNumber,
    );

    return Column(
      children: [
        _buildWeekNavigation(_currentWeekNumber, weekMonday, weekSunday),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: 20,
            onPageChanged: (page) {
              setState(() {
                _currentWeekNumber = page + 1;
              });
            },
            itemBuilder: (context, index) {
              final weekNum = index + 1;
              final monday = DateCalculator.getWeekMonday(widget.firstWeekMonday, weekNum);
              return _buildTimetableGrid(monday, weekNum);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWeekNavigation(int weekNumber, DateTime monday, DateTime sunday) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).appBarTheme.backgroundColor,
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            '第$weekNumber周',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF2D3436),
            ),
          ),
          const Spacer(),
          Text(
            '${monday.month}.${monday.day} - ${sunday.month}.${sunday.day}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white54
                  : const Color(0xFF636E72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetableGrid(DateTime weekMonday, int weekNumber) {
    final weekCourses = _getCoursesForWeek(weekNumber);

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        const double sectionHeight = 100.0;
        const double targetGap = 4.0;
        const int totalBigSections = 6;
        final double totalHeight = totalBigSections * (sectionHeight + targetGap) + 40.0;

        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: screenWidth,
              minHeight: totalHeight,
            ),
            child: Column(
              children: [
                _buildWeekdayHeader(screenWidth, weekMonday),
                SizedBox(
                  height: totalHeight - 40,
                  width: screenWidth,
                  child: Stack(
                    children: [
                      _buildFixedTimeAxis(totalBigSections, sectionHeight, targetGap),
                      ..._buildFixedCourseBlocks(weekCourses, screenWidth, sectionHeight, targetGap),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeekdayHeader(double screenWidth, DateTime weekMonday) {
    final labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final columnWidth = (screenWidth - 55) / 7.0;

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          const SizedBox(width: 55),
          ...List.generate(labels.length, (index) {
            final day = weekMonday.add(Duration(days: index));
            return SizedBox(
              width: columnWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(labels[index], style: const TextStyle(fontSize: 11)),
                  Text('${day.month}/${day.day}', style: const TextStyle(fontSize: 10, color: Color(0xFF636E72))),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFixedTimeAxis(int totalSections, double height, double gap) {
    const times = [
      ['08:00', '09:40'],
      ['10:05', '11:45'],
      ['14:30', '16:10'],
      ['16:35', '18:15'],
      ['19:30', '21:10'],
      ['21:20', '23:00'],
    ];

    return Column(
      children: List.generate(totalSections, (index) {
        return Container(
          height: height,
          width: 55,
          margin: EdgeInsets.only(bottom: gap),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                times[index][0],
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white54
                      : const Color(0xFF636E72),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  List<Widget> _buildFixedCourseBlocks(List<CourseModel> courses, double screenWidth, double blockHeight, double gap) {
    final blocks = <Widget>[];
    const timeColumnWidth = 55.0;
    final columnWidth = (screenWidth - timeColumnWidth) / 7.0;

    for (final course in courses) {
      final int bigSectionIndex = (course.startPeriod - 1) ~/ 2;
      final int periodDuration = (course.endPeriod - course.startPeriod + 1);
      final int bigSectionSpan = (periodDuration / 2).ceil();

      final top = bigSectionIndex * (blockHeight + gap);
      final height = bigSectionSpan * blockHeight + (bigSectionSpan - 1) * gap;

      final dayOffset = (course.dayOfWeek - 1) * columnWidth;
      final left = timeColumnWidth + dayOffset + (gap / 2);
      final width = columnWidth - gap;

      blocks.add(
        Positioned(
          top: top,
          left: left,
          width: width,
          height: height,
          child: _buildCourseBlock(course),
        ),
      );
    }
    return blocks;
  }

  Widget _buildCourseBlock(CourseModel course) {
    final color = CourseColorUtils.getColorForCourse(course.name);
    return GestureDetector(
      onTap: () => _showCourseDetail(course),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              course.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            if (course.classroom.isNotEmpty)
              Text(
                course.classroom,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  height: 1.1,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  void _showCourseDetail(CourseModel course) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Text(course.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _detailRow('教室', course.classroom),
              _detailRow('教师', course.teacher),
              _detailRow('周次', course.weeks),
              _detailRow('节次', course.periods),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  List<CourseModel> _getCoursesForWeek(int weekNumber) {
    return widget.courses.where((course) {
      final weeks = WeekParser.parseWeeks(course.weeks);
      return weeks.contains(weekNumber);
    }).toList();
  }
}
