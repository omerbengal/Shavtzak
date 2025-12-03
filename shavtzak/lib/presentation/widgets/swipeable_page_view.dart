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
  bool _hasInitializedRouter = false;

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
    // Initialize PageController with default index (will be updated in didChangeDependencies)
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Initialize router only once after widget is fully mounted
    if (!_hasInitializedRouter) {
      _hasInitializedRouter = true;

      final router = GoRouter.of(context);
      final currentPath = router.routerDelegate.currentConfiguration.uri.path;
      final initialIndex = _routeToIndex[currentPath] ?? 0;

      if (initialIndex != _currentIndex) {
        _currentIndex = initialIndex;
        // Update PageController without animation since we're initializing
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients && mounted) {
            _pageController.jumpToPage(_currentIndex);
          }
        });
      }

      // Listen to route changes
      router.routerDelegate.addListener(_onRouteChanged);
    }
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

  /// Map bottom nav index to page index
  /// Bottom nav order: Assignments (0) → Events (1) → Team (2)
  /// Page order: Home (0) → Team (1) → Events (2) → Assignments (3)
  int _getBottomNavIndex() {
    switch (_currentIndex) {
      case 3: // Assignments page
        return 0;
      case 2: // Events page
        return 1;
      case 1: // Team page
        return 2;
      default: // Home page or unknown
        return -1; // No selection
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomNavIndex = _getBottomNavIndex();
    final showBottomNav = bottomNavIndex != -1; // Hide on home page

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        // Disable swipe gestures to avoid conflict with Dismissible
        physics: const NeverScrollableScrollPhysics(),
        reverse: true,
        children: const [
          HomeScreen(),
          TeamListScreen(),
          EventListScreen(),
          AssignmentListScreen(),
        ],
      ),
      bottomNavigationBar: showBottomNav
          ? BottomNavigationBar(
              currentIndex: bottomNavIndex,
              onTap: _onBottomNavTapped,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Colors.grey,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.assignment),
                  label: 'שיבוצים',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.event),
                  label: 'אירועים',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.people),
                  label: 'צוות',
                ),
              ],
            )
          : null, // Hide bottom nav on home page
    );
  }

  /// Handle bottom navigation bar taps
  /// Maps bottom nav index to route: 0=Assignments, 1=Events, 2=Team
  void _onBottomNavTapped(int index) {
    final routes = ['/assignments', '/events', '/team-members'];
    context.go(routes[index]);
    // PageController will be updated via _onRouteChanged listener
  }
}
