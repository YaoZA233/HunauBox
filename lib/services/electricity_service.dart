import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' as dio_cookie;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_constants.dart';
import '../models/electricity_model.dart';
import 'app_cookie_manager.dart';
import 'app_logger.dart';
import 'campus_card_service.dart';

class ElectricityService {
  ElectricityService._internal() {
    _dio = Dio();
  }

  static final ElectricityService instance = ElectricityService._internal();

  final _logger = AppLogger.instance;
  late final Dio _dio;
  final String _factoryCode = 'E013';
  static const String _savedRoomKey = 'saved_electricity_room';

  bool _cookiesReady = false;

  CampusCardService get _cardService => CampusCardService.instance;

  Future<String?> _ensureAuthenticated() async {
    if (!_cookiesReady) {
      await AppCookieManager().initialize();
      if (_dio.interceptors.whereType<dio_cookie.CookieManager>().isEmpty) {
        _dio.interceptors.add(
          dio_cookie.CookieManager(AppCookieManager().dioCookieJar),
        );
      }
      _cookiesReady = true;
    }
    if (_cardService.openid == null || _cardService.cachedInfo == null) {
      await _cardService.fetchRechargeInfo();
    }

    final openid = _cardService.openid;
    if (openid == null) return null;

    try {
      await _dio.get(
        'https://fin-serv.hunau.edu.cn/elepay/openElePay',
        queryParameters: {'openid': openid, 'displayflag': '1', 'id': '30'},
        options: Options(headers: {'User-Agent': AppConstants.campusCardUA}),
      );
    } catch (e) {
      _logger.w('openElePay initial call failed: $e');
    }

    return openid;
  }

  Future<List<ElectricityArea>> getAreas() async {
    final openid = await _ensureAuthenticated();
    if (openid == null) throw Exception('授权失败');

    try {
      final response = await _dio.post(
        'https://fin-serv.hunau.edu.cn/channel/getXiaoQuList',
        queryParameters: {'openid': openid, 'connect_redirect': '1'},
        data: {'factorycode': _factoryCode},
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      if (response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data)
            : response.data;
        final List list;
        if (data is List) {
          list = data;
        } else if (data is Map &&
            data.containsKey('resultData') &&
            data['resultData'] is Map &&
            data['resultData'].containsKey('schoolList')) {
          list = data['resultData']['schoolList'];
        } else if (data is Map &&
            data.containsKey('resultData') &&
            data['resultData'] is List) {
          list = data['resultData'];
        } else if (data is Map &&
            data.containsKey('data') &&
            data['data'] is List) {
          list = data['data'];
        } else {
          _logger.w('Unexpected response format for getAreas: $data');
          return [];
        }

        return list.map((e) => ElectricityArea.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      _logger.e('getAreas failed: $e');
      rethrow;
    }
  }

  Future<List<ElectricityBuilding>> getBuildings(String areaName) async {
    final openid = _cardService.openid;
    if (openid == null) throw Exception('未授权');

    try {
      final response = await _dio.post(
        'https://fin-serv.hunau.edu.cn/channel/queryBuildingList',
        queryParameters: {'openid': openid, 'connect_redirect': '1'},
        data: {'factorycode': _factoryCode, 'schoolid': areaName},
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      if (response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data)
            : response.data;
        final List list;
        if (data is List) {
          list = data;
        } else if (data is Map &&
            data.containsKey('resultData') &&
            data['resultData'] is Map &&
            (data['resultData'].containsKey('buildingList') ||
                data['resultData'].containsKey('buildinglist'))) {
          list =
              data['resultData']['buildingList'] ??
              data['resultData']['buildinglist'];
        } else if (data is Map &&
            data.containsKey('resultData') &&
            data['resultData'] is List) {
          list = data['resultData'];
        } else if (data is Map &&
            data.containsKey('data') &&
            data['data'] is List) {
          list = data['data'];
        } else {
          _logger.w('Unexpected response format for getBuildings: $data');
          return [];
        }

        return list.map((e) => ElectricityBuilding.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      _logger.e('getBuildings failed: $e');
      rethrow;
    }
  }

  Future<List<ElectricityRoom>> getRooms(
    String areaName,
    String buildingName,
  ) async {
    final openid = _cardService.openid;
    if (openid == null) throw Exception('未授权');

    try {
      final response = await _dio.post(
        'https://fin-serv.hunau.edu.cn/channel/queryRoomList',
        queryParameters: {'openid': openid, 'connect_redirect': '1'},
        data: {
          'factorycode': _factoryCode,
          'schoolid': areaName,
          'buildingid': buildingName,
        },
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      if (response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data)
            : response.data;
        final List list;
        if (data is List) {
          list = data;
        } else if (data is Map &&
            data.containsKey('resultData') &&
            data['resultData'] is Map &&
            (data['resultData'].containsKey('roomList') ||
                data['resultData'].containsKey('roomlist'))) {
          list =
              data['resultData']['roomList'] ?? data['resultData']['roomlist'];
        } else if (data is Map &&
            data.containsKey('resultData') &&
            data['resultData'] is List) {
          list = data['resultData'];
        } else if (data is Map &&
            data.containsKey('data') &&
            data['data'] is List) {
          list = data['data'];
        } else {
          _logger.w('Unexpected response format for getRooms: $data');
          return [];
        }

        return list.map((e) => ElectricityRoom.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      _logger.e('getRooms failed: $e');
      rethrow;
    }
  }

  Future<ElectricityBalanceInfo> getBalance({
    required String areaName,
    required String buildingName,
    required String roomId,
    required String mertype,
  }) async {
    final openid = _cardService.openid;
    if (openid == null) throw Exception('未授权');

    try {
      final response = await _dio.post(
        'https://fin-serv.hunau.edu.cn/channel/queryEleAccDetail',
        queryParameters: {'openid': openid, 'connect_redirect': '1'},
        data: {
          'schoolid': areaName,
          'buildingid': buildingName,
          'roomid': roomId,
          'mertype': mertype,
          'factorycode': _factoryCode,
        },
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      if (response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data)
            : response.data;
        final Map<String, dynamic> result;
        if (data is Map &&
            data.containsKey('resultData') &&
            data['resultData'] is Map) {
          result = data['resultData'];
        } else if (data is Map<String, dynamic>) {
          result = data;
        } else {
          throw Exception('Unexpected response format for getBalance');
        }
        return ElectricityBalanceInfo.fromJson(result);
      }
      throw Exception('无法获取余额数据');
    } catch (e) {
      _logger.e('getBalance failed: $e');
      rethrow;
    }
  }

  Future<bool> recharge({
    required String areaName,
    required String buildingName,
    required String roomId,
    required String mertype,
    required double amount,
  }) async {
    final openid = _cardService.openid;
    final cardInfo = _cardService.cachedInfo;
    if (openid == null || cardInfo == null) throw Exception('未授权或卡信息缺失');

    try {
      await _dio.post(
        'https://fin-serv.hunau.edu.cn/myaccount/userlastbind',
        queryParameters: {'openid': openid, 'connect_redirect': '1'},
        data: {
          'payinfo': {'elepayWay': '2'},
          'eleinfo': {
            'schoolid': areaName,
            'buildingid': buildingName,
            'roomid': roomId,
            'factorycode': _factoryCode,
          },
          'idserial': cardInfo.idserial,
        },
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      final response = await _dio.post(
        'https://fin-serv.hunau.edu.cn/elepay/createPreThirdTrade',
        queryParameters: {'openid': openid, 'connect_redirect': '1'},
        data: {
          'payamt': amount.toStringAsFixed(0),
          'openid': openid,
          'idserial': cardInfo.idserial,
          'factorycode': _factoryCode,
          'buildingid': buildingName,
          'roomid': roomId,
          'schoolid': areaName,
          'payWay': '2',
          'mertype': mertype,
        },
        options: Options(
          headers: {
            'User-Agent': AppConstants.campusCardUA,
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      if (response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data)
            : response.data;
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      _logger.e('recharge failed: $e');
      rethrow;
    }
  }

  /// 获取上次选择的房间。
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

  /// 保存当前房间，进入电费页面时自动恢复。
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
