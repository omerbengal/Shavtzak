import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'firebase_options.dart';

// Data layer
import 'data/data_sources/firestore_database.dart';
import 'data/repositories/team_repository.dart';
import 'data/repositories/event_repository.dart';
import 'data/repositories/assignment_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/user_selection_repository.dart';
import 'core/utils/device_id.dart';
import 'core/services/user_cache_service.dart';

// Presentation layer
import 'presentation/bloc/team/team_bloc.dart';
import 'presentation/bloc/event/event_bloc.dart';
import 'presentation/bloc/assignment/assignment_bloc.dart';
import 'presentation/bloc/user_selection/user_selection_bloc.dart';

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
    final deviceIdService = DeviceIdService();
    final userCacheService = UserCacheService();

    // Initialize repositories
    final teamRepository = TeamRepository(database);
    final eventRepository = EventRepository(database);
    final assignmentRepository = AssignmentRepository(database);
    final authRepository = AuthRepository(database, deviceIdService);
    final userSelectionRepository = UserSelectionRepository(
      database: database,
      userCacheService: userCacheService,
    );

    // Register device
    await authRepository.registerDevice();

    // Replace loading app with main app
    runApp(MyApp(
      teamRepository: teamRepository,
      eventRepository: eventRepository,
      assignmentRepository: assignmentRepository,
      authRepository: authRepository,
      userSelectionRepository: userSelectionRepository,
    ));
  } catch (e) {
    debugPrint('Initialization error: $e');
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
    debugPrint('Failed to preload Rubik font: $e');
  }
}

class MyApp extends StatelessWidget {
  final TeamRepository teamRepository;
  final EventRepository eventRepository;
  final AssignmentRepository assignmentRepository;
  final AuthRepository authRepository;
  final UserSelectionRepository userSelectionRepository;

  const MyApp({
    super.key,
    required this.teamRepository,
    required this.eventRepository,
    required this.assignmentRepository,
    required this.authRepository,
    required this.userSelectionRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: teamRepository),
        RepositoryProvider.value(value: eventRepository),
        RepositoryProvider.value(value: assignmentRepository),
        RepositoryProvider.value(value: authRepository),
        RepositoryProvider.value(value: userSelectionRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => TeamBloc(teamRepository, assignmentRepository),
          ),
          BlocProvider(
            create: (context) => EventBloc(eventRepository, assignmentRepository),
          ),
          BlocProvider(
            create: (context) => AssignmentBloc(
              assignmentRepository,
              eventRepository,
              teamRepository,
            ),
          ),
          BlocProvider(
            create: (context) => UserSelectionBloc(userSelectionRepository, teamRepository),
          ),
        ],
        child: Builder(
          builder: (context) {
            final userSelectionBloc = context.read<UserSelectionBloc>();
            final userSelectionRepository = context.read<UserSelectionRepository>();
            return MaterialApp.router(
              title: 'שבצק - ניהול צוות',
              theme: AppTheme.lightTheme,
              debugShowCheckedModeBanner: false,
              routerConfig: AppRouter.router(
                userSelectionBloc: userSelectionBloc,
                userSelectionRepository: userSelectionRepository,
              ),
            );
          },
        ),
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
