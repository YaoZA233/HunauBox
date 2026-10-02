import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/app_constants.dart';
import '../models/questionnaire_models.dart';
import 'dio_client.dart';
import 'xgxt_login_service.dart';

class QuestionnaireException implements Exception {
  const QuestionnaireException(
    this.message, {
    this.requiresStatusCheck = false,
  });
  final String message;
  final bool requiresStatusCheck;
  @override
  String toString() => message;
}

/// 移植 ChillEast 的 xs_wjdc / ks_sj 协议，共享当前项目的学工 Cookie。
class QuestionnaireService {
  QuestionnaireService({Dio? dio, Future<bool> Function()? reauthenticate})
    : _client = dio,
      _reauthenticate = reauthenticate;

  final Dio? _client;
  final Future<bool> Function()? _reauthenticate;

  Future<Dio> _clientReady() async {
    if (_client != null) return _client;
    await DioClient().initialize();
    return DioClient().dio;
  }

  Options _options({bool form = false}) => Options(
    contentType: form ? Headers.formUrlEncodedContentType : null,
    responseType: ResponseType.plain,
    followRedirects: false,
    validateStatus: (status) => status != null && status < 500,
    headers: {
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': '${AppConstants.xgxtBaseUrl}/wap/menu/fwk/wjdc/stu/xs_wjdc',
    },
  );

  bool _needsLogin(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    if ((status >= 300 && status < 400) || status == 401 || status == 403) {
      return true;
    }
    final body = response.data;
    if (body is! String) return false;
    final head = body
        .substring(0, body.length > 2048 ? 2048 : body.length)
        .toLowerCase();
    return head.contains('<html') ||
        head.contains('<!doctype html') ||
        head.contains('cas/login');
  }

  Future<void> _login() async {
    final success =
        await (_reauthenticate?.call() ??
            XgxtLoginService().performXgxtCasLogin());
    if (!success) {
      throw const QuestionnaireException('学工登录已失效，请重新登录后重试');
    }
  }

  Future<Response<dynamic>> _read(
    Future<Response<dynamic>> Function() request,
  ) async {
    var response = await request();
    if (_needsLogin(response)) {
      await _login();
      response = await request();
    }
    if (_needsLogin(response)) {
      throw const QuestionnaireException('学工登录已失效，请重新登录后重试');
    }
    return response;
  }

  Map<String, dynamic> _object(Response<dynamic> response) {
    if (response.statusCode != 200) {
      throw QuestionnaireException('学工系统响应异常（${response.statusCode}），请稍后重试');
    }
    dynamic data = response.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        throw const QuestionnaireException('未能读取问卷数据，请刷新或重新登录');
      }
    }
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const QuestionnaireException('问卷数据格式异常，请稍后重试');
  }

  Future<List<QuestionnaireItem>> fetchList() async {
    final dio = await _clientReady();
    final items = <QuestionnaireItem>[];
    final seen = <String>{};
    // 分页读完列表，避免只显示开源实现的前 50 项。
    for (var start = 0; start < 10000; start += 50) {
      final response = await _read(
        () => dio.get(
          AppConstants.xgxtQuestionnaireListUrl,
          queryParameters: {
            'bSortable_0': 'false',
            'bSortable_1': 'false',
            'iSortingCols': '1',
            'iDisplayStart': start.toString(),
            'iDisplayLength': '50',
            'iSortCol_0': '3',
            'sSortDir_0': 'desc',
            '_t_s_': DateTime.now().millisecondsSinceEpoch.toString(),
          },
          options: _options(),
        ),
      );
      final data = _object(response);
      final rows = data['aaData'];
      if (rows is! List || rows.any((row) => row is! Map)) {
        throw const QuestionnaireException('问卷列表数据格式异常');
      }
      var added = 0;
      for (final row in rows.cast<Map>()) {
        final item = QuestionnaireItem.fromJson(Map<String, dynamic>.from(row));
        if (seen.add('${item.dm}:${item.taskTimeM}')) {
          items.add(item);
          added++;
        }
      }
      final total = int.tryParse(
        (data['iTotalDisplayRecords'] ?? '').toString(),
      );
      if (rows.length < 50 || (total != null && start + rows.length >= total)) {
        return items;
      }
      if (added == 0) throw const QuestionnaireException('问卷分页未更新，请稍后重试');
    }
    throw const QuestionnaireException('问卷数量超出读取范围，请在学工系统查看');
  }

  Future<QuestionnaireDetail> fetchDetail(QuestionnaireItem item) async {
    if (item.taskTimeM.isEmpty) {
      throw const QuestionnaireException('该问卷缺少任务标识，无法打开');
    }
    final dio = await _clientReady();
    final response = await _read(
      () => dio.get(
        AppConstants.xgxtQuestionnaireDetailUrl,
        queryParameters: {
          'tasktime': item.taskTimeM,
          'busType': '',
          '_t_s_': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        options: _options(),
      ),
    );
    final data = _object(response);
    if (data['stList'] is! List ||
        (data['stList'] as List).any((row) => row is! Map)) {
      throw const QuestionnaireException('问卷题目数据不完整，请刷新后重试');
    }
    final detail = QuestionnaireDetail.fromJson(data);
    if (detail.questions.any((q) => q.dm.isEmpty) ||
        detail.questions.map((q) => q.dm).toSet().length !=
            detail.questions.length) {
      throw const QuestionnaireException('问卷题目标识异常，请在学工系统网页查看');
    }
    return detail;
  }

  /// 多选使用同名字段重复传值，与学工网页表单一致。
  static String encodeAnswers(
    QuestionnaireDetail detail,
    Map<String, dynamic> answers,
  ) {
    final pairs = <String>[];
    void add(String key, String value) => pairs.add(
      '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
    );
    for (final question in detail.questions) {
      final value = answers[question.dm];
      if (value is List && value.isNotEmpty) {
        for (final entry in value) {
          add(question.dm, entry.toString());
        }
      } else {
        add(question.dm, value is List ? '' : value?.toString() ?? '');
      }
    }
    add('ks_jgdm', detail.jgM);
    for (final field in ['wzDz', 'wzZb', 'wzLy', 'operationType']) {
      add(field, '');
    }
    return pairs.join('&');
  }

  Future<void> submit({
    required QuestionnaireItem item,
    required QuestionnaireDetail detail,
    required Map<String, dynamic> answers,
  }) async {
    if (!item.isPending) throw const QuestionnaireException('该问卷当前不可提交');
    final validation = detail.validate(answers);
    if (validation != null) throw QuestionnaireException(validation);
    // 在只读请求中恢复会话，且重新检查服务器的可提交状态。
    final latest = await fetchDetail(item);
    if (latest.jgM != detail.jgM || latest.dm != detail.dm) {
      throw const QuestionnaireException('问卷已更新，请返回列表重新打开');
    }
    final latestValidation = latest.validate(answers);
    if (latestValidation != null) {
      throw QuestionnaireException(latestValidation);
    }
    final dio = await _clientReady();
    // POST 不自动重试；网络中断可能发生在服务器已经保存之后。
    Response<dynamic> response;
    try {
      response = await dio.post(
        AppConstants.xgxtQuestionnaireSubmitUrl,
        queryParameters: {
          '_t_s_': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        data: encodeAnswers(latest, answers),
        options: _options(form: true),
      );
    } on DioException {
      throw const QuestionnaireException(
        '暂时无法确认提交结果，请返回列表刷新，核对状态后再操作',
        requiresStatusCheck: true,
      );
    }
    if (_needsLogin(response)) {
      throw const QuestionnaireException(
        '提交时登录已失效，请返回列表刷新后再操作',
        requiresStatusCheck: true,
      );
    }
    Map<String, dynamic> data;
    try {
      data = _object(response);
    } on QuestionnaireException {
      throw const QuestionnaireException(
        '暂时无法确认提交结果，请返回列表刷新，核对状态后再操作',
        requiresStatusCheck: true,
      );
    }
    if (!data.containsKey('result')) {
      throw const QuestionnaireException(
        '提交响应格式异常，请返回列表核对状态',
        requiresStatusCheck: true,
      );
    }
    if (data['result'] != true) {
      final errors = data['errorInfoList'];
      throw QuestionnaireException(
        errors is List && errors.isNotEmpty
            ? questionnaireText(errors.first)
            : questionnaireText(data['msg'] ?? '提交失败，请稍后重试'),
      );
    }
  }
}
