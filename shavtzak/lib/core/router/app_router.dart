import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/environment_service.dart';
import '../../presentation/bloc/user_selection/user_selection_bloc.dart';
import '../../presentation/bloc/user_selection/user_selection_state.dart';
import '../../presentation/widgets/swipeable_page_view.dart';
import '../../presentation/screens/whoami/whoami_screen.dart';
import '../../presentation/screens/user/user_navigation_shell.dart';
import '../../presentation/screens/user/constraints_screen.dart';
import '../../presentation/screens/user/user_assignments_screen.dart';
import '../../presentation/screens/user/user_checklist_screen.dart';
import '../../presentation/screens/admin/admin_choice_screen.dart';
import '../../presentation/screens/admin/checklist_screen.dart';
import '../../presentation/screens/team/team_list_screen.dart';
import '../../presentation/screens/event/event_list_screen.dart';
import '../../presentation/screens/assignment/assignment_list_screen.dart';
import '../../../data/repositories/user_selection_repository.dart';

/// Global navigator key for showing snackbars from outside widget tree
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Application router configuration using go_router with authentication
class AppRouter {
  static GoRouter? _instance;
  static UserSelectionBloc? _userSelectionBloc;
  static UserSelectionRepository? _userSelectionRepository;

  /// Helper function to check if a path is in test environment
  static bool _isTestPath(String path) {
    return path.startsWith('/test/') || path == '/test';
  }

  /// Helper function to strip test prefix from path
  static String _stripTestPrefix(String path) {
    if (path.startsWith('/test')) {
      return path.substring(5); // Remove '/test' prefix
    }
    return path;
  }

  /// Helper function to get environment prefix based on path
  static String _getEnvPrefix(String path) {
    return _isTestPath(path) ? '/test' : '';
  }

  /// Get the router singleton instance
  static GoRouter router({UserSelectionBloc? userSelectionBloc, required UserSelectionRepository userSelectionRepository}) {
    _userSelectionBloc = userSelectionBloc;
    _userSelectionRepository = userSelectionRepository;
    _instance ??= _createRouter(userSelectionRepository);

    // Listen to BLoC state changes and trigger navigation when authenticated or signed out
    _userSelectionBloc?.stream.listen((state) {
      if (_instance != null) {
        // Trigger a navigation check after state changes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final currentRoute = _instance!.routeInformationProvider.value.uri.path;
          final envPrefix = _getEnvPrefix(currentRoute);

          // Update environment service based on current path
          EnvironmentService.instance.updateFromPath(currentRoute);

          if (state is UserAuthenticated) {
            // User became authenticated, navigate to appropriate home
            final strippedRoute = _stripTestPrefix(currentRoute);
            if (strippedRoute.startsWith('/whoami') || strippedRoute.isEmpty || strippedRoute == '/') {
              if (state.isAdmin) {
                _instance?.go('$envPrefix/admin');
              } else {
                _instance?.go('$envPrefix/user/assignments');
              }
            }
          } else if (state is UserSignedOut) {
            // User signed out, always go to whoami (with environment prefix)
            final strippedRoute = _stripTestPrefix(currentRoute);
            if (!strippedRoute.startsWith('/whoami')) {
              _instance?.go('$envPrefix/whoami');
            }
          }
        });
      }
    });

    return _instance!;
  }

  /// Create the router instance
  static GoRouter _createRouter(UserSelectionRepository userSelectionRepository) {
    return GoRouter(
      // Initial location determined by cached user check
      initialLocation: '/whoami', // Fallback, will be updated by redirect logic

      // Set the global navigator key
      navigatorKey: navigatorKey,

      // Redirect based on authentication state
      redirect: (context, state) {
        final currentRoute = state.uri.path;

        // Update environment service based on current path
        EnvironmentService.instance.updateFromPath(currentRoute);
        final envPrefix = _getEnvPrefix(currentRoute);
        final strippedRoute = _stripTestPrefix(currentRoute);

        // Handle empty path (root URL without hash)
        if (currentRoute.isEmpty || currentRoute == '/') {
          return '$envPrefix/whoami';
        }

        if (_userSelectionBloc == null || _userSelectionRepository == null) {
          return '$envPrefix/whoami'; // Default to whoami if no BLoC provided
        }

        final currentState = _userSelectionBloc!.state;

        // If user is not authenticated yet, check cache first before showing whoami
        if (currentState is! UserAuthenticated) {
          // Check cache asynchronously, but for now allow whoami to load
          // The BLoC will handle cache check and navigation
        }

        // Handle authentication redirects
        if (currentState is UserSignedOut) {
          // User signed out, always redirect to whoami
          if (!strippedRoute.startsWith('/whoami')) {
            return '$envPrefix/whoami';
          }
        } else if (currentState is UserAuthenticated) {
          // User is authenticated, redirect based on admin status
          if (currentState.isAdmin) {
            // Admin user - only redirect from whoami to admin choice
            if (strippedRoute.startsWith('/whoami')) {
              return '$envPrefix/admin'; // Redirect to admin choice screen
            }
            // Admins can access both user and admin routes, no restriction
          } else {
            // Non-admin user - only redirect from whoami to user routes
            if (strippedRoute.startsWith('/whoami')) {
              return '$envPrefix/user/assignments'; // Redirect to user assignments
            }
            // If non-admin tries to access admin routes, redirect to user
            if (strippedRoute.startsWith('/admin/')) {
              return '$envPrefix/user/assignments'; // Redirect to user assignments
            }
          }
        } else {
          // User not authenticated, redirect to whoami unless already there
          if (!strippedRoute.startsWith('/whoami')) {
            return '$envPrefix/whoami';
          }
        }

        return null; // No redirect needed
      },

      routes: [
        // Authentication route - whoami screen
        GoRoute(
          path: '/whoami',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: WhoamiScreen(key: ValueKey('whoami_prod')),
          ),
        ),

        // Admin routes shell - uses existing SwipeablePageView
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            // Only allow admin users to access this shell
            final userSelectionState = context.watch<UserSelectionBloc>().state;
            if (userSelectionState is! UserAuthenticated || !userSelectionState.isAdmin) {
              return const Scaffold(
                body: Center(
                  child: Text('גישה לא מורשית - דרוש הרשאות מנהל'),
                ),
              );
            }

            return SwipeablePageView(navigationShell: navigationShell);
          },
          branches: [
            // Admin choice branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/admin',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: AdminChoiceScreen(key: ValueKey('admin_choice_prod')),
                  ),
                ),
              ],
            ),

            // Admin team members branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/admin/team-members',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: TeamListScreen(key: ValueKey('team_members_prod')),
                  ),
                ),
              ],
            ),

            // Admin events branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/admin/events',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: EventListScreen(key: ValueKey('events_prod')),
                  ),
                ),
              ],
            ),

            // Admin assignments branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/admin/assignments',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: AssignmentListScreen(key: ValueKey('assignments_prod')),
                  ),
                ),
              ],
            ),

            // Admin checklist branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/admin/checklist',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: AdminChecklistScreen(key: ValueKey('admin_checklist_prod')),
                  ),
                ),
              ],
            ),
          ],
        ),

        // User routes shell - uses UserNavigationShell
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            // Allow both regular users and admins to access this shell
            final userSelectionState = context.watch<UserSelectionBloc>().state;
            if (userSelectionState is! UserAuthenticated) {
              return const Scaffold(
                body: Center(
                  child: Text('גישה לא מורשית - דרוש אימות'),
                ),
              );
            }

            return UserNavigationShell(navigationShell: navigationShell);
          },
          branches: [
            // User assignments branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/user/assignments',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: UserAssignmentsScreen(key: ValueKey('user_assignments_prod')),
                  ),
                ),
              ],
            ),

            // User constraints branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/user/constraints',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: ConstraintsScreen(key: ValueKey('user_constraints_prod')),
                  ),
                ),
              ],
            ),

            // User checklist branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/user/checklist',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: UserChecklistScreen(key: ValueKey('user_checklist_prod')),
                  ),
                ),
              ],
            ),
          ],
        ),

        // ========== TEST ENVIRONMENT ROUTES ==========
        // These mirror the production routes but with /test prefix

        // Test authentication route
        GoRoute(
          path: '/test/whoami',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: WhoamiScreen(key: ValueKey('whoami_test')),
          ),
        ),

        // Test admin routes shell
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            // Only allow admin users to access this shell
            final userSelectionState = context.watch<UserSelectionBloc>().state;
            if (userSelectionState is! UserAuthenticated || !userSelectionState.isAdmin) {
              return const Scaffold(
                body: Center(
                  child: Text('גישה לא מורשית - דרוש הרשאות מנהל'),
                ),
              );
            }

            return SwipeablePageView(navigationShell: navigationShell);
          },
          branches: [
            // Test admin choice branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/test/admin',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: AdminChoiceScreen(key: ValueKey('admin_choice_test')),
                  ),
                ),
              ],
            ),

            // Test admin team members branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/test/admin/team-members',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: TeamListScreen(key: ValueKey('team_members_test')),
                  ),
                ),
              ],
            ),

            // Test admin events branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/test/admin/events',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: EventListScreen(key: ValueKey('events_test')),
                  ),
                ),
              ],
            ),

            // Test admin assignments branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/test/admin/assignments',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: AssignmentListScreen(key: ValueKey('assignments_test')),
                  ),
                ),
              ],
            ),

            // Test admin checklist branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/test/admin/checklist',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: AdminChecklistScreen(key: ValueKey('admin_checklist_test')),
                  ),
                ),
              ],
            ),
          ],
        ),

        // Test user routes shell
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            // Allow both regular users and admins to access this shell
            final userSelectionState = context.watch<UserSelectionBloc>().state;
            if (userSelectionState is! UserAuthenticated) {
              return const Scaffold(
                body: Center(
                  child: Text('גישה לא מורשית - דרוש אימות'),
                ),
              );
            }

            return UserNavigationShell(navigationShell: navigationShell);
          },
          branches: [
            // Test user assignments branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/test/user/assignments',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: UserAssignmentsScreen(key: ValueKey('user_assignments_test')),
                  ),
                ),
              ],
            ),

            // Test user constraints branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/test/user/constraints',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: ConstraintsScreen(key: ValueKey('user_constraints_test')),
                  ),
                ),
              ],
            ),

            // Test user checklist branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/test/user/checklist',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: UserChecklistScreen(key: ValueKey('user_checklist_test')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],

      // Error handling - redirect to whoami for navigation errors
      errorBuilder: (context, state) => const WhoamiScreen(),
    );
  }

  /// Reset router singleton (useful for testing or hot reload issues)
  static void reset() {
    _instance = null;
    _userSelectionBloc = null;
  }
}
