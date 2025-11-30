import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/team/team_list_screen.dart';
import '../../presentation/screens/event/event_list_screen.dart';
import '../../presentation/screens/assignment/assignment_list_screen.dart';

/// Application router configuration using go_router
class AppRouter {
  /// The main router instance
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,

    routes: [
      // Home route - landing page with navigation cards
      GoRoute(
        path: '/',
        name: 'home',
        pageBuilder: (context, state) => _buildPageWithNoTransition(
          context: context,
          state: state,
          child: const HomeScreen(),
        ),
      ),

      // Team members route
      GoRoute(
        path: '/team-members',
        name: 'team-members',
        pageBuilder: (context, state) => _buildPageWithNoTransition(
          context: context,
          state: state,
          child: const TeamListScreen(),
        ),
      ),

      // Events route
      GoRoute(
        path: '/events',
        name: 'events',
        pageBuilder: (context, state) => _buildPageWithNoTransition(
          context: context,
          state: state,
          child: const EventListScreen(),
        ),
      ),

      // Assignments route
      GoRoute(
        path: '/assignments',
        name: 'assignments',
        pageBuilder: (context, state) => _buildPageWithNoTransition(
          context: context,
          state: state,
          child: const AssignmentListScreen(),
        ),
      ),
    ],

    // Error handling - redirect to home on 404
    errorBuilder: (context, state) => const HomeScreen(),
  );

  /// Builds a page with no transition animation (web standard)
  static Page<void> _buildPageWithNoTransition({
    required BuildContext context,
    required GoRouterState state,
    required Widget child,
  }) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          child, // No animation - instant navigation
    );
  }
}
