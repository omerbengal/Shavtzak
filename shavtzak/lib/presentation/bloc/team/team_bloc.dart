import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/team_repository.dart';
import '../../../domain/entities/team_member.dart';
import 'team_event.dart';
import 'team_state.dart';

/// BLoC for managing team members
class TeamBloc extends Bloc<TeamEvent, TeamState> {
  final TeamRepository _repository;

  TeamBloc(this._repository) : super(const TeamInitial()) {
    // Register event handlers - using emit.forEach for real-time updates
    on<LoadTeamMembers>(_onLoadTeamMembers);
    on<LoadActiveTeamMembers>(_onLoadActiveTeamMembers);
    on<SearchTeamMembers>(_onSearchTeamMembers);
    on<LoadTeamMemberById>(_onLoadTeamMemberById);
    on<CreateTeamMember>(_onCreateTeamMember);
    on<UpdateTeamMember>(_onUpdateTeamMember);
    on<DeleteTeamMember>(_onDeleteTeamMember);
    on<DeactivateTeamMember>(_onDeactivateTeamMember);
    on<ReactivateTeamMember>(_onReactivateTeamMember);
    on<RefreshTeamMembers>(_onRefreshTeamMembers);
  }

  /// Load all team members with real-time updates
  Future<void> _onLoadTeamMembers(
    LoadTeamMembers event,
    Emitter<TeamState> emit,
  ) async {
    emit(const TeamLoading());

    try {
      // Use emit.forEach to subscribe to real-time stream
      await emit.forEach<List<TeamMember>>(
        _repository.watchTeamMembers(),
        onData: (members) {
          if (members.isEmpty) {
            return const TeamEmpty('אין חברי צוות במערכת');
          } else {
            return TeamLoaded(members);
          }
        },
        onError: (error, stackTrace) {
          return TeamError('שגיאה בטעינת חברי הצוות: $error');
        },
      );
    } catch (e) {
      emit(TeamError('שגיאה בטעינת חברי הצוות: $e'));
    }
  }

  /// Load active team members only
  Future<void> _onLoadActiveTeamMembers(
    LoadActiveTeamMembers event,
    Emitter<TeamState> emit,
  ) async {
    emit(const TeamLoading());

    try {
      final members = await _repository.getActiveTeamMembers();

      if (members.isEmpty) {
        emit(const TeamEmpty('אין חברי צוות פעילים במערכת'));
      } else {
        emit(TeamLoaded(members));
      }
    } catch (e) {
      emit(TeamError('שגיאה בטעינת חברי הצוות: $e'));
    }
  }

  /// Search team members
  Future<void> _onSearchTeamMembers(
    SearchTeamMembers event,
    Emitter<TeamState> emit,
  ) async {
    emit(const TeamLoading());

    try {
      final members = await _repository.searchTeamMembers(event.query);

      if (members.isEmpty) {
        emit(const TeamEmpty('לא נמצאו חברי צוות'));
      } else {
        emit(TeamLoaded(members, searchQuery: event.query));
      }
    } catch (e) {
      emit(TeamError('שגיאה בחיפוש: $e'));
    }
  }

  /// Load team member by ID
  Future<void> _onLoadTeamMemberById(
    LoadTeamMemberById event,
    Emitter<TeamState> emit,
  ) async {
    emit(const TeamLoading());

    try {
      final member = await _repository.getTeamMemberById(event.id);

      if (member == null) {
        emit(TeamError('חבר/ת צוות לא נמצא/ה'));
      } else {
        emit(TeamMemberDetailLoaded(member));
      }
    } catch (e) {
      emit(TeamError('שגיאה בטעינת פרטי חבר/ת הצוות: $e'));
    }
  }

  /// Create new team member
  Future<void> _onCreateTeamMember(
    CreateTeamMember event,
    Emitter<TeamState> emit,
  ) async {
    emit(const TeamMemberOperating('creating'));

    try {
      await _repository.createTeamMember(event.member);
      emit(const TeamMemberOperationSuccess('חבר/ת הצוות נוסף/ה בהצלחה'));
      // Restart real-time listener
      add(const LoadTeamMembers());
    } catch (e) {
      emit(TeamError('שגיאה בהוספת חבר/ת צוות: $e'));
    }
  }

  /// Update team member
  Future<void> _onUpdateTeamMember(
    UpdateTeamMember event,
    Emitter<TeamState> emit,
  ) async {
    emit(const TeamMemberOperating('updating'));

    try {
      await _repository.updateTeamMember(event.member);
      emit(const TeamMemberOperationSuccess('פרטי חבר/ת הצוות עודכנו בהצלחה'));
      // Restart real-time listener
      add(const LoadTeamMembers());
    } catch (e) {
      emit(TeamError('שגיאה בעדכון פרטי חבר/ת הצוות: $e'));
    }
  }

  /// Delete team member
  Future<void> _onDeleteTeamMember(
    DeleteTeamMember event,
    Emitter<TeamState> emit,
  ) async {
    emit(const TeamMemberOperating('deleting'));

    try {
      await _repository.deleteTeamMember(event.id);
      emit(const TeamMemberOperationSuccess('חבר/ת הצוות נמחק/ה בהצלחה'));
      // Restart real-time listener
      add(const LoadTeamMembers());
    } catch (e) {
      emit(TeamError('שגיאה במחיקת חבר/ת הצוות: $e'));
    }
  }

  /// Deactivate team member
  Future<void> _onDeactivateTeamMember(
    DeactivateTeamMember event,
    Emitter<TeamState> emit,
  ) async {
    emit(const TeamMemberOperating('deactivating'));

    try {
      await _repository.deactivateTeamMember(event.id);
      emit(const TeamMemberOperationSuccess('חבר/ת הצוות הוסר/ה מרשימת הפעילים'));
      // Restart real-time listener
      add(const LoadTeamMembers());
    } catch (e) {
      emit(TeamError('שגיאה בהסרת חבר/ת הצוות: $e'));
    }
  }

  /// Reactivate team member
  Future<void> _onReactivateTeamMember(
    ReactivateTeamMember event,
    Emitter<TeamState> emit,
  ) async {
    emit(const TeamMemberOperating('reactivating'));

    try {
      await _repository.reactivateTeamMember(event.id);
      emit(const TeamMemberOperationSuccess('חבר/ת הצוות הופעל/ה מחדש'));
      // Restart real-time listener
      add(const LoadTeamMembers());
    } catch (e) {
      emit(TeamError('שגיאה בהפעלת חבר/ת הצוות: $e'));
    }
  }

  /// Refresh team members
  Future<void> _onRefreshTeamMembers(
    RefreshTeamMembers event,
    Emitter<TeamState> emit,
  ) async {
    // Simply reload
    add(const LoadTeamMembers());
  }
}
