import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weather.dart';
import '../pages/weather_settings_page.dart';
import '../providers/weather_provider.dart';
import 'app_motion.dart';

class WeatherRailStatus extends ConsumerWidget {
  const WeatherRailStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weatherProvider);
    if (!state.settings.enabled || !state.settings.showInRail) {
      return const SizedBox.shrink();
    }
    final data = state.data;
    final colors = Theme.of(context).colorScheme;
    final stale = data != null && !data.freshAt(DateTime.now());
    final label = data?.label ?? (state.loading ? '获取中' : '设置天气');
    final description = data == null
        ? state.failure?.message ?? '正在获取当前位置的天气'
        : '${data.location.description}，$label，${weatherTemperature(data.temperature, state.settings.unit)}${stale ? '，缓存待刷新' : ''}${state.failure == null ? '' : '，${state.failure!.message}'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 6, 5, 12),
      child: Tooltip(
        message: description,
        child: Semantics(
          button: true,
          label: '$description，打开天气设置',
          excludeSemantics: true,
          child: AppPressable(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WeatherSettingsPage(),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Column(
                children: [
                  Icon(
                    data?.icon ??
                        (state.failure == null
                            ? Icons.cloud_outlined
                            : Icons.cloud_off_outlined),
                    size: 23,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 4),
                  if (data != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        weatherTemperature(
                          data.temperature,
                          state.settings.unit,
                          suffix: false,
                        ),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (stale)
                    Text(
                      '缓存',
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WeatherGreeting extends ConsumerWidget {
  const WeatherGreeting({super.key, this.realName});
  final String? realName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weather = ref.watch(weatherProvider).greeting(DateTime.now());
    final name = realName?.trim();
    final hasName = name != null && name.isNotEmpty;
    final text = weather == null
        ? hasName
              ? '$name，今天好'
              : 'HunauBox'
        : '${hasName ? name : '农大学子'}，$weather';
    return Text(
      text,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontSize: 25,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class WeatherSummary extends StatelessWidget {
  const WeatherSummary({super.key, required this.state});
  final WeatherState state;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    final colors = Theme.of(context).colorScheme;
    if (data == null) {
      return Text(
        state.loading
            ? '正在获取天气…'
            : state.settings.enabled
            ? '天气尚未获取'
            : '天气已关闭',
      );
    }
    final unit = state.settings.unit;
    final time = data.localObservedAt;
    final fresh = data.freshAt(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data.location.description,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(data.icon, size: 34, color: colors.primary),
            Text(
              weatherTemperature(data.temperature, unit),
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            Text(data.label, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            if (data.minimum != null && data.maximum != null)
              Text(
                '今日 ${weatherTemperature(data.minimum!, unit)} ～ ${weatherTemperature(data.maximum!, unit)}',
              ),
            if (data.apparentTemperature != null)
              Text('体感 ${weatherTemperature(data.apparentTemperature!, unit)}'),
            if (data.humidity != null) Text('湿度 ${data.humidity!.round()}%'),
            if (data.windKmh != null)
              Text('风速 ${(data.windKmh! / 3.6).toStringAsFixed(1)} m/s'),
            if (data.rainProbability != null)
              Text('今日降雨概率 ${data.rainProbability!.round()}%'),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${fresh ? '天气时间' : '缓存天气 · 待刷新'} ${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}（当地时间）',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        if (data.location.name == '当前位置') ...[
          const SizedBox(height: 4),
          Text(
            '纬度 ${data.location.latitude.toStringAsFixed(2)} · 经度 ${data.location.longitude.toStringAsFixed(2)}',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
