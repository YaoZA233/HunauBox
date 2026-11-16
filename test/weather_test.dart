import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_hunan_agri/models/weather.dart';
import 'package:smart_hunan_agri/pages/main_navigator.dart';
import 'package:smart_hunan_agri/pages/weather_settings_page.dart';
import 'package:smart_hunan_agri/providers/weather_provider.dart';
import 'package:smart_hunan_agri/services/weather_service.dart';
import 'package:smart_hunan_agri/widgets/weather_widgets.dart';

import 'support/session_http_adapter.dart';

ResponseBody weatherResponse(String body) => ResponseBody.fromString(
  body,
  200,
  headers: {
    'content-type': ['application/json'],
  },
);

const changsha = WeatherLocation(
  name: '长沙',
  region: '中国 · 湖南',
  latitude: 28.23,
  longitude: 112.94,
);
const beijing = WeatherLocation(
  name: '北京',
  region: '中国 · 北京',
  latitude: 39.90,
  longitude: 116.41,
);

WeatherSnapshot exampleWeather({
  DateTime? now,
  WeatherLocation location = changsha,
  int code = 0,
}) => WeatherSnapshot(
  location: location,
  temperature: 21,
  code: code,
  isDay: true,
  observedAt: now ?? DateTime.now(),
  fetchedAt: now ?? DateTime.now(),
  apparentTemperature: 22,
  humidity: 75,
  windKmh: 10.8,
  maximum: 26,
  minimum: 18,
  rainProbability: 35,
);

class FakeWeatherService extends WeatherService {
  final fetches = <WeatherLocation>[];
  Future<WeatherSnapshot> Function(WeatherLocation)? onFetch;
  Future<List<WeatherLocation>> Function(String)? onSearch;
  @override
  Future<WeatherSnapshot> fetch(
    WeatherLocation location, {
    CancelToken? cancelToken,
    DateTime Function()? now,
  }) {
    fetches.add(location);
    return onFetch?.call(location) ??
        Future.value(exampleWeather(location: location, now: now?.call()));
  }

  @override
  Future<List<WeatherLocation>> search(
    String query, {
    CancelToken? cancelToken,
  }) =>
      onSearch?.call(query) ?? Future.value(WeatherService.searchLocal(query));
}

class FakeWeatherLocator extends WeatherLocationService {
  final requests = <bool>[];
  WeatherFailure? failure;
  @override
  Future<WeatherLocation> locate({bool requestPermission = false}) async {
    requests.add(requestPermission);
    if (failure != null) throw failure!;
    return const WeatherLocation(
      name: '当前位置',
      latitude: 28.19,
      longitude: 113.08,
    );
  }
}

void setWeatherPrefs({
  WeatherSettings settings = const WeatherSettings(
    useDeviceLocation: false,
    manualLocation: changsha,
  ),
  WeatherSnapshot? cached,
  bool deviceCache = false,
  bool prompted = false,
}) => SharedPreferences.setMockInitialValues({
  WeatherController.settingsKey: jsonEncode(settings.toJson()),
  WeatherController.permissionKey: prompted,
  if (cached != null)
    WeatherController.cacheKey: jsonEncode({
      'deviceLocation': deviceCache,
      'snapshot': cached.toJson(),
    }),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => setWeatherPrefs());

  test('公开接口请求使用经纬度，无密钥；正确解析位置时区与可缺失的指标', () async {
    final adapter = SessionHttpAdapter((request) {
      expect(request.uri.host, 'api.open-meteo.com');
      expect(request.uri.queryParameters['latitude'], '28.23');
      expect(request.uri.queryParameters['longitude'], '112.94');
      expect(request.uri.queryParameters['timezone'], 'auto');
      expect(request.uri.queryParameters.containsKey('apikey'), isFalse);
      return weatherResponse(
        jsonEncode({
          'utc_offset_seconds': 28800,
          'current': {
            'time': '2026-10-18T20:00',
            'temperature_2m': 20.7,
            'is_day': 0,
            'weather_code': 63,
            'relative_humidity_2m': null,
          },
          'daily': {
            'temperature_2m_min': [19.4],
            'temperature_2m_max': [26.8],
            'precipitation_probability_max': [null],
          },
        }),
      );
    });
    final data = await WeatherService(
      dio: Dio()..httpClientAdapter = adapter,
    ).fetch(changsha, now: () => DateTime.utc(2026, 10, 18, 12, 5));
    expect(data.observedAt, DateTime.utc(2026, 10, 18, 12));
    expect(data.localObservedAt.hour, 20);
    expect(data.humidity, isNull);
    expect(data.rainProbability, isNull);
    expect(data.label, '中雨');
    expect(data.minimum, 19.4);
    expect(data.freshAt(DateTime.utc(2026, 10, 18, 12, 5)), isTrue);
    expect(
      WeatherSnapshot.fromJson(
        jsonDecode(jsonEncode(data.toJson())),
      ).observedAt,
      data.observedAt,
    );
  });

  test('缺少必要天气字段不会默认为晴天，未知天气码不生成晴天问候', () {
    expect(
      () => WeatherService.parse(
        {
          'current': {'weather_code': 0},
        },
        changsha,
        DateTime.now(),
      ),
      throwsA(isA<WeatherFailure>()),
    );
    final unknown = exampleWeather(code: 1000);
    expect(unknown.label, '天气未知');
    expect(WeatherState(data: unknown).greeting(DateTime.now()), isNull);
    expect(weatherTemperature(20, TemperatureUnit.fahrenheit), '68°F');
    for (final code in [
      0,
      2,
      3,
      45,
      51,
      56,
      61,
      63,
      65,
      71,
      73,
      75,
      80,
      85,
      95,
      99,
    ]) {
      expect(weatherLabel(code), isNot('天气未知'));
      expect(weatherIcon(code), isA<IconData>());
    }
  });

  test('城市中文精确匹配优先湖南长沙，保留其他同名城市的地区信息', () async {
    final adapter = SessionHttpAdapter(
      (request) => weatherResponse(
        jsonEncode({
          'results': [
            {
              'name': '长沙',
              'latitude': 31.0,
              'longitude': 108.3,
              'country': '中国',
              'admin1': '重庆市',
            },
            {'name': '损坏记录'},
          ],
        }),
      ),
    );
    final results = await WeatherService(
      dio: Dio()..httpClientAdapter = adapter,
    ).search('长沙');
    expect(results.first.description, '长沙 · 中国 · 湖南');
    expect(results.first.latitude, closeTo(28.2282, .001));
    expect(results.last.region, contains('重庆市'));
    expect(WeatherService.searchLocal('Changsha').first.name, '长沙');
    expect(WeatherService.searchLocal('北京市').single.name, '北京');
  });

  test('手动城市不访问定位；设置恢复、单位修改不额外请求天气', () async {
    final service = FakeWeatherService();
    final locator = FakeWeatherLocator();
    final controller = WeatherController(service: service, locator: locator);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(locator.requests, isEmpty);
    expect(service.fetches, hasLength(1));
    await controller.update(
      controller.state.settings.copyWith(
        unit: TemperatureUnit.fahrenheit,
        weatherGreeting: false,
        refreshMinutes: 60,
      ),
    );
    expect(service.fetches, hasLength(1));
    final saved = WeatherSettings.fromJson(
      jsonDecode(
        (await SharedPreferences.getInstance()).getString(
          WeatherController.settingsKey,
        )!,
      ),
    );
    expect(saved.unit, TemperatureUnit.fahrenheit);
    expect(saved.refreshMinutes, 60);
    expect(controller.state.greeting(DateTime.now()), isNull);
  });

  test('拒绝定位不会伪装成长沙，不在自动刷新时反复请求授权', () async {
    setWeatherPrefs(settings: const WeatherSettings());
    final locator = FakeWeatherLocator()
      ..failure = const WeatherFailure(
        WeatherFailureKind.permission,
        '未获得定位权限',
      );
    final controller = WeatherController(
      service: FakeWeatherService(),
      locator: locator,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.state.data, isNull);
    expect(controller.state.failure!.kind, WeatherFailureKind.permission);
    await controller.refresh();
    expect(locator.requests, [true, false]);
    await controller.refresh(requestPermission: true);
    expect(locator.requests.last, isTrue);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        WeatherController.permissionKey,
      ),
      isTrue,
    );
  });

  test('离线沿用同一城市的缓存并标记错误，陈旧天气不进入首页问候', () async {
    final now = DateTime.now();
    setWeatherPrefs(
      cached: exampleWeather(now: now.subtract(const Duration(hours: 2))),
    );
    final service = FakeWeatherService()
      ..onFetch = (_) async =>
          throw const WeatherFailure(WeatherFailureKind.network, '网络不可用');
    final controller = WeatherController(
      service: service,
      locator: FakeWeatherLocator(),
      now: () => now,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.state.data!.location.id, changsha.id);
    expect(controller.state.failure!.message, '网络不可用');
    expect(controller.state.greeting(now), isNull);
  });

  test('超过六小时或其他城市的缓存不会当成当前城市天气', () async {
    for (final cached in [
      exampleWeather(now: DateTime.now().subtract(const Duration(hours: 7))),
      exampleWeather(location: beijing),
    ]) {
      setWeatherPrefs(cached: cached);
      final service = FakeWeatherService()
        ..onFetch = (_) async =>
            throw const WeatherFailure(WeatherFailureKind.network, '网络不可用');
      final controller = WeatherController(
        service: service,
        locator: FakeWeatherLocator(),
      );
      await controller.refresh();
      expect(controller.state.data, isNull);
      controller.dispose();
    }
  });

  test('切换城市取消旧请求，迟到的旧位置结果不会覆盖新天气', () async {
    final old = Completer<WeatherSnapshot>();
    final service = FakeWeatherService()
      ..onFetch = (location) => location.id == changsha.id
          ? old.future
          : Future.value(exampleWeather(location: location, code: 3));
    final controller = WeatherController(
      service: service,
      locator: FakeWeatherLocator(),
    );
    addTearDown(controller.dispose);
    await controller.ready;
    final oldTask = controller.refresh();
    await controller.update(
      controller.state.settings.copyWith(manualLocation: beijing),
    );
    await controller.refresh();
    expect(controller.state.data!.location.name, '北京');
    old.complete(exampleWeather());
    await oldTask;
    expect(controller.state.data!.location.name, '北京');
    expect(controller.state.data!.label, '阴');
  });

  testWidgets('前台定时刷新，后台不启动定位或网络，恢复后刷新过期天气', (tester) async {
    var now = DateTime.now();
    final service = FakeWeatherService();
    final controller = WeatherController(
      service: service,
      locator: FakeWeatherLocator(),
      now: () => now,
    );
    await controller.refresh();
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(hours: 1));
    await tester.pump(const Duration(hours: 1));
    expect(service.fetches, hasLength(1));
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await controller.refresh();
    expect(service.fetches, hasLength(2));
    now = now.add(const Duration(minutes: 30));
    await tester.pump(const Duration(minutes: 30));
    await tester.pumpAndSettle();
    expect(service.fetches, hasLength(3));
    controller.dispose();
  });

  Future<ProviderContainer> weatherContainer() async {
    final container = ProviderContainer(
      overrides: [
        weatherServiceProvider.overrideWithValue(FakeWeatherService()),
        weatherLocationServiceProvider.overrideWithValue(FakeWeatherLocator()),
      ],
    );
    await container.read(weatherProvider.notifier).refresh();
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('天气问候动态更新、开关关闭恢复原文，关闭天气不再发起请求', (tester) async {
    final container = await weatherContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: WeatherGreeting(realName: '小明')),
        ),
      ),
    );
    expect(find.text('小明，今天晴'), findsOneWidget);
    final controller = container.read(weatherProvider.notifier);
    await controller.update(
      controller.state.settings.copyWith(weatherGreeting: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('小明，今天好'), findsOneWidget);
    await controller.update(controller.state.settings.copyWith(enabled: false));
    await controller.refresh();
    expect(
      (container.read(weatherServiceProvider) as FakeWeatherService).fetches,
      hasLength(1),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('天气设置 $brightness 窄屏大字体可阅读和操作城市选择', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = await weatherContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(
              brightness: brightness,
              colorSchemeSeed: Colors.green,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const WeatherSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('21°C'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('手动选择天气城市'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('手动选择天气城市'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '北京');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(ListTile), matching: find.text('北京')),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(weatherProvider).settings.manualLocation!.name,
        '北京',
      );
      expect(
        container.read(weatherProvider).settings.useDeviceLocation,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  }

  testWidgets('左栏天气在电量下方，小屏横向和大字体可滚动到导航入口', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/battery'),
      (call) async => call.method == 'getBatteryLevel' ? 75 : 'discharging',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/charging'),
      (_) async => null,
    );
    await tester.binding.setSurfaceSize(const Size(640, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await weatherContainer();
    int? selected;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 78,
                  child: CampusNavigationRail(
                    agentEnabled: true,
                    onChanged: (value) => selected = value,
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(WeatherRailStatus)).dy,
      greaterThan(tester.getBottomLeft(find.text('75%')).dy),
    );
    await tester.scrollUntilVisible(
      find.text('Agent'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agent'));
    expect(selected, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets('城市搜索快速改词时忽略迟到的旧结果，退出后不更新页面', (tester) async {
    final pending = Completer<List<WeatherLocation>>();
    final service = FakeWeatherService()
      ..onSearch = (query) =>
          query == '北京' ? pending.future : Future.value([changsha]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WeatherCityPicker(service: service)),
      ),
    );
    await tester.enterText(find.byType(TextField), '北京');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.enterText(find.byType(TextField), '长沙');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(ListTile), matching: find.text('长沙')),
      findsOneWidget,
    );
    pending.complete([beijing]);
    await tester.pumpAndSettle();
    expect(find.text('北京'), findsNothing);
    final late = Completer<List<WeatherLocation>>();
    service.onSearch = (_) => late.future;
    await tester.enterText(find.byType(TextField), '上海');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpWidget(const SizedBox());
    late.complete([beijing]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
