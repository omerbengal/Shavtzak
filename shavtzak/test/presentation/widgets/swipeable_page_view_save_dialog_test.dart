// Widget test for the "smoke-fix" BUG 2: tapping a different bottom-nav tab
// while the assignments tab has unsaved staged changes, then choosing "שמור
// והמשך" in the unsaved-changes leave-guard dialog, must show the SAME kind
// of blocking "שומר שינויים..." loading feedback the on-screen Save button
// gives via assignment_list_screen.dart's mutation overlay
// (_buildMutationDialogOverlay / _startMutation('שומר שינויים...')).
//
// Root cause (pre-fix): SwipeablePageView._onBottomNavTapped's
// LeaveDecision.save branch dispatched SaveStagedChanges directly to the
// AssignmentBloc and awaited the completer with no loading UI at all, so the
// admin saw nothing happen until the save resolved.
//
// Harness notes:
// - SwipeablePageView needs a real StatefulNavigationShell, which only
//   go_router's StatefulShellRoute.indexedStack can produce — there is no
//   way to fake/construct one standalone (see the header comment in the
//   existing swipeable_page_view_test.dart, which sidesteps this by testing
//   BottomNavWithDebugTrigger in isolation instead). This test takes the
//   other path: build a minimal GoRouter with the same branch shape as the
//   real admin shell in app_router.dart (home / team-members / events /
//   assignments / checklist, in that order) with trivial placeholder
//   screens standing in for the real ones, and pump SwipeablePageView as the
//   shell's actual branch builder — then drive it exactly like a user would
//   (tap a bottom-nav icon -> tap a dialog button -> ...).
// - AssignmentBloc is stubbed with bloc_test's MockBloc, mirroring
//   assignment_staged_delete_overlay_test.dart's _MockAssignmentBloc:
//   hasStagedChanges/stagedCount are overridden directly as plain Dart
//   fields (not via mocktail's when()/whenListen for arbitrary methods —
//   this codebase's convention, per that file's comments, is to sidestep
//   mocktail's matcher machinery where a manual override is simpler). add()
//   records dispatched events into a list so the test can reach into the
//   SaveStagedChanges event's own `completion` completer and complete it on
//   demand from outside the widget — the only way to control the timing of
//   the awaited save.
// - CircularProgressIndicator (indeterminate) never stops scheduling
//   frames, so pumpAndSettle() would hang for as long as the loading dialog
//   is on screen. This test uses plain pump() (with explicit durations
//   where an animation needs to finish) instead, anywhere the loading
//   dialog might be visible.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';
import 'package:shavtzak/presentation/bloc/assignment/models/assignment_conflict.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_event.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';
import 'package:shavtzak/presentation/screens/assignment/models/assignment_slot.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/conflict_resolution_dialog.dart';
import 'package:shavtzak/presentation/widgets/swipeable_page_view.dart';

class _MockAssignmentBloc extends MockBloc<AssignmentEvent, AssignmentState>
    implements AssignmentBloc {
  _MockAssignmentBloc({
    required this.hasStagedChanges,
    required this.stagedCount,
    this.conflictsToReturn = const [],
    this.lastLoadedSlotsToReturn = const [],
  });

  @override
  final bool hasStagedChanges;

  @override
  final int stagedCount;

  /// Canned result for classifyStagedConflicts — a plain Dart override, not
  /// a mocktail when() stub, same convention as hasStagedChanges/stagedCount
  /// above (see assignment_staged_delete_overlay_test.dart's header notes,
  /// referenced from this file's own header).
  final List<AssignmentConflict> conflictsToReturn;

  /// Canned return for the bloc-cached [lastLoadedSlots] getter — the robust
  /// slot source both Save paths now read (instead of branching on a
  /// possibly-non-loaded live `state`). Defaults empty for tests that don't
  /// exercise the slots argument.
  final List<AssignmentSlot> lastLoadedSlotsToReturn;

  @override
  List<AssignmentSlot> get lastLoadedSlots => lastLoadedSlotsToReturn;

  /// The `currentSlots` argument [classifyStagedConflicts] was last invoked
  /// with. Lets a test prove the leave-guard passed the REAL cached slots
  /// (from [lastLoadedSlots]) and not an empty list — the regression this
  /// mock previously couldn't catch, because the old override ignored its
  /// argument entirely.
  List<AssignmentSlot>? capturedClassifySlots;

  @override
  List<AssignmentConflict> classifyStagedConflicts(
      List<AssignmentSlot> currentSlots) {
    capturedClassifySlots = currentSlots;
    return conflictsToReturn;
  }

  /// Events the widget dispatched onto this mock bloc. In particular, lets
  /// the test grab the SaveStagedChanges event's own `completion` completer
  /// and complete it on demand (see file header).
  final List<AssignmentEvent> addedEvents = [];

  @override
  void add(AssignmentEvent event) {
    addedEvents.add(event);
  }
}

class _MockUserSelectionBloc
    extends MockBloc<UserSelectionEvent, UserSelectionState>
    implements UserSelectionBloc {}

void main() {
  final now = DateTime(2026, 7, 1);
  final admin = TeamMember(
    id: 'admin1',
    name: 'מנהלת',
    isActive: true,
    constraints: const [],
    roleCapabilities: const {},
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'unique-admin1',
    isAdmin: true,
  );

  // A single real filled slot (slotKey "e1_medic_0"), used to prove the
  // leave-guard hands classifyStagedConflicts the bloc's cached slots rather
  // than an empty list when the live state is not AssignmentSlotsLoaded.
  final assignedMember = TeamMember(
    id: 'm1',
    name: 'יוסי כהן',
    isActive: true,
    constraints: const [],
    roleCapabilities: const {'medic': true},
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'unique-m1',
  );
  final event = Event(
    id: 'e1',
    name: 'אירוע קיץ',
    startDate: now,
    endDate: now,
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
  final role = Role(
    id: 'medic',
    key: 'medic',
    hebrewName: 'חובש',
    sortOrder: 0,
    createdAt: now,
    updatedAt: now,
  );
  final assignment = Assignment(
    id: 'a1',
    eventId: 'e1',
    teamMemberId: 'm1',
    roleType: 'medic',
    slotIndex: 0,
    status: AssignmentStatus.confirmed,
    notes: '',
    createdAt: now,
    updatedAt: now,
    teamMember: assignedMember,
  );
  final realSlot = AssignmentSlot(
    event: event,
    role: role,
    slotIndex: 0,
    currentAssignment: assignment,
    availableMembers: [assignedMember],
  );

  /// Builds a minimal admin shell (matching app_router.dart's branch order:
  /// home / team-members / events / assignments / checklist) starting on
  /// the assignments tab, with SwipeablePageView as the real shell builder.
  Future<_MockAssignmentBloc> pumpAdminShellOnAssignmentsTab(
    WidgetTester tester, {
    required bool hasStagedChanges,
    int stagedCount = 1,
    List<AssignmentConflict> conflictsToReturn = const [],
    List<AssignmentSlot> lastLoadedSlotsToReturn = const [],
    AssignmentState initialState = const AssignmentInitial(),
  }) async {
    final assignmentBloc = _MockAssignmentBloc(
      hasStagedChanges: hasStagedChanges,
      stagedCount: stagedCount,
      conflictsToReturn: conflictsToReturn,
      lastLoadedSlotsToReturn: lastLoadedSlotsToReturn,
    );
    whenListen(
      assignmentBloc,
      Stream<AssignmentState>.empty(),
      initialState: initialState,
    );

    final userSelectionBloc = _MockUserSelectionBloc();
    whenListen(
      userSelectionBloc,
      Stream<UserSelectionState>.empty(),
      initialState: UserAuthenticated(admin),
    );

    final router = GoRouter(
      initialLocation: '/admin/assignments',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              SwipeablePageView(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/admin',
                builder: (context, state) =>
                    const Scaffold(body: Text('Home')),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/admin/team-members',
                builder: (context, state) =>
                    const Scaffold(body: Text('Team')),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/admin/events',
                builder: (context, state) =>
                    const Scaffold(body: Text('Events')),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/admin/assignments',
                builder: (context, state) =>
                    const Scaffold(body: Text('Assignments')),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/admin/checklist',
                builder: (context, state) =>
                    const Scaffold(body: Text('Checklist')),
              ),
            ]),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AssignmentBloc>.value(value: assignmentBloc),
          BlocProvider<UserSelectionBloc>.value(value: userSelectionBloc),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    // No indeterminate spinners on screen yet — safe to settle fully.
    await tester.pumpAndSettle();

    return assignmentBloc;
  }

  /// Taps the "team members" bottom-nav tab (people icon) while sitting on
  /// the assignments tab, then taps "שמור והמשך" in the resulting
  /// unsaved-changes leave-guard dialog. Leaves the SaveStagedChanges
  /// completer UNRESOLVED so callers can assert on in-flight UI state.
  Future<void> triggerTabSwitchAndChooseSave(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.people));
    // Finite dialog-entrance transition only — safe to settle.
    await tester.pumpAndSettle();

    expect(find.text('שינויי שיבוצים לא נשמרו'), findsOneWidget);
    await tester.tap(find.text('שמור והמשך'));
    // From here on a loading dialog may be showing an indeterminate
    // spinner — plain pump() only, never pumpAndSettle().
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'tab-switch save shows the blocking "שומר שינויים..." loading dialog '
    'while the save is in flight, then dismisses it and navigates on success',
    (tester) async {
      final assignmentBloc = await pumpAdminShellOnAssignmentsTab(
        tester,
        hasStagedChanges: true,
        stagedCount: 2,
      );

      await triggerTabSwitchAndChooseSave(tester);

      // No staged-vs-DB conflicts configured on this mock — the conflict
      // dialog must not appear, and the save proceeds straight through.
      expect(find.byType(ConflictResolutionDialog), findsNothing);

      final saveEvents =
          assignmentBloc.addedEvents.whereType<SaveStagedChanges>().toList();
      expect(saveEvents, hasLength(1));
      final completion = saveEvents.single.completion!;
      expect(completion.isCompleted, isFalse,
          reason: 'the test must observe the loading UI before the save '
              'resolves, otherwise this proves nothing');

      // THE BUG: with no fix, nothing shows this text at all.
      expect(find.text('שומר שינויים...'), findsOneWidget);

      completion.complete(const CrudActionResult.success());
      await tester.pump(); // resume past `await` on the completer
      await tester.pump(const Duration(milliseconds: 300)); // dialog exit

      expect(find.text('שומר שינויים...'), findsNothing);

      // Navigation proceeded to the team-members branch (bottom-nav index 3
      // per SwipeablePageView._getBottomNavIndex(): page index 1 -> 3).
      final bottomNav =
          tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bottomNav.currentIndex, 3);
    },
  );

  testWidgets(
    'tab-switch save dismisses the loading dialog and stays put when the '
    'save fails',
    (tester) async {
      final assignmentBloc = await pumpAdminShellOnAssignmentsTab(
        tester,
        hasStagedChanges: true,
        stagedCount: 1,
      );

      await triggerTabSwitchAndChooseSave(tester);

      final completion = assignmentBloc.addedEvents
          .whereType<SaveStagedChanges>()
          .single
          .completion!;
      expect(find.text('שומר שינויים...'), findsOneWidget);

      completion.complete(const CrudActionResult.failure('שמירה נכשלה'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('שומר שינויים...'), findsNothing);

      // Stayed on the assignments tab (bottom-nav index 1).
      final bottomNav =
          tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bottomNav.currentIndex, 1);
    },
  );

  // BUG: tab-switch save must run the SAME conflict-resolution flow as the
  // on-screen Save button (bloc.classifyStagedConflicts +
  // ConflictResolutionDialog), not skip it. Pre-fix,
  // SwipeablePageView._onBottomNavTapped's LeaveDecision.save branch
  // dispatches SaveStagedChanges directly with no classification/dialog at
  // all, so these two tests fail (RED) before the shared-helper fix.
  group('tab-switch save conflict resolution (parity with on-screen Save)', () {
    const conflict = AssignmentConflict(
      slotKey: 'e1_medic_0',
      type: AssignmentConflictType.slotTaken,
      description: 'המשרה נתפסה: בינתיים שובץ שם אדם אחר ב-DB.',
    );

    testWidgets(
      'shows the ConflictResolutionDialog when staged-vs-DB conflicts '
      'exist, and cancelling it does NOT dispatch SaveStagedChanges and '
      'stays on the assignments tab',
      (tester) async {
        final assignmentBloc = await pumpAdminShellOnAssignmentsTab(
          tester,
          hasStagedChanges: true,
          stagedCount: 1,
          conflictsToReturn: const [conflict],
        );

        await tester.tap(find.byIcon(Icons.people));
        await tester.pumpAndSettle();
        expect(find.text('שינויי שיבוצים לא נשמרו'), findsOneWidget);
        await tester.tap(find.text('שמור והמשך'));
        // No indeterminate spinner can be showing yet — the conflict
        // dialog (a plain AlertDialog, finite entrance animation) gates
        // the loading dialog, so settling here is safe.
        await tester.pumpAndSettle();

        // The SAME conflict-resolution dialog the on-screen Save button
        // uses.
        expect(find.byType(ConflictResolutionDialog), findsOneWidget);
        expect(find.text('נמצאו התנגשויות'), findsOneWidget);

        // Nothing dispatched yet, and no loading dialog either.
        expect(
          assignmentBloc.addedEvents.whereType<SaveStagedChanges>(),
          isEmpty,
        );
        expect(find.text('שומר שינויים...'), findsNothing);

        await tester.tap(find.text('ביטול'));
        await tester.pumpAndSettle();

        expect(find.byType(ConflictResolutionDialog), findsNothing);
        expect(
          assignmentBloc.addedEvents.whereType<SaveStagedChanges>(),
          isEmpty,
          reason: 'cancelling the conflict dialog must not save',
        );

        // Stayed on the assignments tab (bottom-nav index 1).
        final bottomNav = tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
        expect(bottomNav.currentIndex, 1);
      },
    );

    testWidgets(
      'resolving the ConflictResolutionDialog dispatches SaveStagedChanges '
      'WITH the chosen resolutions, shows the loading dialog, and '
      'navigates on success',
      (tester) async {
        final assignmentBloc = await pumpAdminShellOnAssignmentsTab(
          tester,
          hasStagedChanges: true,
          stagedCount: 1,
          conflictsToReturn: const [conflict],
        );

        await tester.tap(find.byIcon(Icons.people));
        await tester.pumpAndSettle();
        await tester.tap(find.text('שמור והמשך'));
        await tester.pumpAndSettle();

        expect(find.byType(ConflictResolutionDialog), findsOneWidget);

        // Confirm with the dialog's default resolution (overrideDb, i.e.
        // "דרוס DB") via its own "שמור" action button.
        await tester.tap(find.text('שמור'));
        // From here on a loading dialog may be showing an indeterminate
        // spinner — plain pump() only, never pumpAndSettle(). The explicit
        // duration lets the conflict dialog's exit transition AND the
        // loading dialog's entrance transition both finish (mirrors the
        // 300ms exit pump used below for the loading dialog itself).
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(ConflictResolutionDialog), findsNothing);
        expect(find.text('שומר שינויים...'), findsOneWidget);

        final saveEvents =
            assignmentBloc.addedEvents.whereType<SaveStagedChanges>().toList();
        expect(saveEvents, hasLength(1));
        expect(
          saveEvents.single.resolutions,
          {'e1_medic_0': ConflictResolution.overrideDb},
        );

        final completion = saveEvents.single.completion!;
        completion.complete(const CrudActionResult.success());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('שומר שינויים...'), findsNothing);

        // Navigation proceeded to the team-members branch (bottom-nav
        // index 3).
        final bottomNav = tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
        expect(bottomNav.currentIndex, 3);
      },
    );
  });

  // REGRESSION (fix wave): the leave-guard must source the slots it
  // classifies from the bloc's cached `lastLoadedSlots`, NOT from a
  // `state is AssignmentSlotsLoaded ? state.slots : const []` branch. The
  // AssignmentBloc is the app-scoped singleton, so during a leave-guard its
  // live state is frequently NOT AssignmentSlotsLoaded (e.g.
  // AssignmentOperating while a save is in flight — see the getter's own doc
  // and stagedCount's). Passing const [] there makes every still-present
  // staged slot fail classifyStagedConflicts' type-D containment check and
  // get misclassified as a false `slotVanished` conflict.
  group('tab-switch save slots source (regression: bloc-cached slots)', () {
    testWidgets(
      'passes the bloc-cached lastLoadedSlots (not an empty list) to '
      'classifyStagedConflicts when the shared bloc is mid-save '
      '(AssignmentOperating, not AssignmentSlotsLoaded)',
      (tester) async {
        final assignmentBloc = await pumpAdminShellOnAssignmentsTab(
          tester,
          hasStagedChanges: true,
          stagedCount: 1,
          // The regression scenario: the app-scoped bloc is NOT currently
          // AssignmentSlotsLoaded, yet it holds real last-known grid slots.
          initialState: const AssignmentOperating('saving'),
          lastLoadedSlotsToReturn: [realSlot],
          // No real conflicts -> the save proceeds; this test is about WHICH
          // slots the guard classifies with, not the dialog.
          conflictsToReturn: const [],
        );

        await triggerTabSwitchAndChooseSave(tester);

        // With the pre-fix `state is AssignmentSlotsLoaded ? ... : const []`
        // code, an AssignmentOperating live state hands classifyStagedConflicts
        // an EMPTY list here (RED). Reading lastLoadedSlots hands it the real
        // cached slot (GREEN).
        expect(assignmentBloc.capturedClassifySlots, isNotNull);
        expect(
          assignmentBloc.capturedClassifySlots,
          isNotEmpty,
          reason: 'the leave-guard must not pass an empty slot list just '
              'because the live state is not AssignmentSlotsLoaded — that '
              'misclassifies every staged slot as a false slotVanished',
        );
        expect(assignmentBloc.capturedClassifySlots, equals([realSlot]));

        // No conflicts -> no dialog, straight to the save dispatch.
        expect(find.byType(ConflictResolutionDialog), findsNothing);
        expect(
          assignmentBloc.addedEvents.whereType<SaveStagedChanges>(),
          hasLength(1),
        );
      },
    );
  });
}
