import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/services/calendar_sync_service.dart';
import 'package:shavtzak/core/services/google_calendar_service.dart';
import 'package:shavtzak/data/data_sources/database_interface.dart';

import 'calendar_sync_service_attendee_delta_test.mocks.dart';

@GenerateMocks([DatabaseInterface, GoogleCalendarService])
void main() {
  test('legacy app-event guest hooks have no database or Calendar behavior',
      () async {
    final database = MockDatabaseInterface();
    final calendar = MockGoogleCalendarService();
    final service = CalendarSyncService(
      database: database,
      calendarService: calendar,
    );

    await service.syncAttendeeForAssignmentChange(
      eventId: 'event-1',
      addedMemberId: 'member-1',
      removedMemberId: 'member-2',
    );
    await service.addAttendeeToAppEvent(
      eventId: 'event-1',
      email: 'new@example.com',
    );
    await service.removeAttendeeFromAppEvent(
      eventId: 'event-1',
      email: 'old@example.com',
    );
    await service.syncAttendeesForAppEvent('event-1');
    await service.onTeamMemberEmailChanged(
      teamMemberId: 'member-1',
      oldEmail: 'old@example.com',
      newEmail: 'new@example.com',
    );

    verifyNever(database.getEventCalendarSyncState(any));
    verifyNever(database.getAssignmentsByEvent(any));
    verifyNever(database.getAssignmentsByPerson(any));
    verifyNever(calendar.addAttendeeToEvent(any, any));
    verifyNever(calendar.removeAttendeeFromEvent(any, any));
    verifyNever(calendar.updateEventAttendees(any, any));
  });
}
