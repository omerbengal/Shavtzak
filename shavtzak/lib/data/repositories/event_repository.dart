import 'package:uuid/uuid.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/assignment.dart';
import '../../core/constants/role_types.dart';
import '../data_sources/database_interface.dart';
import '../data_sources/firestore_database.dart';

/// Repository for event operations
/// Provides high-level business logic on top of database operations
class EventRepository {
  final DatabaseInterface _database;

  EventRepository(this._database);

  /// Watch all events in real-time
  Stream<List<Event>> watchEvents() {
    // Cast to FirestoreDatabase to access stream methods
    if (_database is FirestoreDatabase) {
      return (_database as FirestoreDatabase).watchEvents();
    }
    // Fallback: convert Future to Stream for non-Firestore databases
    return Stream.fromFuture(_database.getEvents());
  }

  /// Get all events
  Future<List<Event>> getAllEvents() async {
    return await _database.getEvents();
  }

  /// Get event by ID
  Future<Event?> getEventById(String id) async {
    return await _database.getEventById(id);
  }

  /// Get upcoming events (starts after today)
  Future<List<Event>> getUpcomingEvents() async {
    return await _database.getUpcomingEvents();
  }

  /// Get events by date range
  Future<List<Event>> getEventsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    return await _database.getEventsByDateRange(start, end);
  }

  /// Get events occurring on a specific date
  Future<List<Event>> getEventsOnDate(DateTime date) async {
    final all = await getAllEvents();
    return all.where((event) => event.occursOn(date)).toList();
  }

  /// Create a new event
  Future<void> createEvent(Event event) async {
    await _database.insertEvent(event);
  }

  /// Update an existing event
  Future<void> updateEvent(Event event) async {
    await _database.updateEvent(event);
  }

  /// Delete an event
  /// Also deletes all assignments for this event
  Future<void> deleteEvent(String id) async {
    // Delete all assignments first
    await _database.deleteAssignmentsByEvent(id);

    // Then delete the event
    await _database.deleteEvent(id);
  }

  /// Search events by name or location
  Future<List<Event>> searchEvents(String query) async {
    if (query.trim().isEmpty) {
      return await getAllEvents();
    }

    final all = await getAllEvents();
    final lowerQuery = query.trim().toLowerCase();

    return all
        .where(
          (event) =>
              event.name.toLowerCase().contains(lowerQuery) ||
              event.location.toLowerCase().contains(lowerQuery),
        )
        .toList();
  }

  /// Get events requiring a specific role
  Future<List<Event>> getEventsRequiringRole(RoleType role) async {
    final all = await getAllEvents();
    return all
        .where(
          (event) => event.roleRequirements[role] != null &&
              event.roleRequirements[role]! > 0,
        )
        .toList();
  }

  /// Import events in batch (for V1 data import)
  Future<void> importEvents(List<Event> events) async {
    await _database.insertEventsBatch(events);
  }

  /// Get statistics
  Future<Map<String, int>> getStatistics() async {
    final all = await getAllEvents();
    final upcoming = all.where((e) => e.isUpcoming).length;
    final past = all.where((e) => e.isPast).length;
    final active = all.where((e) => e.isActive).length;

    return {
      'total': all.length,
      'upcoming': upcoming,
      'past': past,
      'active': active,
    };
  }

  /// Get current month events
  Future<List<Event>> getCurrentMonthEvents() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    return await getEventsByDateRange(start, end);
  }

  /// Get this week's events
  Future<List<Event>> getThisWeekEvents() async {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6, hours: 23, minutes: 59));

    return await getEventsByDateRange(weekStart, weekEnd);
  }

  /// Duplicate an event with new date/time and copy all assignments
  Future<void> duplicateEvent(
    Event originalEvent,
    Event newEvent,
    List<Assignment> originalAssignments,
  ) async {
    
    // Create the new event in database
    await _database.insertEvent(newEvent);

    // Create new assignments for the duplicated event
    final newAssignments = originalAssignments.map((assignment) => Assignment(
      id: const Uuid().v4(), // Generate unique ID for each duplicated assignment
      eventId: newEvent.id, // Use the ID from newEvent directly
      teamMemberId: assignment.teamMemberId,
      roleType: assignment.roleType,
      slotIndex: assignment.slotIndex,
      status: AssignmentStatus.confirmed, // Default to confirmed for duplicated assignments
      notes: assignment.notes,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      teamMember: assignment.teamMember,
      event: newEvent, // Use newEvent directly
    )).toList();

    // Insert all new assignments in batch
    await _database.insertAssignmentsBatch(newAssignments);
  }
}
