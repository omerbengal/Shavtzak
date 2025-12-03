import 'package:go_router/go_router.dart';
import '../../presentation/widgets/swipeable_page_view.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/team/team_list_screen.dart';
import '../../presentation/screens/event/event_list_screen.dart';
import '../../presentation/screens/assignment/assignment_list_screen.dart';

/// Application router configuration using go_router with StatefulShellRoute
/// Hot reload test
class AppRouter {
  static GoRouter? _instance;

  /// Get the router singleton instance
  static GoRouter get router {
    _instance ??= _createRouter();
    return _instance!;
  }

  /// Create the router instance
  static GoRouter _createRouter() {
    return GoRouter(
      // NO initialLocation - let Flutter hot reload handle route restoration!

      // Add redirect to handle hot reload navigation issues
      redirect: (context, state) {
        // During hot reload, router might try to navigate to routes that don't exist
        // Ensure we always redirect to a valid route
        final validRoutes = ['/', '/team-members', '/events', '/assignments'];
        final currentRoute = state.uri.path;

        if (!validRoutes.contains(currentRoute)) {
          return '/'; // Redirect to home for invalid routes
        }
        return null; // No redirect needed for valid routes
      },

      routes: [
      // StatefulShellRoute maintains shell state across navigation
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          // Return the SwipeablePageView with the navigation shell
          return SwipeablePageView(navigationShell: navigationShell);
        },
        branches: [
          // Home branch
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: HomeScreen(),
                ),
              ),
            ],
          ),

          // Team members branch
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/team-members',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: TeamListScreen(),
                ),
              ),
            ],
          ),

          // Events branch
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/events',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: EventListScreen(),
                ),
              ),
            ],
          ),

          // Assignments branch
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/assignments',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: AssignmentListScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
    ],

    // Error handling - redirect to home on 404 or navigation errors
    errorBuilder: (context, state) => const HomeScreen(),
    );
  }
}
