import 'package:flutter/material.dart';

enum TemperatureUnit { celsius, fahrenheit }

@immutable
class WeatherLocation {
  const WeatherLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.region = '',
  });
  final String name;
  final double latitude;
  final double longitude;
  final String region;
  bool get valid =>
      name.trim().isNotEmpty &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;
  String get id =>
      '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}';
  String get description => region.isEmpty ? name : '$name · $region';
  Map<String, dynamic> toJson() => {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'region': region,
  };
  factory WeatherLocation.fromJson(Map<String, dynamic> json) {
    final location = WeatherLocation(
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      region: json['region'] as String? ?? '',
    );
    if (!location.valid) throw const FormatException('无效的天气位置');
    return location;
  }
}

@immutable
class WeatherSettings {
  const WeatherSettings({
    this.enabled = true,
    this.useDeviceLocation = true,
    this.manualLocation,
    this.unit = TemperatureUnit.celsius,
    this.refreshMinutes = 30,
    this.showInRail = true,
    this.weatherGreeting = true,
  });
  final bool enabled;
  final bool useDeviceLocation;
  final WeatherLocation? manualLocation;
  final TemperatureUnit unit;
  final int refreshMinutes;
  final bool showInRail;
  final bool weatherGreeting;
  WeatherSettings copyWith({
    bool? enabled,
    bool? useDeviceLocation,
    WeatherLocation? manualLocation,
    TemperatureUnit? unit,
    int? refreshMinutes,
    bool? showInRail,
    bool? weatherGreeting,
  }) => WeatherSettings(
    enabled: enabled ?? this.enabled,
    useDeviceLocation: useDeviceLocation ?? this.useDeviceLocation,
    manualLocation: manualLocation ?? this.manualLocation,
    unit: unit ?? this.unit,
    refreshMinutes: refreshMinutes ?? this.refreshMinutes,
    showInRail: showInRail ?? this.showInRail,
    weatherGreeting: weatherGreeting ?? this.weatherGreeting,
  );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'useDeviceLocation': useDeviceLocation,
    'manualLocation': manualLocation?.toJson(),
    'unit': unit.name,
    'refreshMinutes': refreshMinutes,
    'showInRail': showInRail,
    'weatherGreeting': weatherGreeting,
  };
  factory WeatherSettings.fromJson(Map<String, dynamic> json) {
    WeatherLocation? location;
    try {
      if (json['manualLocation'] is Map<String, dynamic>) {
        location = WeatherLocation.fromJson(json['manualLocation']);
      }
    } catch (_) {
      /* Keep automatic mode for malformed cities. */
    }
    return WeatherSettings(
      enabled: json['enabled'] != false,
      useDeviceLocation: json['useDeviceLocation'] != false || location == null,
      manualLocation: location,
      unit: json['unit'] == 'fahrenheit'
          ? TemperatureUnit.fahrenheit
          : TemperatureUnit.celsius,
      refreshMinutes: [15, 30, 60].contains(json['refreshMinutes'])
          ? json['refreshMinutes'] as int
          : 30,
      showInRail: json['showInRail'] != false,
      weatherGreeting: json['weatherGreeting'] != false,
    );
  }
}

enum WeatherFailureKind {
  network,
  permission,
  permissionForever,
  locationDisabled,
  locationUnavailable,
  invalidResponse,
}

class WeatherFailure implements Exception {
  const WeatherFailure(this.kind, this.message);
  final WeatherFailureKind kind;
  final String message;
  @override
  String toString() => message;
}

String weatherLabel(int code) => switch (code) {
  0 || 1 => '晴',
  2 => '多云',
  3 => '阴',
  45 || 48 => '雾',
  51 || 53 || 55 => '毛毛雨',
  56 || 57 || 66 || 67 => '冻雨',
  61 || 80 => '小雨',
  63 || 81 => '中雨',
  65 || 82 => '大雨',
  71 || 77 || 85 => '小雪',
  73 => '中雪',
  75 || 86 => '大雪',
  95 => '雷雨',
  96 || 99 => '雷雨冰雹',
  _ => '天气未知',
};

IconData weatherIcon(int code, {bool isDay = true}) => switch (code) {
  0 || 1 => isDay ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined,
  2 || 3 => Icons.cloud_outlined,
  45 || 48 => Icons.foggy,
  >= 95 && <= 99 => Icons.thunderstorm_outlined,
  >= 71 && <= 77 || 85 || 86 => Icons.ac_unit_rounded,
  >= 51 && <= 67 || >= 80 && <= 82 => Icons.water_drop_outlined,
  _ => Icons.thermostat_outlined,
};

String weatherTemperature(
  double value,
  TemperatureUnit unit, {
  bool suffix = true,
}) {
  final converted = unit == TemperatureUnit.fahrenheit
      ? value * 9 / 5 + 32
      : value;
  return '${converted.round()}${suffix
      ? unit == TemperatureUnit.fahrenheit
            ? '°F'
            : '°C'
      : '°'}';
}

@immutable
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.location,
    required this.temperature,
    required this.code,
    required this.isDay,
    required this.observedAt,
    required this.fetchedAt,
    this.utcOffsetSeconds = 28800,
    this.apparentTemperature,
    this.humidity,
    this.windKmh,
    this.maximum,
    this.minimum,
    this.rainProbability,
  });
  final WeatherLocation location;
  final double temperature;
  final int code;
  final bool isDay;
  final DateTime observedAt;
  final DateTime fetchedAt;
  final int utcOffsetSeconds;
  final double? apparentTemperature,
      humidity,
      windKmh,
      maximum,
      minimum,
      rainProbability;
  String get label => weatherLabel(code);
  IconData get icon => weatherIcon(code, isDay: isDay);
  DateTime get localObservedAt =>
      observedAt.toUtc().add(Duration(seconds: utcOffsetSeconds));
  bool cacheUsableAt(DateTime now) {
    final fetchedAge = now.toUtc().difference(fetchedAt.toUtc());
    final observedAge = now.toUtc().difference(observedAt.toUtc());
    return fetchedAge >= Duration.zero &&
        fetchedAge < const Duration(hours: 6) &&
        observedAge >= const Duration(minutes: -15) &&
        observedAge < const Duration(hours: 6);
  }

  bool freshAt(DateTime now) {
    final observedAge = now.toUtc().difference(observedAt.toUtc());
    final fetchedAge = now.toUtc().difference(fetchedAt.toUtc());
    return observedAge >= const Duration(minutes: -15) &&
        observedAge <= const Duration(minutes: 90) &&
        fetchedAge >= Duration.zero &&
        fetchedAge <= const Duration(minutes: 90);
  }

  Map<String, dynamic> toJson() => {
    'location': location.toJson(),
    'temperature': temperature,
    'code': code,
    'isDay': isDay,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'utcOffsetSeconds': utcOffsetSeconds,
    'apparentTemperature': apparentTemperature,
    'humidity': humidity,
    'windKmh': windKmh,
    'maximum': maximum,
    'minimum': minimum,
    'rainProbability': rainProbability,
  };
  factory WeatherSnapshot.fromJson(Map<String, dynamic> json) {
    double? optional(String key) => (json[key] as num?)?.toDouble();
    final temperature = (json['temperature'] as num).toDouble();
    if (!temperature.isFinite) throw const FormatException('无效的气温');
    return WeatherSnapshot(
      location: WeatherLocation.fromJson(json['location']),
      temperature: temperature,
      code: json['code'] as int,
      isDay: json['isDay'] == true,
      observedAt: DateTime.parse(json['observedAt']),
      fetchedAt: DateTime.parse(json['fetchedAt']),
      utcOffsetSeconds: json['utcOffsetSeconds'] as int? ?? 28800,
      apparentTemperature: optional('apparentTemperature'),
      humidity: optional('humidity'),
      windKmh: optional('windKmh'),
      maximum: optional('maximum'),
      minimum: optional('minimum'),
      rainProbability: optional('rainProbability'),
    );
  }
}

@immutable
class WeatherState {
  const WeatherState({
    this.settings = const WeatherSettings(),
    this.data,
    this.loading = false,
    this.initialized = false,
    this.failure,
  });
  final WeatherSettings settings;
  final WeatherSnapshot? data;
  final bool loading;
  final bool initialized;
  final WeatherFailure? failure;
  String? greeting(DateTime now) =>
      settings.enabled &&
          settings.weatherGreeting &&
          data != null &&
          data!.freshAt(now) &&
          data!.label != '天气未知'
      ? '今天${data!.label}'
      : null;
}
