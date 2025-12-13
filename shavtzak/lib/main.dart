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
      // Recreate all BLoCs when environment changes by using a key based on environment
      child: ListenableBuilder(
        listenable: EnvironmentService.instance,
        builder: (context, child) {
          // Using environment as key forces BLoCs to recreate when environment changes
          final envKey = 'repos_${EnvironmentService.instance.isTestMode}';
          final env = EnvironmentService.instance.isTestMode ? 'TEST' : 'PROD';
          developer.log('main.dart: ListenableBuilder rebuilding with environment=$env, key=$envKey', name: 'Main');

          return MultiRepositoryProvider(
            key: ValueKey(envKey),
            providers: [
              // Recreate repositories with new database instance when environment changes
              RepositoryProvider(
                create: (context) {
                  developer.log('main.dart: Creating TeamRepository with new FirestoreDatabase for $env environment', name: 'Main');
                  final db = FirestoreDatabase();
                  return TeamRepository(db);
                },
              ),
              RepositoryProvider(
                create: (context) {
                  developer.log('main.dart: Creating EventRepository with new FirestoreDatabase for $env environment', name: 'Main');
                  final db = FirestoreDatabase();
                  return EventRepository(db);
                },
              ),
              RepositoryProvider(
                create: (context) {
                  developer.log('main.dart: Creating AssignmentRepository with new FirestoreDatabase for $env environment', name: 'Main');
                  final db = FirestoreDatabase();
                  return AssignmentRepository(db);
                },
              ),
              RepositoryProvider.value(value: userSelectionRepository),
            ],
            child: MultiBlocProvider(
              key: ValueKey(EnvironmentService.instance.isTestMode),
              providers: [
                // CalendarSyncBloc must be created first since TeamBloc depends on it
                BlocProvider<CalendarSyncBloc>(
                  create: (context) {
                    print('🗓️ [main.dart] Creating CalendarSyncBloc for $env environment');
                    developer.log('main.dart: Creating CalendarSyncBloc for $env environment', name: 'Main');
                    final db = FirestoreDatabase();
                    final bloc = CalendarSyncBloc(database: db);

                    // Initialize with credentials
                    print('🗓️ [main.dart] Adding InitializeCalendarSync event...');
                    bloc.add(InitializeCalendarSync(
                      serviceAccountJson: '''
{
  "type": "service_account",
  "project_id": "nice-abbey-481107-a2",
  "private_key_id": "de9c0ea20ad8b93734faab3688b5689344e28a13",
  "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDyvetTt+oZP5Tp\\nf7DAEb2jdq9/Cz95d5U0eS80yNj9m5V295lL0yHDnOSIF13NpbjgSi8wzh0jQo2J\\nBzmURejktA+HxN4xwtucmcQY7ZhL4583uHc/qigHGNYlamLzFVTLyXBd+BZnlf66\\nqq/aLQA9vnYLo1MebUU/XQXRZJ/zQS5zMI40emOMfyMIPR2ikmRFUt8dgvCkLGZb\\n7LJB4JaR8QMdkRIdn63UozKGC/s2DHIHo68jvrGxQ68LzQlwtK2237ohID1CHAxu\\ndpQhl/Vu5AVd9PXbpKwQjOP9CkNqFQOUM6u9YakTKNVE8sU51rVtsot0FJP/Xewq\\n6KrMfu4VAgMBAAECggEAKAhWzlqDNtFD1YNryq1SVWpONJlOCVIFrx76QE4MbTzS\\nuElKxJTIGXrfPKt/2pnFZOYPJNElQIqqDWp93jxuVYN1mTpIO7QrZEb+rm7GwmNC\\nf53COuNs0QjRTl/efEDtGGO7DqBKz6AO38mlEUoBI22tCavQmjDCrhnBCyC5eVQZ\\nHz6LN4cmeCg+j5iboJvlezTncStSQjVghd21B+fC8kjQspJ99EYshqrHUsa5aGt1\\nty/wUzgHnHcVFUjRs361cifxd48Jgn6DJy0jAL9RkYtBsH9+VSzk2d4QfNb4iaT4\\nqDu2X8nBLTlKl/uLtyUUJFcwDEY0HbyLI2mv7RHoCQKBgQD+nHr+ZfEyvkTIY8Xm\\nRAcVW8tFFLd+71MlQE91AU7DXxy8s4hw/AxkJh6sTktr7LdlgXQIS2Ki9AyXm46q\\nmS7z8MYNhkc8LpkayL78VV0h5jLThNfagQeeYvwcjVGFq7E4Dl3HoEEj7HnKUYGR\\n9s+JmmN0ySUEmPg6/HTvcv5U+QKBgQD0EN2FMaVDmsul9eYT0Wgvr6ykeNhXuoGc\\nscH9bDok9c8SENRHFYEmPW3vMnCHEGs4q7BLPkU3ghLVav/k45qqR91SBOrrtgeg\\nkqxI5dgV2drkxONFRgNznVrQl9oa8yS1CM1hJOkezNhRvB1/HEiBz+DpYbk416Pp\\nSCe0cG2U/QKBgFxKxJqqwT+vkKdC412QkzC+0XP9CnbMscrzANpc2vwe4f/U5ERw\\nWN2Eo+G5j8VTTTdSMYlAKkT/SgE6tgBI/qgWQvRsFC5QhdcbpX86QkQjeZEKumPO\\nGcDkCJcg8sgNcHPtYTkXcgVfltYrrVgHqzsp55tRvkVoXbKkCI8zk9WhAoGAUdzu\\nUGSsiBZ9xDbMa01L4uLLx4b5GcPnAYXmCXipsAf64pZefVFLNmZYX2jNsZ/iNunv\\nge1rDglFA+yV1FI7aG4eYApiOZmeyU8pFnJxnjKqZx1bFbs8ISVgdqLYdz2izE4d\\nhT36K2iODixIwH/eGhx91gn/NH+v7OlU2AL13okCgYEAskmPeX9IG3O9X5PdyCC7\\nWlSk1mj91/L2Ha+7uGhInqOpVINAuZV4vpOHDPtAGZ+7Run5yGOfMbRNhtTh0RF8\\nYXwyixMSWjrw1m+6M53qSAiMR11LsDU73QVaG9NtGlmkMi620o+W+T+si5px9rEw\\nuYpB9wSJ1npg6poVc3laRq4=\\n-----END PRIVATE KEY-----\\n",
  "client_email": "shavtzak-googlecalendar-sync@nice-abbey-481107-a2.iam.gserviceaccount.com",
  "client_id": "112794767181200330833",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/shavtzak-googlecalendar-sync%40nice-abbey-481107-a2.iam.gserviceaccount.com",
  "universe_domain": "googleapis.com"
}
''',
                      calendarId: 'atkamiluaim@gmail.com',
                    ));

                    return bloc;
                  },
                ),
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
            ),
          );
        },
      ),
    );
  }
}

/// Loading screen shown during app initialization
class LoadingApp extends StatelessWidget {
  const LoadingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App logo or icon (you can customize this)
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.people,
                  size: 60,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'שבצק',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'ניהול צוות ואירועים',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'טוען...',
                style: TextStyle(
                  fontSize: 14,
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
                  ElevatedButton.icon(
                    onPressed: () {
                      // Reload the page
                      // ignore: avoid_web_libraries_in_flutter
                      // html.window.location.reload();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('נסה שוב'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
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
