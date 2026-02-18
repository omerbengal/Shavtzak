import 'dart:async';
import 'dart:developer' as developer;
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
import '../../presentation/screens/summary/summary_screen.dart';
import '../../presentation/screens/db/db_preview_screen.dart';
import '../../../data/repositories/user_selection_repository.dart';

/// Global navigator key for showing snackbars from outside widget tree
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Application router configuration using go_router with authentication
class AppRouter {
  static GoRouter? _instance;
  static UserSelectionBloc? _userSelectionBloc;
  static UserSelectionRepository? _userSelectionRepository;

  /// Capture the initial URL hash BEFORE any Flutter code runs
  /// This is set by main.dart at the very start
  static String? capturedInitialHash;

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

  static StreamSubscription? _blocSubscription;
  static String? _lastAuthSignature;

  /// Get the router singleton instance
  static GoRouter router(
      {UserSelectionBloc? userSelectionBloc,
      required UserSelectionRepository userSelectionRepository}) {
    developer.log(
        '[DB-DEBUG] router() called - capturedInitialHash: "$capturedInitialHash"',
        name: 'DB');

    _userSelectionBloc = userSelectionBloc;
    _userSelectionRepository = userSelectionRepository;
    _instance ??= _createRouter(userSelectionRepository);

    // If /db was captured in initial URL, navigate there after first frame
    if (capturedInitialHash != null && capturedInitialHash!.contains('/db')) {
      developer.log('[DB-DEBUG] /db found in hash, will navigate after frame',
          name: 'DB');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_instance != null) {
          final currentPath =
              _instance!.routeInformationProvider.value.uri.path;
          developer.log(
              '[DB-DEBUG] PostFrameCallback - currentPath: "$currentPath"',
              name: 'DB');
          if (currentPath != '/db' && currentPath != '/test/db') {
            final envPath =
                capturedInitialHash!.contains('/test/') ? '/test/db' : '/db';
            developer.log('[DB-DEBUG] Navigating to: "$envPath"', name: 'DB');

            // Update environment service BEFORE navigation
            EnvironmentService.instance.updateFromPath(envPath);
            developer.log(
                '[DB-DEBUG] EnvironmentService.isTestMode after update: ${EnvironmentService.instance.isTestMode}',
                name: 'DB');
            developer.log(
                '[DB-DEBUG] EnvironmentService.collectionPrefix: "${EnvironmentService.instance.collectionPrefix}"',
                name: 'DB');

            _instance!.go(envPath);
            capturedInitialHash = null; // Clear after use
          }
        }
      });
    }

    // Cancel previous subscription to prevent multiple listeners
    _blocSubscription?.cancel();

    // Listen to BLoC state changes and trigger navigation when authenticated or signed out
    _blocSubscription = _userSelectionBloc?.stream.listen((state) {
      if (_instance != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final currentRoute =
              _instance!.routeInformationProvider.value.uri.path;
          final strippedRoute = _stripTestPrefix(currentRoute);
          developer.log(
            'bloc stream state=${state.runtimeType} currentRoute="$currentRoute"',
            name: 'AppRouter',
          );

          // /db route is unauthenticated - never redirect away from it
          if (strippedRoute.startsWith('/db')) {
            return;
          }

          final envPrefix = _getEnvPrefix(currentRoute);

          String currentSignature;
          if (state is UserAuthenticated) {
            currentSignature =
                'auth:${state.user.id}:${state.isAdmin}:${state.user.canAccessSummaryScreen}:${state.user.canAccessShamapExport}';
          } else if (state is UserSignedOut) {
            currentSignature = 'signed_out';
          } else {
            currentSignature = state.runtimeType.toString();
          }

          final isNavRelevantRoute = strippedRoute.startsWith('/whoami') ||
              strippedRoute.isEmpty ||
              strippedRoute == '/';
          final shouldSkip = _lastAuthSignature == currentSignature &&
              !isNavRelevantRoute &&
              state is UserAuthenticated;
          if (shouldSkip) {
            developer.log(
              'skip stream handling for non-nav auth update signature="$currentSignature" route="$currentRoute"',
              name: 'AppRouter',
            );
            return;
          }
          _lastAuthSignature = currentSignature;

          // Update environment service based on current path
          EnvironmentService.instance.updateFromPath(currentRoute);

          if (state is UserAuthenticated) {
            // User became authenticated, navigate to appropriate home
            if (strippedRoute.startsWith('/whoami') ||
                strippedRoute.isEmpty ||
                strippedRoute == '/') {
              developer.log(
                'authenticated on whoami/root, redirecting to home',
                name: 'AppRouter',
              );
              if (state.isAdmin) {
                _instance?.go('$envPrefix/admin');
              } else if (state.user.canAccessSummaryScreen ||
                  state.user.canAccessShamapExport) {
                _instance?.go('$envPrefix/choice');
              } else {
                _instance?.go('$envPrefix/user/assignments');
              }
            }
          } else if (state is UserSignedOut) {
            // User signed out, go to whoami
            if (!strippedRoute.startsWith('/whoami')) {
              developer.log(
                'signed out, redirecting to whoami',
                name: 'AppRouter',
              );
              _instance?.go('$envPrefix/whoami');
            }
          }
        });
      }
    });

    return _instance!;
  }

  /// Create the router instance
  static GoRouter _createRouter(
      UserSelectionRepository userSelectionRepository) {
    // IMPORTANT: Always use '/' as initialLocation to avoid early navigation errors
    // We'll manually navigate to the correct route (like /db) after the router is built
    const String initialLocation = '/';

    return GoRouter(
      // Start at root to avoid "route not found" errors during initialization
      initialLocation: initialLocation,

      // Set the global navigator key
      navigatorKey: navigatorKey,

      // Redirect based on authentication state
      redirect: (context, state) {
        final currentRoute = state.uri.path;
        final strippedRoute = _stripTestPrefix(currentRoute);

        // /db route is unauthenticated - bypass ALL checks
        if (strippedRoute == '/db' || strippedRoute.startsWith('/db')) {
          return null;
        }

        // Update environment service based on current path
        EnvironmentService.instance.updateFromPath(currentRoute);
        final envPrefix = _getEnvPrefix(currentRoute);

        // Handle empty path (root URL)
        if (currentRoute.isEmpty || currentRoute == '/') {
          // Check if we should be in test environment based on captured initial hash
          final isTestFromHash = capturedInitialHash != null &&
              capturedInitialHash!.contains('/test/');
          final envPrefix = isTestFromHash ? '/test' : '';

          // Check for pre-authenticated user BEFORE deciding on whoami
          if (_userSelectionBloc != null) {
            final currentState = _userSelectionBloc!.state;
            if (currentState is UserAuthenticated) {
              if (currentState.isAdmin) {
                return '$envPrefix/admin';
              } else if (currentState.user.canAccessSummaryScreen ||
                  currentState.user.canAccessShamapExport) {
                return '$envPrefix/choice';
              } else {
                return '$envPrefix/user/assignments';
              }
            }
          }

          return '$envPrefix/whoami';
        }

        if (_userSelectionBloc == null || _userSelectionRepository == null) {
          return '$envPrefix/whoami';
        }

        final currentState = _userSelectionBloc!.state;

        if (currentRoute.startsWith('/user') ||
            currentRoute.startsWith('/test/user')) {
          developer.log(
            'redirect check route="$currentRoute" authState=${currentState.runtimeType}',
            name: 'AppRouter',
          );
        }

        // Handle authentication redirects
        if (currentState is UserSignedOut) {
          if (!strippedRoute.startsWith('/whoami')) {
            return '$envPrefix/whoami';
          }
        } else if (currentState is UserAuthenticated) {
          if (currentState.isAdmin) {
            if (strippedRoute.startsWith('/whoami')) {
              return '$envPrefix/admin';
            }
          } else {
            if (strippedRoute.startsWith('/whoami')) {
              if (currentState.user.canAccessSummaryScreen ||
                  currentState.user.canAccessShamapExport) {
                return '$envPrefix/choice';
              }
              return '$envPrefix/user/assignments';
            }
            if (strippedRoute.startsWith('/admin')) {
              return '$envPrefix/user/assignments';
            }
            if (strippedRoute.startsWith('/summary')) {
              if (!currentState.user.canAccessSummaryScreen) {
                return '$envPrefix/user/assignments';
              }
            }
            if (strippedRoute.startsWith('/choice')) {
              final canAccessChoice =
                  currentState.user.canAccessSummaryScreen ||
                      currentState.user.canAccessShamapExport;
              if (!canAccessChoice) {
                return '$envPrefix/user/assignments';
              }
            }
          }
        } else {
          if (!strippedRoute.startsWith('/whoami')) {
            developer.log(
              'unauthenticated, redirecting to whoami from "$currentRoute"',
              name: 'AppRouter',
            );
            return '$envPrefix/whoami';
          }
        }

        return null;
      },

      routes: [
        // Authentication route - whoami screen
        GoRoute(
          path: '/whoami',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: WhoamiScreen(key: ValueKey('whoami_prod')),
          ),
        ),

        // DB Preview route - hidden, unauthenticated diagnostic screen
        GoRoute(
          path: '/db',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DbPreviewScreen(key: ValueKey('db_prod')),
          ),
        ),

        // Summary screen - isolated admin screen
        GoRoute(
          path: '/summary',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SummaryScreen(key: ValueKey('summary_prod')),
          ),
        ),

        // Choice route for non-admin users with summary/export access
        GoRoute(
          path: '/choice',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AdminChoiceScreen(key: ValueKey('choice_prod')),
          ),
        ),

        // Admin routes shell - uses existing SwipeablePageView
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            final canAccessAdminShell =
                context.select<UserSelectionBloc, bool>((bloc) {
              final blocState = bloc.state;
              return blocState is UserAuthenticated && blocState.isAdmin;
            });
            if (!canAccessAdminShell) {
              return const Scaffold(
                body: Center(child: Text('גישה לא מורשית - דרוש הרשאות מנהל')),
              );
            }
            return SwipeablePageView(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/admin',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: AdminChoiceScreen(
                          key: ValueKey('admin_choice_prod'))))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/admin/team-members',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child:
                          TeamListScreen(key: ValueKey('team_members_prod'))))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/admin/events',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: EventListScreen(key: ValueKey('events_prod'))))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/admin/assignments',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: AssignmentListScreen(
                          key: ValueKey('assignments_prod'))))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/admin/checklist',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: AdminChecklistScreen(
                          key: ValueKey('admin_checklist_prod'))))
            ]),
          ],
        ),

        // User routes shell
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            final isAuthenticated = context.select<UserSelectionBloc, bool>(
                (bloc) => bloc.state is UserAuthenticated);
            if (!isAuthenticated) {
              developer.log(
                'user shell builder unauthenticated at route="${state.uri.path}"',
                name: 'AppRouter',
              );
              return const Scaffold(
                  body: Center(child: Text('גישה לא מורשית - דרוש אימות')));
            }
            return UserNavigationShell(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/user/assignments',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: UserAssignmentsScreen(
                          key: ValueKey('user_assignments_prod'))))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/user/constraints',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: ConstraintsScreen(
                          key: ValueKey('user_constraints_prod'))))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/user/checklist',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: UserChecklistScreen(
                          key: ValueKey('user_checklist_prod'))))
            ]),
          ],
        ),

        // ========== TEST ENVIRONMENT ROUTES ==========

        GoRoute(
            path: '/test/whoami',
            pageBuilder: (context, state) => const NoTransitionPage(
                child: WhoamiScreen(key: ValueKey('whoami_test')))),
        GoRoute(
            path: '/test/db',
            pageBuilder: (context, state) => const NoTransitionPage(
                child: DbPreviewScreen(key: ValueKey('db_test')))),
        GoRoute(
            path: '/test/summary',
            pageBuilder: (context, state) => const NoTransitionPage(
                child: SummaryScreen(key: ValueKey('summary_test')))),
        GoRoute(
            path: '/test/choice',
            pageBuilder: (context, state) => const NoTransitionPage(
                child: AdminChoiceScreen(key: ValueKey('choice_test')))),

        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            final canAccessAdminShell =
                context.select<UserSelectionBloc, bool>((bloc) {
              final blocState = bloc.state;
              return blocState is UserAuthenticated && blocState.isAdmin;
            });
            if (!canAccessAdminShell) {
              return const Scaffold(
                  body:
                      Center(child: Text('גישה לא מורשית - דרוש הרשאות מנהל')));
            }
            return SwipeablePageView(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/test/admin',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: AdminChoiceScreen(
                          key: ValueKey('admin_choice_test'))))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/test/admin/team-members',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child:
                          TeamListScreen(key: ValueKey('team_members_test'))))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/test/admin/events',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: EventListScreen(key: ValueKey('events_test'))))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/test/admin/assignments',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: AssignmentListScreen(
                          key: ValueKey('assignments_test'))))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/test/admin/checklist',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: AdminChecklistScreen(
                          key: ValueKey('admin_checklist_test'))))
            ]),
          ],
        ),

        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            final isAuthenticated = context.select<UserSelectionBloc, bool>(
                (bloc) => bloc.state is UserAuthenticated);
            if (!isAuthenticated) {
              developer.log(
                'test user shell builder unauthenticated at route="${state.uri.path}"',
                name: 'AppRouter',
              );
              return const Scaffold(
                  body: Center(child: Text('גישה לא מורשית - דרוש אימות')));
            }
            return UserNavigationShell(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/test/user/assignments',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: UserAssignmentsScreen(
                          key: ValueKey('user_assignments_test'))))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/test/user/constraints',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: ConstraintsScreen(
                          key: ValueKey('user_constraints_test'))))
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/test/user/checklist',
                  pageBuilder: (context, state) => const NoTransitionPage(
                      child: UserChecklistScreen(
                          key: ValueKey('user_checklist_test'))))
            ]),
          ],
        ),
      ],

      errorBuilder: (context, state) => const WhoamiScreen(),
    );
  }

  /// Reset router singleton
  static void reset() {
    _instance = null;
    _userSelectionBloc = null;
    _lastAuthSignature = null;
  }
}
