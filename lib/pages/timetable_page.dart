import 'package:flutter/material.dart';

import '../models/course_model.dart';
import '../services/timetable_storage.dart';
import '../utils/ics_parser.dart';
import '../widgets/download_timetable_screen.dart';
import '../widgets/empty_timetable_state.dart';
import '../widgets/weekly_calendar_view.dart';

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  final GlobalKey<WeeklyCalendarViewState> _weeklyKey = GlobalKey();

  List<CourseModel> _courses = [];
  DateTime? _firstWeekMonday;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLocalTimetable();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的课表'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _openDownload,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            onPressed: _isLoading ? null : _handleTodayClick,
            icon: const Icon(Icons.today_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ),
          Expanded(
            child: _courses.isEmpty || _firstWeekMonday == null
                ? EmptyTimetableState(onDownload: _openDownload)
                : WeeklyCalendarView(
                    key: _weeklyKey,
                    courses: _courses,
                    firstWeekMonday: _firstWeekMonday!,
                  ),
          ),
        ],
      ),
    );
  }

  void _handleTodayClick() {
    _weeklyKey.currentState?.jumpToToday();
  }

  Future<void> _loadLocalTimetable() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final storage = TimetableStorage();
      final hasTimetable = await storage.hasLocalTimetable();

      if (hasTimetable) {
        final icsContent = await storage.readTimetable();
        final metadata = await storage.readMetadata();

        if (icsContent != null) {
          final courses = IcsParser.parse(icsContent);
          DateTime? firstWeekMonday;
          if (metadata != null && metadata['firstWeekMonday'] != null) {
            firstWeekMonday = DateTime.parse(metadata['firstWeekMonday'] as String);
          }

          setState(() {
            _courses = courses;
            _firstWeekMonday = firstWeekMonday;
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openDownload() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await Navigator.of(context).push<TimetableImportResult>(
      MaterialPageRoute(builder: (_) => const DownloadTimetableScreen()),
    );

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _courses = result.courses;
        _firstWeekMonday = result.firstWeekMonday;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
