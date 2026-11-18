import 'package:flutter/material.dart';

/// Shared determinate progress treatment. Value changes settle smoothly so
/// progress does not jump when data arrives in chunks.
class CampusProgressBar extends StatelessWidget {
  const CampusProgressBar({
    super.key,
    required this.value,
    this.minHeight = 4,
    this.backgroundColor,
    this.color,
    this.semanticsLabel,
    this.borderRadius,
  });

  final double? value;
  final double minHeight;
  final Color? backgroundColor;
  final Color? color;
  final String? semanticsLabel;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return _CampusIndeterminateProgressBar(
        minHeight: minHeight,
        backgroundColor: backgroundColor,
        color: color,
        semanticsLabel: semanticsLabel,
        borderRadius: borderRadius,
      );
    }
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final target = value!.clamp(0.0, 1.0);
    return Semantics(
      label: semanticsLabel,
      value: '${(target * 100).round()}%',
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(minHeight),
        child: SizedBox(
          height: minHeight,
          child: ColoredBox(
            color: backgroundColor ?? colors.surfaceContainerHighest,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: target),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              builder: (context, progress, _) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress,
                  heightFactor: 1,
                  child: ColoredBox(color: color ?? colors.primary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CampusIndeterminateProgressBar extends StatefulWidget {
  const _CampusIndeterminateProgressBar({
    required this.minHeight,
    required this.backgroundColor,
    required this.color,
    required this.semanticsLabel,
    required this.borderRadius,
  });

  final double minHeight;
  final Color? backgroundColor;
  final Color? color;
  final String? semanticsLabel;
  final BorderRadius? borderRadius;

  @override
  State<_CampusIndeterminateProgressBar> createState() =>
      _CampusIndeterminateProgressBarState();
}

class _CampusIndeterminateProgressBarState
    extends State<_CampusIndeterminateProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _reduceMotion = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: widget.semanticsLabel ?? '正在加载',
      child: ClipRRect(
        borderRadius:
            widget.borderRadius ?? BorderRadius.circular(widget.minHeight),
        child: SizedBox(
          height: widget.minHeight,
          child: LayoutBuilder(
            builder: (context, constraints) => ColoredBox(
              color: widget.backgroundColor ?? colors.surfaceContainerHighest,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final width = constraints.maxWidth;
                  final segmentWidth = width * .28;
                  final progress = _reduceMotion ? .36 : _controller.value;
                  return Transform.translate(
                    offset: Offset(
                      progress * (width + segmentWidth) - segmentWidth,
                      0,
                    ),
                    child: SizedBox(
                      width: segmentWidth,
                      height: widget.minHeight,
                      child: ColoredBox(
                        color: widget.color ?? colors.primary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
