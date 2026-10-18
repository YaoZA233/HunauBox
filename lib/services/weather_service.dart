import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';

import '../models/weather.dart';

/// Open-Meteo's public forecast and GeoNames-backed city search need no key.
class WeatherService {
  WeatherService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 12),
            ),
          );
  final Dio _dio;

  Future<WeatherSnapshot> fetch(
    WeatherLocation location, {
    CancelToken? cancelToken,
    DateTime Function()? now,
  }) async {
    if (!location.valid) {
      throw const WeatherFailure(
        WeatherFailureKind.locationUnavailable,
        '天气位置无效，请重新选择',
      );
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.open-meteo.com/v1/forecast',
        cancelToken: cancelToken,
        queryParameters: {
          'latitude': location.latitude.toStringAsFixed(2),
          'longitude': location.longitude.toStringAsFixed(2),
          'current':
              'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m',
          'daily':
              'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
          'forecast_days': 1,
          'timezone': 'auto',
          'wind_speed_unit': 'kmh',
          'temperature_unit': 'celsius',
        },
      );
      return parse(response.data!, location, (now ?? DateTime.now)());
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw const WeatherFailure(WeatherFailureKind.network, '天气获取失败，请检查网络后重试');
    } on WeatherFailure {
      rethrow;
    } catch (_) {
      throw const WeatherFailure(
        WeatherFailureKind.invalidResponse,
        '天气数据暂不可用，请稍后刷新',
      );
    }
  }

  static WeatherSnapshot parse(
    Map<String, dynamic> json,
    WeatherLocation location,
    DateTime now,
  ) {
    try {
      if (json['error'] == true) throw const FormatException();
      final current = json['current'] as Map<String, dynamic>;
      double? number(dynamic value) =>
          value is num && value.isFinite ? value.toDouble() : null;
      final temperature = number(current['temperature_2m']);
      final code = current['weather_code'];
      final offset = json['utc_offset_seconds'] as int;
      if (temperature == null ||
          code is! int ||
          (current['is_day'] != 0 && current['is_day'] != 1) ||
          offset.abs() > 86400) {
        throw const FormatException();
      }
      // The API's ISO time is in the requested city's timezone, not the phone's.
      final localTime = DateTime.parse('${current['time']}Z');
      final observedAt = localTime.subtract(Duration(seconds: offset));
      final daily = json['daily'] as Map<String, dynamic>?;
      double? first(String key) {
        final values = daily?[key];
        return values is List && values.isNotEmpty
            ? number(values.first)
            : null;
      }

      return WeatherSnapshot(
        location: location,
        temperature: temperature,
        code: code,
        isDay: current['is_day'] == 1,
        observedAt: observedAt,
        fetchedAt: now.toUtc(),
        utcOffsetSeconds: offset,
        apparentTemperature: number(current['apparent_temperature']),
        humidity: number(current['relative_humidity_2m']),
        windKmh: number(current['wind_speed_10m']),
        maximum: first('temperature_2m_max'),
        minimum: first('temperature_2m_min'),
        rainProbability: first('precipitation_probability_max'),
      );
    } catch (_) {
      throw const WeatherFailure(
        WeatherFailureKind.invalidResponse,
        '天气数据暂不可用，请稍后刷新',
      );
    }
  }

  Future<List<WeatherLocation>> search(
    String query, {
    CancelToken? cancelToken,
  }) async {
    final text = query.trim();
    if (text.isEmpty) return [];
    final local = searchLocal(text);
    if (text.runes.length < 2) return local;
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://geocoding-api.open-meteo.com/v1/search',
        cancelToken: cancelToken,
        queryParameters: {
          'name': text,
          'count': 20,
          'language': 'zh',
          'format': 'json',
        },
      );
      final results = response.data?['results'];
      final locations = <String, WeatherLocation>{
        for (final location in local) location.id: location,
      };
      if (results is List) {
        for (final item in results) {
          if (item is! Map<String, dynamic>) continue;
          try {
            final regions = [item['country'], item['admin1'], item['admin2']]
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .toSet()
                .join(' · ');
            final location = WeatherLocation.fromJson({
              ...item,
              'region': regions,
            });
            locations.putIfAbsent(location.id, () => location);
          } catch (_) {
            /* Ignore incomplete search results. */
          }
        }
      }
      return locations.values.toList();
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      if (local.isNotEmpty) return local;
      throw const WeatherFailure(WeatherFailureKind.network, '城市搜索失败，请检查网络后重试');
    } catch (_) {
      if (local.isNotEmpty) return local;
      throw const WeatherFailure(
        WeatherFailureKind.invalidResponse,
        '城市搜索暂不可用',
      );
    }
  }

  static List<WeatherLocation> searchLocal(String query) {
    final text = query.trim().toLowerCase().replaceAll('市', '');
    return [
      for (final place in _places)
        if (text.isEmpty ||
            place.$1.contains(text) ||
            place.$2.contains(text) ||
            place.$5.contains(text))
          WeatherLocation(
            name: place.$1,
            region: '中国 · ${place.$2}',
            latitude: place.$3,
            longitude: place.$4,
          ),
    ];
  }

  // Exact common-city matches prevent GeoNames' identically named villages
  // from replacing provincial capitals in Chinese searches.
  static const _places = [
    ('长沙', '湖南', 28.2282, 112.9388, 'changsha'),
    ('湖南农业大学', '湖南 · 长沙', 28.19, 113.08, 'hunannongyedaxue hunau'),
    ('株洲', '湖南', 27.8274, 113.1339, 'zhuzhou'),
    ('湘潭', '湖南', 27.8297, 112.9441, 'xiangtan'),
    ('衡阳', '湖南', 26.8932, 112.5719, 'hengyang'),
    ('邵阳', '湖南', 27.2389, 111.4678, 'shaoyang'),
    ('岳阳', '湖南', 29.3571, 113.1292, 'yueyang'),
    ('常德', '湖南', 29.0316, 111.6985, 'changde'),
    ('张家界', '湖南', 29.1171, 110.4792, 'zhangjiajie'),
    ('益阳', '湖南', 28.5539, 112.3552, 'yiyang'),
    ('郴州', '湖南', 25.7706, 113.0147, 'chenzhou'),
    ('永州', '湖南', 26.4204, 111.6134, 'yongzhou'),
    ('怀化', '湖南', 27.5501, 109.9782, 'huaihua'),
    ('娄底', '湖南', 27.6973, 111.9945, 'loudi'),
    ('吉首', '湖南 · 湘西', 28.2626, 109.6981, 'jishou xiangxi'),
    ('北京', '北京', 39.9042, 116.4074, 'beijing'),
    ('上海', '上海', 31.2304, 121.4737, 'shanghai'),
    ('天津', '天津', 39.0842, 117.2009, 'tianjin'),
    ('重庆', '重庆', 29.563, 106.5516, 'chongqing'),
    ('广州', '广东', 23.1291, 113.2644, 'guangzhou'),
    ('深圳', '广东', 22.5431, 114.0579, 'shenzhen'),
    ('杭州', '浙江', 30.2741, 120.1551, 'hangzhou'),
    ('南京', '江苏', 32.0603, 118.7969, 'nanjing'),
    ('武汉', '湖北', 30.5928, 114.3055, 'wuhan'),
    ('成都', '四川', 30.5728, 104.0668, 'chengdu'),
    ('南昌', '江西', 28.6829, 115.8582, 'nanchang'),
    ('合肥', '安徽', 31.8206, 117.2272, 'hefei'),
    ('福州', '福建', 26.0745, 119.2965, 'fuzhou'),
    ('厦门', '福建', 24.4798, 118.0894, 'xiamen'),
    ('济南', '山东', 36.6512, 117.1201, 'jinan'),
    ('郑州', '河南', 34.7466, 113.6254, 'zhengzhou'),
    ('西安', '陕西', 34.3416, 108.9398, 'xian'),
    ('石家庄', '河北', 38.0428, 114.5149, 'shijiazhuang'),
    ('太原', '山西', 37.8706, 112.5489, 'taiyuan'),
    ('沈阳', '辽宁', 41.8057, 123.4315, 'shenyang'),
    ('长春', '吉林', 43.8171, 125.3235, 'changchun'),
    ('哈尔滨', '黑龙江', 45.8038, 126.535, 'haerbin harbin'),
    ('呼和浩特', '内蒙古', 40.8426, 111.7492, 'huhehaote hohhot'),
    ('南宁', '广西', 22.817, 108.3669, 'nanning'),
    ('海口', '海南', 20.044, 110.1999, 'haikou'),
    ('贵阳', '贵州', 26.647, 106.6302, 'guiyang'),
    ('昆明', '云南', 25.0389, 102.7183, 'kunming'),
    ('拉萨', '西藏', 29.652, 91.1721, 'lasa lhasa'),
    ('兰州', '甘肃', 36.0611, 103.8343, 'lanzhou'),
    ('西宁', '青海', 36.6171, 101.7782, 'xining'),
    ('银川', '宁夏', 38.4872, 106.2309, 'yinchuan'),
    ('乌鲁木齐', '新疆', 43.8256, 87.6168, 'wulumuqi urumqi'),
    ('香港', '香港', 22.3193, 114.1694, 'xianggang hongkong'),
    ('澳门', '澳门', 22.1987, 113.5439, 'aomen macau'),
    ('台北', '台湾', 25.033, 121.5654, 'taibei taipei'),
  ];
}

class WeatherLocationService {
  Future<WeatherLocation> locate({bool requestPermission = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const WeatherFailure(
          WeatherFailureKind.locationDisabled,
          '设备定位服务未开启，可开启定位或手动选择城市',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const WeatherFailure(
          WeatherFailureKind.permissionForever,
          '定位权限已关闭，请在应用权限设置中开启，或手动选择城市',
        );
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        throw const WeatherFailure(
          WeatherFailureKind.permission,
          '未获得定位权限，可授权定位或手动选择城市',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return WeatherLocation(
        name: '当前位置',
        latitude: double.parse(position.latitude.toStringAsFixed(2)),
        longitude: double.parse(position.longitude.toStringAsFixed(2)),
      );
    } on WeatherFailure {
      rethrow;
    } catch (_) {
      throw const WeatherFailure(
        WeatherFailureKind.locationUnavailable,
        '暂时无法获取设备位置，请重试或手动选择城市',
      );
    }
  }

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}
