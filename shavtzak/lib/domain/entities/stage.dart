import 'package:equatable/equatable.dart';

/// Someone to call during a [Stage], usually hotel staff who are not in the
/// app. [phone] and [role] may be empty.
class StageContact extends Equatable {
  final String id;
  final String name;
  final String phone;
  final String role;

  const StageContact({
    required this.id,
    required this.name,
    this.phone = '',
    this.role = '',
  });

  StageContact copyWith({String? id, String? name, String? phone, String? role}) {
    return StageContact(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      role: role ?? this.role,
    );
  }

  @override
  List<Object?> get props => [id, name, phone, role];
}

/// One block of a דו יומי event, such as arrival or dinner. Tasks live under
/// a stage, and take their day from it.
///
/// Every timestamp is stamped by the backend.
class Stage extends Equatable {
  final String id;
  final String eventId; // Foreign key to Event
  final String title;

  /// The stage's day, at local midnight. One of the event's days.
  final DateTime date;

  /// `HH:mm`, or null for a stage with no set time.
  final String? startTime;

  /// `HH:mm` after [startTime], or null for a single time or none.
  final String? endTime;

  final String requirements; // Hotel requirements and logistics
  final String hotelLocation;
  final String notes;
  final List<StageContact> contacts;

  final DateTime createdAt;
  final String createdById;
  final DateTime updatedAt;

  const Stage({
    required this.id,
    required this.eventId,
    required this.title,
    required this.date,
    this.startTime,
    this.endTime,
    this.requirements = '',
    this.hotelLocation = '',
    this.notes = '',
    this.contacts = const [],
    required this.createdAt,
    required this.createdById,
    required this.updatedAt,
  });

  /// Whether the fold under the title line has anything to show.
  bool get hasDetails =>
      requirements.isNotEmpty || notes.isNotEmpty || contacts.isNotEmpty;

  Stage copyWith({
    String? id,
    String? eventId,
    String? title,
    DateTime? date,
    String? startTime,
    String? endTime,
    String? requirements,
    String? hotelLocation,
    String? notes,
    List<StageContact>? contacts,
    DateTime? createdAt,
    String? createdById,
    DateTime? updatedAt,
    bool clearStartTime = false,
    bool clearEndTime = false,
  }) {
    return Stage(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      title: title ?? this.title,
      date: date ?? this.date,
      startTime: clearStartTime ? null : (startTime ?? this.startTime),
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      requirements: requirements ?? this.requirements,
      hotelLocation: hotelLocation ?? this.hotelLocation,
      notes: notes ?? this.notes,
      contacts: contacts ?? this.contacts,
      createdAt: createdAt ?? this.createdAt,
      createdById: createdById ?? this.createdById,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        eventId,
        title,
        date,
        startTime,
        endTime,
        requirements,
        hotelLocation,
        notes,
        contacts,
        createdAt,
        createdById,
        updatedAt,
      ];
}
