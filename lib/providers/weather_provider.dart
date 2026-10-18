import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather.dart';
import '../services/weather_service.dart';

final weatherServiceProvider = Provider((ref) => WeatherService());
final weatherLocationServiceProvider = Provider(
  (ref) => WeatherLocationService(),
);
final weatherProvider = StateNotifierProvider<WeatherController, WeatherState>(
  (ref) => WeatherController(
    service: ref.watch(weatherServiceProvider),
    locator: ref.watch(weatherLocationServiceProvider),
  ),
);

class WeatherController extends StateNotifier<WeatherState>
    with WidgetsBindingObserver {
  WeatherController({
    required WeatherService service,
    required WeatherLocationService locator,
    DateTime Function()? now,
  }) : _service = service,
       _locator = locator,
       _now = now ?? DateTime.now,
       super(const WeatherState()) {
    WidgetsBinding.instance.addObserver(this);
    ready = _load();
  }
  static const settingsKey = 'weather_settings_v1';
  static const cacheKey = 'weather_cache_v1';
  static const permissionKey = 'weather_location_permission_prompted';
  final WeatherService _service;
  final WeatherLocationService _locator;
  final DateTime Function() _now;
  late final Future<void> ready;
  SharedPreferences? _prefs;
  Timer? _timer;
  CancelToken? _cancel;
  Future<void>? _task;
  Future<void> _writes = Future.value();
  int _generation = 0;
  bool _foreground = true;
  bool _asked = false;

  Future<void> _load() async {
    var settings = const WeatherSettings();
    WeatherSnapshot? cache;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _prefs = prefs;
      _asked = prefs.getBool(permissionKey) == true;
      try {
        final raw = prefs.getString(settingsKey);
        if (raw != null) settings = WeatherSettings.fromJson(jsonDecode(raw));
      } catch (_) {
        /* Invalid settings fall back without breaking the app. */
      }
      try {
        final raw = prefs.getString(cacheKey);
        if (raw != null && settings.enabled) {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final snapshot = WeatherSnapshot.fromJson(json['snapshot']);
          if (json['deviceLocation'] == settings.useDeviceLocation &&
              (settings.useDeviceLocation ||
                  snapshot.location.id == settings.manualLocation?.id) &&
              snapshot.cacheUsableAt(_now())) {
            cache = snapshot;
          }
        }
      } catch (_) {
        /* Cache is optional. */
      }
    } catch (_) {
      /* Weather remains usable if preferences are unavailable. */
    }
    if (!mounted) return;
    state = WeatherState(settings: settings, data: cache, initialized: true);
    if (settings.enabled) {
      if (_due()) {
        unawaited(_refresh());
      } else {
        _schedule();
      }
    }
  }

  bool _due() =>
      state.data == null ||
      !state.data!.freshAt(_now()) ||
      _now().difference(state.data!.fetchedAt) >=
          Duration(minutes: state.settings.refreshMinutes);

  Future<void> refresh({bool requestPermission = false}) async {
    await ready;
    if (!mounted || !state.settings.enabled) return;
    await (_task ?? _refresh(requestPermission: requestPermission));
  }

  Future<void> _refresh({bool requestPermission = false}) {
    _timer?.cancel();
    final generation = _generation;
    final token = CancelToken();
    _cancel = token;
    state = WeatherState(
      settings: state.settings,
      data: state.data,
      initialized: true,
      loading: true,
    );
    return _task = _fetch(generation, token, requestPermission);
  }

  Future<void> _fetch(
    int generation,
    CancelToken token,
    bool requestPermission,
  ) async {
    final settings = state.settings;
    try {
      WeatherLocation location;
      if (settings.useDeviceLocation) {
        final ask = requestPermission || !_asked;
        if (ask) {
          _asked = true;
          // Save before invoking the platform, so denied access is not prompted
          // again by every automatic refresh or app restart.
          try {
            await _prefs?.setBool(permissionKey, true);
          } catch (_) {
            /* Continue without blocking location. */
          }
        }
        if (!mounted || generation != _generation || !_foreground) return;
        location = await _locator.locate(requestPermission: ask);
      } else {
        location = settings.manualLocation!;
      }
      if (!mounted || generation != _generation || !_foreground) return;
      final snapshot = await _service.fetch(
        location,
        cancelToken: token,
        now: _now,
      );
      if (!mounted || generation != _generation || !_foreground) return;
      state = WeatherState(
        settings: state.settings,
        data: snapshot,
        initialized: true,
      );
      try {
        await _prefs?.setString(
          cacheKey,
          jsonEncode({
            'deviceLocation': settings.useDeviceLocation,
            'snapshot': snapshot.toJson(),
          }),
        );
      } catch (_) {
        /* A cache write must not discard a successful forecast. */
      }
    } catch (error) {
      if (!mounted ||
          generation != _generation ||
          (error is DioException && CancelToken.isCancel(error))) {
        return;
      }
      state = WeatherState(
        settings: state.settings,
        data: state.data?.cacheUsableAt(_now()) == true ? state.data : null,
        initialized: true,
        failure: error is WeatherFailure
            ? error
            : const WeatherFailure(WeatherFailureKind.network, '天气暂不可用，请稍后重试'),
      );
    } finally {
      if (mounted && generation == _generation) {
        _task = null;
        if (state.loading) {
          state = WeatherState(
            settings: state.settings,
            data: state.data,
            initialized: true,
            failure: state.failure,
          );
        }
        _schedule();
      }
    }
  }

  Future<void> update(WeatherSettings settings) async {
    await ready;
    if (!mounted) return;
    if (!settings.useDeviceLocation && settings.manualLocation == null) return;
    final previous = state.settings;
    final changedLocation =
        previous.useDeviceLocation != settings.useDeviceLocation ||
        (!settings.useDeviceLocation &&
            previous.manualLocation?.id != settings.manualLocation?.id);
    final restart = changedLocation || previous.enabled != settings.enabled;
    if (restart) {
      _generation++;
      _cancel?.cancel();
      _task = null;
    }
    _timer?.cancel();
    state = WeatherState(
      settings: settings,
      data: settings.enabled && !changedLocation ? state.data : null,
      loading: !restart && state.loading,
      initialized: true,
      failure: restart ? null : state.failure,
    );
    final raw = jsonEncode(settings.toJson());
    final write = _writes.then((_) async {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      if (!await prefs.setString(settingsKey, raw)) {
        throw StateError('天气设置保存失败');
      }
    });
    _writes = write.catchError((Object _) {});
    if (settings.enabled && restart && _foreground) {
      unawaited(_refresh());
    } else {
      _schedule();
    }
    await write;
  }

  void _schedule() {
    _timer?.cancel();
    if (!_foreground || !state.settings.enabled || state.loading) return;
    _timer = Timer(Duration(minutes: state.settings.refreshMinutes), () {
      if (mounted && _foreground) unawaited(refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _timer?.cancel();
      // A runtime permission prompt can temporarily mark the app inactive;
      // do not cancel that in-flight request, but never start background GPS.
      return;
    }
    if (!this.state.initialized || !this.state.settings.enabled) return;
    if (_due()) {
      unawaited(refresh());
    } else {
      _schedule();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _cancel?.cancel();
    _generation++;
    super.dispose();
  }
}
