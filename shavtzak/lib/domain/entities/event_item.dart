import 'package:equatable/equatable.dart';

/// Something an event has ("מה יש באירוע"): סריקה, חנוכייה, להקה…, with an
/// optional emoji shown next to it on the pictures and the member's card.
///
/// There is no catalogue: the form suggests names already used on other
/// events (see `suggestEventItems`), and each event keeps its own emoji.
class EventItem extends Equatable {
  final String name;
  final String? emoji;

  const EventItem({required this.name, this.emoji});

  /// `name emoji`, or just the name when there is no emoji.
  String get label => emoji == null ? name : '$name $emoji';

  /// The emoji, or the name when there is none (the calendar picture's line).
  String get compact => emoji ?? name;

  EventItem copyWith({String? name, String? Function()? emoji}) => EventItem(
        name: name ?? this.name,
        emoji: emoji != null ? emoji() : this.emoji,
      );

  Map<String, dynamic> toJson() => {'name': name, 'emoji': emoji};

  /// Null for anything that has no name. A blank emoji counts as none.
  static EventItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] as String? ?? '').trim();
    if (name.isEmpty) return null;
    final emoji = (raw['emoji'] as String? ?? '').trim();
    return EventItem(name: name, emoji: emoji.isEmpty ? null : emoji);
  }

  static List<EventItem> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(EventItem.fromJson).whereType<EventItem>().toList();
  }

  @override
  List<Object?> get props => [name, emoji];
}
