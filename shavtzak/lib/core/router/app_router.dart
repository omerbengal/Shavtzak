import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/widgets/swipeable_page_view.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/team/team_list_screen.dart';
import '../../presentation/screens/event/event_list_screen.dart';
import '../../presentation/screens/assignment/assignment_list_screen.dart';

/// Application router configuration using go_router with swipeable PageView
class AppRouter {
  /// The main router instance
  static final GoRouter router = GoRouter(
    debugLogDiagnostics: false, // Disable to prevent hot restart error messages

    // Redirect handler to validate routes and prevent hot restart errors
    redirect: (context, state) {
      // Allow all defined routes
      final validRoutes = ['/', '/team-members', '/events', '/assignments'];
      final currentPath = state.uri.path;

      // If route is valid, allow navigation
      if (validRoutes.contains(currentPath)) {
        return null; // null means no redirect, proceed with navigation
      }

      // If route is invalid, redirect to home
      return '/';
    },

    routes: [
      // Shell route with swipeable PageView
      ShellRoute(
        builder: (context, state, child) => const SwipeablePageView(),
        routes: [
          // Home route
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HomeScreen(), // Actual page (though rendered by PageView)
            ),
          ),

          // Team members route
          GoRoute(
            path: '/team-members',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TeamListScreen(), // Actual page (though rendered by PageView)
            ),
          ),

          // Events route
          GoRoute(
            path: '/events',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: EventListScreen(), // Actual page (though rendered by PageView)
            ),
          ),

          // Assignments route
          GoRoute(
            path: '/assignments',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AssignmentListScreen(), // Actual page (though rendered by PageView)
            ),
          ),
        ],
      ),
    ],

    // Error handling - redirect to home on 404
    errorBuilder: (context, state) => const HomeScreen(),
  );
}
