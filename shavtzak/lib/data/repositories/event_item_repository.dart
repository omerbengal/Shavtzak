import 'package:uuid/uuid.dart';
import '../../domain/entities/event_item.dart';
import '../data_sources/database_interface.dart';

/// The "מה יש באירוע" list (managed like the categories).
class EventItemRepository {
  final DatabaseInterface _database;

  EventItemRepository(this._database);

  /// Every item, archived ones included, in their order.
  Stream<List<EventItem>> watchEventItems() => _database.watchEventItems();

  /// A new item placed after every existing one ([nextSortOrder]).
  Future<EventItem> createEventItem(
    String name,
    String? emoji, {
    required int nextSortOrder,
  }) async {
    final now = DateTime.now();
    final item = EventItem(
      id: const Uuid().v4(),
      name: name,
      emoji: emoji,
      sortOrder: nextSortOrder,
      createdAt: now,
      updatedAt: now,
    );
    await _database.insertEventItem(item);
    return item;
  }

  Future<void> updateEventItem(EventItem item) =>
      _database.updateEventItem(item.copyWith(updatedAt: DateTime.now()));

  Future<void> deleteEventItem(String id) => _database.deleteEventItem(id);

  Future<void> permanentlyDeleteEventItem(String id) =>
      _database.permanentlyDeleteEventItem(id);

  Future<void> restoreEventItem(String id) => _database.restoreEventItem(id);

  /// Writes the position of every item whose place changed.
  Future<void> reorderEventItems(List<EventItem> items) async {
    for (var i = 0; i < items.length; i++) {
      if (items[i].sortOrder != i) {
        await updateEventItem(items[i].copyWith(sortOrder: i));
      }
    }
  }
}
