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

    // Preload Rubik font to prevent FOUT (Flash of Unstyled Text)
    await _preloadFont();

    // Use path-based URLs instead of hash-based URLs
    // usePathUrlStrategy();

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize database
    final database = FirestoreDatabase();
    await database.initialize();

    // Initialize services
    final userCacheService = UserCacheService();

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
    // Give the font a moment to register with the Flutter engine
    await Future.delayed(const Duration(milliseconds: 100));
  } catch (e) {
    // Font loading failed, app will fall back to default system font
  }
}

class MyApp extends StatelessWidget {
  final TeamRepository teamRepository;
  final EventRepository eventRepository;
  final AssignmentRepository assignmentRepository;
  final UserSelectionRepository userSelectionRepository;

  const MyApp({
    super.key,
    required this.teamRepository,
    required this.eventRepository,
    required this.assignmentRepository,
    required this.userSelectionRepository,
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
          return FutureBuilder<CalendarSyncBloc>(
            future: _createCalendarSyncBloc(env),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const MaterialApp(
                  home: Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                );
              }

              if (snapshot.hasError) {
                return MaterialApp(
                  home: Scaffold(
                    body: Center(
                      child: Text('Error initializing app: ${snapshot.error}'),
                    ),
                  ),
                );
              }

              final calendarSyncBloc = snapshot.data!;

              return MultiBlocProvider(
                key: ValueKey(EnvironmentService.instance.isTestMode),
                providers: [
                  // CalendarSyncBloc
                  BlocProvider.value(value: calendarSyncBloc),
                  BlocProvider(
                    create: (context) {
                      developer.log('main.dart: Creating TeamBloc for $env environment', name: 'Main');
                      return TeamBloc(
                        context.read<TeamRepository>(),
                        context.read<AssignmentRepository>(),
                        calendarSyncBloc: context.read<CalendarSyncBloc>(),
                      );
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
                      child: MaterialApp.router(
                        title: 'שבצק - ניהול צוות',
                        theme: AppTheme.lightTheme,
                        debugShowCheckedModeBanner: false,
                        routerConfig: AppRouter.router(
                          userSelectionBloc: userSelectionBloc,
                          userSelectionRepository: userSelectionRepository,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Create and initialize CalendarSyncBloc with config from Firestore
Future<CalendarSyncBloc> _createCalendarSyncBloc(String env) async {
  print('🗓️ [main.dart] Creating CalendarSyncBloc for $env environment');
  developer.log('main.dart: Creating CalendarSyncBloc for $env environment', name: 'Main');
  final db = FirestoreDatabase();
  final bloc = CalendarSyncBloc(database: db);

  // Initialize with credentials from Firestore
  print('🗓️ [main.dart] Fetching Google Calendar config from Firestore...');
  final config = await db.getGoogleCalendarConfig();

  if (config != null && config['serviceAccountJson'] != null && config['calendarId'] != null) {
    print('🗓️ [main.dart] Google Calendar config found, initializing...');
    bloc.add(InitializeCalendarSync(
      serviceAccountJson: config['serviceAccountJson']!,
      calendarId: config['calendarId']!,
    ));
  } else {
    print('🗓️ [main.dart] No Google Calendar config found, sync disabled');
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