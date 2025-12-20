import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'firebase_options.dart';
import 'dart:developer' as developer;

// Data layer
import 'data/data_sources/firestore_database.dart';
import 'data/repositories/team_repository.dart';
import 'data/repositories/event_repository.dart';
import 'data/repositories/assignment_repository.dart';
import 'data/repositories/user_selection_repository.dart';
import 'core/services/user_cache_service.dart';
import 'core/services/environment_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/drive_service.dart';
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

    // Run parallel initialization tasks:
    // 1. DriveService config loading
    // 2. CalendarSyncBloc config loading
    // 3. Font preloading (already started)
    final results = await Future.wait([
      _initializeDriveService(database),
      _createCalendarSyncBloc(database),
      fontFuture,
    ]);

    final calendarSyncBloc = results[1] as CalendarSyncBloc;

    // Initialize repositories
    final teamRepository = TeamRepository(database);
    final eventRepository = EventRepository(database);
    final assignmentRepository = AssignmentRepository(database);
    final userSelectionRepository = UserSelectionRepository(
      database: database,
      userCacheService: userCacheService,
    );

    // Replace loading app with main app
    runApp(MyApp(
      teamRepository: teamRepository,
      eventRepository: eventRepository,
      assignmentRepository: assignmentRepository,
      userSelectionRepository: userSelectionRepository,
      calendarSyncBloc: calendarSyncBloc,
    ));
  } catch (e) {
    // Show error screen
    runApp(ErrorApp(error: e.toString()));
  }
}

/// Preload custom Rubik font to prevent FOUT
Future<void> _preloadFont() async {
  try {
    // Preload the font by loading it into memory
    await rootBundle.load('assets/fonts/Rubik-VariableFont_wght.ttf');
    // Font is loaded - Flutter engine will register it on next frame
  } catch (e) {
    // Font loading failed, app will fall back to default system font
  }
}

class MyApp extends StatelessWidget {
  final TeamRepository teamRepository;
  final EventRepository eventRepository;
  final AssignmentRepository assignmentRepository;
  final UserSelectionRepository userSelectionRepository;
  final CalendarSyncBloc calendarSyncBloc;

  const MyApp({
    super.key,
    required this.teamRepository,
    required this.eventRepository,
    required this.assignmentRepository,
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

/// Initialize DriveService with config from Firestore
Future<void> _initializeDriveService(FirestoreDatabase database) async {
  try {
    final config = await database.getDriveConfig();

    if (config != null && config['scriptUrl'] != null && config['apiKey'] != null) {
      DriveService.instance.initialize(
        scriptUrl: config['scriptUrl']!,
        apiKey: config['apiKey']!,
      );
      developer.log(
        'main.dart: DriveService initialized successfully',
        name: 'Main',
      );
    } else {
      developer.log(
        'main.dart: DriveService not initialized - missing config in Firestore (keys/googleDrive)',
        name: 'Main',
      );
    }
  } catch (e) {
    developer.log(
      'main.dart: Failed to initialize DriveService: $e',
      name: 'Main',
      error: e,
    );
    // Don't throw - app can work without Drive integration
  }
}

/// Create and initialize CalendarSyncBloc with config from Firestore
Future<CalendarSyncBloc> _createCalendarSyncBloc(FirestoreDatabase database) async {
  final env = EnvironmentService.instance.isTestMode ? 'TEST' : 'PROD';
  developer.log('main.dart: Creating CalendarSyncBloc for $env environment', name: 'Main');
  final bloc = CalendarSyncBloc(database: database);

  // Initialize with credentials from Firestore
  final config = await database.getGoogleCalendarConfig();

  if (config != null && config['serviceAccountJson'] != null && config['calendarId'] != null) {
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

  return bloc;
}

/// Loading screen shown during app initialization
class LoadingApp extends StatelessWidget {
  const LoadingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        navigatorKey: navigatorKey, // Global navigator key for snackbars
        title: 'שבצק - ניהול צוות',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
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