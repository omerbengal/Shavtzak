import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'firebase_options.dart';
import 'dart:developer' as developer;
import 'dart:ui' as ui;
import 'package:web/web.dart' as web;

// Data layer
import 'data/data_sources/firestore_database.dart';
import 'data/repositories/team_repository.dart';
import 'data/repositories/event_repository.dart';
import 'data/repositories/assignment_repository.dart';
import 'data/repositories/user_selection_repository.dart';
import 'data/repositories/checklist_repository.dart';
import 'data/repositories/preset_repository.dart';
import 'core/services/user_cache_service.dart';
import 'core/services/environment_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/drive_service.dart';
import 'core/services/config_cache_service.dart';
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

// Router
import 'core/router/app_router.dart';

// Theme
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Show loading screen immediately
  runApp(const LoadingApp());

  // Initialize in background
  _initialize();
}

Future<void> _initialize() async {
  try {
    // Initialize environment service (detects test vs production from URL)
    EnvironmentService.instance.initialize();

    // Initialize connectivity service (for offline detection in test mode)
    ConnectivityService.instance.initialize();

    // Initialize config cache service
    final configCache = ConfigCacheService();

    // Start font preloading in parallel (don't await yet)
    final fontFuture = _preloadFont();

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize database
    final database = FirestoreDatabase();
    await database.initialize();

    // Initialize services
    final userCacheService = UserCacheService();

    // Try to get configs from cache first (instant)
    final cachedDriveConfig = await configCache.getDriveConfig();
    final cachedCalendarConfig = await configCache.getCalendarConfig();

    // Determine if we need to fetch from Firestore
    final needsDriveFetch = cachedDriveConfig == null;
    final needsCalendarFetch = cachedCalendarConfig == null;

    // Initialize DriveService with cached or fetched config
    if (!needsDriveFetch) {
      _initializeDriveServiceWithConfig(cachedDriveConfig!);
      developer.log('main.dart: DriveService initialized from cache', name: 'Main');
    }

    // Initialize CalendarSyncBloc with cached or fetched config
    final bloc = CalendarSyncBloc(database: database);
    if (!needsCalendarFetch && cachedCalendarConfig != null) {
      _initializeCalendarBlocWithConfig(bloc, cachedCalendarConfig);
      developer.log('main.dart: CalendarSyncBloc initialized from cache', name: 'Main');
    }

    // If any config was missing, fetch from Firestore (blocking, only on first visit)
    if (needsDriveFetch || needsCalendarFetch) {
      developer.log('main.dart: Fetching missing configs from Firestore', name: 'Main');

      // Fetch only what's missing
      final results = await Future.wait([
        if (needsDriveFetch) _fetchDriveConfigFromFirestore(database),
        if (needsCalendarFetch) _fetchCalendarConfigFromFirestore(database),
        fontFuture,
      ]);

      int resultIndex = 0;

      if (needsDriveFetch) {
        final driveConfig = results[resultIndex++] as Map<String, String?>?;
        if (driveConfig != null) {
          _initializeDriveServiceWithConfig(driveConfig);
          await configCache.saveDriveConfig(driveConfig);
          developer.log('main.dart: DriveService initialized from Firestore, cached', name: 'Main');
        }
      }

      if (needsCalendarFetch) {
        final calendarConfig = results[resultIndex] as Map<String, String?>?;
        if (calendarConfig != null) {
          _initializeCalendarBlocWithConfig(bloc, calendarConfig);
          await configCache.saveCalendarConfig(calendarConfig);
          developer.log('main.dart: CalendarSyncBloc initialized from Firestore, cached', name: 'Main');
        }
      }
    } else {
      // Just await font preload if configs were cached
      await fontFuture;
    }

    // Initialize repositories
    final teamRepository = TeamRepository(database);
    final eventRepository = EventRepository(database);
    final assignmentRepository = AssignmentRepository(database);
    final checklistRepository = ChecklistRepository(database);
    final presetRepository = PresetRepository(database);
    final userSelectionRepository = UserSelectionRepository(
      database: database,
      userCacheService: userCacheService,
    );

    // Replace loading app with main app
    runApp(MyApp(
      teamRepository: teamRepository,
      eventRepository: eventRepository,
      assignmentRepository: assignmentRepository,
      checklistRepository: checklistRepository,
      presetRepository: presetRepository,
      userSelectionRepository: userSelectionRepository,
      calendarSyncBloc: bloc,
    ));

    // Hide the HTML splash screen after Flutter renders
    _hideSplashScreen();

    // Refresh cache in background (non-blocking)
    _refreshConfigCacheInBackground(database, configCache);
  } catch (e) {
    // Show error screen
    runApp(ErrorApp(error: e.toString()));
  }
}

/// Hide the HTML splash screen with a fade-out animation
void _hideSplashScreen() {
  try {
    final splash = web.document.getElementById('splash-screen');
    if (splash != null) {
      // Add hidden class for fade-out transition
      splash.classList.add('splash-hidden');
      // Remove from DOM after transition completes
      Future.delayed(const Duration(milliseconds: 300), () {
        splash.remove();
      });
    }
  } catch (e) {
    developer.log('Failed to hide splash screen: $e', name: 'Main');
  }
}

/// Preload custom Rubik font to prevent FOUT (Flash of Unstyled Text)
Future<void> _preloadFont() async {
  try {
    // Load font bytes from assets
    final fontData = await rootBundle.load('assets/fonts/Rubik-VariableFont_wght.ttf');
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
  final TeamRepository teamRepository;
  final EventRepository eventRepository;
  final AssignmentRepository assignmentRepository;
  final ChecklistRepository checklistRepository;
  final PresetRepository presetRepository;
  final UserSelectionRepository userSelectionRepository;
  final CalendarSyncBloc calendarSyncBloc;

  const MyApp({
    super.key,
    required this.teamRepository,
    required this.eventRepository,
    required this.assignmentRepository,
    required this.checklistRepository,
    required this.presetRepository,
    required this.userSelectionRepository,
    required this.calendarSyncBloc,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: teamRepository),
        RepositoryProvider.value(value: eventRepository),
        RepositoryProvider.value(value: assignmentRepository),
        RepositoryProvider.value(value: checklistRepository),
        RepositoryProvider.value(value: presetRepository),
        RepositoryProvider.value(value: userSelectionRepository),
      ],
      child: ListenableBuilder(
        listenable: EnvironmentService.instance,
        builder: (context, child) {
          final env = EnvironmentService.instance.isTestMode ? 'TEST' : 'PROD';

          return MultiBlocProvider(
            key: ValueKey(EnvironmentService.instance.isTestMode),
            providers: [
              // CalendarSyncBloc - already initialized
              BlocProvider.value(value: calendarSyncBloc),
              BlocProvider(
                create: (context) {
                  developer.log('main.dart: Creating TeamBloc for $env environment', name: 'Main');
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
                  developer.log('main.dart: Creating EventBloc for $env environment', name: 'Main');
                  return EventBloc(
                    context.read<EventRepository>(),
                    context.read<AssignmentRepository>(),
                  );
                },
              ),
              BlocProvider(
                create: (context) {
                  developer.log('main.dart: Creating AssignmentBloc for $env environment', name: 'Main');
                  return AssignmentBloc(
                    context.read<AssignmentRepository>(),
                    context.read<EventRepository>(),
                    context.read<TeamRepository>(),
                  );
                },
              ),
              BlocProvider(
                create: (context) {
                  developer.log('main.dart: Creating UserSelectionBloc for $env environment', name: 'Main');
                  return UserSelectionBloc(
                    userSelectionRepository,
                    context.read<TeamRepository>(),
                  );
                },
              ),
              BlocProvider(
                create: (context) {
                  developer.log('main.dart: Creating ChecklistBloc for $env environment', name: 'Main');
                  return ChecklistBloc(
                    repository: context.read<ChecklistRepository>(),
                    userSelectionBloc: context.read<UserSelectionBloc>(),
                  );
                },
              ),
              BlocProvider(
                create: (context) {
                  developer.log('main.dart: Creating PresetBloc for $env environment', name: 'Main');
                  return PresetBloc(
                    repository: context.read<PresetRepository>(),
                    eventRepository: context.read<EventRepository>(),
                    userSelectionBloc: context.read<UserSelectionBloc>(),
                  );
                },
              ),
            ],
            child: Builder(
              builder: (context) {
                final userSelectionBloc = context.read<UserSelectionBloc>();
                final userSelectionRepository = context.read<UserSelectionRepository>();
                final teamBloc = context.read<TeamBloc>();

                return BlocListener<UserSelectionBloc, UserSelectionState>(
                  listener: (context, state) {
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
    if (config['serviceAccountJson'] != null && config['calendarId'] != null) {
      bloc.add(InitializeCalendarSync(
        serviceAccountJson: config['serviceAccountJson']!,
        calendarId: config['calendarId']!,
      ));
    } else {
      bloc.add(const InitializeCalendarSync(
        serviceAccountJson: null,
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
        developer.log('main.dart: Background: Drive config cached', name: 'Main');
      }

      if (calendarConfig != null) {
        await configCache.saveCalendarConfig(calendarConfig);
        developer.log('main.dart: Background: Calendar config cached', name: 'Main');
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

/// Loading screen shown during app initialization
class LoadingApp extends StatelessWidget {
  const LoadingApp({super.key});

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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App Logo/Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.group,
                    size: 60,
                    color: Colors.blue[600],
                  ),
                ),
                const SizedBox(height: 32),
                // App Name
                const Text(
                  'שבצק',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'מערכת ניהול צוות',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 48),
                // Loading Indicator
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  'טוען...',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
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