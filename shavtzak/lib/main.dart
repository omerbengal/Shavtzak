import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'firebase_options.dart';
import 'dart:developer' as developer;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;

// Conditional imports for web-specific functionality
import 'core/web/web_stub.dart' if (dart.library.js) 'core/web/web_helper.dart';

// Data layer
import 'data/data_sources/firestore_database.dart';
import 'data/repositories/team_repository.dart';
import 'data/repositories/event_repository.dart';
import 'data/repositories/assignment_repository.dart';
import 'data/repositories/user_selection_repository.dart';
import 'data/repositories/checklist_repository.dart';
import 'data/repositories/preset_repository.dart';
import 'data/repositories/role_repository.dart';
import 'data/repositories/category_repository.dart';
import 'domain/entities/team_member.dart';
import 'core/services/user_cache_service.dart';
import 'core/services/environment_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/service_locator.dart';
import 'core/services/drive_service.dart';
import 'core/services/config_cache_service.dart';
import 'core/services/audit_context_service.dart';
import 'presentation/widgets/offline_blocking_overlay.dart';

// Presentation layer
import 'presentation/bloc/team/team_bloc.dart';
import 'presentation/bloc/team/team_event.dart';
import 'presentation/bloc/event/event_bloc.dart';
import 'presentation/bloc/assignment/assignment_bloc.dart';
import 'presentation/bloc/user_selection/user_selection_bloc.dart';
import 'presentation/bloc/user_selection/user_selection_state.dart';
import 'presentation/bloc/calendar_sync/calendar_sync_bloc.dart';
import 'presentation/bloc/calendar_sync/calendar_sync_event.dart';
import 'presentation/bloc/checklist/checklist_bloc.dart';
import 'presentation/bloc/preset/preset_bloc.dart';
import 'presentation/bloc/role/role_bloc.dart';
import 'presentation/bloc/role/role_event.dart';
import 'presentation/bloc/category/category_bloc.dart';
import 'presentation/bloc/category/category_event.dart';

// Router
import 'core/router/app_router.dart';

// Theme
import 'core/theme/app_theme.dart';

void main() {
  // CRITICAL: Capture the initial URL hash BEFORE any Flutter code runs (web only)
  // This is needed for the /db route to work correctly
  if (kIsWeb) {
    AppRouter.capturedInitialHash = WebHelper.getWindowLocationHash();
  }

  WidgetsFlutterBinding.ensureInitialized();

  // Show loading screen immediately
  runApp(const LoadingApp());

  // Initialize in background
  _initialize();
}

/// Helper to time operations
T _timed<T>(String name, T Function() fn) {
  final sw = Stopwatch()..start();
  try {
    final result = fn();
    sw.stop();
    return result;
  } catch (e) {
    sw.stop();
    rethrow;
  }
}

/// Helper to time async operations
Future<T> _timedAsync<T>(String name, Future<T> Function() fn) async {
  final sw = Stopwatch()..start();
  try {
    final result = await fn();
    sw.stop();
    return result;
  } catch (e) {
    sw.stop();
    rethrow;
  }
}

Future<void> _initialize() async {
  final totalSw = Stopwatch()..start();

  try {
    // Initialize environment service (detects test vs production from URL)
    _timed('EnvironmentService.init',
        () => EnvironmentService.instance.initialize());

    // For web, capture initial URL hash for environment detection
    if (kIsWeb) {
      _timed('EnvironmentServiceWeb.detectFromUrlHash', () {
        final hash = WebHelper.getWindowLocationHash();
        EnvironmentService.instance
            .updateFromPath(hash.isNotEmpty ? hash.substring(1) : '');
      });
    }

    // Initialize connectivity service (for offline detection in test mode)
    _timed('ConnectivityService.init',
        () => ConnectivityService.instance.initialize());

    // Initialize config cache service
    final configCache =
        _timed('ConfigCacheService.init', () => ConfigCacheService());

    // Initialize services
    final userCacheService =
        _timed('UserCacheService creation', () => UserCacheService());

    // OPTIMIZATION: Check cache FIRST (async, but fast)
    // If no cached user, we can show whoami immediately without waiting for Firebase
    final cachedUserKey =
        await _timedAsync('UserCacheService.getSelectedUser', () async {
      return await userCacheService.getSelectedUser();
    });

    final hasCachedUser = cachedUserKey != null && cachedUserKey.isNotEmpty;

    // OPTIMIZATION 2: Run independent operations in parallel with Firebase/DB
    final fontFuture = _preloadFont();

    // Firebase and DB must be sequential (DB depends on Firebase)
    await _timedAsync('Firebase.initializeApp', () async {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    });

    final database =
        _timed('FirestoreDatabase creation', () => FirestoreDatabase());
    await _timedAsync(
        'FirestoreDatabase.initialize', () => database.initialize());

    // Config cache checks (instant) - run in parallel with font completion
    final cacheResults =
        await _timedAsync('ConfigCacheService.getBoth', () async {
      return await Future.wait([
        configCache.getDriveConfig(),
        configCache.getCalendarConfig(),
      ]);
    });
    final cachedDriveConfig = cacheResults[0] as Map<String, String?>?;
    final cachedCalendarConfig = cacheResults[1] as Map<String, String?>?;

    // Ensure font is loaded
    await _timedAsync('Font preload (await)', () => fontFuture);

    // Initialize services with cached configs
    if (cachedDriveConfig != null) {
      _timed('DriveService.init (from cache)', () {
        _initializeDriveServiceWithConfig(cachedDriveConfig);
      });
    }

    final bloc = _timed('CalendarSyncBloc creation',
        () => CalendarSyncBloc(database: database));
    if (cachedCalendarConfig != null) {
      _timed('CalendarSyncBloc.init (from cache)', () {
        _initializeCalendarBlocWithConfig(bloc, cachedCalendarConfig);
      });
    }

    // Fetch missing configs from Firestore if needed (blocking)
    if (cachedDriveConfig == null || cachedCalendarConfig == null) {
      final configResults =
          await _timedAsync('Firestore.configFetch', () async {
        return await Future.wait([
          if (cachedDriveConfig == null)
            _fetchDriveConfigFromFirestore(database),
          if (cachedCalendarConfig == null)
            _fetchCalendarConfigFromFirestore(database),
        ]);
      });

      int resultIndex = 0;

      if (cachedDriveConfig == null) {
        final driveConfig =
            configResults[resultIndex++] as Map<String, String?>?;
        if (driveConfig != null) {
          _initializeDriveServiceWithConfig(driveConfig);
          await configCache.saveDriveConfig(driveConfig);
        }
      }

      if (cachedCalendarConfig == null) {
        final calendarConfig =
            configResults[resultIndex++] as Map<String, String?>?;
        if (calendarConfig != null) {
          _initializeCalendarBlocWithConfig(bloc, calendarConfig);
          await configCache.saveCalendarConfig(calendarConfig);
        }
      }
    }

    // Initialize repositories
    final repositories = _timed('Repositories creation', () {
      return (
        team: TeamRepository(database),
        event: EventRepository(database),
        assignment: AssignmentRepository(database),
        checklist: ChecklistRepository(database),
        preset: PresetRepository(database),
        role: RoleRepository(database),
        category: CategoryRepository(database),
        userSelection: UserSelectionRepository(
          database: database,
          userCacheService: userCacheService,
        ),
      );
    });

    // Validate cached user if exists (requires Firebase to be ready)
    TeamMember? preAuthenticatedUser;
    if (hasCachedUser) {
      try {
        final validatedUser =
            await _timedAsync('Database.getTeamMemberByUniqueKey', () async {
          return await database.getTeamMemberByUniqueKey(cachedUserKey);
        });
        if (validatedUser != null) {
          preAuthenticatedUser = validatedUser;
        } else {
          await userCacheService.clearSelection();
        }
      } catch (e) {
        await userCacheService.clearSelection();
      }
    }

    // Replace loading app with main app
    _timed('runApp(MyApp)', () {
      runApp(MyApp(
        teamRepository: repositories.team,
        eventRepository: repositories.event,
        assignmentRepository: repositories.assignment,
        checklistRepository: repositories.checklist,
        presetRepository: repositories.preset,
        roleRepository: repositories.role,
        categoryRepository: repositories.category,
        userSelectionRepository: repositories.userSelection,
        calendarSyncBloc: bloc,
        preAuthenticatedUser: preAuthenticatedUser,
      ));
    });

    totalSw.stop();

    // Hide the HTML splash screen after Flutter renders (web only)
    if (kIsWeb) {
      _hideSplashScreen();
    }

    // Refresh cache in background (non-blocking)
    _refreshConfigCacheInBackground(database, configCache);

    // Run archive check in background (non-blocking)
    _runArchiveCheckInBackground(repositories.event);
  } catch (e) {
    totalSw.stop();
    // Show error screen
    runApp(ErrorApp(error: e.toString()));
  }
}

/// Hide the HTML splash screen with a fade-out animation (web only)
void _hideSplashScreen() {
  if (!kIsWeb) return;
  WebHelper.hideSplashScreen();
}

/// Preload custom Rubik font to prevent FOUT (Flash of Unstyled Text)
Future<void> _preloadFont() async {
  try {
    // Load font bytes from assets
    final fontData =
        await rootBundle.load('assets/fonts/Rubik-VariableFont_wght.ttf');
    // Register font with Flutter's rendering engine
    await ui.loadFontFromList(
      fontData.buffer.asUint8List(),
      fontFamily: 'Rubik',
    );
    // Wait for font to be fully registered with rendering pipeline
    await Future.delayed(const Duration(milliseconds: 50));
  } catch (e) {
    // Font loading failed, app will fall back to default system font
    developer.log('Font preload failed: $e', name: 'Main');
  }
}

class MyApp extends StatelessWidget {
  static int _buildCounter = 0;

  final TeamRepository teamRepository;
  final EventRepository eventRepository;
  final AssignmentRepository assignmentRepository;
  final ChecklistRepository checklistRepository;
  final PresetRepository presetRepository;
  final RoleRepository roleRepository;
  final CategoryRepository categoryRepository;
  final UserSelectionRepository userSelectionRepository;
  final CalendarSyncBloc calendarSyncBloc;
  final TeamMember? preAuthenticatedUser;

  const MyApp({
    super.key,
    required this.teamRepository,
    required this.eventRepository,
    required this.assignmentRepository,
    required this.checklistRepository,
    required this.presetRepository,
    required this.roleRepository,
    required this.categoryRepository,
    required this.userSelectionRepository,
    required this.calendarSyncBloc,
    this.preAuthenticatedUser,
  });

  @override
  Widget build(BuildContext context) {
    if (preAuthenticatedUser != null) {
      AuditContextService.instance.setCurrentUser(preAuthenticatedUser);
    }

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: teamRepository),
        RepositoryProvider.value(value: eventRepository),
        RepositoryProvider.value(value: assignmentRepository),
        RepositoryProvider.value(value: checklistRepository),
        RepositoryProvider.value(value: presetRepository),
        RepositoryProvider.value(value: roleRepository),
        RepositoryProvider.value(value: categoryRepository),
        RepositoryProvider.value(value: userSelectionRepository),
      ],
      child: ListenableBuilder(
        listenable: EnvironmentService.instance,
        builder: (context, child) {
          final env = EnvironmentService.instance.isTestMode ? 'TEST' : 'PROD';
          _buildCounter++;
          developer.log(
            'MyApp build #$_buildCounter env=$env',
            name: 'Main',
          );

          return MultiBlocProvider(
            key: ValueKey(EnvironmentService.instance.isTestMode),
            providers: [
              // CalendarSyncBloc - already initialized
              BlocProvider.value(value: calendarSyncBloc),
              BlocProvider(
                create: (context) {
                  final teamBloc = TeamBloc(
                    context.read<TeamRepository>(),
                    context.read<AssignmentRepository>(),
                    calendarSyncBloc: context.read<CalendarSyncBloc>(),
                  );
                  // Start loading team members immediately to avoid loading screen in WhoamiScreen
                  teamBloc.add(const LoadTeamMembers());
                  return teamBloc;
                },
              ),
              BlocProvider(
                create: (context) {
                  return EventBloc(
                    context.read<EventRepository>(),
                    context.read<AssignmentRepository>(),
                    calendarSyncBloc: context.read<CalendarSyncBloc>(),
                  );
                },
              ),
              BlocProvider(
                create: (context) {
                  return serviceLocator.createAssignmentBloc(
                    calendarSyncBloc: context.read<CalendarSyncBloc>(),
                  );
                },
              ),
              BlocProvider(
                create: (context) {
                  return serviceLocator.createUserSelectionBloc(
                    calendarSyncBloc: context.read<CalendarSyncBloc>(),
                    preAuthenticatedUser: preAuthenticatedUser,
                  );
                },
              ),
              BlocProvider(
                create: (context) {
                  return ChecklistBloc(
                    repository: context.read<ChecklistRepository>(),
                    userSelectionBloc: context.read<UserSelectionBloc>(),
                  );
                },
              ),
              BlocProvider(
                create: (context) {
                  return PresetBloc(
                    repository: context.read<PresetRepository>(),
                    eventRepository: context.read<EventRepository>(),
                    userSelectionBloc: context.read<UserSelectionBloc>(),
                  );
                },
              ),
              BlocProvider(
                create: (context) {
                  final roleBloc = RoleBloc(context.read<RoleRepository>());
                  // Start loading roles immediately
                  roleBloc.add(const LoadRoles());
                  return roleBloc;
                },
              ),
              BlocProvider(
                create: (context) {
                  final categoryBloc = CategoryBloc(
                    context.read<CategoryRepository>(),
                  );
                  // Start loading categories immediately
                  categoryBloc.add(const LoadCategories());
                  return categoryBloc;
                },
              ),
            ],
            child: Builder(
              builder: (context) {
                final userSelectionBloc = context.read<UserSelectionBloc>();
                final userSelectionRepository =
                    context.read<UserSelectionRepository>();
                final teamBloc = context.read<TeamBloc>();

                return BlocListener<UserSelectionBloc, UserSelectionState>(
                  listener: (context, state) {
                    if (state is UserAuthenticated) {
                      AuditContextService.instance.setCurrentUser(state.user);
                    } else if (state is UserSignedOut) {
                      AuditContextService.instance.clear();
                    }

                    // Clear all BLoC states when user signs out
                    if (state is UserSignedOut) {
                      teamBloc.add(const ClearTeamState());
                      // TODO: Add similar clear events for EventBloc and AssignmentBloc
                    }
                  },
                  child: OfflineBlockingOverlay(
                    child: MaterialApp.router(
                      title: 'שבצק - ניהול צוות',
                      theme: AppTheme.lightTheme,
                      debugShowCheckedModeBanner: false,
                      routerConfig: AppRouter.router(
                        userSelectionBloc: userSelectionBloc,
                        userSelectionRepository: userSelectionRepository,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Initialize DriveService with a pre-fetched config
void _initializeDriveServiceWithConfig(Map<String, String?> config) {
  try {
    if (config['scriptUrl'] != null && config['apiKey'] != null) {
      DriveService.instance.initialize(
        scriptUrl: config['scriptUrl']!,
        apiKey: config['apiKey']!,
      );
    }
  } catch (e) {
    developer.log(
      'main.dart: Failed to initialize DriveService: $e',
      name: 'Main',
      error: e,
    );
  }
}

/// Initialize CalendarSyncBloc with a pre-fetched config
void _initializeCalendarBlocWithConfig(
  CalendarSyncBloc bloc,
  Map<String, String?> config,
) {
  try {
    if (config['calendarId'] != null) {
      bloc.add(InitializeCalendarSync(
        calendarId: config['calendarId']!,
      ));
    } else {
      bloc.add(const InitializeCalendarSync(
        calendarId: null,
      ));
    }
  } catch (e) {
    developer.log(
      'main.dart: Failed to initialize CalendarSyncBloc: $e',
      name: 'Main',
      error: e,
    );
  }
}

/// Fetch Drive config from Firestore
Future<Map<String, String?>?> _fetchDriveConfigFromFirestore(
  FirestoreDatabase database,
) async {
  try {
    return await database.getDriveConfig();
  } catch (e) {
    developer.log(
      'main.dart: Failed to fetch Drive config: $e',
      name: 'Main',
      error: e,
    );
    return null;
  }
}

/// Fetch Calendar config from Firestore
Future<Map<String, String?>?> _fetchCalendarConfigFromFirestore(
  FirestoreDatabase database,
) async {
  try {
    return await database.getGoogleCalendarConfig();
  } catch (e) {
    developer.log(
      'main.dart: Failed to fetch Calendar config: $e',
      name: 'Main',
      error: e,
    );
    return null;
  }
}

/// Refresh config cache in background after app renders
void _refreshConfigCacheInBackground(
  FirestoreDatabase database,
  ConfigCacheService configCache,
) {
  // Run after a short delay to not interfere with initial render
  Future.delayed(const Duration(seconds: 2), () async {
    try {
      final results = await Future.wait([
        database.getDriveConfig(),
        database.getGoogleCalendarConfig(),
      ]);

      final driveConfig = results[0] as Map<String, String?>?;
      final calendarConfig = results[1] as Map<String, String?>?;

      if (driveConfig != null) {
        await configCache.saveDriveConfig(driveConfig);
      }

      if (calendarConfig != null) {
        await configCache.saveCalendarConfig(calendarConfig);
      }
    } catch (e) {
      developer.log(
        'main.dart: Background config refresh failed: $e',
        name: 'Main',
        error: e,
      );
    }
  });
}

/// Run archive check in background after app renders
void _runArchiveCheckInBackground(EventRepository eventRepository) {
  // Run after a short delay to not interfere with initial render
  Future.delayed(const Duration(seconds: 3), () async {
    try {
      // Use reflection to call the private method, or make it public
      // Since _runArchiveCheckInBackground is private in EventRepository,
      // we'll need to make it public or add a public method for this purpose
      developer.log(
        'main.dart: Background: Running archive check on startup',
        name: 'Main',
      );

      // Access the private method via a public API
      // We need to add a public method to EventRepository for this
      await eventRepository.runArchiveCheckIfReady();

      developer.log(
        'main.dart: Background: Archive check completed',
        name: 'Main',
      );
    } catch (e) {
      developer.log(
        'main.dart: Background archive check failed: $e',
        name: 'Main',
        error: e,
      );
    }
  });
}

/// Loading screen shown during app initialization
/// Sizes match the HTML splash screen in index.html for seamless transition
class LoadingApp extends StatelessWidget {
  const LoadingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // Global navigator key for snackbars
      title: 'שבצק - ניהול צוות',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const _LoadingScreen(),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Match HTML splash screen responsive breakpoints exactly
    final double iconSize;
    final double iconContainerSize;
    final double iconBorderRadius;
    final double titleFontSize;
    final double subtitleFontSize;
    final double loadingTextFontSize;
    final double spinnerSize;
    final double iconMarginBottom;
    final double subtitleMarginBottom;
    final double spinnerMarginBottom;

    if (screenWidth <= 360) {
      // Small mobile phones
      iconContainerSize = 70;
      iconSize = 35;
      iconBorderRadius = 14;
      iconMarginBottom = 20;
      titleFontSize = 20;
      subtitleFontSize = 13;
      subtitleMarginBottom = 28;
      spinnerSize = 28;
      spinnerMarginBottom = 12;
      loadingTextFontSize = 13;
    } else if (screenWidth <= 480) {
      // Mobile phones
      iconContainerSize = 80;
      iconSize = 40;
      iconBorderRadius = 14;
      iconMarginBottom = 20;
      titleFontSize = 24;
      subtitleFontSize = 14;
      subtitleMarginBottom = 28;
      spinnerSize = 28;
      spinnerMarginBottom = 12;
      loadingTextFontSize = 13;
    } else if (screenWidth <= 768) {
      // Tablets / large phones
      iconContainerSize = 100;
      iconSize = 50;
      iconBorderRadius = 16;
      iconMarginBottom = 24;
      titleFontSize = 28;
      subtitleFontSize = 16;
      subtitleMarginBottom = 36;
      spinnerSize = 32;
      spinnerMarginBottom = 14;
      loadingTextFontSize = 14;
    } else {
      // Desktop / large screens
      iconContainerSize = 120;
      iconSize = 60;
      iconBorderRadius = 20;
      iconMarginBottom = 32;
      titleFontSize = 32;
      subtitleFontSize = 18;
      subtitleMarginBottom = 48;
      spinnerSize = 36;
      spinnerMarginBottom = 16;
      loadingTextFontSize = 16;
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Logo/Icon
              Container(
                width: iconContainerSize,
                height: iconContainerSize,
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(iconBorderRadius),
                ),
                child: Icon(
                  Icons.group,
                  size: iconSize,
                  color: Colors.blue[600],
                ),
              ),
              SizedBox(height: iconMarginBottom),
              // App Name
              Text(
                'שבצק',
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'מערכת ניהול צוות',
                style: TextStyle(
                  fontSize: subtitleFontSize,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: subtitleMarginBottom),
              // Loading Indicator
              SizedBox(
                width: spinnerSize,
                height: spinnerSize,
                child: CircularProgressIndicator(
                  strokeWidth: screenWidth <= 480 ? 2.5 : 3.0,
                ),
              ),
              SizedBox(height: spinnerMarginBottom),
              Text(
                'טוען...',
                style: TextStyle(
                  fontSize: loadingTextFontSize,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error screen shown if initialization fails
class ErrorApp extends StatelessWidget {
  final String error;

  const ErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // Global navigator key for snackbars
      title: 'שבצק - ניהול צוות',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 80,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'שגיאה בטעינת האפליקציה',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    error,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () => main(),
                    child: const Text('נסה שוב'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
