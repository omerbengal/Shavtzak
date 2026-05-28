import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/debug/debug_clipboard_share.dart';
import '../../core/debug/debug_logger.dart';
import '../../core/debug/logger.dart';
import '../../core/services/environment_service.dart';
import '../bloc/user_selection/user_selection_bloc.dart';
import '../bloc/user_selection/user_selection_state.dart';
import 'test_environment_indicator.dart';

/// PageView-based swipeable navigation wrapper
///
/// RTL-friendly: swipe left to advance, swipe right to go back
/// Order: Home → Team → Events → Assignments → Checklist
class SwipeablePageView extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const SwipeablePageView({
    super.key,
    required this.navigationShell,
  });

  @override
  State<SwipeablePageView> createState() => _SwipeablePageViewState();
}

// Global callback to trigger team sync when team page becomes visible
void Function()? onTeamPageVisible;

class _SwipeablePageViewState extends State<SwipeablePageView> {
  int? _previousIndex;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.navigationShell.currentIndex;
  }

  /// Map page index to bottom nav index
  /// Page order: Home (0) → Team (1) → Events (2) → Assignments (3) → Checklist (4)
  /// Bottom nav order: Checklist (0) → Assignments (1) → Events (2) → Team (3)
  int _getBottomNavIndex() {
    switch (widget.navigationShell.currentIndex) {
      case 4: // Checklist page
        return 0;
      case 3: // Assignments page
        return 1;
      case 2: // Events page
        return 2;
      case 1: // Team page
        return 3;
      default: // Home page or unknown
        return -1; // No selection
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;

    // Check if we just navigated to the team page (index 1)
    if (_previousIndex != null &&
        _previousIndex != currentIndex &&
        currentIndex == 1) {
      // Just navigated to team page
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onTeamPageVisible?.call();
      });
    }

    _previousIndex = currentIndex;

    final bottomNavIndex = _getBottomNavIndex();
    final showBottomNav = bottomNavIndex != -1; // Hide on home page

    return Scaffold(
      // Display the current page from the navigation shell with test environment indicator
      body: TestEnvironmentIndicator(child: widget.navigationShell),
      bottomNavigationBar: showBottomNav
          ? BottomNavWithDebugTrigger(
              currentIndex: bottomNavIndex,
              onTap: _onBottomNavTapped,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.checklist),
                  label: 'צ\'קליסט',
                ),
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
              tabRoutes: const [
                '/admin/checklist',
                '/admin/assignments',
                '/admin/events',
                '/admin/team-members',
              ],
              userDisplay: _userDisplay(context),
              isAdmin: _isAdmin(context),
              env: EnvironmentService.instance.isTestMode ? 'test' : 'prod',
              miniFabHeroTag: 'debug-share-mini-fab-admin',
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Colors.grey,
            )
          : null, // Hide bottom nav on home page
    );
  }

  String? _userDisplay(BuildContext context) {
    final state = context.read<UserSelectionBloc>().state;
    return state is UserAuthenticated ? state.user.name : null;
  }

  bool _isAdmin(BuildContext context) {
    final state = context.read<UserSelectionBloc>().state;
    return state is UserAuthenticated && state.user.isAdmin;
  }

  /// Handle bottom navigation bar taps
  /// Maps bottom nav index to page index: 0=Checklist(4), 1=Assignments(3), 2=Events(2), 3=Team(1)
  void _onBottomNavTapped(int index) {
    const routeNames = [
      '/admin/checklist',
      '/admin/assignments',
      '/admin/events',
      '/admin/team-members',
    ];
    DebugLogger.instance.reset(newRoute: routeNames[index]);
    final pageIndices = [4, 3, 2, 1]; // Map bottom nav to page indices
    final pageIndex = pageIndices[index];
    widget.navigationShell.goBranch(pageIndex);
  }
}

/// Wraps a [BottomNavigationBar] with long-press detection that reveals
/// a mini-FAB above the long-pressed tab. The mini-FAB copies the
/// [DebugLogger] buffer to the clipboard via [copyDebugLogsToClipboard].
class BottomNavWithDebugTrigger extends StatefulWidget {
  const BottomNavWithDebugTrigger({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.tabRoutes,
    required this.userDisplay,
    required this.isAdmin,
    required this.env,
    required this.miniFabHeroTag,
    this.type,
    this.selectedItemColor,
    this.unselectedItemColor,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomNavigationBarItem> items;
  final List<String> tabRoutes;
  final String? userDisplay;
  final bool isAdmin;
  final String env;
  final String miniFabHeroTag;
  final BottomNavigationBarType? type;
  final Color? selectedItemColor;
  final Color? unselectedItemColor;

  @override
  State<BottomNavWithDebugTrigger> createState() =>
      _BottomNavWithDebugTriggerState();
}

class _BottomNavWithDebugTriggerState extends State<BottomNavWithDebugTrigger> {
  static const Duration _autoDismissAfter = Duration(seconds: 4);
  static const double _miniFabRadius = 20.0;

  OverlayEntry? _miniFabEntry;
  int? _shownTabIndex;
  Timer? _autoDismiss;

  int get _tabCount => widget.items.length;

  void _handleLongPressStart(LongPressStartDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final tabWidth = screenWidth / _tabCount;
    final tabIndex = (details.localPosition.dx / tabWidth)
        .floor()
        .clamp(0, _tabCount - 1);

    // Only the currently-active tab triggers the menu.
    if (tabIndex != widget.currentIndex) {
      return;
    }

    if (_shownTabIndex == tabIndex) {
      _hideMiniFab();
    } else {
      _showMiniFab(tabIndex);
    }
  }

  void _showMiniFab(int tabIndex) {
    _hideMiniFab();
    final screenWidth = MediaQuery.of(context).size.width;
    final tabWidth = screenWidth / _tabCount;
    final tabCenterX = tabWidth * (tabIndex + 0.5);
    final viewPaddingBottom = MediaQuery.of(context).viewPadding.bottom;
    _miniFabEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: tabCenterX - _miniFabRadius,
        bottom: kBottomNavigationBarHeight + viewPaddingBottom + 8,
        child: FloatingActionButton.small(
          heroTag: widget.miniFabHeroTag,
          tooltip: 'העתק לוג תקלה',
          onPressed: _copyAndDismiss,
          child: const Icon(Icons.bug_report),
        ),
      ),
    );
    Overlay.of(context).insert(_miniFabEntry!);
    setState(() => _shownTabIndex = tabIndex);
    Logger.action('debugShareMenuOpen');
    _autoDismiss?.cancel();
    _autoDismiss = Timer(_autoDismissAfter, () {
      if (mounted) _hideMiniFab();
    });
  }

  void _hideMiniFab() {
    _miniFabEntry?.remove();
    _miniFabEntry = null;
    if (mounted) setState(() => _shownTabIndex = null);
    _autoDismiss?.cancel();
    _autoDismiss = null;
  }

  Future<void> _copyAndDismiss() async {
    // Snapshot the route at trigger time — widget.currentIndex may change
    // during the async clipboard call if the user navigates mid-share.
    final routeAtTrigger = widget.tabRoutes[widget.currentIndex];
    await copyDebugLogsToClipboard(
      context,
      currentRouteForShare: routeAtTrigger,
      userDisplay: widget.userDisplay,
      isAdmin: widget.isAdmin,
      env: widget.env,
    );
    if (mounted) _hideMiniFab();
  }

  @override
  void dispose() {
    // Skip setState — calling setState in dispose() throws even when mounted.
    // Only clean up the overlay entry and timer directly.
    _miniFabEntry?.remove();
    _miniFabEntry = null;
    _autoDismiss?.cancel();
    _autoDismiss = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _handleLongPressStart,
      child: BottomNavigationBar(
        currentIndex: widget.currentIndex,
        onTap: widget.onTap,
        items: widget.items,
        type: widget.type,
        selectedItemColor: widget.selectedItemColor,
        unselectedItemColor: widget.unselectedItemColor,
      ),
    );
  }
}
