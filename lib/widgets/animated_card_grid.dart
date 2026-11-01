import 'package:flutter/material.dart';

/// 带动画的卡片网格，支持拖动重排时的平滑过渡
class AnimatedCardGrid extends StatefulWidget {
  const AnimatedCardGrid({
    super.key,
    required this.children,
    required this.onReorder,
    this.columnCount = 2,
    this.spacing = 12,
  });

  final List<Widget> children;
  final void Function(int oldIndex, int newIndex) onReorder;
  final int columnCount;
  final double spacing;

  @override
  State<AnimatedCardGrid> createState() => _AnimatedCardGridState();
}

class _AnimatedCardGridState extends State<AnimatedCardGrid>
    with TickerProviderStateMixin {
  final Map<Key, AnimationController> _controllers = {};
  final Map<Key, Animation<double>> _animations = {};

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  @override
  void didUpdateWidget(AnimatedCardGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children.length != widget.children.length) {
      _initializeAnimations();
    }
  }

  void _initializeAnimations() {
    final newKeys = <Key>{};
    for (final child in widget.children) {
      if (child.key != null) {
        newKeys.add(child.key!);
        if (!_controllers.containsKey(child.key)) {
          final controller = AnimationController(
            duration: const Duration(milliseconds: 300),
            vsync: this,
          );
          _controllers[child.key!] = controller;
          _animations[child.key!] = CurvedAnimation(
            parent: controller,
            curve: Curves.easeOutCubic,
          );
          controller.forward();
        }
      }
    }

    // 清理不再使用的动画控制器
    final keysToRemove = _controllers.keys.where((k) => !newKeys.contains(k));
    for (final key in keysToRemove.toList()) {
      _controllers[key]?.dispose();
      _controllers.remove(key);
      _animations.remove(key);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: widget.children
          .asMap()
          .entries
          .map((entry) => _buildAnimatedItem(entry.key, entry.value))
          .toList(),
    );
  }

  Widget _buildAnimatedItem(int index, Widget child) {
    final key = child.key;
    if (key == null) return child;

    final animation = _animations[key];
    if (animation == null) return child;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
