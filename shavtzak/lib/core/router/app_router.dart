import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/widgets/swipeable_page_view.dart';
import '../../presentation/screens/home/home_screen.dart';

/// Application router configuration using go_router with swipeable PageView
class AppRouter {
  /// The main router instance
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,

    routes: [
      // Shell route with swipeable PageView
      ShellRoute(
        builder: (context, state, child) => const SwipeablePageView(),
        routes: [
          // Home route
          GoRoute(
            path: '/',
            name: 'home',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SizedBox.shrink(), // Placeholder - rendered by PageView
            ),
          ),

          // Team members route
          GoRoute(
            path: '/team-members',
            name: 'team-members',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SizedBox.shrink(), // Placeholder - rendered by PageView
            ),
          ),

          // Events route
          GoRoute(
            path: '/events',
            name: 'events',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SizedBox.shrink(), // Placeholder - rendered by PageView
            ),
          ),

          // Assignments route
          GoRoute(
            path: '/assignments',
            name: 'assignments',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SizedBox.shrink(), // Placeholder - rendered by PageView
            ),
          ),
        ],
      ),
    ],

    // Error handling - redirect to home on 404
    errorBuilder: (context, state) => const HomeScreen(),
  );
}
