import '../../../data/repositories/team_repository.dart';
import '../../../data/repositories/event_repository.dart';
import '../../../data/repositories/assignment_repository.dart';
import '../../../data/repositories/assignment_label_repository.dart';
import '../../../data/repositories/user_selection_repository.dart';
import '../../../data/repositories/role_repository.dart';
import '../../../data/data_sources/firestore_database.dart';
import '../../../data/data_sources/database_interface.dart';
import '../../../presentation/bloc/team/team_bloc.dart';
import '../../../presentation/bloc/event/event_bloc.dart';
import '../../../presentation/bloc/assignment/assignment_bloc.dart';
import '../../../presentation/bloc/user_selection/user_selection_bloc.dart';
import '../../../presentation/bloc/calendar_sync/calendar_sync_bloc.dart';
import '../../../domain/entities/team_member.dart';
import 'user_cache_service.dart';

/// Factory that creates environment-aware instances
/// This is the single point where test vs production logic is decided
class EnvironmentAwareFactory {
  static DatabaseInterface? _database;

  /// Get the appropriate database instance (cached)
  static DatabaseInterface get database {
    _database ??= FirestoreDatabase();
    return _database!;
  }

  /// Create team repository based on environment
  static TeamRepository createTeamRepository() {
    final db = database;
    // For now, return standard repository. Test repositories can be added later.
    return TeamRepository(db);
  }

  /// Create event repository based on environment
  static EventRepository createEventRepository() {
    final db = database;
    // For now, return standard repository. Test repositories can be added later.
    return EventRepository(db);
  }

  /// Create assignment repository based on environment
  static AssignmentRepository createAssignmentRepository() {
    final db = database;
    // For now, return standard repository. Test repositories can be added later.
    return AssignmentRepository(db);
  }

  /// Create assignment label repository based on environment
  static AssignmentLabelRepository createAssignmentLabelRepository() {
    final db = database;
    return AssignmentLabelRepository(db);
  }

  /// Create role repository based on environment
  static RoleRepository createRoleRepository() {
    final db = database;
    return RoleRepository(db);
  }

  /// Create user selection repository (same for both environments)
  static UserSelectionRepository createUserSelectionRepository() {
    return UserSelectionRepository(
      database: database,
      userCacheService: UserCacheService(),
    );
  }

  /// Create team BLoC based on environment
  static TeamBloc createTeamBloc() {
    // For now, return standard bloc. Test blocs can be added later.
    return TeamBloc(createTeamRepository(), createAssignmentRepository());
  }

  /// Create event BLoC based on environment
  static EventBloc createEventBloc() {
    // For now, return standard bloc. Test blocs can be added later.
    return EventBloc(createEventRepository(), createAssignmentRepository());
  }

  /// Create assignment BLoC based on environment
  static AssignmentBloc createAssignmentBloc({CalendarSyncBloc? calendarSyncBloc}) {
    // For now, return standard bloc. Test blocs can be added later.
    return AssignmentBloc(
      createAssignmentRepository(),
      createEventRepository(),
      createTeamRepository(),
      createRoleRepository(),
      calendarSyncBloc,
    );
  }

  /// Create user selection BLoC (same for both environments)
  static UserSelectionBloc createUserSelectionBloc({
    CalendarSyncBloc? calendarSyncBloc,
    TeamMember? preAuthenticatedUser,
  }) {
    return UserSelectionBloc(
      createUserSelectionRepository(),
      createTeamRepository(),
      calendarSyncBloc,
      preAuthenticatedUser,
    );
  }

  /// Reset all cached instances (useful for testing or environment switching)
  static void reset() {
    _database = null;
  }
}
