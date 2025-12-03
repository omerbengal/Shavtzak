import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/assignment.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import '../models/assignment_model.dart';
import '../models/event_model.dart';
import '../models/team_member_model.dart';
import 'database_interface.dart';

/// Firestore implementation of DatabaseInterface
class FirestoreDatabase implements DatabaseInterface {
  final FirebaseFirestore _firestore;

  // Collection names
  static const String _teamMembersCollection = 'teamMembers';
  static const String _eventsCollection = 'events';
  static const String _assignmentsCollection = 'assignments';

  FirestoreDatabase({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

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

      return snapshot.docs
          .map((doc) => TeamMemberModel.fromFirestore(doc).toEntity())
          .toList();
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
}

/// Custom exception for database errors
class DatabaseException implements Exception {
  final String message;
  DatabaseException(this.message);

  @override
  String toString() => 'DatabaseException: $message';
}
