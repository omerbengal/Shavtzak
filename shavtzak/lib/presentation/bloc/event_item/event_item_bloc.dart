import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../data/repositories/event_item_repository.dart';
import '../../../domain/entities/event_item.dart';
import 'event_item_event.dart';
import 'event_item_state.dart';

/// The "מה יש באירוע" list, live. Built like CategoryBloc.
class EventItemBloc extends Bloc<EventItemEvent, EventItemState> {
  final EventItemRepository _repository;
  bool _isSubscribed = false;

  /// A reorder writes one item at a time; the stream's in-between lists are
  /// skipped for this long so the list does not jump back and forth.
  DateTime? _lastReorderAt;
  static const _reorderGracePeriod = Duration(milliseconds: 1500);

  EventItemBloc(this._repository) : super(const EventItemInitial()) {
    on<LoadEventItems>(_onLoad);
    on<CreateEventItem>(_onCreate);
    on<UpdateEventItem>((event, emit) => _run(
          event.completion,
          () => _repository.updateEventItem(event.item),
          'הפריט עודכן',
          'שגיאה בעדכון הפריט',
        ));
    on<DeleteEventItem>((event, emit) => _run(
          event.completion,
          () => _repository.deleteEventItem(event.itemId),
          'הפריט הועבר לארכיון',
          'שגיאה בהעברת הפריט לארכיון',
        ));
    on<PermanentlyDeleteEventItem>((event, emit) => _run(
          event.completion,
          () => _repository.permanentlyDeleteEventItem(event.itemId),
          'הפריט נמחק לצמיתות',
          'שגיאה במחיקת הפריט',
        ));
    on<RestoreEventItem>((event, emit) => _run(
          event.completion,
          () => _repository.restoreEventItem(event.itemId),
          'הפריט שוחזר',
          'שגיאה בשחזור הפריט',
        ));
    on<ReorderEventItems>(_onReorder);
  }

  Future<void> _onLoad(LoadEventItems event, Emitter<EventItemState> emit) async {
    if (_isSubscribed) return;
    _isSubscribed = true;
    emit(const EventItemLoading());
    await emit.forEach<List<EventItem>>(
      _repository.watchEventItems(),
      onData: (items) {
        final reorderAt = _lastReorderAt;
        if (reorderAt != null) {
          if (DateTime.now().difference(reorderAt) < _reorderGracePeriod) {
            return state;
          }
          _lastReorderAt = null;
        }
        return EventItemsLoaded(
          activeItems: items.where((item) => !item.isArchived).toList(),
          archivedItems: items.where((item) => item.isArchived).toList(),
        );
      },
      onError: (error, _) => EventItemError(error.toString()),
    );
    _isSubscribed = false;
  }

  Future<void> _onCreate(CreateEventItem event, Emitter<EventItemState> emit) {
    final all = state.catalogue;
    final next = all.isEmpty
        ? 0
        : all.map((item) => item.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    return _run(
      event.completion,
      () => _repository.createEventItem(event.name, event.emoji, nextSortOrder: next),
      'הפריט נוסף',
      'שגיאה בהוספת הפריט',
    );
  }

  Future<void> _onReorder(ReorderEventItems event, Emitter<EventItemState> emit) async {
    _lastReorderAt = DateTime.now();
    try {
      await _repository.reorderEventItems(event.items);
    } catch (e) {
      _lastReorderAt = null;
      emit(EventItemError(e.toString()));
    }
  }

  Future<void> _run(
    CrudActionCompleter? completion,
    Future<Object?> Function() action,
    String success,
    String failure,
  ) async {
    try {
      await action();
      completeCrudAction(completion, CrudActionResult.success(success));
    } catch (e) {
      completeCrudAction(completion, CrudActionResult.failure('$failure: $e'));
    }
  }
}
