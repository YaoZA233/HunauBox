import 'package:flutter/material.dart';

import '../models/course_model.dart';
import '../services/timetable_service.dart';

class TimetableImportResult {
  const TimetableImportResult({
    required this.courses,
    required this.firstWeekMonday,
    required this.semester,
  });

  final List<CourseModel> courses;
  final DateTime firstWeekMonday;
  final String semester;
}

/// 当前学期课表自动同步页。
///
/// 页面打开后立即从移动教务拉取，无需选择学期或填写开学日期。
class DownloadTimetableScreen extends StatefulWidget {
  const DownloadTimetableScreen({super.key});

  @override
  State<DownloadTimetableScreen> createState() =>
      _DownloadTimetableScreenState();
}

class _DownloadTimetableScreenState extends State<DownloadTimetableScreen> {
  final _timetableService = TimetableService();

  bool _isLoading = true;
  String _status = '正在准备同步…';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          title: const Text('同步课表'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _error == null
                          ? Icons.calendar_month_rounded
                          : Icons.sync_problem_rounded,
                      size: 34,
                      color: _error == null
                          ? colors.onPrimaryContainer
                          : colors.error,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _error == null ? '正在同步当前学期' : '同步没有完成',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error ?? '系统会自动识别当前学期和开学日期，无需手动选择。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _error == null
                          ? colors.onSurfaceVariant
                          : colors.error,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (_isLoading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      _status,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ] else if (_error != null)
                    FilledButton.icon(
                      onPressed: _sync,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重新同步'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sync() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _status = '正在准备同步…';
    });

    try {
      final result = await _timetableService.downloadAndSaveTimetable(
        onProgress: (progress) {
          if (mounted) setState(() => _status = progress);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        TimetableImportResult(
          courses: result.courses,
          firstWeekMonday: result.firstWeekMonday,
          semester: result.semester,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}
