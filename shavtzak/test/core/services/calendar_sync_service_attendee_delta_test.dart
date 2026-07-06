// Tests for CalendarSyncService.syncAttendeeForAssignmentChange — the targeted
// attendee sync that fixes the "every assignment change emails ALL already
// assigned members" bug.
//
// Before: every assignment change called syncAttendeesForAppEvent, which
// re-pushed the WHOLE attendee roster via updateEventAttendees (a wholesale
// attendee-array replace with sendUpdates:'all') — so Google emailed every
// existing attendee.
//
// After: the change notifies ONLY the added/removed member via the incremental
// addAttendeeToEvent / removeAttendeeFromEvent primitives (which preserve
// existing attendees). A full re-sync (updateEventAttendees) is used ONLY for
// the "invite all permanent when unassigned" roster transitions.
//
// These assert at the GoogleCalendarService boundary:
//   * addAttendeeToEvent / removeAttendeeFromEvent  → targeted (per changed member)
//   * updateEventAttendees                          → full roster re-push (mass email)

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/services/calendar_sync_service.dart';
import 'package:shavtzak/core/services/google_calendar_service.dart';
import 'package:shavtzak/data/data_sources/database_interface.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

import 'calendar_sync_service_attendee_delta_test.mocks.dart';

@GenerateMocks([DatabaseInterface, GoogleCalendarService])
void main() {
  const eventId = 'ev1';
  const assemblyId = 'asm-cal';
  const mainId = 'main-cal';

  final now = DateTime(2026, 1, 1);

  late MockDatabaseInterface db;
  late MockGoogleCalendarService calendar;
  late CalendarSyncService service;

  Event eventWith({
    bool inviteAll = false,
    bool relevantForExtendedTeam = false,
  }) =>
      Event(
        id: eventId,
        name: 'event',
        startDate: DateTime(2026, 6, 1, 9, 0),
        endDate: DateTime(2026, 6, 1, 17, 0),
        startTime: '09:00',
        endTime: '17:00',
        assemblyTime: '08:30',
        requiresArmed: false,
        roleRequirements: const {'medic': 2},
        createdAt: now,
        updatedAt: now,
        inviteAllPermanentWhenUnassigned: inviteAll,
        relevantForExtendedTeam: relevantForExtendedTeam,
      );

  Assignment assignment(String id, String memberId, {String role = 'medic'}) =>
      Assignment(
        id: id,
        eventId: eventId,
        teamMemberId: memberId,
        roleType: role,
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: '',
        createdAt: now,
        updatedAt: now,
      );

  TeamMember member(String id, String? email, {bool permanent = true}) =>
      TeamMember(
        id: id,
        name: 'member-$id',
        isActive: true,
        isPermanent: permanent,
        constraints: const [],
        roleCapabilities: const {},
        createdAt: now,
        updatedAt: now,
        uniqueKey: 'key-$id',
        email: email,
      );

  setUp(() {
    db = MockDatabaseInterface();
    calendar = MockGoogleCalendarService();
    service = CalendarSyncService(database: db, calendarService: calendar);

    // Both calendar events exist for this app event.
    when(db.getEventCalendarSyncState(eventId)).thenAnswer((_) async => {
          'assemblyCalendarEventId': assemblyId,
          'mainCalendarEventId': mainId,
        });

    // Calendar boundary calls succeed by default.
    when(calendar.addAttendeeToEvent(any, any)).thenAnswer((_) async {});
    when(calendar.removeAttendeeFromEvent(any, any)).thenAnswer((_) async {});
    when(calendar.updateEventAttendees(any, any)).thenAnswer((_) async {});
  });

  // ---------------------------------------------------------------------------
  // Create: only the new member is invited; nobody else is touched.
  // ---------------------------------------------------------------------------
  test('create invites only the newly assigned member (no full re-push)',
      () async {
    when(db.getEventById(eventId)).thenAnswer((_) async => eventWith());
    when(db.getAssignmentsByEvent(eventId)).thenAnswer(
        (_) async => [assignment('a1', 'A'), assignment('a2', 'B')]);
    when(db.getTeamMemberById('B'))
        .thenAnswer((_) async => member('B', 'b@x.com'));

    await service.syncAttendeeForAssignmentChange(
      eventId: eventId,
      addedMemberId: 'B',
    );

    // Only B is added, on both calendar events. No mass re-push, no removes.
    verify(calendar.addAttendeeToEvent(assemblyId, 'b@x.com')).called(1);
    verify(calendar.addAttendeeToEvent(mainId, 'b@x.com')).called(1);
    verifyNever(calendar.updateEventAttendees(any, any));
    verifyNever(calendar.removeAttendeeFromEvent(any, any));
  });

  // ---------------------------------------------------------------------------
  // Delete (member has no other role): only that member is removed.
  // ---------------------------------------------------------------------------
  test('delete removes only the unassigned member', () async {
    when(db.getEventById(eventId)).thenAnswer((_) async => eventWith());
    // A is gone; only B remains.
    when(db.getAssignmentsByEvent(eventId))
        .thenAnswer((_) async => [assignment('a2', 'B')]);
    when(db.getTeamMemberById('A'))
        .thenAnswer((_) async => member('A', 'a@x.com'));

    await service.syncAttendeeForAssignmentChange(
      eventId: eventId,
      removedMemberId: 'A',
    );

    verify(calendar.removeAttendeeFromEvent(assemblyId, 'a@x.com')).called(1);
    verify(calendar.removeAttendeeFromEvent(mainId, 'a@x.com')).called(1);
    verifyNever(calendar.updateEventAttendees(any, any));
    verifyNever(calendar.addAttendeeToEvent(any, any));
  });

  // ---------------------------------------------------------------------------
  // Delete but the member still holds another role → they stay invited.
  // ---------------------------------------------------------------------------
  test('delete keeps a member who still holds another role in the event',
      () async {
    when(db.getEventById(eventId)).thenAnswer((_) async => eventWith());
    // A still has a second assignment in this event.
    when(db.getAssignmentsByEvent(eventId)).thenAnswer(
        (_) async => [assignment('a3', 'A', role: 'safetyOfficer')]);

    await service.syncAttendeeForAssignmentChange(
      eventId: eventId,
      removedMemberId: 'A',
    );

    verifyNever(calendar.removeAttendeeFromEvent(any, any));
    verifyNever(calendar.updateEventAttendees(any, any));
    verifyNever(calendar.addAttendeeToEvent(any, any));
  });

  // ---------------------------------------------------------------------------
  // Reassign A → B within the same event: remove A, add B, nobody else.
  // ---------------------------------------------------------------------------
  test('reassignment removes the old member and adds the new one', () async {
    when(db.getEventById(eventId)).thenAnswer((_) async => eventWith());
    when(db.getAssignmentsByEvent(eventId))
        .thenAnswer((_) async => [assignment('a1', 'B')]);
    when(db.getTeamMemberById('A'))
        .thenAnswer((_) async => member('A', 'a@x.com'));
    when(db.getTeamMemberById('B'))
        .thenAnswer((_) async => member('B', 'b@x.com'));

    await service.syncAttendeeForAssignmentChange(
      eventId: eventId,
      addedMemberId: 'B',
      removedMemberId: 'A',
    );

    verify(calendar.addAttendeeToEvent(any, 'b@x.com')).called(2);
    verify(calendar.removeAttendeeFromEvent(any, 'a@x.com')).called(2);
    verifyNever(calendar.updateEventAttendees(any, any));
  });

  // ---------------------------------------------------------------------------
  // Role-only change (same member kept): NOTHING is touched — zero emails.
  // ---------------------------------------------------------------------------
  test('role-only change for the same member touches no attendees', () async {
    await service.syncAttendeeForAssignmentChange(
      eventId: eventId,
      addedMemberId: 'A',
      removedMemberId: 'A',
    );

    verifyNever(calendar.addAttendeeToEvent(any, any));
    verifyNever(calendar.removeAttendeeFromEvent(any, any));
    verifyNever(calendar.updateEventAttendees(any, any));
    // Should not even need to hit the DB for a no-op member-unchanged edit.
    verifyNever(db.getAssignmentsByEvent(any));
  });

  // ---------------------------------------------------------------------------
  // Invite-all transition: LAST assignment removed → full roster re-sync.
  // ---------------------------------------------------------------------------
  test(
      'removing the last assignment on an invite-all event triggers a full '
      're-sync (roster returns to all permanent)', () async {
    when(db.getEventById(eventId))
        .thenAnswer((_) async => eventWith(inviteAll: true));
    when(db.getAssignmentsByEvent(eventId)).thenAnswer((_) async => []);
    // Full re-sync path fetches all members for the invite-all roster.
    when(db.getTeamMembers()).thenAnswer(
        (_) async => [member('P1', 'p1@x.com'), member('P2', 'p2@x.com')]);

    await service.syncAttendeeForAssignmentChange(
      eventId: eventId,
      removedMemberId: 'A',
    );

    // Full roster re-push (all permanent), NOT a targeted remove.
    verify(calendar.updateEventAttendees(any, any)).called(2); // assembly + main
    verifyNever(calendar.removeAttendeeFromEvent(any, any));
  });

  // ---------------------------------------------------------------------------
  // Invite-all transition: FIRST assignment added → full re-sync collapses the
  // roster from all-permanent down to just the assignee.
  // ---------------------------------------------------------------------------
  test(
      'adding the first assignment on an invite-all event triggers a full '
      're-sync (roster collapses to the assignee)', () async {
    when(db.getEventById(eventId))
        .thenAnswer((_) async => eventWith(inviteAll: true));
    when(db.getAssignmentsByEvent(eventId))
        .thenAnswer((_) async => [assignment('a1', 'B')]);
    when(db.getTeamMemberById('B'))
        .thenAnswer((_) async => member('B', 'b@x.com'));

    await service.syncAttendeeForAssignmentChange(
      eventId: eventId,
      addedMemberId: 'B',
    );

    verify(calendar.updateEventAttendees(any, any)).called(2);
    // Not the targeted add path.
    verifyNever(calendar.addAttendeeToEvent(any, any));
  });

  // ---------------------------------------------------------------------------
  // Non-invite-all event, last assignment removed → still targeted (no full
  // re-sync), because there is no all-permanent roster to restore.
  // ---------------------------------------------------------------------------
  test(
      'removing the last assignment on a normal event stays targeted (no full '
      're-sync)', () async {
    when(db.getEventById(eventId))
        .thenAnswer((_) async => eventWith(inviteAll: false));
    when(db.getAssignmentsByEvent(eventId)).thenAnswer((_) async => []);
    when(db.getTeamMemberById('A'))
        .thenAnswer((_) async => member('A', 'a@x.com'));

    await service.syncAttendeeForAssignmentChange(
      eventId: eventId,
      removedMemberId: 'A',
    );

    verify(calendar.removeAttendeeFromEvent(any, 'a@x.com')).called(2);
    verifyNever(calendar.updateEventAttendees(any, any));
  });

  // ---------------------------------------------------------------------------
  // A member without an email is simply skipped (no crash, no calendar call).
  // ---------------------------------------------------------------------------
  test('a newly assigned member without an email is skipped', () async {
    when(db.getEventById(eventId)).thenAnswer((_) async => eventWith());
    when(db.getAssignmentsByEvent(eventId))
        .thenAnswer((_) async => [assignment('a1', 'B')]);
    when(db.getTeamMemberById('B')).thenAnswer((_) async => member('B', null));

    await service.syncAttendeeForAssignmentChange(
      eventId: eventId,
      addedMemberId: 'B',
    );

    verifyNever(calendar.addAttendeeToEvent(any, any));
    verifyNever(calendar.updateEventAttendees(any, any));
  });
}
