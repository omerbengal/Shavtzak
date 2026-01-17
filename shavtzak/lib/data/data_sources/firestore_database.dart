import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/assignment.dart';
import '../../domain/entities/checklist_item.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/preset.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/team_member.dart';
import '../../core/constants/constraint_status.dart';
import '../../core/constants/calendar_constants.dart';
import '../../core/constants/role_types.dart';
import '../../core/services/environment_service.dart';
import '../models/assignment_model.dart';
import '../models/checklist_item_model.dart';
import '../models/event_model.dart';
import '../models/preset_model.dart';
import '../models/role_model.dart';
import '../models/team_member_model.dart';
import 'database_interface.dart';

/// Firestore implementation of DatabaseInterface
class FirestoreDatabase implements DatabaseInterface {
  final FirebaseFirestore _firestore;
  final String _instanceId; // For debugging

  // Collection names with environment prefix
  String get _teamMembersCollection {
    final collection = '${EnvironmentService.instance.collectionPrefix}teamMembers';
    developer.log('FirestoreDatabase._teamMembersCollection: instance=$_instanceId, collection=$collection', name: 'Firestore');
    return collection;
  }

  String get _eventsCollection {
    final collection = '${EnvironmentService.instance.collectionPrefix}events';
    developer.log('FirestoreDatabase._eventsCollection: instance=$_instanceId, collection=$collection', name: 'Firestore');
    return collection;
  }

  String get _assignmentsCollection {
    final collection = '${EnvironmentService.instance.collectionPrefix}assignments';
    developer.log('FirestoreDatabase._assignmentsCollection: instance=$_instanceId, collection=$collection', name: 'Firestore');
    return collection;
  }

  String get _calendarSyncCollection {
    final collection = '${EnvironmentService.instance.collectionPrefix}calendar_sync';
    developer.log('FirestoreDatabase._calendarSyncCollection: instance=$_instanceId, collection=$collection', name: 'Firestore');
    return collection;
  }

  String get _checklistItemsCollection {
    final collection = '${EnvironmentService.instance.collectionPrefix}checklist_items';
    developer.log('FirestoreDatabase._checklistItemsCollection: instance=$_instanceId, collection=$collection', name: 'Firestore');
    return collection;
  }

  String get _presetsCollection {
    final collection = '${EnvironmentService.instance.collectionPrefix}checklist_presets';
    developer.log('FirestoreDatabase._presetsCollection: instance=$_instanceId, collection=$collection', name: 'Firestore');
    return collection;
  }

  FirestoreDatabase({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _instanceId = DateTime.now().millisecondsSinceEpoch.toString() {
    developer.log('FirestoreDatabase.constructor: instance=$_instanceId created', name: 'Firestore');
  }

  @override
  Future<void> initialize() async {
    // Firestore doesn't require explicit initialization
    // Connection is established automatically
  }

  @override
  Future<void> close() async {
    // Firestore connections are managed automatically
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
    final collection = _teamMembersCollection;
    developer.log('FirestoreDatabase.watchTeamMembers: instance=$_instanceId, creating stream for collection=$collection', name: 'Firestore');

    return _firestore
        .collection(collection)
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      final count = snapshot.docs.length;
      developer.log('FirestoreDatabase.watchTeamMembers: instance=$_instanceId, received snapshot with $count documents from $collection', name: 'Firestore');
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
      final model = TeamMemberModel.fromEntity(member);
      await _firestore
          .collection(_teamMembersCollection)
          .doc(member.id)
          .set(model.toFirestore());
    } catch (e) {
      throw DatabaseException('Failed to insert team member: $e');
    }
  }

  @override
  Future<void> updateTeamMember(TeamMember member) async {
    try {
      final model = TeamMemberModel.fromEntity(member);
      await _firestore
          .collection(_teamMembersCollection)
          .doc(member.id)
          .update(model.toFirestore());
    } catch (e) {
      throw DatabaseException('Failed to update team member: $e');
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
      // If constraintIndex is null, teamMemberIdOrConstraintId is actually the constraintId
      // and we need to find which team member owns this constraint
      if (constraintIndex == null) {
        // Find constraint by ID across all team members
        final teamMembersSnapshot = await _firestore
            .collection(_teamMembersCollection)
            .get();


        bool constraintFound = false;
        for (final teamMemberDoc in teamMembersSnapshot.docs) {
          final teamMemberData = teamMemberDoc.data();
          final constraints = (teamMemberData['constraints'] as List<dynamic>?);

          if (constraints != null) {
            // Find the constraint in the inline array
            final constraintIndex = constraints.indexWhere(
              (c) => c['id'] == teamMemberIdOrConstraintId,
            );

            if (constraintIndex != -1) {
              constraintFound = true;

              // Update the constraint status in the array
              final updatedConstraints = List<dynamic>.from(constraints);
              updatedConstraints[constraintIndex]['status'] = newStatus.name;

              if (note != null) {
                updatedConstraints[constraintIndex]['note'] = note;
              }

              if (wasAutoRejectedFromCalendar != null) {
                updatedConstraints[constraintIndex]['wasAutoRejectedFromCalendar'] = wasAutoRejectedFromCalendar;
              }

              await teamMemberDoc.reference.update({
                'constraints': updatedConstraints,
                'updatedAt': FieldValue.serverTimestamp(),
              });
              return;
            }
          }
        }

        if (!constraintFound) {
          throw DatabaseException('Constraint not found: $teamMemberIdOrConstraintId');
        }
      } else {
        // Original logic: update constraint by index in a specific team member
        final teamMemberId = teamMemberIdOrConstraintId;

        // Get the current team member
        final doc = await _firestore
            .collection(_teamMembersCollection)
            .doc(teamMemberId)
            .get();

        if (!doc.exists) {
          throw DatabaseException('Team member not found: $teamMemberId');
        }

        final teamMember = TeamMemberModel.fromFirestore(doc).toEntity();

        // Check if constraint index is valid
        if (constraintIndex < 0 || constraintIndex >= teamMember.constraints.length) {
          throw DatabaseException('Invalid constraint index: $constraintIndex');
        }

        // Update the constraint status
        final updatedConstraints = List<DateConstraint>.from(teamMember.constraints);
        updatedConstraints[constraintIndex] = updatedConstraints[constraintIndex].copyWith(
          status: newStatus,
          note: note, // Also update the note if provided
          wasAutoRejectedFromCalendar: wasAutoRejectedFromCalendar,
        );

        // Convert DateConstraint entities to JSON
        final constraintsJson = updatedConstraints.map((constraint) {
          final model = DateConstraintModel.fromEntity(constraint);
          return model.toJson();
        }).toList();

        // Update only the constraints field in Firestore
        await _firestore
            .collection(_teamMembersCollection)
            .doc(teamMemberId)
            .update({
              'constraints': constraintsJson,
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }
    } catch (e) {
      throw DatabaseException('Failed to update constraint status: $e');
    }
  }

  @override
  Future<void> deleteTeamMember(String id) async {
    try {
      await _firestore.collection(_teamMembersCollection).doc(id).delete();
    } catch (e) {
      throw DatabaseException('Failed to delete team member: $e');
    }
  }

  @override
  Future<void> insertTeamMembersBatch(List<TeamMember> members) async {
    try {
      final batch = _firestore.batch();

      for (final member in members) {
        final model = TeamMemberModel.fromEntity(member);
        final docRef =
            _firestore.collection(_teamMembersCollection).doc(member.id);
        batch.set(docRef, model.toFirestore());
      }

      await batch.commit();
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
      return snapshot.docs
          .map((doc) => EventModel.fromFirestore(doc).toEntity())
          .toList();
    });
  }

  @override
  Future<List<Event>> getEvents() async {
    try {
      final snapshot = await _firestore
          .collection(_eventsCollection)
          .orderBy('startDate', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => EventModel.fromFirestore(doc).toEntity())
          .toList();
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
      final model = EventModel.fromEntity(event);
      await _firestore
          .collection(_eventsCollection)
          .doc(event.id)
          .set(model.toFirestore());
    } catch (e) {
      throw DatabaseException('Failed to insert event: $e');
    }
  }

  @override
  Future<void> updateEvent(Event event) async {
    try {
      final model = EventModel.fromEntity(event);
      await _firestore
          .collection(_eventsCollection)
          .doc(event.id)
          .update(model.toFirestore());
    } catch (e) {
      throw DatabaseException('Failed to update event: $e');
    }
  }

  @override
  Future<void> deleteEvent(String id) async {
    try {
      // Cascade delete: first delete all checklist items for this event
      final checklistItemsSnapshot = await _firestore
          .collection(_checklistItemsCollection)
          .where('eventId', isEqualTo: id)
          .get();

      final batch = _firestore.batch();
      for (var doc in checklistItemsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // Delete the event itself
      batch.delete(_firestore.collection(_eventsCollection).doc(id));

      await batch.commit();
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

      return snapshot.docs
          .map((doc) => EventModel.fromFirestore(doc).toEntity())
          .toList();
    } catch (e) {
      throw DatabaseException('Failed to get upcoming events: $e');
    }
  }

  @override
  Future<List<Event>> getEventsByDateRange(
      DateTime start, DateTime end) async {
    try {
      final startTimestamp = Timestamp.fromDate(start);
      final endTimestamp = Timestamp.fromDate(end);

      final snapshot = await _firestore
          .collection(_eventsCollection)
          .where('startDate', isGreaterThanOrEqualTo: startTimestamp)
          .where('startDate', isLessThanOrEqualTo: endTimestamp)
          .orderBy('startDate')
          .get();

      return snapshot.docs
          .map((doc) => EventModel.fromFirestore(doc).toEntity())
          .toList();
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
        .map((snapshot) => snapshot.docs
            .map((doc) => EventModel.fromFirestore(doc).toEntity())
            .toList());
  }

  @override
  Future<void> insertEventsBatch(List<Event> events) async {
    try {
      final batch = _firestore.batch();

      for (final event in events) {
        final model = EventModel.fromEntity(event);
        final docRef = _firestore.collection(_eventsCollection).doc(event.id);
        batch.set(docRef, model.toFirestore());
      }

      await batch.commit();
    } catch (e) {
      throw DatabaseException('Failed to insert events batch: $e');
    }
  }

  @override
  Future<bool> isDuplicateEvent(String name, DateTime startDate, {String? excludeEventId}) async {
    try {
      // Normalize the date to midnight for comparison
      final normalizedDate = DateTime(startDate.year, startDate.month, startDate.day);
      final startOfDay = Timestamp.fromDate(normalizedDate);
      final endOfDay = Timestamp.fromDate(normalizedDate.add(const Duration(days: 1)));

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
          .where((event) => event.driveFolderId != null && event.driveFolderId!.isNotEmpty)
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
      await _firestore
          .collection(_eventsCollection)
          .doc(eventId)
          .update({
            'isArchived': isArchived,
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          });
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

      // Subscribe to each stream
      for (int i = 0; i < allStreams.length; i++) {
        final stream = allStreams[i];
        stream.listen(
          (data) {
            latestValues.add(data);
            receivedCount.add(i);

            // When we have data from all streams, emit combined result
            if (receivedCount.length == allStreams.length) {
              final combined = latestValues.expand((list) => list).toList();
              controller.add(combined);
            }
          },
          onError: (error) {
            controller.addError(error);
          },
        );
      }

      // Close controller and cancel subscriptions when done
      controller.onCancel = () async {
        await controller.close();
      };

      // Emit the merged stream
      yield* controller.stream;
    } catch (e) {
      throw DatabaseException('Failed to watch assignments in time window: $e');
    }
  }

  @override
  Future<void> insertAssignment(Assignment assignment) async {
    try {
      // Validate foreign keys exist
      await _validateAssignmentForeignKeys(
          assignment.eventId, assignment.teamMemberId);

      final model = AssignmentModel.fromEntity(assignment);
      await _firestore
          .collection(_assignmentsCollection)
          .doc(assignment.id)
          .set(model.toFirestore());
    } catch (e) {
      throw DatabaseException('Failed to insert assignment: $e');
    }
  }

  @override
  Future<void> updateAssignment(Assignment assignment) async {
    try {
      // Validate foreign keys exist
      await _validateAssignmentForeignKeys(
          assignment.eventId, assignment.teamMemberId);

      final model = AssignmentModel.fromEntity(assignment);
      await _firestore
          .collection(_assignmentsCollection)
          .doc(assignment.id)
          .update(model.toFirestore());
    } catch (e) {
      throw DatabaseException('Failed to update assignment: $e');
    }
  }

  @override
  Future<void> deleteAssignment(String id) async {
    try {
      await _firestore.collection(_assignmentsCollection).doc(id).delete();
    } catch (e) {
      throw DatabaseException('Failed to delete assignment: $e');
    }
  }

  @override
  Future<void> deleteAssignmentsByEvent(String eventId) async {
    try {
      final snapshot = await _firestore
          .collection(_assignmentsCollection)
          .where('eventId', isEqualTo: eventId)
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      throw DatabaseException('Failed to delete assignments by event: $e');
    }
  }

  @override
  Future<void> deleteAssignmentsByPerson(String teamMemberId) async {
    try {
      final snapshot = await _firestore
          .collection(_assignmentsCollection)
          .where('teamMemberId', isEqualTo: teamMemberId)
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      throw DatabaseException('Failed to delete assignments by person: $e');
    }
  }

  @override
  Future<void> deleteAssignmentsBatch(List<String> assignmentIds) async {
    try {
      if (assignmentIds.isEmpty) return;

      final batch = _firestore.batch();
      for (final id in assignmentIds) {
        batch.delete(_firestore.collection(_assignmentsCollection).doc(id));
      }
      await batch.commit();
    } catch (e) {
      throw DatabaseException('Failed to delete assignments batch: $e');
    }
  }

  @override
  Future<void> insertAssignmentsBatch(List<Assignment> assignments) async {
    try {
      final batch = _firestore.batch();

      for (final assignment in assignments) {
        // Validate FKs (will throw if invalid)
        await _validateAssignmentForeignKeys(
            assignment.eventId, assignment.teamMemberId);

        final model = AssignmentModel.fromEntity(assignment);
        final docRef =
            _firestore.collection(_assignmentsCollection).doc(assignment.id);
        batch.set(docRef, model.toFirestore());
      }

      await batch.commit();
    } catch (e) {
      throw DatabaseException('Failed to insert assignments batch: $e');
    }
  }

  
  // ========== Utility ==========

  @override
  Future<void> clearAllData() async {
    try {
      // Delete all team members
      final teamMembersSnapshot =
          await _firestore.collection(_teamMembersCollection).get();
      final teamMembersBatch = _firestore.batch();
      for (final doc in teamMembersSnapshot.docs) {
        teamMembersBatch.delete(doc.reference);
      }
      await teamMembersBatch.commit();

      // Delete all events
      final eventsSnapshot =
          await _firestore.collection(_eventsCollection).get();
      final eventsBatch = _firestore.batch();
      for (final doc in eventsSnapshot.docs) {
        eventsBatch.delete(doc.reference);
      }
      await eventsBatch.commit();

      // Delete all assignments
      final assignmentsSnapshot =
          await _firestore.collection(_assignmentsCollection).get();
      final assignmentsBatch = _firestore.batch();
      for (final doc in assignmentsSnapshot.docs) {
        assignmentsBatch.delete(doc.reference);
      }
      await assignmentsBatch.commit();
    } catch (e) {
      throw DatabaseException('Failed to clear all data: $e');
    }
  }

  // ========== Private Helper Methods ==========

  /// Populate assignment relations (event and team member)
  /// OPTIMIZED: Uses batch queries (whereIn) instead of N+1 sequential queries
  /// Firestore allows up to 30 items in a single whereIn clause
  Future<List<Assignment>> _populateAssignmentRelations(
      List<Assignment> assignments) async {
    if (assignments.isEmpty) return assignments;

    // Get unique event IDs and team member IDs
    final eventIds = assignments.map((a) => a.eventId).toSet().toList();
    final memberIds = assignments.map((a) => a.teamMemberId).toSet().toList();

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

    // Populate relations using cached data
    return assignments.map((assignment) {
      return assignment.withRelations(
        event: events[assignment.eventId],
        teamMember: members[assignment.teamMemberId],
      );
    }).toList();
  }

  /// Validate that event and team member exist before creating assignment
  Future<void> _validateAssignmentForeignKeys(
      String eventId, String teamMemberId) async {
    final event = await getEventById(eventId);
    if (event == null) {
      throw DatabaseException('Event not found: $eventId');
    }

    final member = await getTeamMemberById(teamMemberId);
    if (member == null) {
      throw DatabaseException('Team member not found: $teamMemberId');
    }
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
      await _firestore.collection(_calendarSyncCollection).doc(constraintId).set({
        'calendarEventId': calendarEventId,
        'teamMemberId': teamMemberId,
        'status': status.name,
        'syncedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'retryCount': 0,
        'errorMessage': null,
      });
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
  Future<Map<String, dynamic>?> getCalendarSyncState(String constraintId) async {
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
      final updates = <String, dynamic>{
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (errorMessage != null) {
        updates['errorMessage'] = errorMessage;
      }

      if (retryCount != null) {
        updates['retryCount'] = retryCount;
      }

      await _firestore
          .collection(_calendarSyncCollection)
          .doc(constraintId)
          .update(updates);
    } catch (e) {
      throw DatabaseException('Failed to update calendar sync status: $e');
    }
  }

  @override
  Future<void> removeCalendarSyncState(String constraintId) async {
    try {
      await _firestore
          .collection(_calendarSyncCollection)
          .doc(constraintId)
          .delete();
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
      throw DatabaseException('Failed to get synced constraints for member: $e');
    }
  }

  @override
  Future<Map<String, dynamic>?> atomicCheckAndSetSyncState(
    String constraintId,
    String teamMemberId,
  ) async {
    try {
      return await _firestore.runTransaction((transaction) async {
        // Get the current sync state document
        final docRef = _firestore.collection(_calendarSyncCollection).doc(constraintId);
        final docSnapshot = await transaction.get(docRef);

        if (docSnapshot.exists) {
          final data = docSnapshot.data();
          if (data != null && data['status'] == CalendarSyncStatus.synced.name) {
            // Already synced - return update action with existing calendar event ID
            return {
              'action': 'update',
              'calendarEventId': data['calendarEventId'],
              'teamMemberId': data['teamMemberId'],
            };
          }
        }

        // Not synced or doesn't exist - set a pending state to reserve the sync
        final now = FieldValue.serverTimestamp();
        transaction.set(docRef, {
          'calendarEventId': '', // Empty placeholder
          'teamMemberId': teamMemberId,
          'status': CalendarSyncStatus.pending.name,
          'syncedAt': now,
          'updatedAt': now,
          'retryCount': 0,
          'errorMessage': null,
          'reservedBy': DateTime.now().millisecondsSinceEpoch, // For debugging race conditions
        });

        // Return create action
        return {
          'action': 'create',
          'calendarEventId': null,
          'teamMemberId': teamMemberId,
        };
      });
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

  @override
  Future<Map<String, String?>?> getGoogleCalendarConfig() async {
    try {

      final doc = await _firestore.collection('keys').doc('googleCalendar').get();

      if (!doc.exists) {
        return null;
      }

      final data = doc.data() as Map<String, dynamic>;

      // Handle service account credentials - should be stored as a Map/Object
      String? serviceAccountJson;
      final serviceAccountData = data['serviceAccountJson'];

      if (serviceAccountData is Map) {
        // If stored as a Map, convert to JSON string
        serviceAccountJson = _convertMapToJsonString(Map<String, dynamic>.from(serviceAccountData));
      } else if (serviceAccountData is String) {
        // If still stored as a string, try to use it directly
        serviceAccountJson = serviceAccountData;
      } else {
        serviceAccountJson = null;
      }

      final result = {
        'serviceAccountJson': serviceAccountJson,
        'calendarId': data['calendarId'] as String?,
      };

      return result;
    } catch (e) {
      throw DatabaseException('Failed to fetch Google Calendar config: $e');
    }
  }

  @override
  Future<Map<String, String?>?> getDriveConfig() async {
    try {
      final doc = await _firestore.collection('keys').doc('googleDrive').get();

      if (!doc.exists) {
        return null;
      }

      final data = doc.data() as Map<String, dynamic>;

      return {
        'scriptUrl': data['scriptUrl'] as String?,
        'apiKey': data['apiKey'] as String?,
      };
    } catch (e) {
      throw DatabaseException('Failed to fetch Google Drive config: $e');
    }
  }

  /// Helper method to convert a Map to a JSON string with properly formatted private key
  String _convertMapToJsonString(Map<String, dynamic> map) {
    // Create a copy to avoid modifying the original
    final Map<String, dynamic> jsonMap = Map.from(map);

    // For the private_key field, ensure newlines are preserved (NOT escaped)
    // Firestore will handle the JSON encoding properly when storing as a Map
    // When we retrieve it, the private_key should already have proper newlines
    if (jsonMap.containsKey('private_key') && jsonMap['private_key'] is String) {
      // Keep the newlines as-is - they should be stored properly in the Map
    }

    // Use jsonEncode directly without escaping newlines
    return jsonEncode(jsonMap);
  }

  // ========== Checklist Items Implementation ==========

  @override
  Future<List<ChecklistItem>> getChecklistItems() async {
    try {
      final snapshot = await _firestore.collection(_checklistItemsCollection).get();
      final items = <ChecklistItem>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        // Get related data
        final event = await getEventById(data['eventId'] as String);
        final responsible = await getTeamMemberById(data['responsibleId'] as String);

        // Get CC members
        final ccIds = (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final ccMembers = <TeamMember>[];
        for (final ccId in ccIds) {
          final member = await getTeamMemberById(ccId);
          if (member != null) ccMembers.add(member);
        }

        items.add(ChecklistItemModel.fromFirestore(doc, event, responsible, ccMembers));
      }

      return items;
    } catch (e) {
      throw DatabaseException('Failed to fetch checklist items: $e');
    }
  }

  @override
  Future<ChecklistItem?> getChecklistItemById(String id) async {
    try {
      final doc = await _firestore.collection(_checklistItemsCollection).doc(id).get();
      if (!doc.exists) return null;

      final data = doc.data() as Map<String, dynamic>;

      // Get related data
      final event = await getEventById(data['eventId'] as String);
      final responsible = await getTeamMemberById(data['responsibleId'] as String);

      // Get CC members
      final ccIds = (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final ccMembers = <TeamMember>[];
      for (final ccId in ccIds) {
        final member = await getTeamMemberById(ccId);
        if (member != null) ccMembers.add(member);
      }

      return ChecklistItemModel.fromFirestore(doc, event, responsible, ccMembers);
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
        final ccIds = (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final ccMembers = ccIds
            .map((id) => memberMap[id])
            .where((member) => member != null)
            .cast<TeamMember>()
            .toList();

        items.add(ChecklistItemModel.fromFirestore(doc, event, responsible, ccMembers));
      }

      return items;
    } catch (e) {
      throw DatabaseException('Failed to fetch checklist items by event: $e');
    }
  }

  @override
  Future<List<ChecklistItem>> getChecklistItemsForTeamMember(String teamMemberId) async {
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
        final ccIds = (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final ccMembers = ccIds
            .map((id) => memberMap[id])
            .where((member) => member != null)
            .cast<TeamMember>()
            .toList();

        items.add(ChecklistItemModel.fromFirestore(doc, event, responsible, ccMembers));
      }

      return items;
    } catch (e) {
      throw DatabaseException('Failed to fetch checklist items for team member: $e');
    }
  }

  @override
  Future<List<ChecklistItem>> getChecklistItemsWhereResponsible(String teamMemberId) async {
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
        final ccIds = (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final ccMembers = ccIds
            .map((id) => memberMap[id])
            .where((member) => member != null)
            .cast<TeamMember>()
            .toList();

        items.add(ChecklistItemModel.fromFirestore(doc, event, responsible, ccMembers));
      }

      return items;
    } catch (e) {
      throw DatabaseException('Failed to fetch checklist items where responsible: $e');
    }
  }

  @override
  Future<List<ChecklistItem>> getChecklistItemsWhereCc(String teamMemberId) async {
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
        final ccIds = (data['ccIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final ccMembers = ccIds
            .map((id) => memberMap[id])
            .where((member) => member != null)
            .cast<TeamMember>()
            .toList();

        items.add(ChecklistItemModel.fromFirestore(doc, event, responsible, ccMembers));
      }

      return items;
    } catch (e) {
      throw DatabaseException('Failed to fetch checklist items where CC: $e');
    }
  }

  @override
  Future<void> insertChecklistItem(ChecklistItem item) async {
    try {
      await _firestore
          .collection(_checklistItemsCollection)
          .doc(item.id)
          .set(ChecklistItemModel.toFirestore(item));
    } catch (e) {
      throw DatabaseException('Failed to insert checklist item: $e');
    }
  }

  @override
  Future<void> updateChecklistItem(ChecklistItem item) async {
    try {
      await _firestore
          .collection(_checklistItemsCollection)
          .doc(item.id)
          .update(ChecklistItemModel.toFirestore(item));
    } catch (e) {
      throw DatabaseException('Failed to update checklist item: $e');
    }
  }

  @override
  Future<void> deleteChecklistItem(String id) async {
    try {
      await _firestore.collection(_checklistItemsCollection).doc(id).delete();
    } catch (e) {
      throw DatabaseException('Failed to delete checklist item: $e');
    }
  }

  @override
  Future<void> deleteChecklistItemsByEvent(String eventId) async {
    try {
      final batch = _firestore.batch();
      final snapshot = await _firestore
          .collection(_checklistItemsCollection)
          .where('eventId', isEqualTo: eventId)
          .get();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    } catch (e) {
      throw DatabaseException('Failed to delete checklist items by event: $e');
    }
  }

  // ========== Checklist Presets ==========

  @override
  Future<List<Preset>> getPresets() async {
    try {
      final snapshot = await _firestore
          .collection(_presetsCollection)
          .orderBy('name')
          .get();

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
      await _firestore
          .collection(_presetsCollection)
          .doc(preset.id)
          .set(PresetModel.toFirestore(preset));
    } catch (e) {
      throw DatabaseException('Failed to insert preset: $e');
    }
  }

  @override
  Future<void> updatePreset(Preset preset) async {
    try {
      await _firestore
          .collection(_presetsCollection)
          .doc(preset.id)
          .update(PresetModel.toFirestore(preset));
    } catch (e) {
      throw DatabaseException('Failed to update preset: $e');
    }
  }

  @override
  Future<void> deletePreset(String id) async {
    try {
      await _firestore.collection(_presetsCollection).doc(id).delete();
    } catch (e) {
      throw DatabaseException('Failed to delete preset: $e');
    }
  }

  @override
  Future<void> loadPresetIntoEvent(String presetId, String eventId, String creatorAdminId) async {
    try {
      // Get the preset
      final preset = await getPresetById(presetId);
      if (preset == null) {
        throw DatabaseException('Preset not found: $presetId');
      }

      // Create checklist items from preset templates
      final now = DateTime.now();
      final batch = _firestore.batch();

      for (final templateItem in preset.items) {
        final checklistItemId = const Uuid().v4();
        final checklistItem = ChecklistItem(
          id: checklistItemId,
          eventId: eventId,
          name: templateItem.name,
          responsibleId: templateItem.responsibleId,
          ccIds: templateItem.ccIds,
          ccNotes: const {},
          responsibleNote: const ResponsibleNoteEntry(note: ''),
          adminNote: templateItem.adminNote.isNotEmpty
              ? AdminNoteEntry(note: templateItem.adminNote, updatedAt: now)
              : const AdminNoteEntry(note: ''),
          status: false,
          createdAt: now,
          updatedAt: now,
          statusLastUpdatedAt: now,
          createdByAdminId: creatorAdminId,
        );

        final docRef = _firestore
            .collection(_checklistItemsCollection)
            .doc(checklistItemId);
        batch.set(docRef, ChecklistItemModel.toFirestore(checklistItem));
      }

      await batch.commit();
      developer.log('FirestoreDatabase.loadPresetIntoEvent: Loaded ${preset.items.length} items from preset "${preset.name}" into event $eventId', name: 'Firestore');
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
        developer.log('FirestoreDatabase.getRoles: utilities/Lists document does not exist', name: 'Firestore');
        return [];
      }

      final data = doc.data()!;
      final rolesArray = data['Roles'] as List<dynamic>?;

      if (rolesArray == null || rolesArray.isEmpty) {
        developer.log('FirestoreDatabase.getRoles: Roles array is empty or null', name: 'Firestore');
        return [];
      }

      final roles = rolesArray
          .map((roleData) => RoleModel.fromJson(roleData as Map<String, dynamic>).toEntity())
          .toList();

      // Sort by sortOrder
      roles.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      developer.log('FirestoreDatabase.getRoles: Retrieved ${roles.length} roles', name: 'Firestore');
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
      final docRef = _firestore.collection('utilities').doc('Lists');
      final doc = await docRef.get();

      final model = RoleModel.fromEntity(role);
      final roleData = model.toJson();

      if (!doc.exists) {
        // Create the document with the role
        await docRef.set({
          'Roles': [roleData],
        });
      } else {
        // Append to existing array
        await docRef.update({
          'Roles': FieldValue.arrayUnion([roleData]),
        });
      }

      developer.log('FirestoreDatabase.insertRole: Inserted role "${role.hebrewName}" (${role.key})', name: 'Firestore');
    } catch (e) {
      throw DatabaseException('Failed to insert role: $e');
    }
  }

  @override
  Future<void> updateRole(Role role) async {
    try {
      final roles = await getRoles();
      final index = roles.indexWhere((r) => r.id == role.id);

      if (index == -1) {
        throw DatabaseException('Role not found: ${role.id}');
      }

      // Replace the role at the index
      roles[index] = role;

      // Convert all roles to JSON
      final rolesData = roles.map((r) => RoleModel.fromEntity(r).toJson()).toList();

      // Update the entire array
      await _firestore.collection('utilities').doc('Lists').update({
        'Roles': rolesData,
      });

      developer.log('FirestoreDatabase.updateRole: Updated role "${role.hebrewName}" (${role.key})', name: 'Firestore');
    } catch (e) {
      throw DatabaseException('Failed to update role: $e');
    }
  }

  @override
  Future<void> archiveRole(String id) async {
    try {
      final role = await getRoleById(id);
      if (role == null) {
        throw DatabaseException('Role not found: $id');
      }

      final updatedRole = role.copyWith(
        isArchived: true,
        updatedAt: DateTime.now(),
      );

      await updateRole(updatedRole);
      developer.log('FirestoreDatabase.archiveRole: Archived role $id', name: 'Firestore');
    } catch (e) {
      throw DatabaseException('Failed to archive role: $e');
    }
  }

  @override
  Future<void> restoreRole(String id) async {
    try {
      final role = await getRoleById(id);
      if (role == null) {
        throw DatabaseException('Role not found: $id');
      }

      final updatedRole = role.copyWith(
        isArchived: false,
        isVisible: true, // When restoring, also set visible to true
        updatedAt: DateTime.now(),
      );

      await updateRole(updatedRole);
      developer.log('FirestoreDatabase.restoreRole: Restored role $id', name: 'Firestore');
    } catch (e) {
      throw DatabaseException('Failed to restore role: $e');
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
            .map((roleData) => RoleModel.fromJson(roleData as Map<String, dynamic>).toEntity())
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
      final doc = await _firestore.collection('utilities').doc('Lists').get();

      // Check if Roles array already exists and has data
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final rolesArray = data['Roles'] as List<dynamic>?;
        if (rolesArray != null && rolesArray.isNotEmpty) {
          developer.log('FirestoreDatabase.seedRolesFromEnum: Roles array already has data, skipping seed', name: 'Firestore');
          return;
        }
      }

      developer.log('FirestoreDatabase.seedRolesFromEnum: Seeding roles from RoleType enum', name: 'Firestore');

      final now = DateTime.now();
      int sortOrder = 0;
      final rolesData = <Map<String, dynamic>>[];

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

        final model = RoleModel.fromEntity(role);
        rolesData.add(model.toJson());
      }

      // Set or update the document
      await _firestore.collection('utilities').doc('Lists').set({
        'Roles': rolesData,
      }, SetOptions(merge: true));

      developer.log('FirestoreDatabase.seedRolesFromEnum: Seeded ${RoleType.values.length} roles', name: 'Firestore');
    } catch (e) {
      throw DatabaseException('Failed to seed roles from enum: $e');
    }
  }

  @override
  Future<void> updateRolesSortOrder(Map<String, int> roleIdToSortOrder) async {
    try {
      final roles = await getRoles();

      // Update sort order for each role
      for (final role in roles) {
        if (roleIdToSortOrder.containsKey(role.id)) {
          final index = roles.indexOf(role);
          roles[index] = role.copyWith(
            sortOrder: roleIdToSortOrder[role.id]!,
            updatedAt: DateTime.now(),
          );
        }
      }

      // Convert all roles to JSON
      final rolesData = roles.map((r) => RoleModel.fromEntity(r).toJson()).toList();

      // Update the entire array
      await _firestore.collection('utilities').doc('Lists').update({
        'Roles': rolesData,
      });

      developer.log('FirestoreDatabase.updateRolesSortOrder: Updated sort order for ${roleIdToSortOrder.length} roles', name: 'Firestore');
    } catch (e) {
      throw DatabaseException('Failed to update roles sort order: $e');
    }
  }
}

/// Custom exception for database errors
class DatabaseException implements Exception {
  final String message;
  DatabaseException(this.message);

  @override
  String toString() => 'DatabaseException: $message';
}
