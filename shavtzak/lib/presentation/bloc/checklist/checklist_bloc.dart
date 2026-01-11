import 'dart:async';
import 'dart:developer' as developer;
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../../data/repositories/checklist_repository.dart';
import '../user_selection/user_selection_bloc.dart';
import '../user_selection/user_selection_state.dart';

part 'checklist_event.dart';
part 'checklist_state.dart';

/// BLoC for managing checklist items
class ChecklistBloc extends Bloc<ChecklistEvent, ChecklistState> {
  final ChecklistRepository _repository;
  final UserSelectionBloc _userSelectionBloc;

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
    on<UpdateResponsibleNote>(_onUpdateResponsibleNote);
    on<UpdateCcNote>(_onUpdateCcNote);
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
          developer.log('ChecklistBloc: Loaded ${items.length} items', name: 'Checklist');
          return ChecklistLoaded(items);
        },
        onError: (error, stackTrace) {
          developer.log('Error loading checklist items: $error', name: 'Checklist', error: error, stackTrace: stackTrace);
          return ChecklistError('Failed to load checklist items: $error');
        },
      );
    } catch (e) {
      developer.log('Error in _onLoadChecklistItems: $e', name: 'Checklist');
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
          developer.log('ChecklistBloc: Loaded ${items.length} items for event ${event.eventId}', name: 'Checklist');
          return ChecklistLoaded(items);
        },
        onError: (error, stackTrace) {
          developer.log('Error loading checklist items for event: $error', name: 'Checklist', error: error, stackTrace: stackTrace);
          return ChecklistError('Failed to load checklist items for event: $error');
        },
      );
    } catch (e) {
      developer.log('Error in _onLoadChecklistItemsByEvent: $e', name: 'Checklist');
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

          developer.log('ChecklistBloc: Loaded ${responsibleItems.length} responsible and ${ccItems.length} CC items for user ${event.teamMemberId}', name: 'Checklist');

          // Log details of responsible items
          for (final item in responsibleItems) {
            developer.log('Responsible item: ${item.name} (event: ${item.event?.name})', name: 'Checklist');
          }

          // Log details of CC items
          for (final item in ccItems) {
            developer.log('CC item: ${item.name} (event: ${item.event?.name})', name: 'Checklist');
          }

          return UserChecklistLoaded(
            responsibleItems: responsibleItems,
            ccItems: ccItems,
          );
        },
        onError: (error, stackTrace) {
          developer.log('Error loading user checklist items: $error', name: 'Checklist', error: error, stackTrace: stackTrace);
          return ChecklistError('Failed to load your checklist items: $error');
        },
      );
    } catch (e) {
      developer.log('Error in _onLoadUserChecklistItems: $e', name: 'Checklist');
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
        emit(ChecklistError('Only admins can add checklist items'));
        return;
      }

      final item = event.item.copyWith(
        id: const Uuid().v4(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        statusLastUpdatedAt: DateTime.now(),
      );

      await _repository.createChecklistItem(item);
      developer.log('ChecklistBloc: Created checklist item ${item.id}', name: 'Checklist');
    } catch (e) {
      developer.log('Error adding checklist item: $e', name: 'Checklist');
      emit(ChecklistError('Failed to add checklist item: $e'));
    }
  }

  Future<void> _onUpdateChecklistItem(
    UpdateChecklistItem event,
    Emitter<ChecklistState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null) {
        emit(ChecklistError('User not authenticated'));
        return;
      }

      // Check permissions
      if (!event.item.userCanEdit(currentUser.id, currentUser.isAdmin)) {
        emit(ChecklistError('You do not have permission to edit this item'));
        return;
      }

      final updatedItem = event.item.copyWith(
        updatedAt: DateTime.now(),
      );

      await _repository.updateChecklistItem(updatedItem);
      developer.log('ChecklistBloc: Updated checklist item ${updatedItem.id}', name: 'Checklist');
    } catch (e) {
      developer.log('Error updating checklist item: $e', name: 'Checklist');
      emit(ChecklistError('Failed to update checklist item: $e'));
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

      // Check permissions (responsible person or admin can update status)
      if (!item.userCanEdit(currentUser.id, currentUser.isAdmin)) {
        emit(ChecklistError('You do not have permission to update the status of this item'));
        return;
      }

      final updatedItem = item.withUpdatedStatus(event.newStatus);
      await _repository.updateChecklistItem(updatedItem);
      developer.log('ChecklistBloc: Updated status for item ${event.itemId} to ${event.newStatus}', name: 'Checklist');
    } catch (e) {
      developer.log('Error updating checklist item status: $e', name: 'Checklist');
      emit(ChecklistError('Failed to update status: $e'));
    }
  }

  Future<void> _onUpdateResponsibleNote(
    UpdateResponsibleNote event,
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

      // Check permissions (responsible person or admin can update note)
      if (!item.userCanEdit(currentUser.id, currentUser.isAdmin)) {
        emit(ChecklistError('You do not have permission to update this note'));
        return;
      }

      final updatedItem = item.withUpdatedResponsibleNote(event.note);

      await _repository.updateChecklistItem(updatedItem);
      developer.log('ChecklistBloc: Updated responsible note for item ${event.itemId}', name: 'Checklist');
    } catch (e) {
      developer.log('Error updating responsible note: $e', name: 'Checklist');
      emit(ChecklistError('Failed to update note: $e'));
    }
  }

  Future<void> _onUpdateCcNote(
    UpdateCcNote event,
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

      // Check permissions (CC member can only edit their own note, admin can edit any)
      if (!item.userCanEditCcNote(currentUser.id, event.ccMemberId, currentUser.isAdmin)) {
        emit(ChecklistError('You can only edit your own note'));
        return;
      }

      final updatedItem = item.withUpdatedCcNote(event.ccMemberId, event.note);
      await _repository.updateChecklistItem(updatedItem);
      developer.log('ChecklistBloc: Updated CC note for member ${event.ccMemberId} on item ${event.itemId}', name: 'Checklist');
    } catch (e) {
      developer.log('Error updating CC note: $e', name: 'Checklist');
      emit(ChecklistError('Failed to update note: $e'));
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
      developer.log('ChecklistBloc: Added CC member ${event.ccMemberId} to item ${event.itemId}', name: 'Checklist');
    } catch (e) {
      developer.log('Error adding CC member: $e', name: 'Checklist');
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
      developer.log('ChecklistBloc: Removed CC member ${event.ccMemberId} from item ${event.itemId}', name: 'Checklist');
    } catch (e) {
      developer.log('Error removing CC member: $e', name: 'Checklist');
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
        emit(ChecklistError('Only admins can delete checklist items'));
        return;
      }

      await _repository.deleteChecklistItem(event.itemId);
      developer.log('ChecklistBloc: Deleted checklist item ${event.itemId}', name: 'Checklist');
    } catch (e) {
      developer.log('Error deleting checklist item: $e', name: 'Checklist');
      emit(ChecklistError('Failed to delete checklist item: $e'));
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

  @override
  Future<void> close() {
    _repository.dispose();
    return super.close();
  }
}