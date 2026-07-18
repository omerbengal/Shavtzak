import 'dart:async';

import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'package:shavtzak/core/debug/logger.dart';

import '../../core/constants/calendar_constants.dart';
import '../../core/constants/constraint_status.dart';
import '../../domain/entities/assignment.dart';
import '../../domain/entities/assignment_label.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/checklist_item.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/preset.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/team_member.dart';
import 'database_interface.dart';

/// Decorator over [DatabaseInterface] that records DB lifecycle events
/// (`dbStart`, `dbEnd`, `dbStreamEmit`, `dbError`) into [DebugLogger].
///
/// Wraps every method on the interface. One-shot Futures emit
/// `dbStart` -> `dbEnd` (or `dbError`). Stream methods emit `dbStart` on
/// subscription and `dbStreamEmit` per emission.
class LoggingDatabase implements DatabaseInterface {
  LoggingDatabase(this._inner);
  final DatabaseInterface _inner;

  // ===== Helpers =====

  Future<T> _runFuture<T>({
    required String op,
    required Map<String, Object?> ctx,
    required int? Function(T) countOf,
    required Future<T> Function() action,
  }) async {
    final start = DateTime.now().toUtc();
    DebugLogger.instance.record(LogEvent(
      timestamp: start,
      type: LogEventType.dbStart,
      name: op,
      context: ctx,
    ));
    try {
      final result = await action();
      final now = DateTime.now().toUtc();
      final c = countOf(result);
      DebugLogger.instance.record(LogEvent(
        timestamp: now,
        type: LogEventType.dbEnd,
        name: op,
        context: {
          ...ctx,
          'ok': true,
          if (c != null) 'count': c,
        },
        duration: now.difference(start),
      ));
      return result;
    } catch (e, s) {
      final now = DateTime.now().toUtc();
      DebugLogger.instance.record(LogEvent(
        timestamp: now,
        type: LogEventType.dbError,
        name: op,
        context: {
          ...ctx,
          'error': e.runtimeType.toString(),
          'messageLen': Logger.redact(e.toString()),
          'stackHead': s.toString().split('\n').first,
        },
        duration: now.difference(start),
      ));
      rethrow;
    }
  }

  Stream<List<T>> _wrapStream<T>({
    required String op,
    required Map<String, Object?> ctx,
    required Stream<List<T>> Function() inner,
  }) {
    final start = DateTime.now().toUtc();
    DebugLogger.instance.record(LogEvent(
      timestamp: start,
      type: LogEventType.dbStart,
      name: op,
      context: {...ctx, 'kind': 'stream'},
    ));

    late StreamController<List<T>> controller;
    StreamSubscription<List<T>>? sub;

    void onDisposed() {
      final now = DateTime.now().toUtc();
      DebugLogger.instance.record(LogEvent(
        timestamp: now,
        type: LogEventType.dbEnd,
        name: op,
        context: {...ctx, 'disposed': true},
        duration: now.difference(start),
      ));
    }

    controller = StreamController<List<T>>(
      onListen: () {
        sub = inner().listen(
          (snapshot) {
            DebugLogger.instance.record(LogEvent(
              timestamp: DateTime.now().toUtc(),
              type: LogEventType.dbStreamEmit,
              name: op,
              context: {...ctx, 'count': snapshot.length},
            ));
            controller.add(snapshot);
          },
          onError: controller.addError,
          onDone: () {
            onDisposed();
            controller.close();
          },
        );
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
        onDisposed();
      },
    );
    return controller.stream;
  }

  // ===== Team Members =====

  @override
  Future<List<TeamMember>> getTeamMembers() => _runFuture(
        op: 'getTeamMembers',
        ctx: const {'collection': 'teamMembers'},
        countOf: (r) => r.length,
        action: () => _inner.getTeamMembers(),
      );

  @override
  Future<TeamMember?> getTeamMemberById(String id) => _runFuture(
        op: 'getTeamMemberById',
        ctx: {'collection': 'teamMembers', 'id': id},
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getTeamMemberById(id),
      );

  @override
  Future<TeamMember?> getTeamMemberByUniqueKey(String uniqueKey) => _runFuture(
        op: 'getTeamMemberByUniqueKey',
        ctx: {
          'collection': 'teamMembers',
          'uniqueKey': Logger.redact(uniqueKey),
        },
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getTeamMemberByUniqueKey(uniqueKey),
      );

  @override
  Future<void> insertTeamMember(TeamMember member) => _runFuture(
        op: 'insertTeamMember',
        ctx: {'collection': 'teamMembers', 'id': member.id},
        countOf: (_) => null,
        action: () => _inner.insertTeamMember(member),
      );

  @override
  Future<void> updateTeamMember(TeamMember member) => _runFuture(
        op: 'updateTeamMember',
        ctx: {'collection': 'teamMembers', 'id': member.id},
        countOf: (_) => null,
        action: () => _inner.updateTeamMember(member),
      );

  @override
  Future<void> updateTeamMemberPasscode(
          String id, String passcode, int length) =>
      _runFuture(
        op: 'updateTeamMemberPasscode',
        ctx: {
          'collection': 'teamMembers',
          'id': id,
          'fields': const ['passcode'],
          'len': length,
        },
        countOf: (_) => null,
        action: () => _inner.updateTeamMemberPasscode(id, passcode, length),
      );

  @override
  Future<void> clearTeamMemberPasscode(String id) => _runFuture(
        op: 'clearTeamMemberPasscode',
        ctx: {
          'collection': 'teamMembers',
          'id': id,
          'fields': const ['passcode'],
        },
        countOf: (_) => null,
        action: () => _inner.clearTeamMemberPasscode(id),
      );

  @override
  Future<void> deleteTeamMember(String id) => _runFuture(
        op: 'deleteTeamMember',
        ctx: {'collection': 'teamMembers', 'id': id},
        countOf: (_) => null,
        action: () => _inner.deleteTeamMember(id),
      );

  @override
  Stream<List<TeamMember>> watchTeamMembers() => _wrapStream(
        op: 'watchTeamMembers',
        ctx: const {'collection': 'teamMembers'},
        inner: () => _inner.watchTeamMembers(),
      );

  // ===== Events =====

  @override
  Future<List<Event>> getEvents() => _runFuture(
        op: 'getEvents',
        ctx: const {'collection': 'events'},
        countOf: (r) => r.length,
        action: () => _inner.getEvents(),
      );

  @override
  Future<Event?> getEventById(String id) => _runFuture(
        op: 'getEventById',
        ctx: {'collection': 'events', 'id': id},
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getEventById(id),
      );

  @override
  Future<void> insertEvent(Event event) => _runFuture(
        op: 'insertEvent',
        ctx: {'collection': 'events', 'id': event.id},
        countOf: (_) => null,
        action: () => _inner.insertEvent(event),
      );

  @override
  Future<void> updateEvent(Event event) => _runFuture(
        op: 'updateEvent',
        ctx: {'collection': 'events', 'id': event.id},
        countOf: (_) => null,
        action: () => _inner.updateEvent(event),
      );

  @override
  Future<void> deleteEvent(String id) => _runFuture(
        op: 'deleteEvent',
        ctx: {'collection': 'events', 'id': id},
        countOf: (_) => null,
        action: () => _inner.deleteEvent(id),
      );

  @override
  Future<List<Event>> getUpcomingEvents() => _runFuture(
        op: 'getUpcomingEvents',
        ctx: const {'collection': 'events'},
        countOf: (r) => r.length,
        action: () => _inner.getUpcomingEvents(),
      );

  @override
  Future<List<Event>> getEventsByDateRange(DateTime start, DateTime end) =>
      _runFuture(
        op: 'getEventsByDateRange',
        ctx: {
          'collection': 'events',
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
        countOf: (r) => r.length,
        action: () => _inner.getEventsByDateRange(start, end),
      );

  @override
  Future<List<Event>> getEventsBeforeDate(DateTime cursor,
          {required int limit}) =>
      _runFuture(
        op: 'getEventsBeforeDate',
        ctx: {
          'collection': 'events',
          'cursor': cursor.toIso8601String(),
          'limit': limit,
        },
        countOf: (r) => r.length,
        action: () => _inner.getEventsBeforeDate(cursor, limit: limit),
      );

  @override
  Stream<List<Event>> watchEvents() => _wrapStream(
        op: 'watchEvents',
        ctx: const {'collection': 'events'},
        inner: () => _inner.watchEvents(),
      );

  @override
  Stream<List<Event>> watchEventsByDateRange(DateTime start, DateTime end) =>
      _wrapStream(
        op: 'watchEventsByDateRange',
        ctx: {
          'collection': 'events',
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
        inner: () => _inner.watchEventsByDateRange(start, end),
      );

  @override
  Future<bool> isDuplicateEvent(String name, DateTime startDate,
          {String? excludeEventId}) =>
      _runFuture(
        op: 'isDuplicateEvent',
        ctx: {
          'collection': 'events',
          'name': Logger.redact(name),
          'startDate': startDate.toIso8601String(),
          if (excludeEventId != null) 'excludeEventId': excludeEventId,
        },
        countOf: (_) => null,
        action: () => _inner.isDuplicateEvent(name, startDate,
            excludeEventId: excludeEventId),
      );

  // ===== Assignments =====

  @override
  Future<List<Assignment>> getAssignments() => _runFuture(
        op: 'getAssignments',
        ctx: const {'collection': 'assignments'},
        countOf: (r) => r.length,
        action: () => _inner.getAssignments(),
      );

  @override
  Stream<List<Assignment>> watchAssignments() => _wrapStream(
        op: 'watchAssignments',
        ctx: const {'collection': 'assignments'},
        inner: () => _inner.watchAssignments(),
      );

  @override
  Stream<List<Assignment>> watchAssignmentsByEvent(String eventId) =>
      _wrapStream(
        op: 'watchAssignmentsByEvent',
        ctx: {'collection': 'assignments', 'eventId': eventId},
        inner: () => _inner.watchAssignmentsByEvent(eventId),
      );

  @override
  Stream<List<Assignment>> watchAssignmentsByPerson(String teamMemberId) =>
      _wrapStream(
        op: 'watchAssignmentsByPerson',
        ctx: {'collection': 'assignments', 'teamMemberId': teamMemberId},
        inner: () => _inner.watchAssignmentsByPerson(teamMemberId),
      );

  @override
  Future<Assignment?> getAssignmentById(String id) => _runFuture(
        op: 'getAssignmentById',
        ctx: {'collection': 'assignments', 'id': id},
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getAssignmentById(id),
      );

  @override
  Future<List<Assignment>> getAssignmentsByEvent(String eventId) => _runFuture(
        op: 'getAssignmentsByEvent',
        ctx: {'collection': 'assignments', 'eventId': eventId},
        countOf: (r) => r.length,
        action: () => _inner.getAssignmentsByEvent(eventId),
      );

  @override
  Future<List<Assignment>> getAssignmentsByPerson(String teamMemberId) =>
      _runFuture(
        op: 'getAssignmentsByPerson',
        ctx: {'collection': 'assignments', 'teamMemberId': teamMemberId},
        countOf: (r) => r.length,
        action: () => _inner.getAssignmentsByPerson(teamMemberId),
      );

  @override
  Future<List<Assignment>> getAssignmentsByDateRange(
    DateTime start,
    DateTime end,
  ) =>
      _runFuture(
        op: 'getAssignmentsByDateRange',
        ctx: {
          'collection': 'assignments',
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
        countOf: (r) => r.length,
        action: () => _inner.getAssignmentsByDateRange(start, end),
      );

  @override
  Future<List<Assignment>> getAssignmentsInTimeWindow(
    DateTime windowStart,
    DateTime windowEnd,
  ) =>
      _runFuture(
        op: 'getAssignmentsInTimeWindow',
        ctx: {
          'collection': 'assignments',
          'windowStart': windowStart.toIso8601String(),
          'windowEnd': windowEnd.toIso8601String(),
        },
        countOf: (r) => r.length,
        action: () => _inner.getAssignmentsInTimeWindow(windowStart, windowEnd),
      );

  @override
  Future<List<Assignment>> getAssignmentsByEventIds(List<String> eventIds) =>
      _runFuture(
        op: 'getAssignmentsByEventIds',
        ctx: {
          'collection': 'assignments',
          'eventIdCount': eventIds.length,
        },
        countOf: (r) => r.length,
        action: () => _inner.getAssignmentsByEventIds(eventIds),
      );

  @override
  Stream<List<Assignment>> watchAssignmentsInTimeWindow(
    DateTime windowStart,
    DateTime windowEnd,
  ) =>
      _wrapStream(
        op: 'watchAssignmentsInTimeWindow',
        ctx: {
          'collection': 'assignments',
          'windowStart': windowStart.toIso8601String(),
          'windowEnd': windowEnd.toIso8601String(),
        },
        inner: () =>
            _inner.watchAssignmentsInTimeWindow(windowStart, windowEnd),
      );

  @override
  Future<void> insertAssignment(
    Assignment assignment, {
    bool bypassAvailability = false,
  }) =>
      _runFuture(
        op: 'insertAssignment',
        ctx: {
          'collection': 'assignments',
          'id': assignment.id,
          'bypassAvailability': bypassAvailability,
        },
        countOf: (_) => null,
        action: () => _inner.insertAssignment(assignment,
            bypassAvailability: bypassAvailability),
      );

  @override
  Future<void> updateAssignment(
    Assignment assignment, {
    bool bypassAvailability = false,
  }) =>
      _runFuture(
        op: 'updateAssignment',
        ctx: {
          'collection': 'assignments',
          'id': assignment.id,
          'bypassAvailability': bypassAvailability,
        },
        countOf: (_) => null,
        action: () => _inner.updateAssignment(assignment,
            bypassAvailability: bypassAvailability),
      );

  @override
  Future<void> updateAssignmentMetadata(
    String assignmentId, {
    required String notes,
    String? semanticLabelId,
    String? alternativePhoneNumber,
  }) =>
      _runFuture(
        op: 'updateAssignmentMetadata',
        ctx: {
          'collection': 'assignments',
          'id': assignmentId,
          'notes': Logger.redact(notes),
          if (semanticLabelId != null) 'semanticLabelId': semanticLabelId,
          if (alternativePhoneNumber != null)
            'alternativePhoneNumber': Logger.redact(alternativePhoneNumber),
        },
        countOf: (_) => null,
        action: () => _inner.updateAssignmentMetadata(
          assignmentId,
          notes: notes,
          semanticLabelId: semanticLabelId,
          alternativePhoneNumber: alternativePhoneNumber,
        ),
      );

  @override
  Future<void> deleteAssignment(String id) => _runFuture(
        op: 'deleteAssignment',
        ctx: {'collection': 'assignments', 'id': id},
        countOf: (_) => null,
        action: () => _inner.deleteAssignment(id),
      );

  @override
  Future<void> deleteAssignmentsByEvent(String eventId) => _runFuture(
        op: 'deleteAssignmentsByEvent',
        ctx: {'collection': 'assignments', 'eventId': eventId},
        countOf: (_) => null,
        action: () => _inner.deleteAssignmentsByEvent(eventId),
      );

  @override
  Future<void> deleteAssignmentsByPerson(String teamMemberId) => _runFuture(
        op: 'deleteAssignmentsByPerson',
        ctx: {'collection': 'assignments', 'teamMemberId': teamMemberId},
        countOf: (_) => null,
        action: () => _inner.deleteAssignmentsByPerson(teamMemberId),
      );

  @override
  Future<void> deleteAssignmentsBatch(List<String> assignmentIds) => _runFuture(
        op: 'deleteAssignmentsBatch',
        ctx: {'collection': 'assignments', 'count': assignmentIds.length},
        countOf: (_) => null,
        action: () => _inner.deleteAssignmentsBatch(assignmentIds),
      );

  // ===== Assignment Labels =====

  @override
  Future<List<AssignmentLabel>> getAssignmentLabels() => _runFuture(
        op: 'getAssignmentLabels',
        ctx: const {'collection': 'assignmentLabels'},
        countOf: (r) => r.length,
        action: () => _inner.getAssignmentLabels(),
      );

  @override
  Future<void> insertAssignmentLabel(AssignmentLabel label) => _runFuture(
        op: 'insertAssignmentLabel',
        ctx: {'collection': 'assignmentLabels', 'id': label.id},
        countOf: (_) => null,
        action: () => _inner.insertAssignmentLabel(label),
      );

  @override
  Future<void> updateAssignmentLabel(AssignmentLabel label) => _runFuture(
        op: 'updateAssignmentLabel',
        ctx: {'collection': 'assignmentLabels', 'id': label.id},
        countOf: (_) => null,
        action: () => _inner.updateAssignmentLabel(label),
      );

  @override
  Future<void> archiveAssignmentLabel(String id) => _runFuture(
        op: 'archiveAssignmentLabel',
        ctx: {'collection': 'assignmentLabels', 'id': id},
        countOf: (_) => null,
        action: () => _inner.archiveAssignmentLabel(id),
      );

  @override
  Future<void> restoreAssignmentLabel(String id) => _runFuture(
        op: 'restoreAssignmentLabel',
        ctx: {'collection': 'assignmentLabels', 'id': id},
        countOf: (_) => null,
        action: () => _inner.restoreAssignmentLabel(id),
      );

  @override
  Future<void> deleteAssignmentLabel(String id) => _runFuture(
        op: 'deleteAssignmentLabel',
        ctx: {'collection': 'assignmentLabels', 'id': id},
        countOf: (_) => null,
        action: () => _inner.deleteAssignmentLabel(id),
      );

  @override
  Future<void> updateAssignmentLabelsSortOrder(
    Map<String, int> labelIdToSortOrder,
  ) =>
      _runFuture(
        op: 'updateAssignmentLabelsSortOrder',
        ctx: {
          'collection': 'assignmentLabels',
          'count': labelIdToSortOrder.length,
        },
        countOf: (_) => null,
        action: () =>
            _inner.updateAssignmentLabelsSortOrder(labelIdToSortOrder),
      );

  @override
  Stream<List<AssignmentLabel>> watchAssignmentLabels() => _wrapStream(
        op: 'watchAssignmentLabels',
        ctx: const {'collection': 'assignmentLabels'},
        inner: () => _inner.watchAssignmentLabels(),
      );

  // ===== Batch Operations =====

  @override
  Future<void> insertTeamMembersBatch(List<TeamMember> members) => _runFuture(
        op: 'insertTeamMembersBatch',
        ctx: {'collection': 'teamMembers', 'count': members.length},
        countOf: (_) => null,
        action: () => _inner.insertTeamMembersBatch(members),
      );

  @override
  Future<void> insertEventsBatch(List<Event> events) => _runFuture(
        op: 'insertEventsBatch',
        ctx: {'collection': 'events', 'count': events.length},
        countOf: (_) => null,
        action: () => _inner.insertEventsBatch(events),
      );

  @override
  Future<void> insertAssignmentsBatch(List<Assignment> assignments) =>
      _runFuture(
        op: 'insertAssignmentsBatch',
        ctx: {'collection': 'assignments', 'count': assignments.length},
        countOf: (_) => null,
        action: () => _inner.insertAssignmentsBatch(assignments),
      );

  @override
  Future<void> saveAssignmentsBatch({
    required List<Assignment> creates,
    required List<Assignment> updates,
    required List<String> deletes,
    List<EventQuotaBump> eventQuotaBumps = const [],
    List<EventQuotaSet> eventQuotaSets = const [],
  }) =>
      _runFuture(
        op: 'saveAssignmentsBatch',
        ctx: {
          'collection': 'assignments',
          'creates': creates.length,
          'updates': updates.length,
          'deletes': deletes.length,
          'quotaBumps': eventQuotaBumps.length,
          'quotaSets': eventQuotaSets.length,
        },
        countOf: (_) => null,
        action: () => _inner.saveAssignmentsBatch(
          creates: creates,
          updates: updates,
          deletes: deletes,
          eventQuotaBumps: eventQuotaBumps,
          eventQuotaSets: eventQuotaSets,
        ),
      );

  // ===== Utility =====

  @override
  Future<void> initialize() => _runFuture(
        op: 'initialize',
        ctx: const {'scope': 'database'},
        countOf: (_) => null,
        action: () => _inner.initialize(),
      );

  @override
  Future<void> close() => _runFuture(
        op: 'close',
        ctx: const {'scope': 'database'},
        countOf: (_) => null,
        action: () => _inner.close(),
      );

  @override
  Future<void> clearAllData() => _runFuture(
        op: 'clearAllData',
        ctx: const {'scope': 'database'},
        countOf: (_) => null,
        action: () => _inner.clearAllData(),
      );

  // ===== Calendar Sync State =====

  @override
  Future<void> saveCalendarSyncState({
    required String constraintId,
    required String calendarEventId,
    required String teamMemberId,
    required CalendarSyncStatus status,
  }) =>
      _runFuture(
        op: 'saveCalendarSyncState',
        ctx: {
          'collection': 'calendarSyncState',
          'constraintId': constraintId,
          'teamMemberId': teamMemberId,
          'status': status.toString(),
        },
        countOf: (_) => null,
        action: () => _inner.saveCalendarSyncState(
          constraintId: constraintId,
          calendarEventId: calendarEventId,
          teamMemberId: teamMemberId,
          status: status,
        ),
      );

  @override
  Future<String?> getCalendarEventId(String constraintId) => _runFuture(
        op: 'getCalendarEventId',
        ctx: {
          'collection': 'calendarSyncState',
          'constraintId': constraintId,
        },
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getCalendarEventId(constraintId),
      );

  @override
  Future<Map<String, dynamic>?> getCalendarSyncState(String constraintId) =>
      _runFuture(
        op: 'getCalendarSyncState',
        ctx: {
          'collection': 'calendarSyncState',
          'constraintId': constraintId,
        },
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getCalendarSyncState(constraintId),
      );

  @override
  Future<void> updateCalendarSyncStatus(
    String constraintId,
    CalendarSyncStatus status, {
    String? errorMessage,
    int? retryCount,
  }) =>
      _runFuture(
        op: 'updateCalendarSyncStatus',
        ctx: {
          'collection': 'calendarSyncState',
          'constraintId': constraintId,
          'status': status.toString(),
          if (errorMessage != null)
            'errorMessage': Logger.redact(errorMessage),
          if (retryCount != null) 'retryCount': retryCount,
        },
        countOf: (_) => null,
        action: () => _inner.updateCalendarSyncStatus(
          constraintId,
          status,
          errorMessage: errorMessage,
          retryCount: retryCount,
        ),
      );

  @override
  Future<void> removeCalendarSyncState(String constraintId) => _runFuture(
        op: 'removeCalendarSyncState',
        ctx: {
          'collection': 'calendarSyncState',
          'constraintId': constraintId,
        },
        countOf: (_) => null,
        action: () => _inner.removeCalendarSyncState(constraintId),
      );

  @override
  Future<Map<String, dynamic>?> atomicCheckAndSetSyncState(
    String constraintId,
    String teamMemberId,
  ) =>
      _runFuture(
        op: 'atomicCheckAndSetSyncState',
        ctx: {
          'collection': 'calendarSyncState',
          'constraintId': constraintId,
          'teamMemberId': teamMemberId,
        },
        countOf: (r) => r == null ? 0 : 1,
        action: () =>
            _inner.atomicCheckAndSetSyncState(constraintId, teamMemberId),
      );

  @override
  Future<List<Map<String, dynamic>>> getFailedSyncStates() => _runFuture(
        op: 'getFailedSyncStates',
        ctx: const {'collection': 'calendarSyncState'},
        countOf: (r) => r.length,
        action: () => _inner.getFailedSyncStates(),
      );

  @override
  Future<List<Map<String, dynamic>>> getSyncedConstraintsForAllMembers() =>
      _runFuture(
        op: 'getSyncedConstraintsForAllMembers',
        ctx: const {'collection': 'calendarSyncState'},
        countOf: (r) => r.length,
        action: () => _inner.getSyncedConstraintsForAllMembers(),
      );

  // ===== Event Calendar Sync State =====

  @override
  Future<void> saveEventCalendarSyncState({
    required String eventId,
    required String assemblyCalendarEventId,
    required String mainCalendarEventId,
    required CalendarSyncStatus status,
  }) =>
      _runFuture(
        op: 'saveEventCalendarSyncState',
        ctx: {
          'collection': 'eventCalendarSyncState',
          'eventId': eventId,
          'status': status.toString(),
        },
        countOf: (_) => null,
        action: () => _inner.saveEventCalendarSyncState(
          eventId: eventId,
          assemblyCalendarEventId: assemblyCalendarEventId,
          mainCalendarEventId: mainCalendarEventId,
          status: status,
        ),
      );

  @override
  Future<Map<String, dynamic>?> getEventCalendarSyncState(String eventId) =>
      _runFuture(
        op: 'getEventCalendarSyncState',
        ctx: {
          'collection': 'eventCalendarSyncState',
          'eventId': eventId,
        },
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getEventCalendarSyncState(eventId),
      );

  @override
  Future<void> removeEventCalendarSyncState(String eventId) => _runFuture(
        op: 'removeEventCalendarSyncState',
        ctx: {
          'collection': 'eventCalendarSyncState',
          'eventId': eventId,
        },
        countOf: (_) => null,
        action: () => _inner.removeEventCalendarSyncState(eventId),
      );

  @override
  Stream<Map<String, CalendarSyncStatus>> watchEventCalendarSyncStates() =>
      _inner.watchEventCalendarSyncStates();

  // ===== Constraint operations =====

  @override
  Future<void> updateConstraintStatus(
    String teamMemberIdOrConstraintId,
    int? constraintIndex,
    ConstraintStatus newStatus, {
    String? note,
    bool? wasAutoRejectedFromCalendar,
  }) =>
      _runFuture(
        op: 'updateConstraintStatus',
        ctx: {
          'collection': 'teamMembers',
          'targetId': teamMemberIdOrConstraintId,
          if (constraintIndex != null) 'constraintIndex': constraintIndex,
          'newStatus': newStatus.toString(),
          if (note != null) 'note': Logger.redact(note),
          if (wasAutoRejectedFromCalendar != null)
            'wasAutoRejectedFromCalendar': wasAutoRejectedFromCalendar,
        },
        countOf: (_) => null,
        action: () => _inner.updateConstraintStatus(
          teamMemberIdOrConstraintId,
          constraintIndex,
          newStatus,
          note: note,
          wasAutoRejectedFromCalendar: wasAutoRejectedFromCalendar,
        ),
      );

  @override
  Future<void> addConstraint(
    String teamMemberId,
    DateConstraint newConstraint,
  ) =>
      _runFuture(
        op: 'addConstraint',
        ctx: {
          'collection': 'teamMembers',
          'teamMemberId': teamMemberId,
          'fields': const ['constraints'],
        },
        countOf: (_) => null,
        action: () => _inner.addConstraint(teamMemberId, newConstraint),
      );

  @override
  Future<void> editConstraintById(
    String teamMemberId,
    String constraintId,
    DateConstraint updatedConstraint,
  ) =>
      _runFuture(
        op: 'editConstraintById',
        ctx: {
          'collection': 'teamMembers',
          'teamMemberId': teamMemberId,
          'constraintId': constraintId,
          'fields': const ['constraints'],
        },
        countOf: (_) => null,
        action: () => _inner.editConstraintById(
            teamMemberId, constraintId, updatedConstraint),
      );

  @override
  Future<DateConstraint?> removeConstraintById(
    String teamMemberId,
    String constraintId,
  ) =>
      _runFuture(
        op: 'removeConstraintById',
        ctx: {
          'collection': 'teamMembers',
          'teamMemberId': teamMemberId,
          'constraintId': constraintId,
          'fields': const ['constraints'],
        },
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.removeConstraintById(teamMemberId, constraintId),
      );

  @override
  Future<List<Map<String, dynamic>>> getSyncedConstraintsForMember(
          String teamMemberId) =>
      _runFuture(
        op: 'getSyncedConstraintsForMember',
        ctx: {
          'collection': 'calendarSyncState',
          'teamMemberId': teamMemberId,
        },
        countOf: (r) => r.length,
        action: () => _inner.getSyncedConstraintsForMember(teamMemberId),
      );

  // ===== Legacy calendar/drive config =====

  @override
  Future<Map<String, String?>?> getGoogleCalendarConfig() => _runFuture(
        op: 'getGoogleCalendarConfig',
        ctx: const {'collection': 'config', 'kind': 'legacy'},
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getGoogleCalendarConfig(),
      );

  @override
  Future<Map<String, String?>?> getDriveConfig() => _runFuture(
        op: 'getDriveConfig',
        ctx: const {'collection': 'config', 'kind': 'legacy'},
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getDriveConfig(),
      );

  // ===== Checklist Items =====

  @override
  Future<List<ChecklistItem>> getChecklistItems() => _runFuture(
        op: 'getChecklistItems',
        ctx: const {'collection': 'checklistItems'},
        countOf: (r) => r.length,
        action: () => _inner.getChecklistItems(),
      );

  @override
  Future<ChecklistItem?> getChecklistItemById(String id) => _runFuture(
        op: 'getChecklistItemById',
        ctx: {'collection': 'checklistItems', 'id': id},
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getChecklistItemById(id),
      );

  @override
  Future<List<ChecklistItem>> getChecklistItemsByEvent(String eventId) =>
      _runFuture(
        op: 'getChecklistItemsByEvent',
        ctx: {'collection': 'checklistItems', 'eventId': eventId},
        countOf: (r) => r.length,
        action: () => _inner.getChecklistItemsByEvent(eventId),
      );

  @override
  Future<List<ChecklistItem>> getChecklistItemsForTeamMember(
          String teamMemberId) =>
      _runFuture(
        op: 'getChecklistItemsForTeamMember',
        ctx: {'collection': 'checklistItems', 'teamMemberId': teamMemberId},
        countOf: (r) => r.length,
        action: () => _inner.getChecklistItemsForTeamMember(teamMemberId),
      );

  @override
  Future<List<ChecklistItem>> getChecklistItemsWhereResponsible(
          String teamMemberId) =>
      _runFuture(
        op: 'getChecklistItemsWhereResponsible',
        ctx: {'collection': 'checklistItems', 'teamMemberId': teamMemberId},
        countOf: (r) => r.length,
        action: () => _inner.getChecklistItemsWhereResponsible(teamMemberId),
      );

  @override
  Future<List<ChecklistItem>> getChecklistItemsWhereCc(String teamMemberId) =>
      _runFuture(
        op: 'getChecklistItemsWhereCc',
        ctx: {'collection': 'checklistItems', 'teamMemberId': teamMemberId},
        countOf: (r) => r.length,
        action: () => _inner.getChecklistItemsWhereCc(teamMemberId),
      );

  @override
  Future<void> insertChecklistItem(ChecklistItem item) => _runFuture(
        op: 'insertChecklistItem',
        ctx: {'collection': 'checklistItems', 'id': item.id},
        countOf: (_) => null,
        action: () => _inner.insertChecklistItem(item),
      );

  @override
  Future<void> updateChecklistItem(ChecklistItem item) => _runFuture(
        op: 'updateChecklistItem',
        ctx: {'collection': 'checklistItems', 'id': item.id},
        countOf: (_) => null,
        action: () => _inner.updateChecklistItem(item),
      );

  @override
  Future<void> deleteChecklistItem(String id) => _runFuture(
        op: 'deleteChecklistItem',
        ctx: {'collection': 'checklistItems', 'id': id},
        countOf: (_) => null,
        action: () => _inner.deleteChecklistItem(id),
      );

  @override
  Future<void> deleteChecklistItemsByEvent(String eventId) => _runFuture(
        op: 'deleteChecklistItemsByEvent',
        ctx: {'collection': 'checklistItems', 'eventId': eventId},
        countOf: (_) => null,
        action: () => _inner.deleteChecklistItemsByEvent(eventId),
      );

  @override
  Future<void> addNoteToChecklistItem(
          String checklistItemId, Map<String, dynamic> noteData) =>
      _runFuture(
        op: 'addNoteToChecklistItem',
        ctx: {
          'collection': 'checklistItems',
          'id': checklistItemId,
          'noteKeys': noteData.keys.toList(),
        },
        countOf: (_) => null,
        action: () =>
            _inner.addNoteToChecklistItem(checklistItemId, noteData),
      );

  // ===== Checklist Presets =====

  @override
  Future<List<Preset>> getPresets() => _runFuture(
        op: 'getPresets',
        ctx: const {'collection': 'checklistPresets'},
        countOf: (r) => r.length,
        action: () => _inner.getPresets(),
      );

  @override
  Future<Preset?> getPresetById(String id) => _runFuture(
        op: 'getPresetById',
        ctx: {'collection': 'checklistPresets', 'id': id},
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getPresetById(id),
      );

  @override
  Future<void> insertPreset(Preset preset) => _runFuture(
        op: 'insertPreset',
        ctx: {'collection': 'checklistPresets', 'id': preset.id},
        countOf: (_) => null,
        action: () => _inner.insertPreset(preset),
      );

  @override
  Future<void> updatePreset(Preset preset) => _runFuture(
        op: 'updatePreset',
        ctx: {'collection': 'checklistPresets', 'id': preset.id},
        countOf: (_) => null,
        action: () => _inner.updatePreset(preset),
      );

  @override
  Future<void> deletePreset(String id) => _runFuture(
        op: 'deletePreset',
        ctx: {'collection': 'checklistPresets', 'id': id},
        countOf: (_) => null,
        action: () => _inner.deletePreset(id),
      );

  @override
  Future<void> loadPresetIntoEvent(
          String presetId, String eventId, String creatorAdminId) =>
      _runFuture(
        op: 'loadPresetIntoEvent',
        ctx: {
          'collection': 'checklistItems',
          'presetId': presetId,
          'eventId': eventId,
          'creatorAdminId': creatorAdminId,
        },
        countOf: (_) => null,
        action: () =>
            _inner.loadPresetIntoEvent(presetId, eventId, creatorAdminId),
      );

  // ===== Roles =====

  @override
  Future<List<Role>> getRoles() => _runFuture(
        op: 'getRoles',
        ctx: const {'collection': 'roles'},
        countOf: (r) => r.length,
        action: () => _inner.getRoles(),
      );

  @override
  Future<Role?> getRoleById(String id) => _runFuture(
        op: 'getRoleById',
        ctx: {'collection': 'roles', 'id': id},
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getRoleById(id),
      );

  @override
  Future<Role?> getRoleByKey(String key) => _runFuture(
        op: 'getRoleByKey',
        ctx: {'collection': 'roles', 'key': key},
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getRoleByKey(key),
      );

  @override
  Future<void> insertRole(Role role) => _runFuture(
        op: 'insertRole',
        ctx: {'collection': 'roles', 'id': role.id},
        countOf: (_) => null,
        action: () => _inner.insertRole(role),
      );

  @override
  Future<void> updateRole(Role role) => _runFuture(
        op: 'updateRole',
        ctx: {'collection': 'roles', 'id': role.id},
        countOf: (_) => null,
        action: () => _inner.updateRole(role),
      );

  @override
  Future<void> archiveRole(String id) => _runFuture(
        op: 'archiveRole',
        ctx: {'collection': 'roles', 'id': id},
        countOf: (_) => null,
        action: () => _inner.archiveRole(id),
      );

  @override
  Future<void> restoreRole(String id) => _runFuture(
        op: 'restoreRole',
        ctx: {'collection': 'roles', 'id': id},
        countOf: (_) => null,
        action: () => _inner.restoreRole(id),
      );

  @override
  Future<void> deleteRole(String id) => _runFuture(
        op: 'deleteRole',
        ctx: {'collection': 'roles', 'id': id},
        countOf: (_) => null,
        action: () => _inner.deleteRole(id),
      );

  @override
  Stream<List<Role>> watchRoles() => _wrapStream(
        op: 'watchRoles',
        ctx: const {'collection': 'roles'},
        inner: () => _inner.watchRoles(),
      );

  @override
  Future<void> seedRolesFromEnum() => _runFuture(
        op: 'seedRolesFromEnum',
        ctx: const {'collection': 'roles', 'kind': 'migration'},
        countOf: (_) => null,
        action: () => _inner.seedRolesFromEnum(),
      );

  @override
  Future<void> updateRolesSortOrder(Map<String, int> roleIdToSortOrder) =>
      _runFuture(
        op: 'updateRolesSortOrder',
        ctx: {'collection': 'roles', 'count': roleIdToSortOrder.length},
        countOf: (_) => null,
        action: () => _inner.updateRolesSortOrder(roleIdToSortOrder),
      );

  // ===== Categories =====

  @override
  Future<List<Category>> getCategories() => _runFuture(
        op: 'getCategories',
        ctx: const {'collection': 'categories'},
        countOf: (r) => r.length,
        action: () => _inner.getCategories(),
      );

  @override
  Future<List<Category>> getActiveCategories() => _runFuture(
        op: 'getActiveCategories',
        ctx: const {'collection': 'categories', 'filter': 'active'},
        countOf: (r) => r.length,
        action: () => _inner.getActiveCategories(),
      );

  @override
  Future<Category?> getCategoryById(String id) => _runFuture(
        op: 'getCategoryById',
        ctx: {'collection': 'categories', 'id': id},
        countOf: (r) => r == null ? 0 : 1,
        action: () => _inner.getCategoryById(id),
      );

  @override
  Future<void> insertCategory(Category category) => _runFuture(
        op: 'insertCategory',
        ctx: {'collection': 'categories', 'id': category.id},
        countOf: (_) => null,
        action: () => _inner.insertCategory(category),
      );

  @override
  Future<void> updateCategory(Category category) => _runFuture(
        op: 'updateCategory',
        ctx: {'collection': 'categories', 'id': category.id},
        countOf: (_) => null,
        action: () => _inner.updateCategory(category),
      );

  @override
  Future<void> deleteCategory(String id) => _runFuture(
        op: 'deleteCategory',
        ctx: {'collection': 'categories', 'id': id},
        countOf: (_) => null,
        action: () => _inner.deleteCategory(id),
      );

  @override
  Future<void> permanentlyDeleteCategory(String id) => _runFuture(
        op: 'permanentlyDeleteCategory',
        ctx: {'collection': 'categories', 'id': id},
        countOf: (_) => null,
        action: () => _inner.permanentlyDeleteCategory(id),
      );

  @override
  Future<void> restoreCategory(String id) => _runFuture(
        op: 'restoreCategory',
        ctx: {'collection': 'categories', 'id': id},
        countOf: (_) => null,
        action: () => _inner.restoreCategory(id),
      );

  @override
  Stream<List<Category>> watchCategories() => _wrapStream(
        op: 'watchCategories',
        ctx: const {'collection': 'categories'},
        inner: () => _inner.watchCategories(),
      );

  @override
  Stream<List<Category>> watchActiveCategories() => _wrapStream(
        op: 'watchActiveCategories',
        ctx: const {'collection': 'categories', 'filter': 'active'},
        inner: () => _inner.watchActiveCategories(),
      );
}
