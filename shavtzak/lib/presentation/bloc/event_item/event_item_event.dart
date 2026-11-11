import '../../../core/utils/crud_action_result.dart';
import '../../../domain/entities/event_item.dart';

abstract class EventItemEvent {
  const EventItemEvent();
}

class LoadEventItems extends EventItemEvent {
  const LoadEventItems();
}

class CreateEventItem extends EventItemEvent {
  final String name;
  final String? emoji;
  final CrudActionCompleter? completion;

  const CreateEventItem(this.name, this.emoji, {this.completion});
}

class UpdateEventItem extends EventItemEvent {
  final EventItem item;
  final CrudActionCompleter? completion;

  const UpdateEventItem(this.item, {this.completion});
}

/// Archive.
class DeleteEventItem extends EventItemEvent {
  final String itemId;
  final CrudActionCompleter? completion;

  const DeleteEventItem(this.itemId, {this.completion});
}

class PermanentlyDeleteEventItem extends EventItemEvent {
  final String itemId;
  final CrudActionCompleter? completion;

  const PermanentlyDeleteEventItem(this.itemId, {this.completion});
}

class RestoreEventItem extends EventItemEvent {
  final String itemId;
  final CrudActionCompleter? completion;

  const RestoreEventItem(this.itemId, {this.completion});
}

class ReorderEventItems extends EventItemEvent {
  final List<EventItem> items;

  const ReorderEventItems(this.items);
}
