import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/app_constants.dart';
import '../models/score_model.dart';
import 'app_logger.dart';
import 'dio_client.dart';

class ScoreService {
  ScoreService._internal();

  static final ScoreService instance = ScoreService._internal();

  final _logger = AppLogger.instance;
  static const String _scoreUrl = '${AppConstants.portalBaseUrl}/pc/view/scoreIndex';

  Future<void> _ensureReady() async {
    await DioClient().initialize();
  }

  Future<Map<String, dynamic>> fetchScores({String? xn, String? xq}) async {
    try {
      await _ensureReady();

      final queryParams = <String, String>{};
      if (xn != null) queryParams['xn'] = xn;
      if (xq != null) queryParams['xq'] = xq;

      final response = await DioClient().dio.get(
        _scoreUrl,
        queryParameters: queryParams,
        options: Options(
          headers: {
            'Referer': '${AppConstants.portalBaseUrl}/pc/template/scoreIndex',
            'Host': 'portal.hunau.edu.cn',
          },
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('获取成绩失败: HTTP ${response.statusCode}');
      }

      final htmlContent = response.data.toString();
      if (htmlContent.contains('统一登录门户') || htmlContent.contains('cas/login')) {
        throw Exception('会话已失效，请重新登录');
      }

      return _parseScoreHtml(htmlContent);
    } catch (e) {
      _logger.e('❌ Fetch score failed: $e');
      rethrow;
    }
  }

  Map<String, dynamic> _parseScoreHtml(String html) {
    final document = html_parser.parse(html);

    final semesterList = <SemesterModel>[];
    final semesterElements = document.querySelectorAll('.selectSemesterList li');

    for (final element in semesterElements) {
      final text = element.text.trim();
      final isActive = element.className.contains('active');
      final onclick = element.attributes['onclick'] ?? '';
      final match = RegExp(r"selXq\('([^']+)','([^']+)'\)").firstMatch(onclick);

      if (match != null) {
        semesterList.add(
          SemesterModel(
            value: match.group(1)!,
            xq: match.group(2)!,
            name: text,
            isActive: isActive,
          ),
        );
      }
    }

    final scoreList = <ScoreModel>[];
    final scoreElements = document.querySelectorAll('.subjectItem');

    for (final element in scoreElements) {
      final courseName = element.querySelector('.subjectName .line_slh')?.text.trim() ?? '未知课程';
      final scoreVal = element.querySelector('.subjectValue span')?.text.trim() ?? 'N/A';

      final id = element.attributes['id'];
      String? credit;
      String? dailyScore;
      String? examType;

      if (id != null) {
        credit = document.querySelector('#xf$id')?.attributes['value'];
        dailyScore = document.querySelector('#pscj$id')?.attributes['value'];
        examType = document.querySelector('#cxbj$id')?.attributes['value'];
        if (examType == '1') {
          examType = '重修';
        } else if (examType == '0') {
          examType = '正常考试';
        }
      }

      scoreList.add(
        ScoreModel(
          courseName: courseName,
          score: scoreVal,
          credit: credit,
          dailyScore: dailyScore,
          examType: examType,
        ),
      );
    }

    return {
      'semesters': semesterList,
      'scores': scoreList,
    };
  }
}
