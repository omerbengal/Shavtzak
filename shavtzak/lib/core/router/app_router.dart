import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/widgets/swipeable_page_view.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/team/team_list_screen.dart';
import '../../presentation/screens/event/event_list_screen.dart';
import '../../presentation/screens/assignment/assignment_list_screen.dart';

/// Application router configuration using go_router with StatefulShellRoute
class AppRouter {
  /// The main router instance
  static final GoRouter router = GoRouter(
    initialLocation: '/',

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

    // Error handling - redirect to home on 404
    errorBuilder: (context, state) => const HomeScreen(),
  );
}
