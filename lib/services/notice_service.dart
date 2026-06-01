import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import '../models/app_constants.dart';
import '../models/message_model.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';

class NoticeService {
  final _logger = AppLogger.instance;
  late final Dio dio;

  NoticeService() {
    dio = Dio();
    dio.interceptors.add(CookieManager(AppCookieManager().dioCookieJar));
  }
  
  Future<NoticeResult> fetchMessageList({String? lastValue}) async {
    try {
      _logger.i('📨 Fetching notices from Chaoxing...');
      
      final response = await dio.post(
        AppConstants.chaoxingNoticeListUrl,
        data: {
          'type': 2,                         
          'notice_type': '',
          'lastValue': lastValue ?? '',      
          'sort': '',
          'folderUUID': '',
          'kw': '',
          'startTime': '',
          'endTime': '',
          'gKw': '',
          'gName': '',
          'year': DateTime.now().year,       
          'tag': '',
          'fidsCode': '',
          'queryFolderNoticePrevYear': 0,
          'filterSenderPuids': '',
          'filterTags': '',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': 'https://notice.chaoxing.com/pc/notice/myNotice',
          },
        ),
      );
      
      final data = response.data;
      if (data is! Map) {
        return NoticeResult(messages: [], hasMore: false);
      }
      
      final notices = data['notices'] as Map?;
      if (notices == null) {
        return NoticeResult(messages: [], hasMore: false);
      }
      
      final list = notices['list'] as List?;
      if (list == null || list.isEmpty) {
        return NoticeResult(messages: [], hasMore: false);
      }
      
      final nextLastValue = notices['lastGetId']?.toString();
      
      final messages = list
          .map((item) => MessageModel.fromChaoxingJson(item as Map<String, dynamic>))
          .toList();
      
      return NoticeResult(
        messages: messages,
        nextLastValue: nextLastValue,
        hasMore: nextLastValue != null && nextLastValue.isNotEmpty,
      );
    } catch (e) {
      _logger.e('❌ Failed fetching notices: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchNoticeDetail(String uuid) async {
    try {
      final url = '${AppConstants.chaoxingNoticeBaseUrl}/pc/notice/$uuid/getNoticeDetail?sendTag=0';
      
      final response = await dio.get(url);
      
      if (response.statusCode != 200) {
        throw Exception('获取通知详情失败: HTTP ${response.statusCode}');
      }
      
      final data = response.data;
      if (data is! Map || data['status'] != true) {
        throw Exception('API 返回详情加载失败');
      }
      
      final msg = data['msg'] as Map?;
      if (msg == null) {
        throw Exception('详情数据位空');
      }
      
      return Map<String, dynamic>.from(msg);
    } catch (e) {
      _logger.e('❌ Failed fetching notice detail: $e');
      rethrow;
    }
  }

  Future<void> setNoticeRead(String noticeId) async {
    try {
      final url = '${AppConstants.chaoxingNoticeBaseUrl}/mobile/notice/setNoticeRead?noticeId=$noticeId';
      final response = await dio.get(url);
      
      if (response.statusCode == 200) {
        _logger.i('✅ Successfully marked notice $noticeId as read');
      }
    } catch (e) {
      _logger.e('❌ Failed to mark notice as read: $e');
    }
  }
}