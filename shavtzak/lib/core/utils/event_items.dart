import '../../domain/entities/event.dart';
import '../../domain/entities/event_item.dart';

/// `באירוע זה יש: סריקה 🤳🏻, חנוכייה 🕎, להקה`, or null when there are none.
/// Used on the event's picture and on the member's card.
String? eventItemsSentence(List<EventItem> items) {
  if (items.isEmpty) return null;
  return 'באירוע זה יש: ${items.map((item) => item.label).join(', ')}';
}

/// `🤳🏻, 🕎, להקה` (the emoji, or the name without one), or null when there
/// are none. Used on the calendar picture, where there is little room.
String? eventItemsCompactLine(List<EventItem> items) {
  if (items.isEmpty) return null;
  return items.map((item) => item.compact).join(', ');
}

/// What the event form offers while the admin types [query]: every item name
/// used on any of [events] whose name contains the trimmed query, except names
/// already in [exclude], sorted by name.
///
/// Each event keeps its own emoji, so a name may carry different ones. The
/// suggestion takes the emoji (or none) from the most recently saved event
/// (`updatedAt`) that has it.
List<EventItem> suggestEventItems(
  String query,
  List<Event> events,
  List<EventItem> exclude,
) {
  final needle = query.trim();
  final taken = {for (final item in exclude) item.name};
  final latest = <String, ({EventItem item, DateTime at})>{};
  for (final event in events) {
    for (final item in event.items) {
      if (taken.contains(item.name)) continue;
      if (needle.isNotEmpty && !item.name.contains(needle)) continue;
      final current = latest[item.name];
      if (current == null || event.updatedAt.isAfter(current.at)) {
        latest[item.name] = (item: item, at: event.updatedAt);
      }
    }
  }
  final names = latest.keys.toList()..sort();
  return [for (final name in names) latest[name]!.item];
}
