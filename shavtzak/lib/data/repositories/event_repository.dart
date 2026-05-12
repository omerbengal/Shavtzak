import 'package:uuid/uuid.dart';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/assignment.dart';
import '../../core/constants/role_types.dart';
import '../../core/services/drive_service.dart';
import '../data_sources/database_interface.dart';
import '../data_sources/firestore_database.dart';
import '../../core/router/app_router.dart'; // Import for navigatorKey

/// Exception thrown when trying to create a duplicate event
class DuplicateEventException implements Exception {
  final String message;
  DuplicateEventException(this.message);

  @override
  String toString() => message;
}

/// Repository for event operations
/// Provides high-level business logic on top of database operations
class EventRepository {
  final DatabaseInterface _database;
  final DriveService _driveService;

  EventRepository(this._database, {DriveService? driveService})
      : _driveService = driveService ?? DriveService.instance;

  /// Watch all events in real-time
  Stream<List<Event>> watchEvents() {
    // Cast to FirestoreDatabase to access stream methods
    if (_database is FirestoreDatabase) {
      return (_database as FirestoreDatabase).watchEvents();
    }
    // Fallback: convert Future to Stream for non-Firestore databases
    return Stream.fromFuture(_database.getEvents());
  }

  /// Watch events within a date range in real-time
  /// Optimized for pagination - only loads events within the specified window
  Stream<List<Event>> watchEventsByDateRange(DateTime start, DateTime end) {
    // Cast to FirestoreDatabase to access stream methods
    if (_database is FirestoreDatabase) {
      return (_database as FirestoreDatabase)
          .watchEventsByDateRange(start, end);
    }
    // Fallback: convert Future to Stream for non-Firestore databases
    return Stream.fromFuture(_database.getEventsByDateRange(start, end));
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

  /// Check if an event with the same name and date already exists
  Future<bool> isDuplicateEvent(String name, DateTime startDate,
      {String? excludeEventId}) async {
    return await _database.isDuplicateEvent(name, startDate,
        excludeEventId: excludeEventId);
  }

  /// Create a new event
  /// Creates Drive folder in the background and triggers archive check
  /// Throws DuplicateEventException if an event with the same name and date exists
  Future<Event> createEvent(Event event) async {
    // Check for duplicate event
    try {
      final isDuplicate = await isDuplicateEvent(event.name, event.startDate);
      if (isDuplicate) {
        throw DuplicateEventException('כבר קיים אירוע בשם זה בתאריך זה');
      }
    } catch (e) {
      if (e is DuplicateEventException) {
        rethrow;
      }
      developer.log(
        'EventRepository.createEvent: Duplicate check failed: $e',
        name: 'EventRepository',
        error: e,
      );
      // Continue with event creation if duplicate check fails (e.g., missing index)
      // The error will be logged but won't block event creation
    }

    // Insert event to database first
    await _database.insertEvent(event);

    // Create Drive folder in background (don't wait for it)
    _createDriveFolderInBackground(event);


    return event;
  }

  /// Update an existing event
  /// Renames the Drive folder in background if name/date changed and triggers archive check
  /// Throws DuplicateEventException if another event with the same name and date exists
  Future<Event> updateEvent(Event event) async {
    // Check for duplicate event (excluding this event)
    try {
      final isDuplicate = await isDuplicateEvent(
        event.name,
        event.startDate,
        excludeEventId: event.id,
      );
      if (isDuplicate) {
        throw DuplicateEventException('כבר קיים אירוע בשם זה בתאריך זה');
      }
    } catch (e) {
      if (e is DuplicateEventException) {
        rethrow;
      }
      developer.log(
        'EventRepository.updateEvent: Duplicate check failed: $e',
        name: 'EventRepository',
        error: e,
      );
      // Continue with event update if duplicate check fails (e.g., missing index)
    }

    // Get the original event to check if name/date changed
    final originalEvent = await getEventById(event.id);

    // Update event in database first
    await _database.updateEvent(event);

    // Rename Drive folder in background if needed
    if (_driveService.isInitialized && event.hasDriveFolder) {
      // Check if name or date changed
      final nameChanged = originalEvent?.name != event.name;
      final dateChanged = originalEvent?.startDate != event.startDate ||
          originalEvent?.endDate != event.endDate;

      if (nameChanged || dateChanged) {
        _renameDriveFolderInBackground(event, originalEvent);
      }
    }


    return event;
  }

  /// Delete an event
  /// The backend mutation cascades to assignments, checklist items, and
  /// calendar sync state. Drive folder deletion still happens in background.
  Future<void> deleteEvent(String id) async {
    // Get event to check for Drive folder
    final event = await getEventById(id);

    // Delete Drive folder in background if exists
    if (_driveService.isInitialized && event != null && event.hasDriveFolder) {
      _deleteDriveFolderInBackground(event.driveFolderId!);
    }

    // Delete the event through the backend cascade
    await _database.deleteEvent(id);

  }

  /// Get files attached to an event from its Drive folder
  Future<List<DriveFile>> getEventFiles(String eventId) async {
    final event = await getEventById(eventId);
    if (event == null || !event.hasDriveFolder) {
      return [];
    }

    if (!_driveService.isInitialized) {
      return [];
    }

    try {
      final result =
          await _driveService.listFiles(folderId: event.driveFolderId!);
      if (result.success) {
        return result.files;
      }
      return [];
    } catch (e) {
      developer.log(
        'EventRepository.getEventFiles: Error: $e',
        name: 'EventRepository',
        error: e,
      );
      return [];
    }
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
          (event) =>
              event.roleRequirements[role] != null &&
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
    final weekEnd =
        weekStart.add(const Duration(days: 6, hours: 23, minutes: 59));

    return await getEventsByDateRange(weekStart, weekEnd);
  }

  /// Duplicate an event with new date/time and copy all assignments
  /// Creates Drive folder for the new event and runs archive check
  Future<void> duplicateEvent(
    Event originalEvent,
    Event newEvent,
    List<Assignment> originalAssignments,
  ) async {
    // Insert event to database first (Drive folder created in background)
    await _database.insertEvent(newEvent);

    // Create Drive folder in background
    _createDriveFolderInBackground(newEvent);

    // Create new assignments for the duplicated event
    final newAssignments = originalAssignments
        .map((assignment) => Assignment(
              id: const Uuid()
                  .v4(), // Generate unique ID for each duplicated assignment
              eventId: newEvent.id, // Use the ID from newEvent
              teamMemberId: assignment.teamMemberId,
              roleType: assignment.roleType,
              slotIndex: assignment.slotIndex,
              status: AssignmentStatus
                  .confirmed, // Default to confirmed for duplicated assignments
              notes: assignment.notes,
              semanticLabelId: assignment.semanticLabelId,
              alternativePhoneNumber: assignment.alternativePhoneNumber,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              teamMember: assignment.teamMember,
              event: newEvent, // Use newEvent directly
              semanticLabel: assignment.semanticLabel,
            ))
        .toList();

    // Insert all new assignments in batch
    await _database.insertAssignmentsBatch(newAssignments);

  }

  /// Duplicate an event with new date/time and copy all assignments
  /// Returns the created assignments with their IDs mapped from original assignments
  Future<Map<String, Assignment>> duplicateEventWithAssignmentIds(
    Event originalEvent,
    Event newEvent,
    List<Assignment> originalAssignments,
  ) async {
    // Insert event to database first (Drive folder created in background)
    await _database.insertEvent(newEvent);

    // Create Drive folder in background
    _createDriveFolderInBackground(newEvent);

    // Create new assignments for the duplicated event
    final newAssignments = originalAssignments.map((assignment) {
      final newId = const Uuid().v4();
      return Assignment(
        id: newId, // Generate unique ID for each duplicated assignment
        eventId: newEvent.id, // Use the ID from newEvent
        teamMemberId: assignment.teamMemberId,
        roleType: assignment.roleType,
        slotIndex: assignment.slotIndex,
        status: AssignmentStatus
            .confirmed, // Default to confirmed for duplicated assignments
        notes: assignment.notes,
        semanticLabelId: assignment.semanticLabelId,
        alternativePhoneNumber: assignment.alternativePhoneNumber,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        teamMember: assignment.teamMember,
        event: newEvent, // Use newEvent directly
        semanticLabel: assignment.semanticLabel,
      );
    }).toList();

    // Insert all new assignments in batch
    await _database.insertAssignmentsBatch(newAssignments);

    // Return map of original assignment IDs to new assignments
    final idMap = <String, Assignment>{};
    for (int i = 0; i < originalAssignments.length; i++) {
      idMap[originalAssignments[i].id] = newAssignments[i];
    }


    return idMap;
  }

  /// Remove specific assignments after duplication based on quota reduction
  Future<void> removeAssignmentsAfterDuplication(
    List<String> assignmentIdsToRemove,
  ) async {
    // Delete the specified assignments
    for (final assignmentId in assignmentIdsToRemove) {
      await _database.deleteAssignment(assignmentId);
    }
  }

  /// Show error snackbar with Drive error details
  void _showDriveErrorSnackBar(String error) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                'אירעה שגיאה בעת ניסיון עדכון הדרייב. השגיאה:\n$error\nנא לצלם לעומר בנגל ולשלוח בוואטסאפ!',
              ),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 20),
            action: SnackBarAction(
              label: 'סגור',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    });
  }

  /// Create Drive folder in background
  Future<void> _createDriveFolderInBackground(Event event) async {
    if (!_driveService.isInitialized) return;

    try {
      final result = await _driveService.createFolder(
        eventName: event.name,
        date: event.startDate,
        endDate: event.endDate, // Add end date
      );

      if (result.success) {
        // Update event with Drive folder info
        final updatedEvent = event.copyWith(
          driveFolderId: result.folderId,
          driveFolderLink: result.folderLink,
        );
        await _database.updateEvent(updatedEvent);
        developer.log(
          'EventRepository: Created Drive folder ${result.folderId}',
          name: 'EventRepository',
        );
      } else {
        developer.log(
          'EventRepository: Failed to create Drive folder: ${result.error}',
          name: 'EventRepository',
          error: result.error,
        );
        _showDriveErrorSnackBar(result.error ?? 'שגיאה ביצירת תיקיית דרייב');
      }
    } catch (e) {
      developer.log(
        'EventRepository: Drive error: $e',
        name: 'EventRepository',
        error: e,
      );
      _showDriveErrorSnackBar(e.toString());
    }
  }

  /// Rename Drive folder in background
  Future<void> _renameDriveFolderInBackground(
      Event event, Event? originalEvent) async {
    if (!_driveService.isInitialized || !event.hasDriveFolder) return;

    try {
      final success = await _driveService.renameFolder(
        folderId: event.driveFolderId!,
        newName: event.name,
        newDate: event.startDate,
        newEndDate: event.endDate, // Add end date
      );

      if (success) {
        developer.log(
          'EventRepository: Renamed Drive folder ${event.driveFolderId}',
          name: 'EventRepository',
        );
      } else {
        developer.log(
          'EventRepository: Failed to rename Drive folder',
          name: 'EventRepository',
        );
        _showDriveErrorSnackBar('שגיאה בשינוי שם תיקיית דרייב');
      }
    } catch (e) {
      developer.log(
        'EventRepository: Drive error: $e',
        name: 'EventRepository',
        error: e,
      );
      _showDriveErrorSnackBar(e.toString());
    }
  }

  /// Delete Drive folder in background
  Future<void> _deleteDriveFolderInBackground(String folderId) async {
    if (!_driveService.isInitialized) return;

    try {
      final success = await _driveService.deleteFolder(folderId: folderId);
      if (success) {
        developer.log(
          'EventRepository: Deleted Drive folder $folderId',
          name: 'EventRepository',
        );
      } else {
        developer.log(
          'EventRepository: Failed to delete Drive folder',
          name: 'EventRepository',
        );
        _showDriveErrorSnackBar('שגיאה במחיקת תיקיית דרייב');
      }
    } catch (e) {
      developer.log(
        'EventRepository: Drive error: $e',
        name: 'EventRepository',
        error: e,
      );
      _showDriveErrorSnackBar(e.toString());
    }
  }

}
