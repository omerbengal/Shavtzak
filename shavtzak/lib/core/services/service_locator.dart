import '../services/environment_service.dart';
import 'environment_aware_factory.dart';
import '../../data/repositories/team_repository.dart';
import '../../presentation/bloc/calendar_sync/calendar_sync_bloc.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/assignment_repository.dart';
import '../../data/repositories/assignment_label_repository.dart';
import '../../data/repositories/user_selection_repository.dart';
import '../../presentation/bloc/team/team_bloc.dart';
import '../../presentation/bloc/event/event_bloc.dart';
import '../../presentation/bloc/assignment/assignment_bloc.dart';
import '../../presentation/bloc/user_selection/user_selection_bloc.dart';
import '../../domain/entities/team_member.dart';

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
  TeamRepository createTeamRepository() =>
      EnvironmentAwareFactory.createTeamRepository();

  /// Create event repository
  EventRepository createEventRepository() =>
      EnvironmentAwareFactory.createEventRepository();

  /// Create assignment repository
  AssignmentRepository createAssignmentRepository() =>
      EnvironmentAwareFactory.createAssignmentRepository();

  /// Create assignment label repository
  AssignmentLabelRepository createAssignmentLabelRepository() =>
      EnvironmentAwareFactory.createAssignmentLabelRepository();

  /// Create user selection repository
  UserSelectionRepository createUserSelectionRepository() =>
      EnvironmentAwareFactory.createUserSelectionRepository();

  /// Create team BLoC
  TeamBloc createTeamBloc() => EnvironmentAwareFactory.createTeamBloc();

  /// Create event BLoC
  EventBloc createEventBloc() => EnvironmentAwareFactory.createEventBloc();

  /// Create assignment BLoC
  AssignmentBloc createAssignmentBloc({CalendarSyncBloc? calendarSyncBloc}) =>
      EnvironmentAwareFactory.createAssignmentBloc(
          calendarSyncBloc: calendarSyncBloc);

  /// Create user selection BLoC
  UserSelectionBloc createUserSelectionBloc({
    TeamMember? preAuthenticatedUser,
  }) =>
      EnvironmentAwareFactory.createUserSelectionBloc(
        preAuthenticatedUser: preAuthenticatedUser,
      );

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
