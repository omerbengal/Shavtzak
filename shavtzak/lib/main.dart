import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'firebase_options.dart';

// Data layer
import 'data/data_sources/firestore_database.dart';
import 'data/repositories/team_repository.dart';
import 'data/repositories/event_repository.dart';
import 'data/repositories/assignment_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'core/utils/device_id.dart';

// Presentation layer
import 'presentation/bloc/team/team_bloc.dart';
import 'presentation/bloc/event/event_bloc.dart';
import 'presentation/bloc/assignment/assignment_bloc.dart';

// Router
import 'core/router/app_router.dart';

// Theme
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use path-based URLs instead of hash-based URLs
  usePathUrlStrategy();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize database
  final database = FirestoreDatabase();
  await database.initialize();

  // Initialize services
  final deviceIdService = DeviceIdService();

  // Initialize repositories
  final teamRepository = TeamRepository(database);
  final eventRepository = EventRepository(database);
  final assignmentRepository = AssignmentRepository(database);
  final authRepository = AuthRepository(database, deviceIdService);

  // Register device
  await authRepository.registerDevice();

  runApp(MyApp(
    teamRepository: teamRepository,
    eventRepository: eventRepository,
    assignmentRepository: assignmentRepository,
    authRepository: authRepository,
  ));
}

class MyApp extends StatelessWidget {
  final TeamRepository teamRepository;
  final EventRepository eventRepository;
  final AssignmentRepository assignmentRepository;
  final AuthRepository authRepository;

  const MyApp({
    super.key,
    required this.teamRepository,
    required this.eventRepository,
    required this.assignmentRepository,
    required this.authRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: teamRepository),
        RepositoryProvider.value(value: eventRepository),
        RepositoryProvider.value(value: assignmentRepository),
        RepositoryProvider.value(value: authRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => TeamBloc(teamRepository, assignmentRepository),
          ),
          BlocProvider(
            create: (context) => EventBloc(eventRepository),
          ),
          BlocProvider(
            create: (context) => AssignmentBloc(
              assignmentRepository,
              eventRepository,
              teamRepository,
            ),
          ),
        ],
        child: MaterialApp.router(
          title: 'שבצק - ניהול צוות',
          theme: AppTheme.lightTheme,
          debugShowCheckedModeBanner: false,
          routerConfig: AppRouter.router,
        ),
      ),
    );
  }
}
