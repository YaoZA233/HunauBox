import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' as dio_cookie;
import 'session_cookie_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_constants.dart';
import '../models/electricity_model.dart';
import '../utils/dkyw_crypto.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';
import 'campus_card_service.dart';
import 'finance_cache_store.dart';

class ElectricityService {
  ElectricityService.forTesting({
    required Dio dio,
    required CampusCardService card,
  }) : _dio = dio,
       _cardOverride = card {
    _cookiesReady = true;
  }

  ElectricityService._internal()
    : _cardOverride = null,
      _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          followRedirects: true,
          maxRedirects: 10,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

  static final ElectricityService instance = ElectricityService._internal();

  static const _baseUrl = 'https://fin-serv.hunau.edu.cn';
  static const _factoryCode = 'E013';
  static const _savedRoomKey = 'saved_electricity_room';
  static const _secondSavedRoomKey = 'saved_electricity_room_2';

  static String _savedRoomKeyForSlot(int slot) {
    assert(slot >= 0 && slot <= 1);
    return slot == 0 ? _savedRoomKey : _secondSavedRoomKey;
  }

  final _logger = AppLogger.instance;
  final Dio _dio;
  final CampusCardService? _cardOverride;
  bool _cookiesReady = false;
  Future<String>? _authInProgress;
  String? _sessionOpenid;
  bool _recharging = false;
  final _balanceRequests = <String, Future<ElectricityBalanceInfo>>{};

  static String balanceCacheKey(SavedElectricityRoom room) =>
      'electricity:${Uri.encodeComponent(jsonEncode(room.toJson()..remove('roomName')))}';

  Future<void> clearSession() async {
    try {
      await _authInProgress;
    } catch (_) {}
    await Future.wait(
      _balanceRequests.values.map((f) async {
        try {
          await f;
        } catch (_) {}
      }),
    );
    _sessionOpenid = null;
  }

  CampusCardService get _cardService =>
      _cardOverride ?? CampusCardService.instance;

  Future<void> _ensureDioReady() async {
    if (_cookiesReady) return;
    await AppCookieManager().initialize();
    if (_dio.interceptors.whereType<dio_cookie.CookieManager>().isEmpty) {
      _dio.interceptors.add(
        SessionCookieManager(AppCookieManager().dioCookieJar),
      );
    }
    _cookiesReady = true;
  }

  Future<String> _ensureAuthenticated({bool force = false}) async {
    if (_authInProgress != null) return _authInProgress!;
    final future = _authenticate(force: force);
    _authInProgress = future;
    try {
      return await future;
    } finally {
      if (identical(_authInProgress, future)) _authInProgress = null;
    }
  }

  Future<String> _authenticate({bool force = false}) async {
    await _ensureDioReady();
    if (force) await _cardService.invalidateSession();
    if (_cardService.openid == null || _cardService.cachedInfo == null) {
      await _cardService.fetchRechargeInfo(isRetry: force);
    }

    final openid = _cardService.openid;
    if (openid == null || openid.isEmpty) throw Exception('电费服务授权失败');
    if (!force && _sessionOpenid == openid) return openid;

    try {
      final response = await _dio.get(
        '$_baseUrl/elepay/openElePay',
        queryParameters: {'openid': openid, 'displayflag': '1', 'id': '30'},
        options: Options(headers: {'User-Agent': AppConstants.campusCardUA}),
      );
      if (response.statusCode == 200 &&
          !response.realUri.path.contains('errorPage')) {
        _sessionOpenid = openid;
      }
    } catch (e) {
      _logger.w('初始化电费会话失败，将继续尝试接口请求: $e');
    }
    return openid;
  }

  /// 财务平台现已要求所有电费 POST 使用动态 AES datajson 协议。
  Future<dynamic> _post(
    String path,
    Map<String, dynamic> payload, {
    bool isRetry = false,
  }) async {
    final openid = await _ensureAuthenticated();
    final response = await _dio.post(
      '$_baseUrl$path',
      queryParameters: {'openid': openid, 'connect_redirect': '1'},
      data: {'datajson': DkywCrypto.encryptPayload(payload)},
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': AppConstants.campusCardUA,
          'X-Requested-With': 'XMLHttpRequest',
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/javascript, */*; q=0.01',
          'Referer':
              '$_baseUrl/elepay/openElePay?openid=$openid&displayflag=1&id=30',
        },
      ),
    );

    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw Exception('电费服务请求失败：HTTP ${response.statusCode}');
    }

    final data = DkywCrypto.decryptServerResponse(response.data);
    _logger.d('电费接口 $path 响应已解密');
    if (!isRetry &&
        _isSessionExpired(data) &&
        path != '/elepay/createPreThirdTrade') {
      _logger.w('电费会话已失效，重新授权后重试 $path');
      await _ensureAuthenticated(force: true);
      return _post(path, payload, isRetry: true);
    }
    return data;
  }

  Future<List<ElectricityArea>> getAreas() async {
    await _ensureAuthenticated();
    final data = await _post('/channel/getXiaoQuList', {
      'factorycode': _factoryCode,
    });
    _throwIfFailure(data, '获取校区失败');
    return _extractList(data, const [
      'schoolList',
      'schoollist',
    ]).map(ElectricityArea.fromJson).toList();
  }

  Future<List<ElectricityBuilding>> getBuildings(String areaName) async {
    final data = await _post('/channel/queryBuildingList', {
      'factorycode': _factoryCode,
      'schoolid': areaName,
    });
    _throwIfFailure(data, '获取楼栋失败');
    return _extractList(data, const [
      'buildingList',
      'buildinglist',
    ]).map(ElectricityBuilding.fromJson).toList();
  }

  Future<List<ElectricityRoom>> getRooms(
    String areaName,
    String buildingName,
  ) async {
    final data = await _post('/channel/queryRoomList', {
      'factorycode': _factoryCode,
      'schoolid': areaName,
      'buildingid': buildingName,
    });
    _throwIfFailure(data, '获取房间失败');
    return _extractList(data, const [
      'roomList',
      'roomlist',
    ]).map(ElectricityRoom.fromJson).toList();
  }

  Future<ElectricityBalanceInfo> getBalance({
    required String areaName,
    required String buildingName,
    required String roomId,
    required String mertype,
  }) async {
    final room = SavedElectricityRoom(
      areaName: areaName,
      buildingName: buildingName,
      roomId: roomId,
      roomName: roomId,
      mertype: mertype,
    );
    final key = balanceCacheKey(room);
    if (_balanceRequests[key] != null) return _balanceRequests[key]!;
    final future = _queryBalance(room, key);
    _balanceRequests[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_balanceRequests[key], future)) {
        _balanceRequests.remove(key);
      }
    }
  }

  Future<ElectricityBalanceInfo> _queryBalance(
    SavedElectricityRoom room,
    String key,
  ) async {
    final owner = await FinanceCacheStore.account();
    final data = await _post('/channel/queryEleAccDetail', {
      'schoolid': room.areaName,
      'buildingid': room.buildingName,
      'roomid': room.roomId,
      'mertype': room.mertype,
      'factorycode': _factoryCode,
    });
    _throwIfFailure(data, '获取电费余额失败');

    if (data is! Map) throw Exception('获取电费余额失败：响应格式异常');
    final result = Map<String, dynamic>.from(
      data['resultData'] is Map ? data['resultData'] as Map : data,
    );
    await FinanceCacheStore.write(owner, key, result, DateTime.now());
    return ElectricityBalanceInfo.fromJson(result);
  }

  Future<bool> recharge({
    required String areaName,
    required String buildingName,
    required String roomId,
    String? roomName,
    required String mertype,
    required double amount,
    int roomSlot = 0,
  }) async {
    if (!amount.isFinite ||
        amount < 1 ||
        amount > 1000 ||
        amount != amount.roundToDouble()) {
      throw Exception('充值金额必须是 1–1000 元的整数');
    }
    if (_recharging) throw Exception('电费订单正在提交，请勿重复操作');
    _recharging = true;
    try {
      return await _recharge(
        areaName: areaName,
        buildingName: buildingName,
        roomId: roomId,
        roomName: roomName,
        mertype: mertype,
        amount: amount,
        roomSlot: roomSlot,
      );
    } on DioException {
      throw Exception('电费订单未能确认，请先查看充值记录，勿重复支付');
    } finally {
      _recharging = false;
    }
  }

  Future<bool> _recharge({
    required String areaName,
    required String buildingName,
    required String roomId,
    String? roomName,
    required String mertype,
    required double amount,
    required int roomSlot,
  }) async {
    await _ensureAuthenticated();
    final openid = _cardService.openid;
    final cardInfo = _cardService.cachedInfo;
    if (openid == null || cardInfo == null) throw Exception('未授权或卡信息缺失');

    await _post('/myaccount/userlastbind', {
      'payinfo': {'elepayWay': '2'},
      'eleinfo': {
        'schoolid': areaName,
        'buildingid': buildingName,
        'roomid': roomId,
        'factorycode': _factoryCode,
      },
      'idserial': cardInfo.idserial,
    });

    final data = await _post('/elepay/createPreThirdTrade', {
      'payamt': amount.toStringAsFixed(0),
      'openid': _cardService.openid,
      'idserial': _cardService.cachedInfo!.idserial,
      'factorycode': _factoryCode,
      'buildingid': buildingName,
      'roomid': roomId,
      'schoolid': areaName,
      'payWay': '2',
      'mertype': mertype,
    });

    if (data is! Map) throw Exception('充值失败：响应格式异常');
    final success =
        data['success'] == true ||
        data['success']?.toString() == 'true' ||
        data['code']?.toString() == '0' ||
        data['resultData'] != null;
    if (!success) {
      throw Exception(_messageOf(data, '充值失败，请重试'));
    }

    await saveSavedRoom(
      SavedElectricityRoom(
        areaName: areaName,
        buildingName: buildingName,
        roomId: roomId,
        roomName: roomName?.trim().isNotEmpty == true
            ? roomName!.trim()
            : roomId,
        mertype: mertype,
      ),
      slot: roomSlot,
    );
    return true;
  }

  List<Map<String, dynamic>> _extractList(
    dynamic data,
    List<String> nestedKeys,
  ) {
    dynamic raw = data;
    if (data is Map) {
      final result = data['resultData'];
      if (result is List) {
        raw = result;
      } else if (result is Map) {
        raw = null;
        for (final key in nestedKeys) {
          if (result[key] is List) {
            raw = result[key];
            break;
          }
        }
      } else if (data['data'] is List) {
        raw = data['data'];
      }
    }

    if (raw is! List) throw Exception('电费服务响应格式异常');
    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  void _throwIfFailure(dynamic data, String fallback) {
    if (data is Map &&
        (data['success'] == false || data['success']?.toString() == 'false')) {
      throw Exception(_messageOf(data, fallback));
    }
  }

  bool _isSessionExpired(dynamic data) {
    final message = data is Map
        ? '${data['message'] ?? ''} ${data['msg'] ?? ''}'
        : data?.toString() ?? '';
    return const [
      'openid无效',
      '页面丢失',
      '未登录',
      '会话过期',
      '资源受限',
    ].any(message.contains);
  }

  String _messageOf(Map data, String fallback) {
    final message = data['message'] ?? data['msg'];
    return message == null || message.toString().trim().isEmpty
        ? fallback
        : message.toString();
  }

  Future<SavedElectricityRoom?> getSavedRoom({int slot = 0}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_savedRoomKeyForSlot(slot));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return SavedElectricityRoom.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (e) {
      _logger.w('读取已保存电费房间失败: $e');
    }
    return null;
  }

  Future<void> saveSavedRoom(SavedElectricityRoom room, {int slot = 0}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _savedRoomKeyForSlot(slot),
        jsonEncode(room.toJson()),
      );
    } catch (e) {
      _logger.w('保存电费房间失败: $e');
    }
  }

  Future<void> clearSavedRoom({int slot = 0}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_savedRoomKeyForSlot(slot));
    } catch (e) {
      _logger.w('清除已保存电费房间失败: $e');
    }
  }
}
