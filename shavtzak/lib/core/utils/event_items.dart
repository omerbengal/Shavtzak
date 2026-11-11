import '../../domain/entities/event_item.dart';

/// The items [choices] name, looked up in [catalogue] and in its order
/// (`sortOrder`), keeping only the choices [where] accepts. A choice whose
/// item is no longer in the catalogue (deleted for good) is skipped; an
/// archived item still counts.
List<EventItem> eventItemsOf(
  List<EventItemChoice> choices,
  List<EventItem> catalogue, {
  bool Function(EventItemChoice choice)? where,
}) {
  final wanted = {
    for (final choice in choices)
      if (where == null || where(choice)) choice.itemId,
  };
  return catalogue.where((item) => wanted.contains(item.id)).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

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
