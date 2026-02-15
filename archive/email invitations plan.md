Email Field + Google Calendar Invites                  

Context

Team members need an email field so they can be invited to Google Calendar events they're assigned to. This has two parts:
(1) adding the email field (same pattern as phone number), and (2) using that email to manage Google Calendar attendees
when assignments are created/deleted or when a member sets their email.

User decisions:
- Retroactive invite on email fill: future events only (endDate >= today)
- On assignment deletion or email clear: remove invite from calendar
- Implement both parts together

---
Part 1: Email Field

Following the exact phone number field pattern across all layers.

1.1 Entity — lib/domain/entities/team_member.dart

- Add final String? email; field (after phoneNumber ~line 167)
- Add this.email, to constructor (after this.phoneNumber ~line 197)
- Add String? email, bool clearEmail = false, to copyWith() params
- Add email: clearEmail ? null : (email ?? this.email), to copyWith() body
- Add email, to Equatable props

1.2 Model — lib/data/models/team_member_model.dart

- Add final String? email; field, this.email, in constructor
- fromEntity(): email: entity.email,
- toEntity(): email: email,
- fromFirestore(): final email = data['email'] as String?; (migration — defaults null)
- toFirestore(): 'email': email,
- fromJson() / toJson(): same pattern

1.3 Validator — lib/core/utils/validators.dart

Add after the phone number methods (~line 249):

static String? validateEmail(String? value) {
 if (value == null || value.trim().isEmpty) return null; // optional
 final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
 if (!emailRegex.hasMatch(value.trim())) return 'כתובת אימייל לא תקינה';
 return null;
}

1.4 BLoC Event — lib/presentation/bloc/user_selection/user_selection_event.dart

Add UpdateEmail event (after UpdatePhoneNumber):

class UpdateEmail extends UserSelectionEvent {
 final String? email;
 const UpdateEmail(this.email);
 @override
 List<Object?> get props => [email];
}

1.5 BLoC Handler — lib/presentation/bloc/user_selection/user_selection_bloc.dart

- Register on<UpdateEmail>(_onUpdateEmail); in constructor
- Add _onUpdateEmail handler: calls _userSelectionRepository.updateTeamMemberEmail(), then add(RefreshUserData())
- Also dispatches OnTeamMemberEmailChanged to CalendarSyncBloc (Part 2 integration)

1.6 Repository — lib/data/repositories/user_selection_repository.dart

Add updateTeamMemberEmail(uniqueKey, email) — same pattern as updateTeamMemberPhoneNumber: uses copyWith(email: email,
clearEmail: email == null, updatedAt: DateTime.now())

1.7 Email Edit Dialog (NEW) — lib/presentation/widgets/email_edit_dialog.dart

Clone phone_edit_dialog.dart structure:
- TextFormField with Validators.validateEmail, TextInputType.emailAddress
- No custom formatter needed (unlike phone)
- LTR text direction for email input
- Hebrew labels: title "עריכת אימייל", description about calendar invites
- Dispatches UpdateEmail event on save

1.8 Settings Dialog — lib/presentation/widgets/settings_dialog.dart

- Import email_edit_dialog.dart
- Add email Card between phone card and birthday card (same pattern as phone card)
- Icon: Icons.email / Icons.email_outlined
- Hebrew labels: "אימייל", "לא הוגדר אימייל", "הוסף אימייל"
- Add _showEmailEditDialog() and _deleteEmail() methods

1.9 Admin Modal — lib/presentation/screens/team/team_list_screen.dart

- Add _emailController (same pattern as _phoneController)
- Initialize from widget.member!.email ?? ''
- Add email TextFormField in form with Validators.validateEmail
- Add email display in member card (icon + blue text) with click-to-mailto (Uri(scheme: 'mailto', path: email))
- Include email in save: email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim()
- On save, if email changed, dispatch OnTeamMemberEmailChanged to CalendarSyncBloc

---
Part 2: Google Calendar Invites

2.1 GoogleCalendarService — lib/core/services/google_calendar_service.dart

Add three methods:

addAttendeeToCalendarEvent({calendarEventId, email})
- events.get() → add to attendees list (skip if already present) → events.update() with sendUpdates: 'all'
- Handle 404/410 gracefully (event deleted)

removeAttendeeFromCalendarEvent({calendarEventId, email})
- events.get() → filter out email from attendees → events.update() with sendUpdates: 'all'
- Handle 404/410 gracefully

setAttendeesForCalendarEvent({calendarEventId, emails, sendUpdates})
- events.get() → replace full attendees list → events.update()
- Used for batch sync operations

2.2 CalendarSyncService — lib/core/services/calendar_sync_service.dart

Add four methods:

addAttendeeToAppEvent({eventId, email})
- Look up getEventCalendarSyncState(eventId) → get assembly + main calendar IDs
- Call addAttendeeToCalendarEvent on both (skip if ID empty)

removeAttendeeFromAppEvent({eventId, email})
- Same lookup → call removeAttendeeFromCalendarEvent on both

syncAttendeesForAppEvent(eventId)
- Look up sync state → get all assignments for event → collect member emails → setAttendeesForCalendarEvent on both
- Used after assignment deletion (re-sync handles multi-role scenarios)

onTeamMemberEmailChanged({teamMemberId, oldEmail, newEmail})
- Get all assignments for member → filter future events only (endDate >= today)
- Remove old email from each event's calendar events (if old email existed)
- Add new email to each event's calendar events (if new email provided)

2.3 CalendarSyncBloc Events — lib/presentation/bloc/calendar_sync/calendar_sync_event.dart

Add four new events:
- AddAttendeeToAppEvent({eventId, email})
- RemoveAttendeeFromAppEvent({eventId, email})
- SyncAttendeesForAppEvent({eventId})
- OnTeamMemberEmailChanged({teamMemberId, oldEmail, newEmail})

2.4 CalendarSyncBloc Handlers — lib/presentation/bloc/calendar_sync/calendar_sync_bloc.dart

Register and implement handlers for the 4 new events. Each delegates to the corresponding CalendarSyncService method. All
are best-effort (catch and log errors, don't rethrow).

2.5 AssignmentBloc Integration — lib/presentation/bloc/assignment/assignment_bloc.dart

- Add CalendarSyncBloc? _calendarSyncBloc as optional constructor parameter
- Add import for CalendarSyncBloc events

On assignment create (in _onCreateAssignmentWithBypass ~line 1596, after success):
// Calendar invite: add attendee if member has email
final email = event.assignment.teamMember?.email;
if (email != null && email.isNotEmpty) {
 _calendarSyncBloc?.add(AddAttendeeToAppEvent(eventId: event.assignment.eventId, email: email));
}

On assignment delete (in _onDeleteAssignment ~line 327, and _onOptimisticDeleteAssignment):
- Before deleting, capture eventId from the assignment
- After delete, dispatch SyncAttendeesForAppEvent(eventId: eventId) to re-sync attendees
- Use sync (not remove) because member might have other assignments to same event

2.6 main.dart — Pass CalendarSyncBloc

- Pass calendarSyncBloc: context.read<CalendarSyncBloc>() to AssignmentBloc constructor
- Pass context.read<CalendarSyncBloc>() to UserSelectionBloc constructor

2.7 Sync Attendees on Calendar Event Creation — lib/core/services/calendar_sync_service.dart

In syncAppEventToCalendar, after creating calendar events, call syncAttendeesForAppEvent(eventId). This handles the case
where assignments exist before the event is synced to Google Calendar.

2.8 UserSelectionBloc Integration — lib/presentation/bloc/user_selection/user_selection_bloc.dart

- Add CalendarSyncBloc? _calendarSyncBloc as optional constructor parameter
- In _onUpdateEmail, after successful update, dispatch:
_calendarSyncBloc?.add(OnTeamMemberEmailChanged(
 teamMemberId: currentState.user.id,
 oldEmail: oldEmail,
 newEmail: event.email,
));

2.9 Admin Modal Integration — lib/presentation/screens/team/team_list_screen.dart

When admin saves a team member with changed email, also dispatch OnTeamMemberEmailChanged to CalendarSyncBloc.

---
Trigger Summary

┌───────────────────────────────┬──────────────────────────────────────────┬───────────────────────────────────────┐
│            Trigger            │                  Action                  │        CalendarSyncBloc Event         │
├───────────────────────────────┼──────────────────────────────────────────┼───────────────────────────────────────┤
│ Assignment created            │ Add member email to event's calendar     │ AddAttendeeToAppEvent                 │
├───────────────────────────────┼──────────────────────────────────────────┼───────────────────────────────────────┤
│ Assignment deleted            │ Re-sync all attendees for event          │ SyncAttendeesForAppEvent              │
├───────────────────────────────┼──────────────────────────────────────────┼───────────────────────────────────────┤
│ User fills/changes email      │ Update all future assigned events        │ OnTeamMemberEmailChanged              │
├───────────────────────────────┼──────────────────────────────────────────┼───────────────────────────────────────┤
│ User clears email             │ Remove from all future events            │ OnTeamMemberEmailChanged              │
├───────────────────────────────┼──────────────────────────────────────────┼───────────────────────────────────────┤
│ Admin changes member email    │ Update all future assigned events        │ OnTeamMemberEmailChanged              │
├───────────────────────────────┼──────────────────────────────────────────┼───────────────────────────────────────┤
│ Calendar events first created │ Sync attendees from existing assignments │ Inline call in syncAppEventToCalendar │
└───────────────────────────────┴──────────────────────────────────────────┴───────────────────────────────────────┘

---
Files Modified (14) + Files Created (1)

Part 1 — Modified:
1. lib/domain/entities/team_member.dart
2. lib/data/models/team_member_model.dart
3. lib/core/utils/validators.dart
4. lib/presentation/bloc/user_selection/user_selection_event.dart
5. lib/presentation/bloc/user_selection/user_selection_bloc.dart
6. lib/data/repositories/user_selection_repository.dart
7. lib/presentation/widgets/settings_dialog.dart
8. lib/presentation/screens/team/team_list_screen.dart

Part 1 — Created:
9. lib/presentation/widgets/email_edit_dialog.dart

Part 2 — Modified:
10. lib/core/services/google_calendar_service.dart
11. lib/core/services/calendar_sync_service.dart
12. lib/presentation/bloc/calendar_sync/calendar_sync_event.dart
13. lib/presentation/bloc/calendar_sync/calendar_sync_bloc.dart
14. lib/presentation/bloc/assignment/assignment_bloc.dart
15. lib/main.dart

---
Verification

1. flutter analyze — check for compilation errors
2. Test email CRUD: add/edit/delete email in user settings dialog
3. Test email CRUD: add/edit email in admin team member modal
4. Test email display in team member cards (click-to-mailto)
5. Test calendar invite: create assignment for member with email → check Google Calendar event has attendee
6. Test calendar removal: delete assignment → check attendee removed from calendar event
7. Test retroactive invite: set email on member with existing assignments → check future events get attendee
8. Test email clear: clear email → check attendees removed from calendar events