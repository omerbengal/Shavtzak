import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/home/home_screen.dart';
import '../screens/team/team_list_screen.dart';
import '../screens/event/event_list_screen.dart';
import '../screens/assignment/assignment_list_screen.dart';

/// PageView-based swipeable navigation wrapper
///
/// RTL-friendly: swipe left to advance, swipe right to go back
/// Order: Home → Team → Events → Assignments
class SwipeablePageView extends StatefulWidget {
  const SwipeablePageView({super.key});

  @override
  State<SwipeablePageView> createState() => _SwipeablePageViewState();
}

class _SwipeablePageViewState extends State<SwipeablePageView> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isUpdatingFromSwipe = false;

  // Route to index mapping
  static const Map<String, int> _routeToIndex = {
    '/': 0,
    '/team-members': 1,
    '/events': 2,
    '/assignments': 3,
  };

  // Index to route mapping
  static const List<String> _indexToRoute = [
    '/',
    '/team-members',
    '/events',
    '/assignments',
  ];

  @override
  void initState() {
    super.initState();
    // Initialize PageController with current route's index
    final router = GoRouter.of(context);
    final currentPath = router.routerDelegate.currentConfiguration.uri.path;
    _currentIndex = _routeToIndex[currentPath] ?? 0;
    _pageController = PageController(initialPage: _currentIndex);

    // Listen to route changes
    router.routerDelegate.addListener(_onRouteChanged);
  }

  @override
  void dispose() {
    final router = GoRouter.of(context);
    router.routerDelegate.removeListener(_onRouteChanged);
    _pageController.dispose();
    super.dispose();
  }

  /// Handle route changes from external navigation (menu, URL, etc.)
  void _onRouteChanged() {
    if (_isUpdatingFromSwipe) return;

    final router = GoRouter.of(context);
    final currentPath = router.routerDelegate.currentConfiguration.uri.path;
    final newIndex = _routeToIndex[currentPath] ?? 0;

    if (newIndex != _currentIndex) {
      setState(() {
        _currentIndex = newIndex;
      });

      // Animate PageView to new index
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          newIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  /// Handle page changes from swipe gestures
  void _onPageChanged(int index) {
    if (index == _currentIndex) return;

    setState(() {
      _currentIndex = index;
      _isUpdatingFromSwipe = true;
    });

    // Update URL
    context.go(_indexToRoute[index]);

    // Reset flag after a delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _isUpdatingFromSwipe = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pageController,
      onPageChanged: _onPageChanged,
      // Reverse for RTL: swipe left = next page
      reverse: true,
      children: const [
        HomeScreen(),
        TeamListScreen(),
        EventListScreen(),
        AssignmentListScreen(),
      ],
    );
  }
}
