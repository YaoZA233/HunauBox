import 'package:flutter/material.dart';

/// A compact three-beat loader used in list pages instead of an indeterminate
/// spinner. It becomes static when the system asks apps to reduce motion.
class CampusLoadingMark extends StatefulWidget {
  const CampusLoadingMark({super.key, this.color, this.size = 34});

  final Color? color;
  final double size;

  @override
  State<CampusLoadingMark> createState() => _CampusLoadingMarkState();
}

class _CampusLoadingMarkState extends State<CampusLoadingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
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
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final barWidth = widget.size / 7;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (index) {
            final phase = (_controller.value - index * .22 + 1) % 1;
            final pulse = _reduceMotion
                ? .35
                : .35 + .65 * (1 - (phase * 2 - 1).abs());
            return Container(
              width: barWidth,
              height: widget.size * (.34 + pulse * .42),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .35 + pulse * .65),
                borderRadius: BorderRadius.circular(barWidth),
              ),
            );
          }),
        ),
      ),
    );
  }
}
