import 'dart:async';
import 'dart:developer' as developer;
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../../data/repositories/checklist_repository.dart';
import '../../../core/services/checklist_permission_service.dart';
import '../user_selection/user_selection_bloc.dart';
import '../user_selection/user_selection_state.dart';

part 'checklist_event.dart';
part 'checklist_state.dart';

/// BLoC for managing checklist items
class ChecklistBloc extends Bloc<ChecklistEvent, ChecklistState> {
  final ChecklistRepository _repository;
  final UserSelectionBloc _userSelectionBloc;

  // Expose repository for direct stream access
  ChecklistRepository get repository => _repository;

  ChecklistBloc({
    required ChecklistRepository repository,
    required UserSelectionBloc userSelectionBloc,
  })  : _repository = repository,
        _userSelectionBloc = userSelectionBloc,
        super(ChecklistInitial()) {
    on<LoadChecklistItems>(_onLoadChecklistItems);
    on<LoadChecklistItemsByEvent>(_onLoadChecklistItemsByEvent);
    on<LoadUserChecklistItems>(_onLoadUserChecklistItems);
    on<AddChecklistItem>(_onAddChecklistItem);
    on<UpdateChecklistItem>(_onUpdateChecklistItem);
    on<UpdateChecklistItemStatus>(_onUpdateChecklistItemStatus);
    on<AddChecklistNote>(_onAddChecklistNote);
    on<AddCcMember>(_onAddCcMember);
    on<RemoveCcMember>(_onRemoveCcMember);
    on<DeleteChecklistItem>(_onDeleteChecklistItem);
    on<RefreshChecklistItems>(_onRefreshChecklistItems);
  }

  Future<void> _onLoadChecklistItems(
    LoadChecklistItems event,
    Emitter<ChecklistState> emit,
  ) async {
    try {
      emit(ChecklistLoading());

      // Use emit.forEach for proper stream handling
      await emit.forEach(
        _repository.watchChecklistItems(),
        onData: (items) {
          return ChecklistLoaded(items);
        },
        onError: (error, stackTrace) {
          developer.log('ChecklistBloc: Error loading checklist items: $error',
              name: 'Checklist', error: error, stackTrace: stackTrace);
          return ChecklistError('Failed to load checklist items: $error');
        },
      );
    } catch (e) {
      developer.log('ChecklistBloc: Error in _onLoadChecklistItems: $e',
          name: 'Checklist', error: e);
      emit(ChecklistError('Failed to load checklist items: $e'));
    }
  }

  Future<void> _onLoadChecklistItemsByEvent(
    LoadChecklistItemsByEvent event,
    Emitter<ChecklistState> emit,
  ) async {
    try {
      emit(ChecklistLoading());

      // Use emit.forEach for proper stream handling
      await emit.forEach(
        _repository.watchChecklistItemsByEvent(event.eventId),
        onData: (items) {
          return ChecklistLoaded(items);
        },
        onError: (error, stackTrace) {
          developer.log(
              'ChecklistBloc: Error loading checklist items for event: $error',
              name: 'Checklist',
              error: error,
              stackTrace: stackTrace);
          return ChecklistError(
              'Failed to load checklist items for event: $error');
        },
      );
    } catch (e) {
      developer.log('ChecklistBloc: Error in _onLoadChecklistItemsByEvent: $e',
          name: 'Checklist', error: e);
      emit(ChecklistError('Failed to load checklist items for event: $e'));
    }
  }

  Future<void> _onLoadUserChecklistItems(
    LoadUserChecklistItems event,
    Emitter<ChecklistState> emit,
  ) async {
    try {
      emit(ChecklistLoading());

      // Use emit.forEach for proper stream handling
      await emit.forEach(
        _repository.watchChecklistItemsForUser(event.teamMemberId),
        onData: (result) {
          final responsibleItems = result['responsible'] as List<ChecklistItem>;
          final ccItems = result['cc'] as List<ChecklistItem>;

          return UserChecklistLoaded(
            responsibleItems: responsibleItems,
            ccItems: ccItems,
          );
        },
        onError: (error, stackTrace) {
          developer.log(
              'ChecklistBloc: Error loading user checklist items: $error',
              name: 'Checklist',
              error: error,
              stackTrace: stackTrace);
          return ChecklistError('Failed to load your checklist items: $error');
        },
      );
    } catch (e) {
      developer.log('ChecklistBloc: Error in _onLoadUserChecklistItems: $e',
          name: 'Checklist', error: e);
      emit(ChecklistError('Failed to load your checklist items: $e'));
    }
  }

  Future<void> _onAddChecklistItem(
    AddChecklistItem event,
    Emitter<ChecklistState> emit,
  ) async {
    try {
      // Validate permissions
      final currentUser = _getCurrentUser();
      if (currentUser == null || !currentUser.isAdmin) {
        _completeActionFailure(
          event.completion,
          'רק מנהלים יכולים להוסיף פריטי צ\'קליסט',
          emit: emit,
        );
        return;
      }

      final item = event.item.copyWith(
        id: const Uuid().v4(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        statusLastUpdatedAt: DateTime.now(),
      );

      await _repository.createChecklistItem(item);
      _completeActionSuccess(event.completion, 'פריט הצ\'קליסט נוצר בהצלחה');
    } catch (e) {
      final message = 'שגיאה בהוספת פריט צ\'קליסט: $e';
      developer.log(
        'ChecklistBloc: Error adding checklist item: $e',
        name: 'Checklist',
        error: e,
      );
      _completeActionFailure(event.completion, message, emit: emit);
    }
  }

  Future<void> _onUpdateChecklistItem(
    UpdateChecklistItem event,
    Emitter<ChecklistState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null) {
        _completeActionFailure(
          event.completion,
          'המשתמש אינו מחובר',
          emit: emit,
        );
        return;
      }

      // Check permissions
      if (!event.item.userCanEdit(currentUser.id, currentUser.isAdmin)) {
        _completeActionFailure(
          event.completion,
          'אין לך הרשאה לערוך את הפריט הזה',
          emit: emit,
        );
        return;
      }

      final updatedItem = event.item.copyWith(
        updatedAt: DateTime.now(),
      );

      await _repository.updateChecklistItem(updatedItem);
      _completeActionSuccess(event.completion, 'פריט הצ\'קליסט עודכן בהצלחה');
    } catch (e) {
      final message = 'שגיאה בעדכון פריט צ\'קליסט: $e';
      developer.log(
        'ChecklistBloc: Error updating checklist item: $e',
        name: 'Checklist',
        error: e,
      );
      _completeActionFailure(event.completion, message, emit: emit);
    }
  }

  Future<void> _onUpdateChecklistItemStatus(
    UpdateChecklistItemStatus event,
    Emitter<ChecklistState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null) {
        emit(ChecklistError('User not authenticated'));
        return;
      }

      // Get the item to check permissions
      final item = await _repository.getChecklistItemById(event.itemId);
      if (item == null) {
        emit(ChecklistError('Checklist item not found'));
        return;
      }

      // Check permissions using ChecklistPermissionService (allows responsible, admins, and CC members)
      if (!ChecklistPermissionService.canUpdateStatus(item, currentUser)) {
        emit(ChecklistError('אין לך הרשאה לעדכן את הסטטוס של פריט זה'));
        return;
      }

      final updatedItem = item.withUpdatedStatus(event.newStatus);
      await _repository.updateChecklistItem(updatedItem);
    } catch (e) {
      developer.log('ChecklistBloc: Error updating checklist item status: $e',
          name: 'Checklist', error: e);
      emit(ChecklistError('Failed to update status: $e'));
    }
  }

  Future<void> _onAddChecklistNote(
    AddChecklistNote event,
    Emitter<ChecklistState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null) {
        emit(ChecklistError('User not authenticated'));
        return;
      }

      if (event.content.trim().isEmpty) return;

      await _repository.addNoteToChecklistItem(
        checklistItemId: event.itemId,
        content: event.content.trim(),
        teamMemberId: currentUser.id,
        teamMemberName: currentUser.name,
        authorRole: event.authorRole,
      );
    } catch (e) {
      developer.log('ChecklistBloc: Error adding note to checklist item: $e',
          name: 'Checklist', error: e);
      emit(ChecklistError('Failed to add note: $e'));
    }
  }

  Future<void> _onAddCcMember(
    AddCcMember event,
    Emitter<ChecklistState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null) {
        emit(ChecklistError('User not authenticated'));
        return;
      }

      // Get the item
      final item = await _repository.getChecklistItemById(event.itemId);
      if (item == null) {
        emit(ChecklistError('Checklist item not found'));
        return;
      }

      // Check permissions (responsible person or admin can add CC members)
      if (!item.userCanEdit(currentUser.id, currentUser.isAdmin)) {
        emit(ChecklistError('You do not have permission to add CC members'));
        return;
      }

      final updatedItem = item.withAddedCc(event.ccMemberId);
      await _repository.updateChecklistItem(updatedItem);
    } catch (e) {
      developer.log('ChecklistBloc: Error adding CC member: $e',
          name: 'Checklist', error: e);
      emit(ChecklistError('Failed to add CC member: $e'));
    }
  }

  Future<void> _onRemoveCcMember(
    RemoveCcMember event,
    Emitter<ChecklistState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null) {
        emit(ChecklistError('User not authenticated'));
        return;
      }

      // Get the item
      final item = await _repository.getChecklistItemById(event.itemId);
      if (item == null) {
        emit(ChecklistError('Checklist item not found'));
        return;
      }

      // Check permissions (responsible person or admin can remove CC members)
      if (!item.userCanEdit(currentUser.id, currentUser.isAdmin)) {
        emit(ChecklistError('You do not have permission to remove CC members'));
        return;
      }

      final updatedItem = item.withRemovedCc(event.ccMemberId);
      await _repository.updateChecklistItem(updatedItem);
    } catch (e) {
      developer.log('ChecklistBloc: Error removing CC member: $e',
          name: 'Checklist', error: e);
      emit(ChecklistError('Failed to remove CC member: $e'));
    }
  }

  Future<void> _onDeleteChecklistItem(
    DeleteChecklistItem event,
    Emitter<ChecklistState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null || !currentUser.isAdmin) {
        _completeActionFailure(
          event.completion,
          'רק מנהלים יכולים למחוק פריטי צ\'קליסט',
          emit: emit,
        );
        return;
      }

      await _repository.deleteChecklistItem(event.itemId);
      _completeActionSuccess(event.completion, 'פריט הצ\'קליסט נמחק בהצלחה');
    } catch (e) {
      final message = 'שגיאה במחיקת פריט צ\'קליסט: $e';
      developer.log(
        'ChecklistBloc: Error deleting checklist item: $e',
        name: 'Checklist',
        error: e,
      );
      _completeActionFailure(event.completion, message, emit: emit);
    }
  }

  Future<void> _onRefreshChecklistItems(
    RefreshChecklistItems event,
    Emitter<ChecklistState> emit,
  ) async {
    // The real-time streams will automatically refresh,
    // but we can trigger a manual reload if needed
    if (state is ChecklistLoaded) {
      add(LoadChecklistItems());
    } else if (state is UserChecklistLoaded) {
      final currentUser = _getCurrentUser();
      if (currentUser != null) {
        add(LoadUserChecklistItems(currentUser.id));
      }
    }
  }

  TeamMember? _getCurrentUser() {
    final userState = _userSelectionBloc.state;
    if (userState is UserAuthenticated) {
      return userState.user;
    }
    return null;
  }

  void _completeActionSuccess(
    CrudActionCompleter? completion, [
    String? message,
  ]) {
    completeCrudAction(completion, CrudActionResult.success(message));
  }

  void _completeActionFailure(
    CrudActionCompleter? completion,
    String message, {
    Emitter<ChecklistState>? emit,
  }) {
    completeCrudAction(completion, CrudActionResult.failure(message));
    if (completion == null && emit != null) {
      emit(ChecklistError(message));
    }
  }

  @override
  Future<void> close() {
    _repository.dispose();
    return super.close();
  }
}
