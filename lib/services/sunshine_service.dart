import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import '../models/app_constants.dart';
import '../models/sunshine_models.dart';
import 'dio_client.dart';

class SunshineException implements Exception {
  final String message;
  const SunshineException(this.message);
  @override String toString() => message;
}

class SunshineService {
  SunshineService({Dio? dio, Future<bool> Function()? reauthenticate}) : _dio = dio, _reauthenticate = reauthenticate;
  final Dio? _dio;
  final Future<bool> Function()? _reauthenticate;
  Future<Dio> get client async { if (_dio != null) return _dio!; await DioClient().initialize(); return DioClient().dio; }
  Options get _options => Options(responseType: ResponseType.plain, contentType: Headers.formUrlEncodedContentType, followRedirects: true, validateStatus: (s) => s != null && s < 500, responseDecoder: (bytes, _, __) { try { return gbk.decode(bytes); } catch (_) { return utf8.decode(bytes, allowMalformed: true); } }, headers: {'Referer': '${AppConstants.sunshineBaseUrl}/form.aspx?type=2', 'X-Requested-With': 'XMLHttpRequest'});
  dynamic _json(Response r) { if (r.statusCode != 200) throw const SunshineException('阳光服务暂时不可用，请稍后重试'); try { return r.data is String ? jsonDecode(r.data) : r.data; } catch (_) { throw const SunshineException('未能读取阳光服务数据，请检查登录状态后重试'); } }
  List<Map<String, dynamic>> _rows(Response r) { final data = _json(r); final rows = data is Map ? data['rows'] : null; if (rows is! List) throw const SunshineException('阳光服务返回的数据格式异常'); return rows.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(); }
  Future<SunshineStatistics> fetchStatistics() async { final d = await client; final r = await d.post('${AppConstants.sunshineBaseUrl}/AJAX/index.ashx', queryParameters: {'AFlag': 'Statistics'}, options: _options); return SunshineStatistics.fromJson((_json(r) as Map).cast<String, dynamic>()); }
  Future<List<SunshineLetter>> fetchLetters() async { final d = await client; final r = await d.post('${AppConstants.sunshineBaseUrl}/AJAX/index.ashx', data: {'AFlag': 'Suggestion'}, options: _options); return _rows(r).map(SunshineLetter.fromJson).toList(); }
  Future<SunshineTicketDetail> fetchTicketDetail(String id) async { final d = await client; final r = await d.post('${AppConstants.sunshineBaseUrl}/AJAX/form.ashx', data: {'AFlag': 'Detail', 'ID': id}, options: _options); final rows = _rows(r); if (rows.isEmpty) throw const SunshineException('未找到诉求工单详情'); return SunshineTicketDetail.fromJson(rows.first, id: id); }
  Future<SunshineFormData> fetchForm() async {
    final d = await client;
    var identity = await _identity(d);
    if (identity == null) {
      await _authorize(d);
      identity = await _identity(d);
    }
    if (identity == null && _reauthenticate != null) {
      if (!await _reauthenticate!()) throw const SunshineException('统一认证已过期，请重新登录');
      await _authorize(d); identity = await _identity(d);
    }
    if (identity == null) throw const SunshineException('阳光服务登录已失效，请重新登录后重试');
    final r = await d.post('${AppConstants.sunshineBaseUrl}/AJAX/form.ashx', data: {'AFlag': 'LoadCompany'}, options: _options);
    final departments = _rows(r).map(SunshineDepartment.fromJson).where((e) => e.code.isNotEmpty && e.name.isNotEmpty).toList();
    if (departments.isEmpty) throw const SunshineException('暂无可用受理单位');
    return SunshineFormData(identity, departments);
  }
  Future<SunshineIdentity?> _identity(Dio d) async { try { final r = await d.get('${AppConstants.sunshineBaseUrl}/form.aspx', queryParameters: {'type': '2'}, options: Options(responseType: ResponseType.plain, followRedirects: false, validateStatus: (s) => s != null && s < 500)); return r.statusCode == 200 ? SunshineIdentity.fromHtml('${r.data}') : null; } catch (_) { return null; } }
  Future<void> _authorize(Dio d) async { var uri = Uri.parse(AppConstants.sunshineAuthorizationUrl); for (var i = 0; i < 8; i++) { final r = await d.getUri(uri, options: Options(followRedirects: false, validateStatus: (s) => s != null && s < 500)); final loc = r.headers.value('location'); if (loc == null || loc.isEmpty) break; final next = uri.resolve(loc); if (next == uri) break; uri = next; } }
  Future<String> submit({required SunshineIdentity identity, required SunshineDepartment department, required String type, required String title, required String content, required String phone, required String email, required String finishTime}) async { final d = await client; final r = await d.post('${AppConstants.sunshineBaseUrl}/AJAX/form.ashx', queryParameters: {'AFlag': 'insert'}, data: {'type1': type, 'depid': department.code, 'depname': department.name, 'title': title.trim(), 'content': content.trim(), 'username': identity.name, 'telphone': phone.trim(), 'email': email.trim(), 'finishtime': finishTime, 'captchas': '', 'CardCode': identity.cardCode}, options: _options); final result = '${r.data}'.trim(); return ['1', '2'].contains(result) ? result : 'unknown'; }
}
