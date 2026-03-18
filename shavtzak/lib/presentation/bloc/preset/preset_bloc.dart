import 'dart:developer' as developer;
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../domain/entities/preset.dart';
import '../../../domain/entities/team_member.dart';
import '../../../data/repositories/preset_repository.dart';
import '../../../data/repositories/event_repository.dart';
import '../user_selection/user_selection_bloc.dart';
import '../user_selection/user_selection_state.dart';

part 'preset_event.dart';
part 'preset_state.dart';

/// BLoC for managing checklist presets
class PresetBloc extends Bloc<PresetEvent, PresetState> {
  final PresetRepository _repository;
  final EventRepository _eventRepository;
  final UserSelectionBloc _userSelectionBloc;

  PresetBloc({
    required PresetRepository repository,
    required EventRepository eventRepository,
    required UserSelectionBloc userSelectionBloc,
  })  : _repository = repository,
        _eventRepository = eventRepository,
        _userSelectionBloc = userSelectionBloc,
        super(PresetInitial()) {
    on<LoadPresets>(_onLoadPresets);
    on<CreatePreset>(_onCreatePreset);
    on<UpdatePreset>(_onUpdatePreset);
    on<DeletePreset>(_onDeletePreset);
    on<LoadPresetIntoEvent>(_onLoadPresetIntoEvent);
  }

  TeamMember? _getCurrentUser() {
    final userState = _userSelectionBloc.state;
    if (userState is UserAuthenticated) {
      return userState.user;
    }
    return null;
  }

  Future<void> _onLoadPresets(
    LoadPresets event,
    Emitter<PresetState> emit,
  ) async {
    try {
      emit(PresetLoading());

      await emit.forEach(
        _repository.watchPresets(),
        onData: (presets) {
          return PresetsLoaded(presets);
        },
        onError: (error, stackTrace) {
          developer.log('PresetBloc: Error loading presets: $error',
              name: 'Preset', error: error, stackTrace: stackTrace);
          return PresetError('נכשל בטעינת פריסטים: $error');
        },
      );
    } catch (e) {
      developer.log('PresetBloc: Error in _onLoadPresets: $e',
          name: 'Preset', error: e);
      emit(PresetError('נכשל בטעינת פריסטים: $e'));
    }
  }

  Future<void> _onCreatePreset(
    CreatePreset event,
    Emitter<PresetState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null || !currentUser.isAdmin) {
        _completeActionFailure(
          event.completion,
          'רק מנהלים יכולים ליצור פריסטים',
          emit: emit,
        );
        return;
      }

      final now = DateTime.now();
      final preset = Preset(
        id: const Uuid().v4(),
        name: event.preset.name,
        items: event.preset.items,
        createdAt: now,
        updatedAt: now,
      );

      await _repository.createPreset(preset);
      _completeActionSuccess(event.completion, 'הפריסט נוצר בהצלחה');
    } catch (e) {
      final message = 'נכשל ביצירת פריסט: $e';
      developer.log(
        'PresetBloc: Error creating preset: $e',
        name: 'Preset',
        error: e,
      );
      _completeActionFailure(event.completion, message, emit: emit);
    }
  }

  Future<void> _onUpdatePreset(
    UpdatePreset event,
    Emitter<PresetState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null || !currentUser.isAdmin) {
        _completeActionFailure(
          event.completion,
          'רק מנהלים יכולים לערוך פריסטים',
          emit: emit,
        );
        return;
      }

      final preset = event.preset.copyWith(updatedAt: DateTime.now());
      await _repository.updatePreset(preset);
      _completeActionSuccess(event.completion, 'הפריסט עודכן בהצלחה');
    } catch (e) {
      final message = 'נכשל בעדכון פריסט: $e';
      developer.log(
        'PresetBloc: Error updating preset: $e',
        name: 'Preset',
        error: e,
      );
      _completeActionFailure(event.completion, message, emit: emit);
    }
  }

  Future<void> _onDeletePreset(
    DeletePreset event,
    Emitter<PresetState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null || !currentUser.isAdmin) {
        _completeActionFailure(
          event.completion,
          'רק מנהלים יכולים למחוק פריסטים',
          emit: emit,
        );
        return;
      }

      await _repository.deletePreset(event.presetId);
      _completeActionSuccess(event.completion, 'הפריסט נמחק בהצלחה');
    } catch (e) {
      final message = 'נכשל במחיקת פריסט: $e';
      developer.log(
        'PresetBloc: Error deleting preset: $e',
        name: 'Preset',
        error: e,
      );
      _completeActionFailure(event.completion, message, emit: emit);
    }
  }

  Future<void> _onLoadPresetIntoEvent(
    LoadPresetIntoEvent event,
    Emitter<PresetState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null || !currentUser.isAdmin) {
        _completeActionFailure(
          event.completion,
          'רק מנהלים יכולים לטעון פריסטים',
          emit: emit,
        );
        return;
      }

      // Get preset and event for success message
      final preset = await _repository.getPresetById(event.presetId);
      if (preset == null) {
        _completeActionFailure(
          event.completion,
          'הפריסט לא נמצא',
          emit: emit,
        );
        return;
      }

      final targetEvent = await _eventRepository.getEventById(event.eventId);
      if (targetEvent == null) {
        _completeActionFailure(
          event.completion,
          'האירוע לא נמצא',
          emit: emit,
        );
        return;
      }

      await _repository.loadPresetIntoEvent(
        event.presetId,
        event.eventId,
        currentUser.id,
      );

      final successState = PresetLoadedIntoEvent(
        presetName: preset.name,
        eventName: targetEvent.name,
        itemCount: preset.items.length,
      );
      if (event.completion == null) {
        emit(successState);
      } else {
        _completeActionSuccess(
          event.completion,
          'נטענו ${preset.items.length} פריטים מ-"${preset.name}" לאירוע "${targetEvent.name}"',
        );
      }
    } catch (e) {
      final message = 'נכשל בטעינת פריסט לאירוע: $e';
      developer.log(
        'PresetBloc: Error loading preset into event: $e',
        name: 'Preset',
        error: e,
      );
      _completeActionFailure(event.completion, message, emit: emit);
    }
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
    Emitter<PresetState>? emit,
  }) {
    completeCrudAction(completion, CrudActionResult.failure(message));
    if (completion == null && emit != null) {
      emit(PresetError(message));
    }
  }

  @override
  Future<void> close() {
    _repository.dispose();
    return super.close();
  }
}
