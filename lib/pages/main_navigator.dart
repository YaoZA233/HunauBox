import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_page.dart';
import 'function_page.dart';
import 'notice_page.dart';
import 'homework_page.dart';
import '../providers/homework_provider.dart';
import '../providers/notice_provider.dart';
import '../services/auth_guard.dart';
import '../services/navigation_settings_store.dart';

class MainNavigator extends ConsumerStatefulWidget {
  const MainNavigator({super.key});
  @override
  ConsumerState<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends ConsumerState<MainNavigator> {
  int _index = 0;
  final _navStore = NavigationSettingsStore.instance;

  static const _destinations = [
    (Icons.home_outlined, Icons.home, '主页'),
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
              : NavigationBar(
                  height: 60,
                  selectedIndex: _index,
                  onDestinationSelected: _handleDestinationSelected,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: '主页',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.grid_view_outlined),
                      selectedIcon: Icon(Icons.grid_view),
                      label: '功能',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.notifications_outlined),
                      selectedIcon: Icon(Icons.notifications),
                      label: '通知',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.assignment_outlined),
                      selectedIcon: Icon(Icons.assignment),
                      label: '作业',
                    ),
                  ],
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / 4;
        return Stack(
          children: [
            // Animated sliding indicator
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
              left: selectedIndex * itemWidth + 8,
              top: 8,
              width: itemWidth - 16,
              bottom: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            // Navigation items
            Row(
              children: List.generate(4, (i) {
                final isSelected = selectedIndex == i;
                return Expanded(
                  child: InkWell(
                    onTap: () => onChanged(i),
                    borderRadius: BorderRadius.circular(20),
                    splashColor: primaryColor.withValues(alpha: 0.08),
                    highlightColor: primaryColor.withValues(alpha: 0.04),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isSelected
                              ? _MainNavigatorState._destinations[i].$2
                              : _MainNavigatorState._destinations[i].$1,
                          size: 24,
                          color: isSelected ? primaryColor : onSurfaceVariant,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _MainNavigatorState._destinations[i].$3,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isSelected ? primaryColor : onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      },
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
