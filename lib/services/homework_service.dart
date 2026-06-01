import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:dio/dio.dart';
import '../models/homework_model.dart';
import '../services/app_logger.dart';

class HomeworkService {
  final _logger = AppLogger.instance;
  static const String _homeworkUrl = 'https://mooc1-api.chaoxing.com/mooc-ans/work/stu-work';
  final Dio dio;
  
  HomeworkService(this.dio);

  Future<List<HomeworkModel>> fetchHomeworkList(String studentId) async {
    try {
      _logger.i('📝 Fetching homework list from HTML for: $studentId');
      
      final response = await dio.get(_homeworkUrl);
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch homework: ${response.statusCode}');
      }

      final document = html_parser.parse(response.data);
      final List<dom.Element> listItems = document.querySelectorAll('li[onclick^="goTask"]');
      
      List<HomeworkModel> results = [];
      final now = DateTime.now();

      for (var li in listItems) {
        try {
          final dataUrl = li.attributes['data'] ?? '';
          final imgPath = li.querySelector('.spanImg img')?.attributes['src'] ?? '';
          final isGray = imgPath.contains('task-work-gray.png');
          
          final contentDiv = li.querySelector('div[role="option"]');
          if (contentDiv == null) continue;

          final title = contentDiv.querySelector('p')?.text.trim() ?? '';
          final statusText = contentDiv.querySelector('span.status')?.text.trim() ?? 
                            contentDiv.querySelectorAll('span').firstWhere((e) => !e.attributes.containsKey('class'), orElse: () => dom.Element.tag('span')).text.trim();
          
          String courseName = '';
          String remainTimeStr = '';
          
          final spans = contentDiv.querySelectorAll('span');
          for (var span in spans) {
            final text = span.text.trim();
            if (text.startsWith('《') && text.endsWith('》')) {
              courseName = text;
            } else if (text.contains('剩余') || text.contains('小时') || text.contains('分钟')) {
              remainTimeStr = text;
            }
          }

          HomeworkStatus status;
          if (statusText != '未提交') {
            status = HomeworkStatus.completed;
          } else {
            if (!isGray && remainTimeStr.isNotEmpty) {
              status = HomeworkStatus.pending;
            } else {
              status = HomeworkStatus.archived;
            }
          }

          DateTime? endTime;
          if (remainTimeStr.isNotEmpty) {
            endTime = _parseRemainTime(remainTimeStr, now);
          }

          final id = dataUrl.isNotEmpty ? dataUrl : '\$courseName|\$title';
          final finalUrl = _transformDataUrl(dataUrl);

          results.add(HomeworkModel(
            id: id,
            courseName: courseName,
            title: title,
            endTime: endTime,
            status: status,
            studentId: studentId,
            rawTimeStr: remainTimeStr,
            dataUrl: finalUrl,
          ));
        } catch (e) {
          _logger.w('Failed to parse single homework item: \$e');
        }
      }

      return results;
    } catch (e) {
      _logger.e('❌ Fetch homework failed: \$e');
      rethrow;
    }
  }

  String _transformDataUrl(String url) {
    if (url.isEmpty) return '';
    try {
      final uri = Uri.parse(url);
      final taskrefId = uri.queryParameters['taskrefId'];
      final courseId = uri.queryParameters['courseId'];
      final classId = uri.queryParameters['clazzId'];

      if (taskrefId != null && courseId != null && classId != null) {
        return 'https://mooc1-api.chaoxing.com/mooc-ans/work/phone/task-work?taskrefId=\$taskrefId&courseId=\$courseId&classId=\$classId&ut=s';
      }
      return url;
    } catch (e) {
      return url;
    }
  }

  DateTime? _parseRemainTime(String str, DateTime now) {
    try {
      final clean = str.replaceFirst('剩余', '');
      int totalMinutes = 0;

      final dayMatch = RegExp(r'(\\d+)天').firstMatch(clean);
      final hourMatch = RegExp(r'(\\d+)小时').firstMatch(clean);
      final minuteMatch = RegExp(r'(\\d+)分钟').firstMatch(clean);

      if (dayMatch != null) totalMinutes += int.parse(dayMatch.group(1)!) * 24 * 60;
      if (hourMatch != null) totalMinutes += int.parse(hourMatch.group(1)!) * 60;
      if (minuteMatch != null) totalMinutes += int.parse(minuteMatch.group(1)!);

      if (totalMinutes == 0) return null;
      return now.add(Duration(minutes: totalMinutes + 1));
    } catch (e) {
      return null;
    }
  }
}
