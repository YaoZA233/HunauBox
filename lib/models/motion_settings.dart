import 'package:flutter/material.dart';

enum AppTransition {
  slide('平滑滑动', '页面沿操作方向平滑移入', Icons.swipe_outlined),
  fade('淡入淡出', '柔和交替，减少大幅移动', Icons.gradient_rounded),
  perspective('透视', '带有空间倾斜与纵深的切换', Icons.view_in_ar_outlined),
  stack('层叠挤压', '新页面推进，原页面向后收拢', Icons.layers_outlined),
  cube('立方体', '页面沿立方体侧面旋转', Icons.view_in_ar_rounded),
  none('无动画', '立即切换页面', Icons.flash_on_outlined);

  const AppTransition(this.label, this.description, this.icon);
  final String label;
  final String description;
  final IconData icon;
}

enum MotionSpeed {
  fast('快速', 220),
  normal('标准', 300),
  relaxed('舒缓', 420);

  const MotionSpeed(this.label, this.milliseconds);
  final String label;
  final int milliseconds;
}

@immutable
class MotionSettings extends ThemeExtension<MotionSettings> {
  const MotionSettings({
    this.transition = AppTransition.slide,
    this.speed = MotionSpeed.normal,
    this.pressFeedback = true,
    this.bouncyScroll = true,
    this.reduceMotion = false,
  });

  final AppTransition transition;
  final MotionSpeed speed;
  final bool pressFeedback;
  final bool bouncyScroll;
  final bool reduceMotion;

  static MotionSettings of(BuildContext context) =>
      Theme.of(context).extension<MotionSettings>() ?? const MotionSettings();

  bool reduced(BuildContext context) =>
      reduceMotion || MediaQuery.disableAnimationsOf(context);

  AppTransition effectiveTransition(BuildContext context) =>
      transition == AppTransition.none
      ? AppTransition.none
      : reduced(context)
      ? AppTransition.fade
      : transition;

  Duration duration(BuildContext context, {bool reverse = false}) {
    if (transition == AppTransition.none) return Duration.zero;
    if (reduced(context)) return const Duration(milliseconds: 100);
    return Duration(
      milliseconds: (speed.milliseconds * (reverse ? .8 : 1)).round(),
    );
  }

  @override
  MotionSettings copyWith({
    AppTransition? transition,
    MotionSpeed? speed,
    bool? pressFeedback,
    bool? bouncyScroll,
    bool? reduceMotion,
  }) => MotionSettings(
    transition: transition ?? this.transition,
    speed: speed ?? this.speed,
    pressFeedback: pressFeedback ?? this.pressFeedback,
    bouncyScroll: bouncyScroll ?? this.bouncyScroll,
    reduceMotion: reduceMotion ?? this.reduceMotion,
  );

  @override
  MotionSettings lerp(covariant MotionSettings? other, double t) =>
      other == null || t < .5 ? this : other;

  Map<String, Object> toJson() => {
    'transition': transition.name,
    'speed': speed.name,
    'pressFeedback': pressFeedback,
    'bouncyScroll': bouncyScroll,
    'reduceMotion': reduceMotion,
  };

  factory MotionSettings.fromJson(Map<String, dynamic> json) {
    return MotionSettings(
      transition:
          AppTransition.values
              .where((v) => v.name == json['transition'])
              .firstOrNull ??
          AppTransition.slide,
      speed:
          MotionSpeed.values
              .where((v) => v.name == json['speed'])
              .firstOrNull ??
          MotionSpeed.normal,
      pressFeedback: json['pressFeedback'] is bool
          ? json['pressFeedback'] as bool
          : true,
      bouncyScroll: json['bouncyScroll'] is bool
          ? json['bouncyScroll'] as bool
          : true,
      reduceMotion: json['reduceMotion'] == true,
    );
  }
}
