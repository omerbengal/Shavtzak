import 'package:equatable/equatable.dart';
import '../../../domain/entities/event_item.dart';

abstract class EventItemState extends Equatable {
  const EventItemState();

  @override
  List<Object?> get props => [];
}

class EventItemInitial extends EventItemState {
  const EventItemInitial();
}

class EventItemLoading extends EventItemState {
  const EventItemLoading();
}

class EventItemsLoaded extends EventItemState {
  final List<EventItem> activeItems;
  final List<EventItem> archivedItems;

  const EventItemsLoaded({
    required this.activeItems,
    required this.archivedItems,
  });

  @override
  List<Object?> get props => [activeItems, archivedItems];
}

class EventItemError extends EventItemState {
  final String message;

  const EventItemError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Every item an [EventItemState] holds (active, then archived), empty until
/// it has loaded: what an event's choices are looked up in, since an
/// archived item stays on the events that have it.
extension EventItemStateCatalogue on EventItemState {
  List<EventItem> get catalogue {
    final self = this;
    return self is EventItemsLoaded
        ? [...self.activeItems, ...self.archivedItems]
        : const [];
  }
}
