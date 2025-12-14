import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/assignment.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import '../../core/constants/constraint_status.dart';
import '../../core/constants/calendar_constants.dart';
import '../../core/services/environment_service.dart';
import '../../core/utils/json_utils.dart';
import '../models/assignment_model.dart';
import '../models/event_model.dart';
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
      await _firestore.collection(_eventsCollection).doc(id).delete();
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
  Future<List<Assignment>> _populateAssignmentRelations(
      List<Assignment> assignments) async {
    if (assignments.isEmpty) return assignments;

    // Get unique event IDs and team member IDs
    final eventIds = assignments.map((a) => a.eventId).toSet();
    final memberIds = assignments.map((a) => a.teamMemberId).toSet();

    // Fetch all events and team members
    final events = <String, Event>{};
    final members = <String, TeamMember>{};

    for (final eventId in eventIds) {
      final event = await getEventById(eventId);
      if (event != null) events[eventId] = event;
    }

    for (final memberId in memberIds) {
      final member = await getTeamMemberById(memberId);
      if (member != null) members[memberId] = member;
    }

    // Populate relations
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

  /// Helper method to convert a Map to a JSON string with properly formatted private key
  String _convertMapToJsonString(Map<String, dynamic> map) {
    // Create a copy to avoid modifying the original
    final Map<String, dynamic> jsonMap = Map.from(map);

    // For the private_key field, ensure newlines are preserved (NOT escaped)
    // Firestore will handle the JSON encoding properly when storing as a Map
    // When we retrieve it, the private_key should already have proper newlines
    if (jsonMap.containsKey('private_key') && jsonMap['private_key'] is String) {
      final privateKey = jsonMap['private_key'] as String;
      // Keep the newlines as-is - they should be stored properly in the Map
    }

    // Use jsonEncode directly without escaping newlines
    return jsonEncode(jsonMap);
  }
}

/// Custom exception for database errors
class DatabaseException implements Exception {
  final String message;
  DatabaseException(this.message);

  @override
  String toString() => 'DatabaseException: $message';
}
