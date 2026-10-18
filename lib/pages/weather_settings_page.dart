import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/weather.dart';
import '../providers/weather_provider.dart';
import '../services/weather_service.dart';
import '../widgets/weather_widgets.dart';

class WeatherSettingsPage extends ConsumerWidget {
  const WeatherSettingsPage({super.key});

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    WeatherSettings settings,
  ) async {
    try {
      await ref.read(weatherProvider.notifier).update(settings);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('天气设置暂未保存，请重试')));
      }
    }
  }

  Future<void> _chooseCity(BuildContext context, WidgetRef ref) async {
    final location = await showModalBottomSheet<WeatherLocation>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: WeatherCityPicker(service: ref.read(weatherServiceProvider)),
          ),
        ),
      ),
    );
    if (location != null && context.mounted) {
      await _save(
        context,
        ref,
        ref
            .read(weatherProvider)
            .settings
            .copyWith(
              enabled: true,
              useDeviceLocation: false,
              manualLocation: location,
            ),
      );
    }
  }

  Future<void> _openPermissionSettings(
    BuildContext context,
    WidgetRef ref,
    bool app,
  ) async {
    try {
      final locator = ref.read(weatherLocationServiceProvider);
      final opened = app
          ? await locator.openAppSettings()
          : await locator.openLocationSettings();
      if (!opened) throw StateError('not opened');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开系统设置，请手动检查定位权限')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weatherProvider);
    final settings = state.settings;
    final colors = Theme.of(context).colorScheme;
    final controller = ref.read(weatherProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('天气与位置'),
        actions: [
          IconButton(
            tooltip: '刷新天气',
            onPressed: settings.enabled && !state.loading
                ? () => controller.refresh()
                : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WeatherSummary(state: state),
                  if (state.loading) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (state.failure != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      state.failure!.message,
                      style: TextStyle(color: colors.error),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: state.loading
                              ? null
                              : () =>
                                    controller.refresh(requestPermission: true),
                          child: const Text('重试'),
                        ),
                        TextButton(
                          onPressed: () => _chooseCity(context, ref),
                          child: const Text('手动选择城市'),
                        ),
                        if (state.failure!.kind ==
                            WeatherFailureKind.permissionForever)
                          TextButton(
                            onPressed: () =>
                                _openPermissionSettings(context, ref, true),
                            child: const Text('应用权限设置'),
                          ),
                        if (state.failure!.kind ==
                            WeatherFailureKind.locationDisabled)
                          TextButton(
                            onPressed: () =>
                                _openPermissionSettings(context, ref, false),
                            child: const Text('开启系统定位'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用天气'),
            subtitle: const Text('获取所选位置的当前天气与今日气温'),
            value: settings.enabled,
            onChanged: (enabled) =>
                _save(context, ref, settings.copyWith(enabled: enabled)),
          ),
          const Divider(height: 24),
          Text('天气位置', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('使用设备当前位置'),
            subtitle: const Text('仅在前台刷新时定位；手动城市无需定位权限'),
            value: settings.useDeviceLocation,
            onChanged: !settings.enabled
                ? null
                : (automatic) async {
                    if (!automatic && settings.manualLocation == null) {
                      await _chooseCity(context, ref);
                      return;
                    }
                    await _save(
                      context,
                      ref,
                      settings.copyWith(useDeviceLocation: automatic),
                    );
                  },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_city_outlined),
            title: const Text('手动选择天气城市'),
            subtitle: Text(
              settings.manualLocation?.description ?? '搜索城市名称或拼音，例如长沙、Changsha',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _chooseCity(context, ref),
          ),
          if (settings.enabled && settings.useDeviceLocation)
            OutlinedButton.icon(
              onPressed: state.loading
                  ? null
                  : () => controller.refresh(requestPermission: true),
              icon: const Icon(Icons.my_location_rounded),
              label: const Text('重新定位并刷新'),
            ),
          const Divider(height: 32),
          Text('显示与刷新', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final unit in TemperatureUnit.values)
                ChoiceChip(
                  label: Text(
                    unit == TemperatureUnit.celsius ? '摄氏度 °C' : '华氏度 °F',
                  ),
                  selected: settings.unit == unit,
                  onSelected: (_) =>
                      _save(context, ref, settings.copyWith(unit: unit)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('左侧导航栏天气'),
            subtitle: const Text('在电量下方显示天气图标、气温和天气状态'),
            value: settings.showInRail,
            onChanged: (value) =>
                _save(context, ref, settings.copyWith(showInRail: value)),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('首页天气问候'),
            subtitle: const Text('有较新天气时显示“今天晴／雨／阴”等问候'),
            value: settings.weatherGreeting,
            onChanged: (value) =>
                _save(context, ref, settings.copyWith(weatherGreeting: value)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey(settings.refreshMinutes),
            initialValue: settings.refreshMinutes,
            decoration: const InputDecoration(labelText: '前台自动刷新间隔'),
            items: [
              for (final minutes in [15, 30, 60])
                DropdownMenuItem(value: minutes, child: Text('$minutes 分钟')),
            ],
            onChanged: (minutes) {
              if (minutes != null) {
                _save(context, ref, settings.copyWith(refreshMinutes: minutes));
              }
            },
          ),
          const SizedBox(height: 16),
          Text(
            '天气缓存最多保留 6 小时，超过 90 分钟会标记待刷新，并停止用于首页天气问候。后台不持续定位。',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () async {
              try {
                if (!await launchUrl(
                  Uri.parse('https://open-meteo.com/'),
                  mode: LaunchMode.externalApplication,
                )) {
                  throw StateError('not opened');
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('天气来源：open-meteo.com')),
                  );
                }
              }
            },
            child: const Text('天气数据：Open-Meteo · CC BY 4.0'),
          ),
          const Text(
            '城市数据：GeoNames（通过 Open-Meteo）',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class WeatherCityPicker extends StatefulWidget {
  const WeatherCityPicker({super.key, required this.service});
  final WeatherService service;
  @override
  State<WeatherCityPicker> createState() => _WeatherCityPickerState();
}

class _WeatherCityPickerState extends State<WeatherCityPicker> {
  final _text = TextEditingController();
  List<WeatherLocation> _results = WeatherService.searchLocal(
    '',
  ).take(16).toList();
  Timer? _debounce;
  CancelToken? _cancel;
  int _generation = 0;
  bool _loading = false;
  String? _error;

  void _search(String value, {bool immediate = false}) {
    _debounce?.cancel();
    _cancel?.cancel();
    final generation = ++_generation;
    final text = value.trim();
    setState(() {
      _results = WeatherService.searchLocal(text);
      _error = null;
      _loading = text.runes.length >= 2;
    });
    if (!_loading) return;
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 400),
      () async {
        final token = CancelToken();
        _cancel = token;
        try {
          final results = await widget.service.search(text, cancelToken: token);
          if (!mounted || generation != _generation) return;
          setState(() {
            _results = results;
            _loading = false;
          });
        } catch (error) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _loading = false;
            _error = error is WeatherFailure ? error.message : '搜索失败，请稍后重试';
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _cancel?.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('选择天气城市', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          onChanged: _search,
          onSubmitted: (text) => _search(text, immediate: true),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: '城市名称或拼音',
            hintText: '长沙 / Changsha',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: '搜索城市',
              onPressed: () => _search(_text.text, immediate: true),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _results.isEmpty && !_loading
              ? const Center(
                  child: Text('未找到城市，可尝试完整名称或拼音', textAlign: TextAlign.center),
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final location = _results[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(location.name),
                      subtitle: Text(
                        '${location.region}\n${location.latitude.toStringAsFixed(2)}, ${location.longitude.toStringAsFixed(2)}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).pop(location),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
