import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/app_constants.dart';
import '../models/leave_models.dart';
import 'dio_client.dart';
import 'xgxt_login_service.dart';

class LeaveException implements Exception { final String message; const LeaveException(this.message); @override String toString() => message; }
class LeaveService {
  LeaveService({Dio? dio, Future<bool> Function()? reauthenticate}) : _dio = dio, _reauthenticate = reauthenticate;
  final Dio? _dio; final Future<bool> Function()? _reauthenticate;
  Future<Dio> get client async { if (_dio != null) return _dio!; await DioClient().initialize(); return DioClient().dio; }
  Options get _options => Options(responseType: ResponseType.plain, followRedirects: false, validateStatus: (s) => s != null && s < 500, headers: {'Accept': '*/*', 'X-Requested-With': 'XMLHttpRequest', 'Referer': '${AppConstants.xgxtBaseUrl}/wap/menu/student/leave/qjsq'});
  dynamic _json(Response r) { if (r.statusCode != 200) throw const LeaveException('学工系统响应异常'); try { return r.data is String ? jsonDecode(r.data) : r.data; } catch (_) { throw const LeaveException('未能读取请假数据，请重新登录'); } }
  Future<Response> _read(Future<Response> Function(Dio d) fn) async { final d = await client; var r = await fn(d); if (_needsLogin(r)) { final ok = _reauthenticate != null ? await _reauthenticate!() : await XgxtLoginService().performXgxtCasLogin(); if (!ok) throw const LeaveException('学工登录已失效，请重新登录'); r = await fn(d); } return r; }
  bool _needsLogin(Response r) { final s = r.statusCode ?? 0; if (s >= 300 && s < 400) return true; final body = '${r.data}'; return body.contains('cas/login') || body.contains('<html'); }
  Future<List<LeaveDictItem>> fetchTypes() async { final r = await _read((d) => d.get(AppConstants.leaveDictUrl, queryParameters: {'name': 'MsDict', 'paramValue': 'DM_SF_QJLX', '_t_s_': DateTime.now().millisecondsSinceEpoch}, options: _options)); final data = _json(r); if (data is! List) throw const LeaveException('请假类别数据格式异常'); return data.whereType<Map>().map((e) => LeaveDictItem.fromJson(e.cast<String, dynamic>())).toList(); }
  Future<List<RegionNode>> fetchRegions() async { final r = await _read((d) => d.get(AppConstants.leaveRegionUrl, queryParameters: {'xian_allow_empty': '0', '_t_s_': DateTime.now().millisecondsSinceEpoch}, options: _options)); final data = _json(r); if (data is! List) return []; return data.whereType<Map>().map((e) => RegionNode.fromJson(e.cast<String, dynamic>())).toList(); }
  Future<LeaveDuration> calculate(String start, String end) async { final r = await _read((d) => d.get(AppConstants.leaveCalculateUrl, queryParameters: {'kssj': start, 'jssj': end, '_t_s_': DateTime.now().millisecondsSinceEpoch}, options: _options)); final data = _json(r); return LeaveDuration.fromJson((data as Map).cast<String, dynamic>()); }
  Future<List<LeaveRecord>> fetchList() async { final r = await _read((d) => d.get(AppConstants.leaveListUrl, queryParameters: {'bSortable_0': 'false', 'bSortable_1': 'false', 'iSortingCols': '1', 'iDisplayStart': '0', 'iDisplayLength': '50', 'iSortCol_0': '3', 'sSortDir_0': 'desc', '_t_s_': DateTime.now().millisecondsSinceEpoch}, options: _options)); final data = _json(r); final rows = data is Map ? data['aaData'] : null; if (rows is! List) throw const LeaveException('请假列表数据格式异常'); return rows.whereType<Map>().map((e) => LeaveRecord.fromJson(e.cast<String, dynamic>())).toList(); }
  Future<LeaveDetail> fetchRecord(String id) async { final r = await _read((d) => d.get('${AppConstants.leaveApplyUrl}/$id', options: _options)); return LeaveDetail((_json(r) as Map).cast<String, dynamic>()); }
  Future<void> submit({required Map<String, String> fields, String? attachmentPath}) async { final d = await client; final data = attachmentPath != null && attachmentPath.isNotEmpty ? FormData.fromMap({...fields, 'pathFile': await MultipartFile.fromFile(attachmentPath, filename: attachmentPath.split('/').last)}) : fields; final r = await _read((_) => d.post(AppConstants.leaveApplyUrl, queryParameters: {'_t_s_': DateTime.now().millisecondsSinceEpoch}, data: data, options: _options.copyWith(contentType: attachmentPath != null ? Headers.multipartFormDataContentType : Headers.formUrlEncodedContentType))); final j = _json(r); if (j is! Map || j['result'] != true) throw LeaveException(j is Map ? '${j['msg'] ?? '提交失败，请稍后重试'}' : '提交失败，请稍后重试'); }
  Future<void> delete(String id) async { final r = await _read((d) => d.post(AppConstants.leaveDeleteUrl, data: {'dm': id}, options: _options.copyWith(contentType: Headers.formUrlEncodedContentType))); final j = _json(r); if (j != true) throw const LeaveException('撤销失败，该请假单可能已进入审核'); }
}
