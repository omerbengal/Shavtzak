import 'package:equatable/equatable.dart';

/// Something an event can have ("מה יש באירוע"): סריקה, חנוכייה, להקה…,
/// with an optional emoji. A managed list like the categories ("ניהול מה יש
/// באירוע"); events refer to its items by id ([EventItemChoice]).
class EventItem extends Equatable {
  final String id;
  final String name;
  final String? emoji;
  final int sortOrder;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EventItem({
    required this.id,
    required this.name,
    this.emoji,
    required this.sortOrder,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// `name emoji`, or just the name when there is no emoji.
  String get label => emoji == null ? name : '$name $emoji';

  /// The emoji, or the name when there is none (the calendar picture's line).
  String get compact => emoji ?? name;

  EventItem copyWith({
    String? name,
    String? Function()? emoji,
    int? sortOrder,
    bool? isArchived,
    DateTime? updatedAt,
  }) =>
      EventItem(
        id: id,
        name: name ?? this.name,
        emoji: emoji != null ? emoji() : this.emoji,
        sortOrder: sortOrder ?? this.sortOrder,
        isArchived: isArchived ?? this.isArchived,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'sortOrder': sortOrder,
        'isArchived': isArchived,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Null for an entry without an id or a name. A blank emoji counts as none.
  static EventItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = (raw['name'] as String? ?? '').trim();
    if (id is! String || id.isEmpty || name.isEmpty) return null;
    final emoji = (raw['emoji'] as String? ?? '').trim();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return EventItem(
      id: id,
      name: name,
      emoji: emoji.isEmpty ? null : emoji,
      sortOrder: (raw['sortOrder'] as num?)?.toInt() ?? 0,
      isArchived: raw['isArchived'] == true,
      createdAt: DateTime.tryParse(raw['createdAt'] as String? ?? '') ?? epoch,
      updatedAt: DateTime.tryParse(raw['updatedAt'] as String? ?? '') ?? epoch,
    );
  }

  /// The catalogue in its order (`sortOrder`).
  static List<EventItem> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(EventItem.fromJson).whereType<EventItem>().toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  List<Object?> get props =>
      [id, name, emoji, sortOrder, isArchived, createdAt, updatedAt];
}

/// One item an event has, and whether it shows on the event's picture
/// ("להציג בייצוא אירוע") and on the calendar picture ("להציג בייצוא לוח
/// שנה"). The member's card shows every item the event has.
class EventItemChoice extends Equatable {
  final String itemId;
  final bool showInEventExport;
  final bool showInCalendarExport;

  const EventItemChoice({
    required this.itemId,
    this.showInEventExport = true,
    this.showInCalendarExport = true,
  });

  EventItemChoice copyWith({bool? showInEventExport, bool? showInCalendarExport}) =>
      EventItemChoice(
        itemId: itemId,
        showInEventExport: showInEventExport ?? this.showInEventExport,
        showInCalendarExport: showInCalendarExport ?? this.showInCalendarExport,
      );

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'showInEventExport': showInEventExport,
        'showInCalendarExport': showInCalendarExport,
      };

  /// Null for an entry without an item id. A missing switch is on.
  static EventItemChoice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final itemId = raw['itemId'];
    if (itemId is! String || itemId.trim().isEmpty) return null;
    return EventItemChoice(
      itemId: itemId.trim(),
      showInEventExport: raw['showInEventExport'] != false,
      showInCalendarExport: raw['showInCalendarExport'] != false,
    );
  }

  static List<EventItemChoice> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(EventItemChoice.fromJson).whereType<EventItemChoice>().toList();
  }

  @override
  List<Object?> get props => [itemId, showInEventExport, showInCalendarExport];
}
