import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'presentation/bloc/event/event_event.dart';
import 'presentation/bloc/assignment/assignment_bloc.dart';
import 'presentation/bloc/assignment/assignment_event.dart';
import 'presentation/bloc/user_selection/user_selection_bloc.dart';
import 'presentation/bloc/user_selection/user_selection_state.dart';

// Router
import 'core/router/app_router.dart';

// Theme
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SemanticsBinding.instance.ensureSemantics();

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
          developer.log(
              'main.dart: ListenableBuilder rebuilding with environment=$env, key=$envKey',
              name: 'Main');

          return MultiRepositoryProvider(
            key: ValueKey(envKey),
            providers: [
              // Recreate repositories with new database instance when environment changes
              RepositoryProvider(
                create: (context) {
                  developer.log(
                      'main.dart: Creating TeamRepository with new FirestoreDatabase for $env environment',
                      name: 'Main');
                  final db = FirestoreDatabase();
                  return TeamRepository(db);
                },
              ),
              RepositoryProvider(
                create: (context) {
                  developer.log(
                      'main.dart: Creating EventRepository with new FirestoreDatabase for $env environment',
                      name: 'Main');
                  final db = FirestoreDatabase();
                  return EventRepository(db);
                },
              ),
              RepositoryProvider(
                create: (context) {
                  developer.log(
                      'main.dart: Creating AssignmentRepository with new FirestoreDatabase for $env environment',
                      name: 'Main');
                  final db = FirestoreDatabase();
                  return AssignmentRepository(db);
                },
              ),
              RepositoryProvider.value(value: userSelectionRepository),
            ],
            child: MultiBlocProvider(
              key: ValueKey(EnvironmentService.instance.isTestMode),
              providers: [
                BlocProvider(
                  create: (context) {
                    developer.log(
                        'main.dart: Creating TeamBloc for $env environment',
                        name: 'Main');
                    return TeamBloc(
                      context.read<TeamRepository>(),
                      context.read<AssignmentRepository>(),
                    );
                  },
                ),
                BlocProvider(
                  create: (context) {
                    developer.log(
                        'main.dart: Creating EventBloc for $env environment',
                        name: 'Main');
                    return EventBloc(
                      context.read<EventRepository>(),
                      context.read<AssignmentRepository>(),
                    );
                  },
                ),
                BlocProvider(
                  create: (context) {
                    developer.log(
                        'main.dart: Creating AssignmentBloc for $env environment',
                        name: 'Main');
                    return AssignmentBloc(
                      context.read<AssignmentRepository>(),
                      context.read<EventRepository>(),
                      context.read<TeamRepository>(),
                    );
                  },
                ),
                BlocProvider(
                  create: (context) {
                    developer.log(
                        'main.dart: Creating UserSelectionBloc for $env environment',
                        name: 'Main');
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
                  final userSelectionRepository =
                      context.read<UserSelectionRepository>();
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
