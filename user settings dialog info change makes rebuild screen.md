› It seems like changing (not deleting! only changeing) a team member's info from the user settings dialog, makes the whole
  "/user/*" screen rebuild.

  As I said - this is only happening when the detail's dialog is opened and then the team member presses on "שמור".

  On "מחק" - there is no rebuild...


• I’ll trace the /user/* widget tree and UserSelectionBloc listeners to find why pressing שמור triggers a full shell rebuild,
  then patch it so profile updates don’t remount the whole user area.

• I found a likely culprit in routing: every UserSelectionBloc state change calls EnvironmentService.updateFromPath(...). I’m
  checking whether that method notifies listeners even when environment didn’t actually change, because that would rebuild
  the whole app tree.

• Environment notifications are guarded, so I’m now checking /user screens for listeners keyed on full UserAuthenticated
  state; those can trigger full data reloads even when only profile fields changed.

• I found that most /user screens are wrapped in BlocBuilder<UserSelectionBloc, UserSelectionState>, so any profile update
  (UserAuthenticated emit) rebuilds the full page. I’m now checking the save/delete flows and then I’ll narrow those rebuild
  subscriptions to only fields each screen actually needs.

• I’m implementing a targeted optimization: keep user-auth reactions only for route-critical fields (userId, isPermanent,
  etc.), so saving phone/email/birthday won’t trigger full /user/* subtree rebuilds or checklist reloads.

• I’ve applied rebuild-scoping changes across user screens and checklist listener; now I’m running flutter analyze to verify
  there are no compile errors from these edits.

• Root cause was broad subscriptions to UserSelectionBloc state in /user/* screens.
  Pressing שמור emits a new UserAuthenticated (with updated user object), and those builders/listeners rebuilt/reloaded
  entire screens.

  Implemented fix by scoping rebuilds to only routing-relevant fields:

  - shavtzak/lib/presentation/screens/user/user_assignments_screen.dart
      - Switched top-level auth wrapper to BlocSelector on user.id only.
      - Parking edit permission now uses context.select for user.id only.
  - shavtzak/lib/presentation/screens/user/constraints_screen.dart
      - Switched auth wrapper to BlocSelector with minimal context (userId, isAuthenticated, isPermanent).
  - shavtzak/lib/presentation/screens/user/availability_screen.dart
      - Same pattern: BlocSelector with minimal auth context.
  - shavtzak/lib/presentation/screens/user/user_navigation_shell.dart
      - Added buildWhen for app bar and bottom nav so they don’t rebuild on unrelated profile field changes.
  - shavtzak/lib/presentation/screens/user/user_checklist_screen.dart
      - Added listenWhen + buildWhen so checklist reload/rebuild happens only when authenticated user ID changes (not on
        phone/email/etc updates).

  Validation:

  - Ran flutter analyze successfully; no new compile errors from these changes (repo still has existing warnings).

  If you want, I can also add lightweight debug logs around these selectors/buildWhen conditions so you can verify in console
  exactly when rebuilds are now skipped.


› yes... Add the debug logs. It is still happening...
  There is a quick white blank screen, and then the UI comes back... (it looks like a rebuild).


• I’ll add focused debug logs in the auth/router/environment path so we can see exactly what causes that white flash:
  UserSelectionBloc state transitions, router auth checks, and any environment-triggered app-tree rebuild.

• I’m adding high-signal logs now: every UserSelectionBloc state change, router redirect/auth decisions, and environment/
  listenable rebuild triggers in MyApp. That should pinpoint exactly which transition causes the white screen.

• The logging hooks are in place. I’m running flutter analyze now to ensure these debug additions compile cleanly before you
  test the flow again.

• Added debug logging in the exact flow that can cause the white flash.

  ### Logs added

  - shavtzak/lib/presentation/bloc/user_selection/user_selection_bloc.dart
      - Logs every state change (onChange)
      - Logs when team stream pushes updated authenticated user
  - shavtzak/lib/core/router/app_router.dart
      - Logs user-selection stream events + current route
      - Logs redirect checks for /user*
      - Logs when unauthenticated redirect is triggered
      - Logs when user shell builder renders unauthenticated fallback
  - shavtzak/lib/core/services/environment_service.dart
      - Logs every updateFromPath and setTestMode, including notify-triggering changes
  - shavtzak/lib/main.dart
      - Logs each MyApp build count + current env (to detect top-level tree rebuilds)

  ### What to do now

  Reproduce the issue once (open details dialog -> שמור), then send me the console lines around the flash containing these
  tags:

  - UserSelectionBloc
  - AppRouter
  - EnvironmentService
  - Main

  If possible, include about 2-3 seconds before and after the white screen.
  That will let me identify the exact trigger (auth-state fallback, redirect bounce, or full app rebuild) and patch it
  directly.


› developer_patch.dart:70 dart.developer.log {message: 'team stream detected user change for dbf7cb5e-8120…2-88dc-
  99b0e586b073 -> emitting UserAuthenticated', name: 'UserSelectionBloc', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'state change: UserAuthenticated -> UserAuthenticated', name:
  'UserSelectionBloc', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'bloc stream state=UserAuthenticated currentRoute="/user/
  assignments"', name: 'AppRouter', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'EnvironmentService.updateFromPath path="/user/assignments"
  current=false new=false', name: 'EnvironmentService', level: 0}


• Thanks, this log is useful: it shows a pure UserAuthenticated -> UserAuthenticated update (not sign-out), so I’m now
  patching router logic to ignore non-navigation auth updates and adding a few more pinpoint logs around update/refresh
  events. This should either stop the flash or prove exactly where it comes from.

• I’ve added the skip-logic and extra logs; running analyzer now to confirm clean compile before you retest.

• Great, your log confirms it was a non-auth-loss update (UserAuthenticated -> UserAuthenticated) during save.

  I added a targeted guard so router handling is skipped for non-navigation auth updates, plus deeper logs around update/
  refresh flow:

  - shavtzak/lib/core/router/app_router.dart
      - New auth-signature skip path:
      - log: skip stream handling for non-nav auth update ...
  - shavtzak/lib/presentation/bloc/user_selection/user_selection_bloc.dart
      - Logs for UpdatePhoneNumber/UpdateEmail/UpdateBirthday/UpdateVehicleInfo
      - Logs for RefreshUserData start and emit
  - Existing logs remain in:
      - shavtzak/lib/main.dart (MyApp build #...)
      - shavtzak/lib/core/services/environment_service.dart

  Please retest once and share logs around the flash, especially:

  1. UserSelectionBloc (Update..., RefreshUserData..., state change...)
  2. AppRouter (skip stream handling..., redirect check..., any unauthenticated...)
  3. Main (MyApp build #...)

  If the flash still appears and we do not see MyApp build or unauth redirect logs, I’ll patch next at page-level (likely a
  specific /user/assignments subtree reset rather than global rebuild).


› Still flashing... Here are the logs:

  dart.developer.log {message: 'UpdateEmail requested for user=dbf7cb5e-8120-4152-88dc-99b0e586b073
  value="omerbengal7@gmail.com"', name: 'UserSelectionBloc', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'team stream detected user change for dbf7cb5e-8120…2-88dc-
  99b0e586b073 -> emitting UserAuthenticated', name: 'UserSelectionBloc', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'state change: UserAuthenticated -> UserAuthenticated', name:
  'UserSelectionBloc', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'bloc stream state=UserAuthenticated currentRoute="/user/
  assignments"', name: 'AppRouter', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'EnvironmentService.updateFromPath path="/user/assignments"
  current=false new=false', name: 'EnvironmentService', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'RefreshUserData start for user=dbf7cb5e-8120-4152-88dc-
  99b0e586b073', name: 'UserSelectionBloc', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'RefreshUserData emit UserAuthenticated user=dbf7cb5e-8120-4152-88dc-
  99b0e586b073', name: 'UserSelectionBloc', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event u0aeo6s6to7oke5avud30nt7c8', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event a5416bpva297sg4ga282fdsj00', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event a14i4u46i7g6jqvrlcbnm92m4c', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event o8fajrrg7c0v8cd51rbhtn3gus', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event 74e0v0j7r7e13nrvs4da8uedak', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event df5q904q0hjpba7ar9tojp8ucs', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event qorujk6cqoc87h8proc9k9kojk', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event 9tfng504mn041ak07cfn930054', name: 'GoogleCalendar', level: 0}


• I’m going one level deeper: I suspect another listener is reloading assignment data on every UserAuthenticated emission
  (same user), which would produce a brief blank/loading frame. I’ll trace all LoadUserAssignments triggers and patch them to
  fire only when user ID actually changes.

• I found a likely concrete trigger: UserAssignmentsScreen shows a loading/blank state whenever AssignmentBloc gets
  AssignmentLoading, and that can happen if the screen is recreated and re-dispatches LoadUserAssignments. I’m going to
  harden this screen so it reuses the last loaded assignments during any reload and never flashes blank.

• I see one strong remaining issue: each save currently causes two authenticated emits (team stream + RefreshUserData), which
  can still trigger transient UI churn. I’m patching the update handlers to stop forcing RefreshUserData after writes and
  rely on the existing team stream update only.

• I removed the duplicate refresh emissions. I’ll run analyzer quickly, then you can retest and we’ll compare logs (you
  should now see only one UserAuthenticated -> UserAuthenticated on save).

• Applied a concrete reduction that should cut the flash source:

  - Removed forced RefreshUserData after profile updates in:
      - shavtzak/lib/presentation/bloc/user_selection/user_selection_bloc.dart
      - UpdatePhoneNumber
      - UpdateBirthday
      - UpdateVehicleInfo
      - UpdateEmail

  Now profile save should emit only once (from the team stream), instead of twice (team stream + manual refresh).

  Please retest the same flow and share logs again.
  Expected difference: you should no longer see:

  - RefreshUserData start...
  - RefreshUserData emit UserAuthenticated...

  If the flash still happens with only a single UserAuthenticated -> UserAuthenticated, I’ll make the next fix by decoupling
  route guards from raw auth state stream updates entirely (so profile field updates never touch shell rendering at all).


› Still happening!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  dart.developer.log {message: 'UpdateEmail requested for user=dbf7cb5e-8120-4152-88dc-99b0e586b073
  value="omerbengal7@gmail.com"', name: 'UserSelectionBloc', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'team stream detected user change for dbf7cb5e-8120…2-88dc-
  99b0e586b073 -> emitting UserAuthenticated', name: 'UserSelectionBloc', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'state change: UserAuthenticated -> UserAuthenticated', name:
  'UserSelectionBloc', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'bloc stream state=UserAuthenticated currentRoute="/user/
  assignments"', name: 'AppRouter', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'skip stream handling for non-nav auth update signa…
  99b0e586b073:true:true" route="/user/assignments"', name: 'AppRouter', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event u0aeo6s6to7oke5avud30nt7c8', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event a5416bpva297sg4ga282fdsj00', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event a14i4u46i7g6jqvrlcbnm92m4c', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event o8fajrrg7c0v8cd51rbhtn3gus', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event 74e0v0j7r7e13nrvs4da8uedak', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event df5q904q0hjpba7ar9tojp8ucs', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event qorujk6cqoc87h8proc9k9kojk', name: 'GoogleCalendar', level: 0}
  developer_patch.dart:70 dart.developer.log {message: 'GoogleCalendarService: Attendee omerbengal7@gmail.com already in
  event 9tfng504mn041ak07cfn930054', name: 'GoogleCalendar', level: 0}


• I have enough signal now: router/auth is no longer the trigger. I’m going to inspect and patch the edit-dialog save flow
  itself (loading overlay + pop timing), which is likely causing the white frame when pressing שמור.

• Found the actual cause: the edit dialogs paint a full-screen white LoadingOverlay on שמור right before closing, which looks
  exactly like the flash you’re describing. I’m removing that overlay behavior from the save path so save won’t white-out the
  app anymore.

• I removed the white loading overlay from all profile edit dialogs and stopped setting _isSaving = true before close, so
  שמור no longer paints the full white layer. I’m running analyze once, then you can retest immediately.

• I introduced syntax issues while removing the Stack wrappers. I’m fixing those dialog build blocks now and rerunning
  analyze.

• You were right to push on this. The white flash source was not router/auth anymore.

  I found and fixed a direct UI cause:

  - On שמור, the edit dialogs were rendering a full-screen white LoadingOverlay (Colors.white.withOpacity(0.8)) right before
    closing.
  - That creates exactly a quick white blank frame.

  ### Fixed

  Removed the white overlay behavior from save flow in:

  - shavtzak/lib/presentation/widgets/email_edit_dialog.dart
  - shavtzak/lib/presentation/widgets/phone_edit_dialog.dart
  - shavtzak/lib/presentation/widgets/birthday_edit_dialog.dart
  - shavtzak/lib/presentation/widgets/vehicle_info_edit_dialog.dart

  Specifically:

  - Removed LoadingOverlay(isLoading: _isSaving, ...) from these dialogs.
  - Stopped setting _isSaving = true in save methods (which was triggering the overlay frame).

  flutter analyze passes with the same pre-existing repo warnings (no new compile errors).

  Please retest now. If you still see any flash, I’ll immediately strip the remaining dialog animation transition itself
  (next likely source, much smaller).


› It works!