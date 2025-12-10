import '../services/environment_service.dart';
import 'environment_aware_factory.dart';

/// Simple service locator for dependency injection
/// Centralizes all service creation and ensures single instances
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  /// Initialize all services
  /// This should be called once during app startup
  Future<void> initialize() async {
    // Environment-aware factory uses static methods, no instance needed
  }

  /// Create team repository
  TeamRepository createTeamRepository() => EnvironmentAwareFactory.createTeamRepository();

  /// Create event repository
  EventRepository createEventRepository() => EnvironmentAwareFactory.createEventRepository();

  /// Create assignment repository
  AssignmentRepository createAssignmentRepository() => EnvironmentAwareFactory.createAssignmentRepository();

  /// Create user selection repository
  UserSelectionRepository createUserSelectionRepository() => EnvironmentAwareFactory.createUserSelectionRepository();

  /// Create team BLoC
  TeamBloc createTeamBloc() => EnvironmentAwareFactory.createTeamBloc();

  /// Create event BLoC
  EventBloc createEventBloc() => EnvironmentAwareFactory.createEventBloc();

  /// Create assignment BLoC
  AssignmentBloc createAssignmentBloc() => EnvironmentAwareFactory.createAssignmentBloc();

  /// Create user selection BLoC
  UserSelectionBloc createUserSelectionBloc() => EnvironmentAwareFactory.createUserSelectionBloc();

  /// Reset all services
  /// Useful for environment switching or testing
  void reset() {
    EnvironmentAwareFactory.reset();
  }
}

/// Global service locator instance
final serviceLocator = ServiceLocator();

/// Helper to get current environment service
EnvironmentService get environmentService => EnvironmentService.instance;