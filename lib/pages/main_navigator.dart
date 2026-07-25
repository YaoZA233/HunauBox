import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/homework_provider.dart';
import '../providers/notice_provider.dart';
import '../services/auth_guard.dart';
import '../services/navigation_settings_store.dart';
import 'function_page.dart';
import 'home_page.dart';
import 'homework_page.dart';
import 'notice_page.dart';

class MainNavigator extends ConsumerStatefulWidget {
  const MainNavigator({super.key});

  @override
  ConsumerState<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends ConsumerState<MainNavigator> {
  int _index = 0;
  final _navStore = NavigationSettingsStore.instance;

  static const _destinations = [
    (Icons.home_outlined, Icons.home, '首页'),
    (Icons.grid_view_outlined, Icons.grid_view, '功能'),
    (Icons.notifications_outlined, Icons.notifications, '通知'),
    (Icons.assignment_outlined, Icons.assignment, '作业'),
  ];

  @override
  void initState() {
    super.initState();
    _navStore.load();
  }

  Future<void> _handleDestinationSelected(int value) async {
    if (value == _index) return;

    if (value != 0) {
      final result = await AuthGuard.ensureLoggedIn(context);
      if (!result.allowed || !mounted) return;

      if (value == 2) {
        ref.read(noticeProvider.notifier).refresh();
      } else if (value == 3) {
        ref.read(homeworkProvider.notifier).refresh();
      }
    }

    if (!mounted) return;
    setState(() => _index = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<bool>(
      valueListenable: _navStore.useFloatingNav,
      builder: (context, useFloatingNav, _) {
        return Scaffold(
          body: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  bottom: useFloatingNav
                      ? 80 + MediaQuery.paddingOf(context).bottom
                      : 0,
                ),
                child: AnimatedIndexedStack(
                  index: _index,
                  children: [
                    HomePage(isActive: _index == 0),
                    FunctionPage(),
                    NoticePage(),
                    HomeworkPage(),
                  ],
                ),
              ),
              if (useFloatingNav)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 12 + MediaQuery.paddingOf(context).bottom,
                  child: _FloatingNavBar(
                    selectedIndex: _index,
                    onChanged: _handleDestinationSelected,
                    surfaceColor: theme.colorScheme.surface,
                    primaryColor: theme.colorScheme.primary,
                    onSurfaceVariant: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          bottomNavigationBar: useFloatingNav
              ? null
              : _BottomNavBar(
                  selectedIndex: _index,
                  onChanged: _handleDestinationSelected,
                  surfaceColor: theme.colorScheme.surface,
                  primaryColor: theme.colorScheme.primary,
                  onSurfaceVariant: theme.colorScheme.onSurfaceVariant,
                ),
        );
      },
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Color surfaceColor;
  final Color primaryColor;
  final Color onSurfaceVariant;

  const _FloatingNavBar({
    required this.selectedIndex,
    required this.onChanged,
    required this.surfaceColor,
    required this.primaryColor,
    required this.onSurfaceVariant,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: _NavBarContent(
          selectedIndex: selectedIndex,
          onChanged: onChanged,
          primaryColor: primaryColor,
          onSurfaceVariant: onSurfaceVariant,
        ),
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Color surfaceColor;
  final Color primaryColor;
  final Color onSurfaceVariant;

  const _BottomNavBar({
    required this.selectedIndex,
    required this.onChanged,
    required this.surfaceColor,
    required this.primaryColor,
    required this.onSurfaceVariant,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: _NavBarContent(
            selectedIndex: selectedIndex,
            onChanged: onChanged,
            primaryColor: primaryColor,
            onSurfaceVariant: onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _NavBarContent extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Color primaryColor;
  final Color onSurfaceVariant;

  const _NavBarContent({
    required this.selectedIndex,
    required this.onChanged,
    required this.primaryColor,
    required this.onSurfaceVariant,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (index) {
        final isSelected = selectedIndex == index;
        final destination = _MainNavigatorState._destinations[index];

        return Expanded(
          child: Semantics(
            button: true,
            selected: isSelected,
            label: destination.$3,
            child: InkWell(
              onTap: () => onChanged(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isSelected ? destination.$2 : destination.$1,
                        size: 22,
                        color: isSelected ? primaryColor : onSurfaceVariant,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        destination.$3,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.1,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isSelected ? primaryColor : onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class AnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const AnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  @override
  State<AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class _AnimatedIndexedStackState extends State<AnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late int _previousIndex;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _controller.forward();
    _previousIndex = widget.index;
  }

  @override
  void didUpdateWidget(covariant AnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != _previousIndex) {
      _previousIndex = widget.index;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeIn),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
            ),
        child: IndexedStack(index: widget.index, children: widget.children),
      ),
    );
  }
}
