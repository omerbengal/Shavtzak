import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'test_environment_indicator.dart';

/// PageView-based swipeable navigation wrapper
///
/// RTL-friendly: swipe left to advance, swipe right to go back
/// Order: Home → Team → Events → Assignments
class SwipeablePageView extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const SwipeablePageView({
    super.key,
    required this.navigationShell,
  });

  @override
  State<SwipeablePageView> createState() => _SwipeablePageViewState();
}

class _SwipeablePageViewState extends State<SwipeablePageView> {

  /// Map page index to bottom nav index
  /// Page order: Home (0) → Team (1) → Events (2) → Assignments (3)
  /// Bottom nav order: Assignments (0) → Events (1) → Team (2)
  int _getBottomNavIndex() {
    switch (widget.navigationShell.currentIndex) {
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
      // Display the current page from the navigation shell with test environment indicator
      body: TestEnvironmentIndicator(child: widget.navigationShell),
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
  /// Maps bottom nav index to page index: 0=Assignments(3), 1=Events(2), 2=Team(1)
  void _onBottomNavTapped(int index) {
    final pageIndices = [3, 2, 1]; // Map bottom nav to page indices
    final pageIndex = pageIndices[index];
    widget.navigationShell.goBranch(pageIndex);
  }
}
