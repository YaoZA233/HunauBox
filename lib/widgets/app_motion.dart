import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/motion_settings.dart';

/// Shared geometry for routes, swipeable pages and the settings preview.
class AppMotionSurface extends StatelessWidget {
  const AppMotionSurface({
    super.key,
    required this.offset,
    required this.style,
    required this.child,
    this.translate = false,
  });

  final double offset;
  final AppTransition style;
  final Widget child;
  final bool translate;

  @override
  Widget build(BuildContext context) {
    final delta = offset.clamp(-1.0, 1.0);
    final distance = delta.abs();
    if (style == AppTransition.none) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final perspective = .65 / math.max(width, 1);
        final matrix = Matrix4.identity();
        var opacity = 1.0;
        var alignment = Alignment.center;
        switch (style) {
          case AppTransition.slide:
            if (translate) matrix.translateByDouble(delta * width, 0, 0, 1);
          case AppTransition.fade:
            opacity = 1 - distance;
          case AppTransition.perspective:
            matrix.setEntry(3, 2, perspective);
            if (translate) matrix.translateByDouble(delta * width, 0, 0, 1);
            matrix.rotateY(-delta * math.pi / 10);
            matrix.scaleByDouble(1 - .06 * distance, 1 - .06 * distance, 1, 1);
            opacity = 1 - .25 * distance;
          case AppTransition.stack:
            if (translate) {
              matrix.translateByDouble(
                delta * width * (delta < 0 ? .18 : 1),
                0,
                0,
                1,
              );
            }
            final scale = 1 - (delta < 0 ? .08 : .02) * distance;
            matrix.scaleByDouble(scale, scale, 1, 1);
            opacity = 1 - (delta < 0 ? .25 : 0) * distance;
          case AppTransition.cube:
            alignment = delta < 0
                ? Alignment.centerRight
                : Alignment.centerLeft;
            matrix.setEntry(3, 2, perspective);
            if (translate) matrix.translateByDouble(delta * width, 0, 0, 1);
            matrix.rotateY(delta * math.pi / 2);
            opacity = distance >= .9999 ? 0 : 1;
          case AppTransition.none:
            break;
        }
        return Transform(
          transform: matrix,
          alignment: alignment,
          child: Opacity(opacity: opacity.clamp(0, 1), child: child),
        );
      },
    );
  }
}

class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder(this.settings);
  final MotionSettings settings;

  @override
  Duration get transitionDuration => settings.transition == AppTransition.none
      ? Duration.zero
      : Duration(
          milliseconds:
              settings.reduceMotion ||
                  WidgetsBinding
                      .instance
                      .platformDispatcher
                      .accessibilityFeatures
                      .disableAnimations
              ? 100
              : settings.speed.milliseconds,
        );

  @override
  Duration get reverseTransitionDuration =>
      Duration(milliseconds: (transitionDuration.inMilliseconds * .8).round());

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final style = settings.effectiveTransition(context);
    if (style == AppTransition.none) return child;
    final platform = Theme.of(context).platform;
    if (style == AppTransition.slide &&
        (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS)) {
      // Preserve the native, cancellable edge-back gesture for the default
      // horizontal transition on Apple platforms.
      return const CupertinoPageTransitionsBuilder().buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        // Gesture progress must follow the finger without time-based easing.
        final linear = route.popGestureInProgress;
        final entering = linear
            ? animation.value
            : Curves.easeOutCubic.transform(animation.value);
        final leaving = linear
            ? secondaryAnimation.value
            : Curves.easeOutCubic.transform(secondaryAnimation.value);
        return AppMotionSurface(
          offset: 1 - entering - leaving,
          style: style,
          translate: true,
          child: child!,
        );
      },
    );
  }
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  // The physics already supplies edge resistance. A second stretch/glow would
  // distort content twice and would remain visible when bounce is disabled.
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final settings = MotionSettings.of(context);
    return settings.bouncyScroll && !settings.reduced(context)
        ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
        : const ClampingScrollPhysics();
  }
}

/// PageView supplies the horizontal position; only add depth to that position.
class AppMotionPage extends StatelessWidget {
  const AppMotionPage({
    super.key,
    required this.controller,
    required this.index,
    required this.child,
  });
  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = MotionSettings.of(context);
    final style = settings.effectiveTransition(context);
    return AnimatedBuilder(
      animation: controller,
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        final page =
            controller.hasClients && controller.position.hasContentDimensions
            ? controller.page ?? controller.initialPage.toDouble()
            : controller.initialPage.toDouble();
        return AppMotionSurface(
          offset: index - page,
          style: style,
          child: child!,
        );
      },
    );
  }
}

/// Uses InkWell's gesture arbitration: scrolling/long-press cancels the tap.
class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      borderRadius: widget.borderRadius,
      onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
      child: AppPressScale(
        pressed:
            _pressed && (widget.onTap != null || widget.onLongPress != null),
        child: widget.child,
      ),
    );
  }
}

class AppPressScale extends StatelessWidget {
  const AppPressScale({super.key, required this.pressed, required this.child});
  final bool pressed;
  final Widget child;

  static Widget buttonBuilder(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) => AppPressScale(
    pressed:
        states.contains(WidgetState.pressed) &&
        !states.contains(WidgetState.disabled),
    child: child ?? const SizedBox.shrink(),
  );

  @override
  Widget build(BuildContext context) {
    final settings = MotionSettings.of(context);
    final enabled = settings.pressFeedback && !settings.reduced(context);
    return AnimatedScale(
      scale: pressed && enabled ? .97 : 1,
      duration: enabled
          ? Duration(milliseconds: pressed ? 80 : 150)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      child: child,
    );
  }
}

/// Keeps both calendar states mounted while allowing rapid reversals.
class AppMotionIndexedStack extends StatefulWidget {
  const AppMotionIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });
  final int index;
  final List<Widget> children;

  @override
  State<AppMotionIndexedStack> createState() => _AppMotionIndexedStackState();
}

class _AppMotionIndexedStackState extends State<AppMotionIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: widget.index.toDouble(),
  );

  @override
  void didUpdateWidget(covariant AppMotionIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      final settings = MotionSettings.of(context);
      _controller.animateTo(
        widget.index.toDouble(),
        duration: settings.duration(context),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = MotionSettings.of(context).effectiveTransition(context);
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            for (var index = 0; index < widget.children.length; index++)
              Offstage(
                offstage:
                    index != widget.index &&
                    (!_controller.isAnimating ||
                        (index - _controller.value).abs() >= 1),
                child: TickerMode(
                  enabled: index == widget.index,
                  child: IgnorePointer(
                    ignoring: index != widget.index,
                    child: ExcludeSemantics(
                      excluding: index != widget.index,
                      child: AppMotionSurface(
                        offset: index - _controller.value,
                        style: style,
                        translate: true,
                        child: widget.children[index],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
