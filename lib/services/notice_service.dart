import 'package:dio/dio.dart';
import 'session_cookie_manager.dart';
import '../models/app_constants.dart';
import '../models/message_model.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';

class NoticeService {
  final _logger = AppLogger.instance;
  late final Dio dio;

  NoticeService() {
    dio = Dio();
    dio.interceptors.add(SessionCookieManager(AppCookieManager().dioCookieJar));
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
          .map(
            (item) =>
                MessageModel.fromChaoxingJson(item as Map<String, dynamic>),
          )
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

  Future<NoticeResult> fetchAllMessageList() async {
    final messages = <MessageModel>[];
    final seenIds = <String>{};
    final seenCursors = <String>{};
    String? cursor;

    // The endpoint returns a cursor page (usually 20 records) rather than the
    // complete inbox. Keep advancing until the server signals the final page.
    for (var page = 0; page < 500; page++) {
      final result = await fetchMessageList(lastValue: cursor);
      for (final message in result.messages) {
        final id = message.uuid.isNotEmpty ? message.uuid : message.idCode;
        final fallback = '${message.sendTime}|${message.createrName}|${message.title}';
        if (seenIds.add(id.isNotEmpty ? id : fallback)) {
          messages.add(message);
        }
      }

      final nextCursor = result.nextLastValue;
      if (!result.hasMore || nextCursor == null || nextCursor.isEmpty) {
        return NoticeResult(messages: messages, hasMore: false);
      }
      if (!seenCursors.add(nextCursor)) {
        _logger.w('Notice pagination cursor stopped advancing; ending refresh');
        return NoticeResult(messages: messages, hasMore: false);
      }
      if (result.messages.isEmpty) {
        _logger.w('Notice pagination returned an empty page; ending refresh');
        return NoticeResult(messages: messages, hasMore: false);
      }
      cursor = nextCursor;
    }

    throw StateError('通知数量超出读取范围，请稍后重试');
  }

  Future<Map<String, dynamic>> fetchNoticeDetail(String uuid) async {
    try {
      final url =
          '${AppConstants.chaoxingNoticeBaseUrl}/pc/notice/$uuid/getNoticeDetail?sendTag=0';

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
      final url =
          '${AppConstants.chaoxingNoticeBaseUrl}/mobile/notice/setNoticeRead?noticeId=$noticeId';
      final response = await dio.get(url);

      if (response.statusCode == 200) {
        _logger.i('✅ Successfully marked notice $noticeId as read');
      }
    } catch (e) {
      _logger.e('❌ Failed to mark notice as read: $e');
    }
  }
}
