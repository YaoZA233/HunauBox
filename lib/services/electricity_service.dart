import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' as dio_cookie;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_constants.dart';
import '../models/electricity_model.dart';
import '../utils/dkyw_crypto.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';
import 'campus_card_service.dart';

class ElectricityService {
  ElectricityService._internal()
    : _dio = Dio(
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

  final _logger = AppLogger.instance;
  final Dio _dio;
  bool _cookiesReady = false;

  CampusCardService get _cardService => CampusCardService.instance;

  Future<void> _ensureDioReady() async {
    if (_cookiesReady) return;
    await AppCookieManager().initialize();
    if (_dio.interceptors.whereType<dio_cookie.CookieManager>().isEmpty) {
      _dio.interceptors.add(
        dio_cookie.CookieManager(AppCookieManager().dioCookieJar),
      );
    }
    _cookiesReady = true;
  }

  Future<String> _ensureAuthenticated({bool force = false}) async {
    await _ensureDioReady();
    if (force) await _cardService.invalidateSession();
    if (_cardService.openid == null || _cardService.cachedInfo == null) {
      await _cardService.fetchRechargeInfo(isRetry: force);
    }

    final openid = _cardService.openid;
    if (openid == null || openid.isEmpty) throw Exception('电费服务授权失败');

    try {
      await _dio.get(
        '$_baseUrl/elepay/openElePay',
        queryParameters: {'openid': openid, 'displayflag': '1', 'id': '30'},
        options: Options(headers: {'User-Agent': AppConstants.campusCardUA}),
      );
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
    final openid = _cardService.openid ?? await _ensureAuthenticated();
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
    if (!isRetry && _isSessionExpired(data)) {
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
    return _extractList(data, const ['schoolList', 'schoollist'])
        .map(ElectricityArea.fromJson)
        .toList();
  }

  Future<List<ElectricityBuilding>> getBuildings(String areaName) async {
    final data = await _post('/channel/queryBuildingList', {
      'factorycode': _factoryCode,
      'schoolid': areaName,
    });
    _throwIfFailure(data, '获取楼栋失败');
    return _extractList(data, const ['buildingList', 'buildinglist'])
        .map(ElectricityBuilding.fromJson)
        .toList();
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
    return _extractList(data, const ['roomList', 'roomlist'])
        .map(ElectricityRoom.fromJson)
        .toList();
  }

  Future<ElectricityBalanceInfo> getBalance({
    required String areaName,
    required String buildingName,
    required String roomId,
    required String mertype,
  }) async {
    final data = await _post('/channel/queryEleAccDetail', {
      'schoolid': areaName,
      'buildingid': buildingName,
      'roomid': roomId,
      'mertype': mertype,
      'factorycode': _factoryCode,
    });
    _throwIfFailure(data, '获取电费余额失败');

    if (data is Map && data['resultData'] is Map) {
      return ElectricityBalanceInfo.fromJson(
        Map<String, dynamic>.from(data['resultData'] as Map),
      );
    }
    if (data is Map) {
      return ElectricityBalanceInfo.fromJson(Map<String, dynamic>.from(data));
    }
    throw Exception('获取电费余额失败：响应格式异常');
  }

  Future<bool> recharge({
    required String areaName,
    required String buildingName,
    required String roomId,
    String? roomName,
    required String mertype,
    required double amount,
  }) async {
    if (amount < 1 || amount > 1000 || amount != amount.roundToDouble()) {
      throw Exception('充值金额必须是 1–1000 元的整数');
    }

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
      'openid': openid,
      'idserial': cardInfo.idserial,
      'factorycode': _factoryCode,
      'buildingid': buildingName,
      'roomid': roomId,
      'schoolid': areaName,
      'payWay': '2',
      'mertype': mertype,
    });

    if (data is! Map) throw Exception('充值失败：响应格式异常');
    final success = data['success'] == true ||
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
        roomName: roomName?.trim().isNotEmpty == true ? roomName!.trim() : roomId,
        mertype: mertype,
      ),
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
    return const ['openid无效', '页面丢失', '未登录', '会话过期', '资源受限']
        .any(message.contains);
  }

  String _messageOf(Map data, String fallback) {
    final message = data['message'] ?? data['msg'];
    return message == null || message.toString().trim().isEmpty
        ? fallback
        : message.toString();
  }

  Future<SavedElectricityRoom?> getSavedRoom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_savedRoomKey);
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

  Future<void> saveSavedRoom(SavedElectricityRoom room) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_savedRoomKey, jsonEncode(room.toJson()));
    } catch (e) {
      _logger.w('保存电费房间失败: $e');
    }
  }

  Future<void> clearSavedRoom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_savedRoomKey);
    } catch (e) {
      _logger.w('清除已保存电费房间失败: $e');
    }
  }
}
