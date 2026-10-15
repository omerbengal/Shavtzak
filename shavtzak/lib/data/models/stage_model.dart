import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/stage.dart';

/// Converts between [Stage] entities, Firestore documents and the payload the
/// backend's stage mutations accept.
class StageModel {
  /// Builds a [Stage] from a stored document. Tolerant, like the task model:
  /// one odd document must not blank the screen for everyone.
  static Stage fromMap(String id, Map<String, dynamic> data) {
    return Stage(
      id: id,
      eventId: _string(data['eventId']) ?? '',
      title: _string(data['title']) ?? '',
      date: _day(data['date']) ?? DateTime(1970),
      startTime: _string(data['startTime']),
      endTime: _string(data['endTime']),
      requirements: _string(data['requirements']) ?? '',
      hotelLocation: _string(data['hotelLocation']) ?? '',
      notes: _string(data['notes']) ?? '',
      contacts: _contacts(data['contacts']),
      createdAt: _date(data['createdAt']) ?? _epoch,
      createdById: _string(data['createdById']) ?? '',
      updatedAt: _date(data['updatedAt']) ?? _epoch,
    );
  }

  /// The payload for `stage.insert` and `stage.update`. The day goes out as a
  /// plain `yyyy-MM-dd`, so no time zone can move it.
  static Map<String, dynamic> toMutationPayload(Stage stage) {
    return {
      'id': stage.id,
      'eventId': stage.eventId,
      'title': stage.title,
      'date': formatDay(stage.date),
      'startTime': stage.startTime,
      'endTime': stage.endTime,
      'requirements': stage.requirements,
      'hotelLocation': stage.hotelLocation,
      'notes': stage.notes,
      'contacts': [
        for (final contact in stage.contacts)
          {
            'id': contact.id,
            'name': contact.name,
            'phone': contact.phone,
            'role': contact.role,
          },
      ],
    };
  }

  /// `yyyy-MM-dd` for [day]'s calendar date.
  static String formatDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static final RegExp _dayPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static String? _string(Object? value) => value is String ? value : null;

  static DateTime? _date(Object? value) =>
      value is Timestamp ? value.toDate() : null;

  static DateTime? _day(Object? value) {
    if (value is! String) return null;
    final match = _dayPattern.firstMatch(value);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  static List<StageContact> _contacts(Object? value) {
    if (value is! List) return const [];
    final contacts = <StageContact>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! String || id.isEmpty) continue;
      contacts.add(StageContact(
        id: id,
        name: _string(entry['name']) ?? '',
        phone: _string(entry['phone']) ?? '',
        role: _string(entry['role']) ?? '',
      ));
    }
    return contacts;
  }
}
