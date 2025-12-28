import 'dart:developer' as developer;
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
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
          developer.log('PresetBloc: Loaded ${presets.length} presets', name: 'Preset');
          return PresetsLoaded(presets);
        },
        onError: (error, stackTrace) {
          developer.log('Error loading presets: $error', name: 'Preset', error: error, stackTrace: stackTrace);
          return PresetError('נכשל בטעינת פריסטים: $error');
        },
      );
    } catch (e) {
      developer.log('Error in _onLoadPresets: $e', name: 'Preset');
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
        emit(const PresetError('רק מנהלים יכולים ליצור פריסטים'));
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
      developer.log('PresetBloc: Created preset ${preset.id} (${preset.name})', name: 'Preset');

      // Re-emit current state to trigger UI update (the stream will handle the rest)
    } catch (e) {
      developer.log('Error creating preset: $e', name: 'Preset');
      emit(PresetError('נכשל ביצירת פריסט: $e'));
    }
  }

  Future<void> _onUpdatePreset(
    UpdatePreset event,
    Emitter<PresetState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null || !currentUser.isAdmin) {
        emit(const PresetError('רק מנהלים יכולים לערוך פריסטים'));
        return;
      }

      final preset = event.preset.copyWith(updatedAt: DateTime.now());
      await _repository.updatePreset(preset);
      developer.log('PresetBloc: Updated preset ${preset.id} (${preset.name})', name: 'Preset');
    } catch (e) {
      developer.log('Error updating preset: $e', name: 'Preset');
      emit(PresetError('נכשל בעדכון פריסט: $e'));
    }
  }

  Future<void> _onDeletePreset(
    DeletePreset event,
    Emitter<PresetState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null || !currentUser.isAdmin) {
        emit(const PresetError('רק מנהלים יכולים למחוק פריסטים'));
        return;
      }

      await _repository.deletePreset(event.presetId);
      developer.log('PresetBloc: Deleted preset ${event.presetId}', name: 'Preset');
    } catch (e) {
      developer.log('Error deleting preset: $e', name: 'Preset');
      emit(PresetError('נכשל במחיקת פריסט: $e'));
    }
  }

  Future<void> _onLoadPresetIntoEvent(
    LoadPresetIntoEvent event,
    Emitter<PresetState> emit,
  ) async {
    try {
      final currentUser = _getCurrentUser();
      if (currentUser == null || !currentUser.isAdmin) {
        emit(const PresetError('רק מנהלים יכולים לטעון פריסטים'));
        return;
      }

      // Get preset and event for success message
      final preset = await _repository.getPresetById(event.presetId);
      if (preset == null) {
        emit(const PresetError('הפריסט לא נמצא'));
        return;
      }

      final targetEvent = await _eventRepository.getEventById(event.eventId);
      if (targetEvent == null) {
        emit(const PresetError('האירוע לא נמצא'));
        return;
      }

      await _repository.loadPresetIntoEvent(
        event.presetId,
        event.eventId,
        currentUser.id,
      );

      developer.log('PresetBloc: Loaded preset "${preset.name}" into event "${targetEvent.name}"', name: 'Preset');

      emit(PresetLoadedIntoEvent(
        presetName: preset.name,
        eventName: targetEvent.name,
        itemCount: preset.items.length,
      ));
    } catch (e) {
      developer.log('Error loading preset into event: $e', name: 'Preset');
      emit(PresetError('נכשל בטעינת פריסט לאירוע: $e'));
    }
  }

  @override
  Future<void> close() {
    _repository.dispose();
    return super.close();
  }
}
