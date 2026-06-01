import 'package:html/parser.dart' as html_parser;

import '../models/app_constants.dart';
import '../models/classroom_model.dart';
import 'app_logger.dart';
import 'dio_client.dart';

class ClassroomService {
  ClassroomService._internal();

  static final ClassroomService instance = ClassroomService._internal();

  final _logger = AppLogger.instance;

  static const String _indexUrl = '${AppConstants.portalBaseUrl}/pc/view/kxClassRoomIndex';
  static const String _queryUrl = '${AppConstants.portalBaseUrl}/pc/view/refreshKxClassRoom';

  Future<void> _ensureReady() async {
    await DioClient().initialize();
  }

  Future<ClassroomInquiryOptions> fetchOptions() async {
    try {
      await _ensureReady();

      final response = await DioClient().dio.get(_indexUrl);
      final html = response.data.toString();
      if (html.contains('统一登录门户') || html.contains('cas/login')) {
        throw Exception('会话已失效，请重新登录');
      }

      final document = html_parser.parse(html);

      final buildings = document
          .querySelectorAll('#jxlCondition a')
          .map((e) => e.text.trim())
          .where((value) => value.isNotEmpty)
          .toList();

      final sections = document
          .querySelectorAll('#jcCondition a')
          .map((e) => e.text.trim())
          .where((value) => value.isNotEmpty)
          .toList();

      final weeks = document
          .querySelectorAll('#zcCondition a')
          .map((e) => e.text.trim())
          .where((value) => value.isNotEmpty)
          .toList();

      final days = document.querySelectorAll('#weekCondition a').map((e) {
        return {
          'label': e.text.trim(),
          'value': e.attributes['data-value'] ?? '',
        };
      }).where((item) => item['label']?.isNotEmpty == true && item['value']?.isNotEmpty == true).toList();

      return ClassroomInquiryOptions(
        buildings: buildings,
        sections: sections,
        weeks: weeks,
        days: days,
      );
    } catch (e) {
      _logger.e('❌ Fetch classroom options failed: $e');
      rethrow;
    }
  }

  Future<List<ClassroomModel>> queryClassrooms({
    required String building,
    required String week,
    required String jc,
    required String day,
  }) async {
    try {
      await _ensureReady();

      final response = await DioClient().dio.get(
        _queryUrl,
        queryParameters: {
          'jxl': building,
          'week': day,
          'jc': jc,
          'zc': week,
        },
        options: DioClient.getOptions(
          referer: _indexUrl,
          isXmlHttpRequest: true,
        ),
      );

      final data = response.data;
      if (data is String && (data.contains('统一登录门户') || data.contains('cas/login'))) {
        throw Exception('会话已失效，请重新登录');
      }

      List<dynamic> classroomList = const [];
      if (data is Map<String, dynamic> && data['data'] is List) {
        classroomList = data['data'] as List<dynamic>;
      } else if (data is Map<String, dynamic> && data['resultData'] is List) {
        classroomList = data['resultData'] as List<dynamic>;
      } else if (data is Map<String, dynamic> && data['rows'] is List) {
        classroomList = data['rows'] as List<dynamic>;
      } else if (data is List) {
        classroomList = data;
      }

      return classroomList
          .whereType<Map>()
          .map((json) => ClassroomModel.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();
    } catch (e) {
      _logger.e('❌ Query classrooms failed: $e');
      rethrow;
    }
  }
}