import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/assignment.dart';
import '../../domain/entities/assignment_label.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/checklist_item.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/preset.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/team_member.dart';
import '../../core/constants/constraint_status.dart';
import '../../core/constants/calendar_constants.dart';
import '../../core/constants/role_types.dart';
import '../../core/services/backend_api_service.dart';
import '../../core/services/environment_service.dart';
import '../../core/utils/event_sorting.dart';
import '../models/assignment_model.dart';
import '../models/assignment_label_model.dart';
import '../models/category_model.dart';
import '../models/checklist_item_model.dart';
import '../models/checklist_note_model.dart';
import '../models/event_model.dart';
import '../models/preset_model.dart';
import '../models/role_model.dart';
import '../models/team_member_model.dart';
import 'database_interface.dart';

/// Firestore implementation of DatabaseInterface
class FirestoreDatabase implements DatabaseInterface {
  final FirebaseFirestore _firestore;
  final BackendApiService _backendApiService;

  // Collection names with environment prefix
  String get _teamMembersCollection {
    return '${EnvironmentService.instance.collectionPrefix}teamMembers';
  }

  String get _eventsCollection {
    return '${EnvironmentService.instance.collectionPrefix}events';
  }

  String get _assignmentsCollection {
    return '${EnvironmentService.instance.collectionPrefix}assignments';
  }

  String get _assignmentLabelsCollection {
    return '${EnvironmentService.instance.collectionPrefix}assignmentLabels';
  }

  String get _calendarSyncCollection {
    return '${EnvironmentService.instance.collectionPrefix}calendar_sync';
  }

  String get _eventCalendarSyncCollection {
    return '${EnvironmentService.instance.collectionPrefix}event_calendar_sync';
  }

  String get _checklistItemsCollection {
    return '${EnvironmentService.instance.collectionPrefix}checklist_items';
  }

  String get _presetsCollection {
    return '${EnvironmentService.instance.collectionPrefix}checklist_presets';
  }

  FirestoreDatabase({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _backendApiService = BackendApiService();

  @override
  Future<void> initialize() async {
    // Firestore doesn't require explicit initialization
    // Connection is established automatically
  }

  @override
  Future<void> close() async {
    // Firestore connections are managed automatically
  }

  Future<Map<String, dynamic>> _invokeMutation(
    String operation, {
    Map<String, dynamic>? payload,
  }) async {
    try {
      return await _backendApiService.mutate(
        operation,
        payload: payload,
      );
    } catch (e) {
      throw DatabaseException('Failed backend mutation $operation: $e');
    }
  }

  Map<String, dynamic> _teamMemberEntityToMap(TeamMember member) {
    return TeamMemberModel.fromEntity(member).toJson();
  }

  Map<String, dynamic> _eventEntityToMap(Event event) {
    return EventModel.fromEntity(event).toJson();
  }

  Map<String, dynamic> _assignmentEntityToMap(Assignment assignment) {
    return AssignmentModel.fromEntity(assignment).toJson();
  }

  Map<String, dynamic> _assignmentLabelEntityToMap(AssignmentLabel label) {
    return AssignmentLabelModel.fromEntity(label).toJson();
  }

  Map<String, dynamic> _constraintEntityToMap(DateConstraint constraint) {
    return DateConstraintModel.fromEntity(constraint).toJson();
  }

  Map<String, dynamic> _checklistItemEntityToMap(ChecklistItem item) {
    return {
      'id': item.id,
      'eventId': item.eventId,
      'name': item.name,
      'responsibleId': item.responsibleId,
      'notes': item.notes.map(ChecklistNoteModel.toMap).toList(),
      'ccIds': item.ccIds,
      'status': item.status,
      'createdAt': item.createdAt.toIso8601String(),
      'updatedAt': item.updatedAt.toIso8601String(),
      'statusLastUpdatedAt': item.statusLastUpdatedAt.toIso8601String(),
      'createdByAdminId': item.createdByAdminId,
    };
  }

  Map<String, dynamic> _presetEntityToMap(Preset preset) {
    return {
      'id': preset.id,
      'name': preset.name,
      'items': preset.items
          .map((item) => {
                'name': item.name,
                'responsibleId': item.responsibleId,
                'ccIds': item.ccIds,
                'adminNote': item.adminNote,
              })
          .toList(),
      'createdAt': preset.createdAt.toIso8601String(),
      'updatedAt': preset.updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> _roleEntityToMap(Role role) {
    return RoleModel.fromEntity(role).toJson();
  }

  Map<String, dynamic> _categoryEntityToMap(Category category) {
    return CategoryModel.fromEntity(category).toJson();
  }

  // ========== Team Members ==========

  @override
  Future<List<TeamMember>> getTeamMembers() async {
    try {
      final snapshot = await _firestore
          .collection(_teamMembersCollection)
          .orderBy('name')
          .get();

      final teamMembers = snapshot.docs
          .map((doc) => TeamMemberModel.fromFirestore(doc).toEntity())
          .toList();

      return teamMembers;
    } catch (e) {
      throw DatabaseException('Failed to get team members: $e');
    }
  }

  /// Watch team members in real-time
  Stream<List<TeamMember>> watchTeamMembers() {
    return _firestore
        .collection(_teamMembersCollection)
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => TeamMemberModel.fromFirestore(doc).toEntity())
          .toList();
    });
  }

  @override
  Future<TeamMember?> getTeamMemberById(String id) async {
    try {
      final doc =
          await _firestore.collection(_teamMembersCollection).doc(id).get();

      if (!doc.exists) return null;

      return TeamMemberModel.fromFirestore(doc).toEntity();
    } catch (e) {
      throw DatabaseException('Failed to get team member: $e');
    }
  }

  @override
  Future<TeamMember?> getTeamMemberByUniqueKey(String uniqueKey) async {
    try {
      final snapshot = await _firestore
          .collection(_teamMembersCollection)
          .where('uniqueKey', isEqualTo: uniqueKey)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      return TeamMemberModel.fromFirestore(snapshot.docs.first).toEntity();
    } catch (e) {
      throw DatabaseException('Failed to get team member by unique key: $e');
    }
  }

  @override
  Future<void> insertTeamMember(TeamMember member) async {
    try {
      await _invokeMutation(
        'teamMember.insert',
        payload: {'member': _teamMemberEntityToMap(member)},
      );
    } catch (e) {
      throw DatabaseException('Failed to insert team member: $e');
    }
  }

  @override
  Future<void> updateTeamMember(TeamMember member) async {
    try {
      await _invokeMutation(
        'teamMember.update',
        payload: {'member': _teamMemberEntityToMap(member)},
      );
    } catch (e) {
      throw DatabaseException('Failed to update team member: $e');
    }
  }

  @override
  Future<void> updateTeamMemberPasscode(
      String id, String passcode, int length) async {
    try {
      await _invokeMutation(
        'teamMember.updatePasscode',
        payload: {
          'memberId': id,
          'passcode': passcode,
          'length': length,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to update team member passcode: $e');
    }
  }

  @override
  Future<void> clearTeamMemberPasscode(String id) async {
    try {
      await _invokeMutation(
        'teamMember.clearPasscode',
        payload: {'memberId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to clear team member passcode: $e');
    }
  }

  @override
  Future<void> updateConstraintStatus(
    String teamMemberIdOrConstraintId,
    int? constraintIndex,
    ConstraintStatus newStatus, {
    String? note,
    bool? wasAutoRejectedFromCalendar,
  }) async {
    try {
      await _invokeMutation(
        'constraint.updateStatus',
        payload: {
          'teamMemberIdOrConstraintId': teamMemberIdOrConstraintId,
          'constraintIndex': constraintIndex,
          'newStatus': newStatus.name,
          if (note != null) 'note': note,
          if (wasAutoRejectedFromCalendar != null)
            'wasAutoRejectedFromCalendar': wasAutoRejectedFromCalendar,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to update constraint status: $e');
    }
  }

  @override
  Future<void> addConstraint(
    String teamMemberId,
    DateConstraint newConstraint,
  ) async {
    try {
      await _invokeMutation(
        'constraint.add',
        payload: {
          'teamMemberId': teamMemberId,
          'constraint': _constraintEntityToMap(newConstraint),
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to add constraint: $e');
    }
  }

  @override
  Future<void> editConstraintById(
    String teamMemberId,
    String constraintId,
    DateConstraint updatedConstraint,
  ) async {
    try {
      await _invokeMutation(
        'constraint.edit',
        payload: {
          'teamMemberId': teamMemberId,
          'constraintId': constraintId,
          'constraint': _constraintEntityToMap(updatedConstraint),
        },
      );
    } catch (e) {
      if (e is DatabaseException) rethrow;
      throw DatabaseException('Failed to edit constraint: $e');
    }
  }

  @override
  Future<DateConstraint?> removeConstraintById(
    String teamMemberId,
    String constraintId,
  ) async {
    try {
      final doc = await _firestore
          .collection(_teamMembersCollection)
          .doc(teamMemberId)
          .get();

      if (!doc.exists) {
        throw DatabaseException('Team member not found: $teamMemberId');
      }

      final data = doc.data() as Map<String, dynamic>;
      final constraints = (data['constraints'] as List<dynamic>?) ?? [];

      // Find the constraint by ID
      final constraintIndex = constraints.indexWhere(
        (c) => c['id'] == constraintId,
      );

      if (constraintIndex == -1) {
        return null; // Constraint already removed (idempotent)
      }

      // Parse the constraint before removing so we can return it
      final removedConstraintData =
          constraints[constraintIndex] as Map<String, dynamic>;
      final removedConstraint =
          DateConstraintModel.fromJson(removedConstraintData).toEntity();
      await _invokeMutation(
        'constraint.remove',
        payload: {
          'teamMemberId': teamMemberId,
          'constraintId': constraintId,
        },
      );

      return removedConstraint;
    } catch (e) {
      if (e is DatabaseException) rethrow;
      throw DatabaseException('Failed to remove constraint: $e');
    }
  }

  @override
  Future<void> deleteTeamMember(String id) async {
    try {
      await _invokeMutation(
        'teamMember.delete',
        payload: {'memberId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to delete team member: $e');
    }
  }

  @override
  Future<void> insertTeamMembersBatch(List<TeamMember> members) async {
    try {
      await _invokeMutation(
        'teamMember.insertBatch',
        payload: {
          'members': members.map(_teamMemberEntityToMap).toList(),
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to insert team members batch: $e');
    }
  }

  // ========== Events ==========

  /// Watch events in real-time
  Stream<List<Event>> watchEvents() {
    return _firestore
        .collection(_eventsCollection)
        .orderBy('startDate', descending: true)
        .snapshots()
        .map((snapshot) {
      final events = snapshot.docs
          .map((doc) => EventModel.fromFirestore(doc).toEntity())
          .toList();
      events.sort(compareEventsChronologicallyDescending);
      return events;
    });
  }

  @override
  Future<List<Event>> getEvents() async {
    try {
      final snapshot = await _firestore
          .collection(_eventsCollection)
          .orderBy('startDate', descending: true)
          .get();

      final events = snapshot.docs
          .map((doc) => EventModel.fromFirestore(doc).toEntity())
          .toList();
      events.sort(compareEventsChronologicallyDescending);
      return events;
    } catch (e) {
      throw DatabaseException('Failed to get events: $e');
    }
  }

  @override
  Future<Event?> getEventById(String id) async {
    try {
      final doc = await _firestore.collection(_eventsCollection).doc(id).get();

      if (!doc.exists) return null;

      return EventModel.fromFirestore(doc).toEntity();
    } catch (e) {
      throw DatabaseException('Failed to get event: $e');
    }
  }

  @override
  Future<void> insertEvent(Event event) async {
    try {
      await _invokeMutation(
        'event.insert',
        payload: {'event': _eventEntityToMap(event)},
      );
    } catch (e) {
      throw DatabaseException('Failed to insert event: $e');
    }
  }

  @override
  Future<void> updateEvent(Event event) async {
    try {
      await _invokeMutation(
        'event.update',
        payload: {'event': _eventEntityToMap(event)},
      );
    } catch (e) {
      throw DatabaseException('Failed to update event: $e');
    }
  }

  @override
  Future<void> deleteEvent(String id) async {
    try {
      await _invokeMutation(
        'event.delete',
        payload: {'eventId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to delete event: $e');
    }
  }

  @override
  Future<List<Event>> getUpcomingEvents() async {
    try {
      final now = Timestamp.now();
      final snapshot = await _firestore
          .collection(_eventsCollection)
          .where('startDate', isGreaterThan: now)
          .orderBy('startDate')
          .get();

      final events = snapshot.docs
          .map((doc) => EventModel.fromFirestore(doc).toEntity())
          .toList();
      events.sort(compareEventsChronologically);
      return events;
    } catch (e) {
      throw DatabaseException('Failed to get upcoming events: $e');
    }
  }

  @override
  Future<List<Event>> getEventsByDateRange(DateTime start, DateTime end) async {
    try {
      final startTimestamp = Timestamp.fromDate(start);
      final endTimestamp = Timestamp.fromDate(end);

      final snapshot = await _firestore
          .collection(_eventsCollection)
          .where('startDate', isGreaterThanOrEqualTo: startTimestamp)
          .where('startDate', isLessThanOrEqualTo: endTimestamp)
          .orderBy('startDate')
          .get();

      final events = snapshot.docs
          .map((doc) => EventModel.fromFirestore(doc).toEntity())
          .toList();
      events.sort(compareEventsChronologically);
      return events;
    } catch (e) {
      throw DatabaseException('Failed to get events by date range: $e');
    }
  }

  @override
  Stream<List<Event>> watchEventsByDateRange(DateTime start, DateTime end) {
    final startTimestamp = Timestamp.fromDate(start);
    final endTimestamp = Timestamp.fromDate(end);

    return _firestore
        .collection(_eventsCollection)
        .where('startDate', isGreaterThanOrEqualTo: startTimestamp)
        .where('startDate', isLessThanOrEqualTo: endTimestamp)
        .orderBy('startDate')
        .snapshots()
        .map((snapshot) {
      final events = snapshot.docs
          .map((doc) => EventModel.fromFirestore(doc).toEntity())
          .toList();
      events.sort(compareEventsChronologically);
      return events;
    });
  }

  @override
  Future<void> insertEventsBatch(List<Event> events) async {
    try {
      await _invokeMutation(
        'event.insertBatch',
        payload: {
          'events': events.map(_eventEntityToMap).toList(),
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to insert events batch: $e');
    }
  }

  @override
  Future<bool> isDuplicateEvent(String name, DateTime startDate,
      {String? excludeEventId}) async {
    try {
      // Normalize the date to midnight for comparison
      final normalizedDate =
          DateTime(startDate.year, startDate.month, startDate.day);
      final startOfDay = Timestamp.fromDate(normalizedDate);
      final endOfDay =
          Timestamp.fromDate(normalizedDate.add(const Duration(days: 1)));

      final snapshot = await _firestore
          .collection(_eventsCollection)
          .where('name', isEqualTo: name)
          .where('startDate', isGreaterThanOrEqualTo: startOfDay)
          .where('startDate', isLessThan: endOfDay)
          .get();

      // If excludeEventId is provided, filter it out
      if (excludeEventId != null) {
        return snapshot.docs.any((doc) => doc.id != excludeEventId);
      }

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      throw DatabaseException('Failed to check for duplicate event: $e');
    }
  }

  @override
  Future<List<Event>> getEventsToArchive() async {
    try {
      final now = Timestamp.fromDate(DateTime.now());
      developer.log(
        'FirestoreDatabase.getEventsToArchive: Querying for events with endDate < $now (${now.toDate().toLocal()})',
        name: 'FirestoreDatabase',
      );

      // Get events where endDate < now, isArchived = false, and driveFolderId is not null
      // Note: Firestore doesn't support != null queries directly, so we filter in memory
      final snapshot = await _firestore
          .collection(_eventsCollection)
          .where('endDate', isLessThan: now)
          .where('isArchived', isEqualTo: false)
          .get();

      developer.log(
        'FirestoreDatabase.getEventsToArchive: Found ${snapshot.docs.length} events from Firestore query',
        name: 'FirestoreDatabase',
      );

      final allEvents = snapshot.docs
          .map((doc) => EventModel.fromFirestore(doc).toEntity())
          .toList();

      // Log all events for debugging
      for (final event in allEvents) {
        developer.log(
          'FirestoreDatabase.getEventsToArchive: Event - ${event.name}, endDate: ${event.endDate.toLocal()}, isArchived: ${event.isArchived}, driveFolderId: ${event.driveFolderId}',
          name: 'FirestoreDatabase',
        );
      }

      final withFolder = allEvents
          .where((event) =>
              event.driveFolderId != null && event.driveFolderId!.isNotEmpty)
          .toList();

      developer.log(
        'FirestoreDatabase.getEventsToArchive: Returning ${withFolder.length} events with drive folders',
        name: 'FirestoreDatabase',
      );

      return withFolder;
    } catch (e) {
      throw DatabaseException('Failed to get events to archive: $e');
    }
  }

  @override
  Future<void> updateEventArchiveStatus(String eventId, bool isArchived) async {
    try {
      await _invokeMutation(
        'event.updateArchiveStatus',
        payload: {
          'eventId': eventId,
          'isArchived': isArchived,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to update event archive status: $e');
    }
  }

  // ========== Assignments ==========

  /// Watch all assignments in real-time
  Stream<List<Assignment>> watchAssignments() {
    return _firestore
        .collection(_assignmentsCollection)
        .snapshots()
        .asyncMap((snapshot) async {
      final assignments = snapshot.docs
          .map((doc) => AssignmentModel.fromFirestore(doc).toEntity())
          .toList();

      // Populate relations
      return await _populateAssignmentRelations(assignments);
    });
  }

  /// Watch assignments for a specific event in real-time
  Stream<List<Assignment>> watchAssignmentsByEvent(String eventId) {
    return _firestore
        .collection(_assignmentsCollection)
        .where('eventId', isEqualTo: eventId)
        .snapshots()
        .asyncMap((snapshot) async {
      final assignments = snapshot.docs
          .map((doc) => AssignmentModel.fromFirestore(doc).toEntity())
          .toList();

      return await _populateAssignmentRelations(assignments);
    });
  }

  /// Watch assignments for a specific team member in real-time
  Stream<List<Assignment>> watchAssignmentsByPerson(String teamMemberId) {
    return _firestore
        .collection(_assignmentsCollection)
        .where('teamMemberId', isEqualTo: teamMemberId)
        .snapshots()
        .asyncMap((snapshot) async {
      final assignments = snapshot.docs
          .map((doc) => AssignmentModel.fromFirestore(doc).toEntity())
          .toList();

      return await _populateAssignmentRelations(assignments);
    });
  }

  @override
  Future<List<Assignment>> getAssignments() async {
    try {
      final snapshot =
          await _firestore.collection(_assignmentsCollection).get();

      final assignments = snapshot.docs
          .map((doc) => AssignmentModel.fromFirestore(doc).toEntity())
          .toList();

      // Populate relations
      return await _populateAssignmentRelations(assignments);
    } catch (e) {
      throw DatabaseException('Failed to get assignments: $e');
    }
  }

  @override
  Future<Assignment?> getAssignmentById(String id) async {
    try {
      final doc =
          await _firestore.collection(_assignmentsCollection).doc(id).get();

      if (!doc.exists) return null;

      final assignment = AssignmentModel.fromFirestore(doc).toEntity();

      // Populate relations
      final populated = await _populateAssignmentRelations([assignment]);
      return populated.firstOrNull;
    } catch (e) {
      throw DatabaseException('Failed to get assignment: $e');
    }
  }

  @override
  Future<List<Assignment>> getAssignmentsByEvent(String eventId) async {
    try {
      final snapshot = await _firestore
          .collection(_assignmentsCollection)
          .where('eventId', isEqualTo: eventId)
          .get();

      final assignments = snapshot.docs
          .map((doc) => AssignmentModel.fromFirestore(doc).toEntity())
          .toList();

      return await _populateAssignmentRelations(assignments);
    } catch (e) {
      throw DatabaseException('Failed to get assignments by event: $e');
    }
  }

  @override
  Future<List<Assignment>> getAssignmentsByPerson(String teamMemberId) async {
    try {
      final snapshot = await _firestore
          .collection(_assignmentsCollection)
          .where('teamMemberId', isEqualTo: teamMemberId)
          .get();

      final assignments = snapshot.docs
          .map((doc) => AssignmentModel.fromFirestore(doc).toEntity())
          .toList();

      return await _populateAssignmentRelations(assignments);
    } catch (e) {
      throw DatabaseException('Failed to get assignments by person: $e');
    }
  }

  @override
  Future<List<Assignment>> getAssignmentsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    try {
      // First get all events in the date range
      final events = await getEventsByDateRange(start, end);
      final eventIds = events.map((e) => e.id).toList();

      if (eventIds.isEmpty) return [];

      // Then get assignments for those events
      final snapshot = await _firestore
          .collection(_assignmentsCollection)
          .where('eventId', whereIn: eventIds)
          .get();

      final assignments = snapshot.docs
          .map((doc) => AssignmentModel.fromFirestore(doc).toEntity())
          .toList();

      return await _populateAssignmentRelations(assignments);
    } catch (e) {
      throw DatabaseException('Failed to get assignments by date range: $e');
    }
  }

  @override
  Future<List<Assignment>> getAssignmentsInTimeWindow(
    DateTime windowStart,
    DateTime windowEnd,
  ) async {
    try {
      // Step 1: Get events in the time window
      final events = await getEventsByDateRange(windowStart, windowEnd);
      if (events.isEmpty) return [];

      final eventIds = events.map((e) => e.id).toList();

      // Step 2: Batch fetch assignments (Firestore limits whereIn to 30 items)
      final assignments = <Assignment>[];
      for (int i = 0; i < eventIds.length; i += 30) {
        final chunk = eventIds.skip(i).take(30).toList();
        final snapshot = await _firestore
            .collection(_assignmentsCollection)
            .where('eventId', whereIn: chunk)
            .get();

        final chunkAssignments = snapshot.docs
            .map((doc) => AssignmentModel.fromFirestore(doc).toEntity())
            .toList();

        assignments.addAll(chunkAssignments);
      }

      // Step 3: Populate relations using optimized batch method
      return await _populateAssignmentRelations(assignments);
    } catch (e) {
      throw DatabaseException('Failed to get assignments in time window: $e');
    }
  }

  @override
  Stream<List<Assignment>> watchAssignmentsInTimeWindow(
    DateTime windowStart,
    DateTime windowEnd,
  ) async* {
    try {
      // Step 1: Get initial event IDs in the time window
      final events = await getEventsByDateRange(windowStart, windowEnd);
      if (events.isEmpty) {
        yield [];
        return;
      }

      final eventIds = events.map((e) => e.id).toList();

      // Step 2: Create streams for each chunk of event IDs
      final allStreams = <Stream<List<Assignment>>>[];
      for (int i = 0; i < eventIds.length; i += 30) {
        final chunk = eventIds.skip(i).take(30).toList();

        final stream = _firestore
            .collection(_assignmentsCollection)
            .where('eventId', whereIn: chunk)
            .snapshots()
            .asyncMap((snapshot) async {
          final assignments = snapshot.docs
              .map((doc) => AssignmentModel.fromFirestore(doc).toEntity())
              .toList();
          final populated = await _populateAssignmentRelations(assignments);
          return populated;
        });

        allStreams.add(stream);
      }

      // Step 3: Merge all streams and emit combined results
      // Using StreamGroup.merge instead of CombineLatestStream because:
      // - CombineLatestStream waits for ALL streams to emit before emitting
      // - With merge, we get updates as soon as any chunk has data
      // - We emit initial empty list first, then merge all stream emissions
      if (allStreams.isEmpty) {
        yield [];
        return;
      }

      // Create a controller that will emit combined results
      final controller = StreamController<List<Assignment>>();

      // Track latest values from each stream
      final latestValues = <List<Assignment>>[];
      final receivedCount = <int>{};

      // Track subscriptions so we can cancel them
      final subscriptions = <StreamSubscription>[];

      // Subscribe to each stream
      for (int i = 0; i < allStreams.length; i++) {
        final stream = allStreams[i];
        final index = i; // Capture for closure
        final subscription = stream.listen(
          (data) {
            // Don't add to closed controller
            if (controller.isClosed) return;

            // Replace old value at this index instead of appending
            while (latestValues.length <= index) {
              latestValues.add([]);
            }
            latestValues[index] = data;
            receivedCount.add(index);

            // CRITICAL FIX: Always emit combined result when ANY stream updates
            // (not just when all streams have emitted for the first time)
            // Build combined from all streams that have emitted so far
            final combined = <Assignment>[];
            for (int j = 0; j < allStreams.length; j++) {
              if (j < latestValues.length) {
                combined.addAll(latestValues[j]);
              }
            }
            controller.add(combined);
          },
          onError: (error) {
            if (!controller.isClosed) {
              controller.addError(error);
            }
          },
        );
        subscriptions.add(subscription);
      }

      // Cancel subscriptions when stream is canceled
      controller.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };

      // Emit the merged stream
      yield* controller.stream;
    } catch (e) {
      throw DatabaseException('Failed to watch assignments in time window: $e');
    }
  }

  @override
  Future<void> insertAssignment(
    Assignment assignment, {
    bool bypassAvailability = false,
  }) async {
    try {
      await _invokeMutation(
        'assignment.insert',
        payload: {
          'assignment': _assignmentEntityToMap(assignment),
          if (bypassAvailability) 'bypassAvailability': true,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to insert assignment: $e');
    }
  }

  @override
  Future<void> updateAssignment(
    Assignment assignment, {
    bool bypassAvailability = false,
  }) async {
    try {
      await _invokeMutation(
        'assignment.update',
        payload: {
          'assignment': _assignmentEntityToMap(assignment),
          if (bypassAvailability) 'bypassAvailability': true,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to update assignment: $e');
    }
  }

  @override
  Future<void> updateAssignmentMetadata(
    String assignmentId, {
    required String notes,
    String? semanticLabelId,
    String? alternativePhoneNumber,
  }) async {
    try {
      await _invokeMutation(
        'assignment.updateMetadata',
        payload: {
          'assignmentId': assignmentId,
          'notes': notes,
          'semanticLabelId': semanticLabelId,
          'alternativePhoneNumber': alternativePhoneNumber,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to update assignment metadata: $e');
    }
  }

  @override
  Future<void> deleteAssignment(String id) async {
    try {
      await _invokeMutation(
        'assignment.delete',
        payload: {'assignmentId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to delete assignment: $e');
    }
  }

  @override
  Future<void> deleteAssignmentsByEvent(String eventId) async {
    try {
      await _invokeMutation(
        'assignment.deleteByEvent',
        payload: {'eventId': eventId},
      );
    } catch (e) {
      throw DatabaseException('Failed to delete assignments by event: $e');
    }
  }

  @override
  Future<void> deleteAssignmentsByPerson(String teamMemberId) async {
    try {
      await _invokeMutation(
        'assignment.deleteByPerson',
        payload: {'teamMemberId': teamMemberId},
      );
    } catch (e) {
      throw DatabaseException('Failed to delete assignments by person: $e');
    }
  }

  @override
  Future<void> deleteAssignmentsBatch(List<String> assignmentIds) async {
    try {
      if (assignmentIds.isEmpty) return;
      await _invokeMutation(
        'assignment.deleteBatch',
        payload: {'assignmentIds': assignmentIds},
      );
    } catch (e) {
      throw DatabaseException('Failed to delete assignments batch: $e');
    }
  }

  @override
  Future<void> insertAssignmentsBatch(List<Assignment> assignments) async {
    try {
      await _invokeMutation(
        'assignment.insertBatch',
        payload: {
          'assignments': assignments.map(_assignmentEntityToMap).toList(),
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to insert assignments batch: $e');
    }
  }

  // ========== Assignment Labels ==========

  @override
  Future<List<AssignmentLabel>> getAssignmentLabels() async {
    try {
      final snapshot = await _firestore
          .collection(_assignmentLabelsCollection)
          .orderBy('sortOrder')
          .get();

      return snapshot.docs
          .map((doc) => AssignmentLabelModel.fromFirestore(doc).toEntity())
          .toList();
    } catch (e) {
      throw DatabaseException('Failed to get assignment labels: $e');
    }
  }

  @override
  Future<void> insertAssignmentLabel(AssignmentLabel label) async {
    try {
      await _invokeMutation(
        'assignmentLabel.insert',
        payload: {'label': _assignmentLabelEntityToMap(label)},
      );
    } catch (e) {
      throw DatabaseException('Failed to insert assignment label: $e');
    }
  }

  @override
  Future<void> updateAssignmentLabel(AssignmentLabel label) async {
    try {
      await _invokeMutation(
        'assignmentLabel.update',
        payload: {'label': _assignmentLabelEntityToMap(label)},
      );
    } catch (e) {
      throw DatabaseException('Failed to update assignment label: $e');
    }
  }

  @override
  Future<void> archiveAssignmentLabel(String id) async {
    try {
      await _invokeMutation(
        'assignmentLabel.archive',
        payload: {'labelId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to archive assignment label: $e');
    }
  }

  @override
  Future<void> restoreAssignmentLabel(String id) async {
    try {
      await _invokeMutation(
        'assignmentLabel.restore',
        payload: {'labelId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to restore assignment label: $e');
    }
  }

  @override
  Future<void> deleteAssignmentLabel(String id) async {
    try {
      await _invokeMutation(
        'assignmentLabel.delete',
        payload: {'labelId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to delete assignment label: $e');
    }
  }

  @override
  Future<void> updateAssignmentLabelsSortOrder(
    Map<String, int> labelIdToSortOrder,
  ) async {
    try {
      await _invokeMutation(
        'assignmentLabel.reorder',
        payload: {'labelIdToSortOrder': labelIdToSortOrder},
      );
    } catch (e) {
      throw DatabaseException(
        'Failed to update assignment labels sort order: $e',
      );
    }
  }

  @override
  Stream<List<AssignmentLabel>> watchAssignmentLabels() {
    return _firestore
        .collection(_assignmentLabelsCollection)
        .orderBy('sortOrder')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => AssignmentLabelModel.fromFirestore(doc).toEntity())
          .toList();
    });
  }

  // ========== Utility ==========

  @override
  Future<void> clearAllData() async {
    try {
      await _invokeMutation('utility.clearAllData');
    } catch (e) {
      throw DatabaseException('Failed to clear all data: $e');
    }
  }

  // ========== Private Helper Methods ==========

  /// Populate assignment relations (event, team member, and semantic label)
  /// OPTIMIZED: Uses batch queries (whereIn) instead of N+1 sequential queries
  /// Firestore allows up to 30 items in a single whereIn clause
  Future<List<Assignment>> _populateAssignmentRelations(
      List<Assignment> assignments) async {
    if (assignments.isEmpty) return assignments;

    // Get unique event IDs, team member IDs, and label IDs
    final eventIds = assignments.map((a) => a.eventId).toSet().toList();
    final memberIds = assignments.map((a) => a.teamMemberId).toSet().toList();
    final labelIds = assignments
        .map((a) => a.semanticLabelId)
        .whereType<String>()
        .toSet()
        .toList();

    // Batch fetch events (Firestore allows 30 items per whereIn query)
    final events = <String, Event>{};
    for (int i = 0; i < eventIds.length; i += 30) {
      final chunk = eventIds.skip(i).take(30).toList();
      final snapshot = await _firestore
          .collection(_eventsCollection)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in snapshot.docs) {
        final event = EventModel.fromFirestore(doc).toEntity();
        events[event.id] = event;
      }
    }

    // Batch fetch team members (same pattern)
    final members = <String, TeamMember>{};
    for (int i = 0; i < memberIds.length; i += 30) {
      final chunk = memberIds.skip(i).take(30).toList();
      final snapshot = await _firestore
          .collection(_teamMembersCollection)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in snapshot.docs) {
        final member = TeamMemberModel.fromFirestore(doc).toEntity();
        members[member.id] = member;
      }
    }

    // Batch fetch semantic labels (same pattern)
    final labels = <String, AssignmentLabel>{};
    for (int i = 0; i < labelIds.length; i += 30) {
      final chunk = labelIds.skip(i).take(30).toList();
      final snapshot = await _firestore
          .collection(_assignmentLabelsCollection)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in snapshot.docs) {
        final label = AssignmentLabelModel.fromFirestore(doc).toEntity();
        labels[label.id] = label;
      }
    }

    // Populate relations using cached data
    return assignments.map((assignment) {
      return assignment.withRelations(
        event: events[assignment.eventId],
        teamMember: members[assignment.teamMemberId],
        semanticLabel: () => assignment.semanticLabelId == null
            ? null
            : labels[assignment.semanticLabelId!],
      );
    }).toList();
  }

  // ========== Calendar Sync State ==========

  @override
  Future<void> saveCalendarSyncState({
    required String constraintId,
    required String calendarEventId,
    required String teamMemberId,
    required CalendarSyncStatus status,
  }) async {
    try {
      await _invokeMutation(
        'calendar.saveSyncState',
        payload: {
          'constraintId': constraintId,
          'calendarEventId': calendarEventId,
          'teamMemberId': teamMemberId,
          'status': status.name,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to save calendar sync state: $e');
    }
  }

  @override
  Future<String?> getCalendarEventId(String constraintId) async {
    try {
      final doc = await _firestore
          .collection(_calendarSyncCollection)
          .doc(constraintId)
          .get();

      if (!doc.exists) return null;

      return doc.data()?['calendarEventId'] as String?;
    } catch (e) {
      throw DatabaseException('Failed to get calendar event ID: $e');
    }
  }

  @override
  Future<Map<String, dynamic>?> getCalendarSyncState(
      String constraintId) async {
    try {
      final doc = await _firestore
          .collection(_calendarSyncCollection)
          .doc(constraintId)
          .get();

      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      return {
        'constraintId': constraintId,
        'calendarEventId': data['calendarEventId'],
        'teamMemberId': data['teamMemberId'],
        'status': data['status'],
        'syncedAt': data['syncedAt'],
        'updatedAt': data['updatedAt'],
        'retryCount': data['retryCount'] ?? 0,
        'errorMessage': data['errorMessage'],
      };
    } catch (e) {
      throw DatabaseException('Failed to get calendar sync state: $e');
    }
  }

  @override
  Future<void> updateCalendarSyncStatus(
    String constraintId,
    CalendarSyncStatus status, {
    String? errorMessage,
    int? retryCount,
  }) async {
    try {
      await _invokeMutation(
        'calendar.updateSyncStatus',
        payload: {
          'constraintId': constraintId,
          'status': status.name,
          if (errorMessage != null) 'errorMessage': errorMessage,
          if (retryCount != null) 'retryCount': retryCount,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to update calendar sync status: $e');
    }
  }

  @override
  Future<void> removeCalendarSyncState(String constraintId) async {
    try {
      await _invokeMutation(
        'calendar.removeSyncState',
        payload: {'constraintId': constraintId},
      );
    } catch (e) {
      throw DatabaseException('Failed to remove calendar sync state: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getFailedSyncStates() async {
    try {
      final snapshot = await _firestore
          .collection(_calendarSyncCollection)
          .where('status', isEqualTo: CalendarSyncStatus.failed.name)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'constraintId': doc.id,
          'calendarEventId': data['calendarEventId'],
          'teamMemberId': data['teamMemberId'],
          'status': data['status'],
          'syncedAt': data['syncedAt'],
          'updatedAt': data['updatedAt'],
          'retryCount': data['retryCount'] ?? 0,
          'errorMessage': data['errorMessage'],
        };
      }).toList();
    } catch (e) {
      throw DatabaseException('Failed to get failed sync states: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getSyncedConstraintsForMember(
      String teamMemberId) async {
    try {
      final snapshot = await _firestore
          .collection(_calendarSyncCollection)
          .where('teamMemberId', isEqualTo: teamMemberId)
          .where('status', isEqualTo: CalendarSyncStatus.synced.name)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'constraintId': doc.id,
          'calendarEventId': data['calendarEventId'],
          'teamMemberId': data['teamMemberId'],
          'status': data['status'],
          'syncedAt': data['syncedAt'],
          'updatedAt': data['updatedAt'],
        };
      }).toList();
    } catch (e) {
      throw DatabaseException(
          'Failed to get synced constraints for member: $e');
    }
  }

  @override
  Future<Map<String, dynamic>?> atomicCheckAndSetSyncState(
    String constraintId,
    String teamMemberId,
  ) async {
    try {
      return await _invokeMutation(
        'calendar.atomicCheckAndSetSyncState',
        payload: {
          'constraintId': constraintId,
          'teamMemberId': teamMemberId,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to atomic check and set sync state: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getSyncedConstraintsForAllMembers() async {
    try {
      final snapshot = await _firestore
          .collection(_calendarSyncCollection)
          .where('status', isEqualTo: CalendarSyncStatus.synced.name)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        final result = {
          'constraintId': doc.id,
          'calendarEventId': data['calendarEventId'],
          'teamMemberId': data['teamMemberId'],
          'status': data['status'],
          'syncedAt': data['syncedAt'],
          'updatedAt': data['updatedAt'],
        };
        return result;
      }).toList();
    } catch (e) {
      throw DatabaseException('Failed to get synced constraints: $e');
    }
  }

  // ========== Event Calendar Sync State ==========

  @override
  Future<void> saveEventCalendarSyncState({
    required String eventId,
    required String assemblyCalendarEventId,
    required String mainCalendarEventId,
    required CalendarSyncStatus status,
  }) async {
    try {
      await _invokeMutation(
        'calendar.saveEventSyncState',
        payload: {
          'eventId': eventId,
          'assemblyCalendarEventId': assemblyCalendarEventId,
          'mainCalendarEventId': mainCalendarEventId,
          'status': status.name,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to save event calendar sync state: $e');
    }
  }

  @override
  Future<Map<String, dynamic>?> getEventCalendarSyncState(
      String eventId) async {
    try {
      final doc = await _firestore
          .collection(_eventCalendarSyncCollection)
          .doc(eventId)
          .get();

      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      return {
        'eventId': eventId,
        'assemblyCalendarEventId': data['assemblyCalendarEventId'],
        'mainCalendarEventId': data['mainCalendarEventId'],
        'status': data['status'],
        'syncedAt': data['syncedAt'],
        'updatedAt': data['updatedAt'],
      };
    } catch (e) {
      throw DatabaseException('Failed to get event calendar sync state: $e');
    }
  }

  @override
  Future<void> removeEventCalendarSyncState(String eventId) async {
    try {
      await _invokeMutation(
        'calendar.removeEventSyncState',
        payload: {'eventId': eventId},
      );
    } catch (e) {
      throw DatabaseException('Failed to remove event calendar sync state: $e');
    }
  }

  @override
  Future<Map<String, String?>?> getGoogleCalendarConfig() async {
    // Google Calendar config is backend-only. The client should never read it.
    return null;
  }

  @override
  Future<Map<String, String?>?> getDriveConfig() async {
    // Google Drive config is backend-only. The client should never read it.
    return null;
  }

  // ========== Checklist Items Implementation ==========

  @override
  Future<List<ChecklistItem>> getChecklistItems() async {
    try {
      final snapshot =
          await _firestore.collection(_checklistItemsCollection).get();
      final items = <ChecklistItem>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        // Get related data
        final event = await getEventById(data['eventId'] as String);
        final responsibleId = (data['responsibleId'] as String?) ?? '';
        final responsible = responsibleId.trim().isEmpty
            ? null
            : await getTeamMemberById(responsibleId);

        // Get CC members
        final ccIds =
            (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final ccMembers = <TeamMember>[];
        for (final ccId in ccIds) {
          final member = await getTeamMemberById(ccId);
          if (member != null) ccMembers.add(member);
        }

        items.add(ChecklistItemModel.fromFirestore(
            doc, event, responsible, ccMembers));
      }

      return items;
    } catch (e) {
      throw DatabaseException('Failed to fetch checklist items: $e');
    }
  }

  @override
  Future<ChecklistItem?> getChecklistItemById(String id) async {
    try {
      final doc =
          await _firestore.collection(_checklistItemsCollection).doc(id).get();
      if (!doc.exists) return null;

      final data = doc.data() as Map<String, dynamic>;

      // Get related data
      final event = await getEventById(data['eventId'] as String);
      final responsibleId = (data['responsibleId'] as String?) ?? '';
      final responsible = responsibleId.trim().isEmpty
          ? null
          : await getTeamMemberById(responsibleId);

      // Get CC members
      final ccIds =
          (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final ccMembers = <TeamMember>[];
      for (final ccId in ccIds) {
        final member = await getTeamMemberById(ccId);
        if (member != null) ccMembers.add(member);
      }

      return ChecklistItemModel.fromFirestore(
          doc, event, responsible, ccMembers);
    } catch (e) {
      throw DatabaseException('Failed to fetch checklist item by ID: $e');
    }
  }

  @override
  Future<List<ChecklistItem>> getChecklistItemsByEvent(String eventId) async {
    try {
      final snapshot = await _firestore
          .collection(_checklistItemsCollection)
          .where('eventId', isEqualTo: eventId)
          .get();
      final items = <ChecklistItem>[];

      // Get related data once for efficiency
      final event = await getEventById(eventId);
      final allTeamMembers = await getTeamMembers();
      final memberMap = {for (var member in allTeamMembers) member.id: member};

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final responsibleId = data['responsibleId'] as String;
        final responsible = memberMap[responsibleId];

        // Get CC members
        final ccIds =
            (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final ccMembers = ccIds
            .map((id) => memberMap[id])
            .where((member) => member != null)
            .cast<TeamMember>()
            .toList();

        items.add(ChecklistItemModel.fromFirestore(
            doc, event, responsible, ccMembers));
      }

      return items;
    } catch (e) {
      throw DatabaseException('Failed to fetch checklist items by event: $e');
    }
  }

  @override
  Future<List<ChecklistItem>> getChecklistItemsForTeamMember(
      String teamMemberId) async {
    try {
      // Query where team member is either responsible or CC'd
      final responsibleSnapshot = await _firestore
          .collection(_checklistItemsCollection)
          .where('responsibleId', isEqualTo: teamMemberId)
          .get();

      final ccSnapshot = await _firestore
          .collection(_checklistItemsCollection)
          .where('ccIds', arrayContains: teamMemberId)
          .get();

      final items = <ChecklistItem>[];
      final allDocs = [...responsibleSnapshot.docs, ...ccSnapshot.docs];
      final seenIds = <String>{};

      // Get all related data once
      final allTeamMembers = await getTeamMembers();
      final memberMap = {for (var member in allTeamMembers) member.id: member};
      final allEvents = await getEvents();
      final eventMap = {for (var event in allEvents) event.id: event};

      for (final doc in allDocs) {
        if (seenIds.contains(doc.id)) continue; // Avoid duplicates
        seenIds.add(doc.id);

        final data = doc.data();

        final eventId = data['eventId'] as String;
        final event = eventMap[eventId];

        final responsibleId = data['responsibleId'] as String;
        final responsible = memberMap[responsibleId];

        // Get CC members
        final ccIds =
            (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final ccMembers = ccIds
            .map((id) => memberMap[id])
            .where((member) => member != null)
            .cast<TeamMember>()
            .toList();

        items.add(ChecklistItemModel.fromFirestore(
            doc, event, responsible, ccMembers));
      }

      return items;
    } catch (e) {
      throw DatabaseException(
          'Failed to fetch checklist items for team member: $e');
    }
  }

  @override
  Future<List<ChecklistItem>> getChecklistItemsWhereResponsible(
      String teamMemberId) async {
    try {
      final snapshot = await _firestore
          .collection(_checklistItemsCollection)
          .where('responsibleId', isEqualTo: teamMemberId)
          .get();
      final items = <ChecklistItem>[];

      // Get all related data once
      final allTeamMembers = await getTeamMembers();
      final memberMap = {for (var member in allTeamMembers) member.id: member};
      final allEvents = await getEvents();
      final eventMap = {for (var event in allEvents) event.id: event};

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final eventId = data['eventId'] as String;
        final event = eventMap[eventId];

        final responsibleId = data['responsibleId'] as String;
        final responsible = memberMap[responsibleId];

        // Get CC members
        final ccIds =
            (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final ccMembers = ccIds
            .map((id) => memberMap[id])
            .where((member) => member != null)
            .cast<TeamMember>()
            .toList();

        items.add(ChecklistItemModel.fromFirestore(
            doc, event, responsible, ccMembers));
      }

      return items;
    } catch (e) {
      throw DatabaseException(
          'Failed to fetch checklist items where responsible: $e');
    }
  }

  @override
  Future<List<ChecklistItem>> getChecklistItemsWhereCc(
      String teamMemberId) async {
    try {
      final snapshot = await _firestore
          .collection(_checklistItemsCollection)
          .where('ccIds', arrayContains: teamMemberId)
          .get();
      final items = <ChecklistItem>[];

      // Get all related data once
      final allTeamMembers = await getTeamMembers();
      final memberMap = {for (var member in allTeamMembers) member.id: member};
      final allEvents = await getEvents();
      final eventMap = {for (var event in allEvents) event.id: event};

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final eventId = data['eventId'] as String;
        final event = eventMap[eventId];

        final responsibleId = data['responsibleId'] as String;
        final responsible = memberMap[responsibleId];

        // Get CC members
        final ccIds =
            (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final ccMembers = ccIds
            .map((id) => memberMap[id])
            .where((member) => member != null)
            .cast<TeamMember>()
            .toList();

        items.add(ChecklistItemModel.fromFirestore(
            doc, event, responsible, ccMembers));
      }

      return items;
    } catch (e) {
      throw DatabaseException('Failed to fetch checklist items where CC: $e');
    }
  }

  @override
  Future<void> insertChecklistItem(ChecklistItem item) async {
    try {
      await _invokeMutation(
        'checklist.insert',
        payload: {'item': _checklistItemEntityToMap(item)},
      );
    } catch (e) {
      throw DatabaseException('Failed to insert checklist item: $e');
    }
  }

  @override
  Future<void> updateChecklistItem(ChecklistItem item) async {
    try {
      await _invokeMutation(
        'checklist.update',
        payload: {'item': _checklistItemEntityToMap(item)},
      );
    } catch (e) {
      throw DatabaseException('Failed to update checklist item: $e');
    }
  }

  @override
  Future<void> deleteChecklistItem(String id) async {
    try {
      await _invokeMutation(
        'checklist.delete',
        payload: {'itemId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to delete checklist item: $e');
    }
  }

  @override
  Future<void> deleteChecklistItemsByEvent(String eventId) async {
    try {
      await _invokeMutation(
        'checklist.deleteByEvent',
        payload: {'eventId': eventId},
      );
    } catch (e) {
      throw DatabaseException('Failed to delete checklist items by event: $e');
    }
  }

  @override
  Future<void> addNoteToChecklistItem(
      String checklistItemId, Map<String, dynamic> noteData) async {
    try {
      await _invokeMutation(
        'checklist.addNote',
        payload: {
          'checklistItemId': checklistItemId,
          'noteData': noteData,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to add note to checklist item: $e');
    }
  }

  // ========== Checklist Presets ==========

  @override
  Future<List<Preset>> getPresets() async {
    try {
      final snapshot =
          await _firestore.collection(_presetsCollection).orderBy('name').get();

      return snapshot.docs
          .map((doc) => PresetModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw DatabaseException('Failed to get presets: $e');
    }
  }

  @override
  Future<Preset?> getPresetById(String id) async {
    try {
      final doc = await _firestore.collection(_presetsCollection).doc(id).get();
      if (!doc.exists) return null;
      return PresetModel.fromFirestore(doc);
    } catch (e) {
      throw DatabaseException('Failed to get preset by ID: $e');
    }
  }

  @override
  Future<void> insertPreset(Preset preset) async {
    try {
      await _invokeMutation(
        'preset.insert',
        payload: {'preset': _presetEntityToMap(preset)},
      );
    } catch (e) {
      throw DatabaseException('Failed to insert preset: $e');
    }
  }

  @override
  Future<void> updatePreset(Preset preset) async {
    try {
      await _invokeMutation(
        'preset.update',
        payload: {'preset': _presetEntityToMap(preset)},
      );
    } catch (e) {
      throw DatabaseException('Failed to update preset: $e');
    }
  }

  @override
  Future<void> deletePreset(String id) async {
    try {
      await _invokeMutation(
        'preset.delete',
        payload: {'presetId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to delete preset: $e');
    }
  }

  @override
  Future<void> loadPresetIntoEvent(
      String presetId, String eventId, String creatorAdminId) async {
    try {
      await _invokeMutation(
        'preset.loadIntoEvent',
        payload: {
          'presetId': presetId,
          'eventId': eventId,
          'creatorAdminId': creatorAdminId,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to load preset into event: $e');
    }
  }

  // ========== Roles ==========
  // Roles are stored in utilities/Lists document, Roles field (array)

  @override
  Future<List<Role>> getRoles() async {
    try {
      final doc = await _firestore.collection('utilities').doc('Lists').get();

      if (!doc.exists || doc.data() == null) {
        developer.log(
            'FirestoreDatabase.getRoles: utilities/Lists document does not exist',
            name: 'Firestore');
        return [];
      }

      final data = doc.data()!;
      final rolesArray = data['Roles'] as List<dynamic>?;

      if (rolesArray == null || rolesArray.isEmpty) {
        developer.log(
            'FirestoreDatabase.getRoles: Roles array is empty or null',
            name: 'Firestore');
        return [];
      }

      final roles = rolesArray
          .map((roleData) =>
              RoleModel.fromJson(roleData as Map<String, dynamic>).toEntity())
          .toList();

      // Sort by sortOrder
      roles.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      return roles;
    } catch (e) {
      throw DatabaseException('Failed to get roles: $e');
    }
  }

  @override
  Future<Role?> getRoleById(String id) async {
    try {
      final roles = await getRoles();
      try {
        return roles.firstWhere((role) => role.id == id);
      } catch (e) {
        return null;
      }
    } catch (e) {
      throw DatabaseException('Failed to get role by ID: $e');
    }
  }

  @override
  Future<Role?> getRoleByKey(String key) async {
    try {
      final roles = await getRoles();
      try {
        return roles.firstWhere((role) => role.key == key);
      } catch (e) {
        return null;
      }
    } catch (e) {
      throw DatabaseException('Failed to get role by key: $e');
    }
  }

  @override
  Future<void> insertRole(Role role) async {
    try {
      await _invokeMutation(
        'role.insert',
        payload: {'role': _roleEntityToMap(role)},
      );
    } catch (e) {
      throw DatabaseException('Failed to insert role: $e');
    }
  }

  @override
  Future<void> updateRole(Role role) async {
    try {
      await _invokeMutation(
        'role.update',
        payload: {'role': _roleEntityToMap(role)},
      );
    } catch (e) {
      throw DatabaseException('Failed to update role: $e');
    }
  }

  @override
  Future<void> archiveRole(String id) async {
    try {
      await _invokeMutation(
        'role.archive',
        payload: {'roleId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to archive role: $e');
    }
  }

  @override
  Future<void> restoreRole(String id) async {
    try {
      await _invokeMutation(
        'role.restore',
        payload: {'roleId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to restore role: $e');
    }
  }

  @override
  Future<void> deleteRole(String id) async {
    try {
      await _invokeMutation(
        'role.delete',
        payload: {'roleId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to delete role: $e');
    }
  }

  @override
  Stream<List<Role>> watchRoles() {
    try {
      return _firestore
          .collection('utilities')
          .doc('Lists')
          .snapshots()
          .map((doc) {
        if (!doc.exists || doc.data() == null) {
          return <Role>[];
        }

        final data = doc.data()!;
        final rolesArray = data['Roles'] as List<dynamic>?;

        if (rolesArray == null || rolesArray.isEmpty) {
          return <Role>[];
        }

        final roles = rolesArray
            .map((roleData) =>
                RoleModel.fromJson(roleData as Map<String, dynamic>).toEntity())
            .toList();

        // Sort by sortOrder
        roles.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

        return roles;
      });
    } catch (e) {
      throw DatabaseException('Failed to watch roles: $e');
    }
  }

  @override
  Future<void> seedRolesFromEnum() async {
    try {
      final now = DateTime.now();
      int sortOrder = 0;
      final roles = <Map<String, dynamic>>[];

      for (final roleType in RoleType.values) {
        final role = Role(
          id: roleType.key,
          key: roleType.key,
          hebrewName: roleType.hebrewName,
          isVisible: true,
          isArchived: false,
          sortOrder: sortOrder++,
          createdAt: now,
          updatedAt: now,
        );

        roles.add(_roleEntityToMap(role));
      }
      await _invokeMutation(
        'role.seed',
        payload: {'roles': roles},
      );
    } catch (e) {
      throw DatabaseException('Failed to seed roles from enum: $e');
    }
  }

  @override
  Future<void> updateRolesSortOrder(Map<String, int> roleIdToSortOrder) async {
    try {
      await _invokeMutation(
        'role.reorder',
        payload: {'roleIdToSortOrder': roleIdToSortOrder},
      );
    } catch (e) {
      throw DatabaseException('Failed to update roles sort order: $e');
    }
  }

  // ========== Categories ==========
  // Categories are stored in utilities/Lists document, Categories field (array)

  @override
  Future<List<Category>> getCategories() async {
    try {
      final doc = await _firestore.collection('utilities').doc('Lists').get();

      if (!doc.exists || doc.data() == null) {
        developer.log(
            'FirestoreDatabase.getCategories: utilities/Lists document does not exist',
            name: 'Firestore');
        return [];
      }

      final data = doc.data()!;
      final categoriesArray = data['Categories'] as List<dynamic>?;

      if (categoriesArray == null || categoriesArray.isEmpty) {
        developer.log(
            'FirestoreDatabase.getCategories: Categories array is empty or null',
            name: 'Firestore');
        return [];
      }

      final categories = categoriesArray
          .map((categoryData) =>
              CategoryModel.fromJson(categoryData as Map<String, dynamic>)
                  .toEntity())
          .toList();

      // Sort by sortOrder
      categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      return categories;
    } catch (e) {
      throw DatabaseException('Failed to get categories: $e');
    }
  }

  @override
  Future<List<Category>> getActiveCategories() async {
    try {
      final allCategories = await getCategories();
      final activeCategories =
          allCategories.where((cat) => !cat.isArchived).toList();
      return activeCategories;
    } catch (e) {
      throw DatabaseException('Failed to get active categories: $e');
    }
  }

  @override
  Future<Category?> getCategoryById(String id) async {
    try {
      final categories = await getCategories();
      try {
        return categories.firstWhere((category) => category.id == id);
      } catch (e) {
        return null;
      }
    } catch (e) {
      throw DatabaseException('Failed to get category: $e');
    }
  }

  @override
  Future<void> insertCategory(Category category) async {
    try {
      await _invokeMutation(
        'category.insert',
        payload: {'category': _categoryEntityToMap(category)},
      );
    } catch (e) {
      throw DatabaseException('Failed to insert category: $e');
    }
  }

  @override
  Future<void> updateCategory(Category category) async {
    try {
      await _invokeMutation(
        'category.update',
        payload: {'category': _categoryEntityToMap(category)},
      );
    } catch (e) {
      throw DatabaseException('Failed to update category: $e');
    }
  }

  @override
  Future<void> deleteCategory(String id) async {
    try {
      await _invokeMutation(
        'category.delete',
        payload: {'categoryId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to delete category: $e');
    }
  }

  @override
  Future<void> permanentlyDeleteCategory(String id) async {
    try {
      await _invokeMutation(
        'category.permanentlyDelete',
        payload: {'categoryId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to permanently delete category: $e');
    }
  }

  @override
  Future<void> restoreCategory(String id) async {
    try {
      await _invokeMutation(
        'category.restore',
        payload: {'categoryId': id},
      );
    } catch (e) {
      throw DatabaseException('Failed to restore category: $e');
    }
  }

  @override
  Stream<List<Category>> watchCategories() {
    return _firestore
        .collection('utilities')
        .doc('Lists')
        .snapshots()
        .map<List<Category>>((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        developer.log(
            'FirestoreDatabase.watchCategories: Document does not exist',
            name: 'Firestore');
        return <Category>[];
      }

      final data = snapshot.data()!;
      final categoriesArray = data['Categories'] as List<dynamic>?;

      if (categoriesArray == null || categoriesArray.isEmpty) {
        developer.log(
            'FirestoreDatabase.watchCategories: Categories array is empty or null',
            name: 'Firestore');
        return <Category>[];
      }

      final categories = categoriesArray
          .map((categoryData) =>
              CategoryModel.fromJson(categoryData as Map<String, dynamic>)
                  .toEntity())
          .toList();

      // Sort by sortOrder
      categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      return categories;
    }).handleError((error) {
      throw DatabaseException('Failed to watch categories: $error');
    });
  }

  @override
  Stream<List<Category>> watchActiveCategories() {
    return watchCategories().map((categories) {
      final activeCategories =
          categories.where((cat) => !cat.isArchived).toList();
      return activeCategories;
    });
  }
}

/// Custom exception for database errors
class DatabaseException implements Exception {
  final String message;
  DatabaseException(this.message);

  @override
  String toString() => 'DatabaseException: $message';
}
