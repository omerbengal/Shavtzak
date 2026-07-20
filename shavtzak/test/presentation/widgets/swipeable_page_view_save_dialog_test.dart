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
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_event.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';
import 'package:shavtzak/presentation/widgets/swipeable_page_view.dart';

class _MockAssignmentBloc extends MockBloc<AssignmentEvent, AssignmentState>
    implements AssignmentBloc {
  _MockAssignmentBloc({
    required this.hasStagedChanges,
    required this.stagedCount,
  });

  @override
  final bool hasStagedChanges;

  @override
  final int stagedCount;

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

  /// Builds a minimal admin shell (matching app_router.dart's branch order:
  /// home / team-members / events / assignments / checklist) starting on
  /// the assignments tab, with SwipeablePageView as the real shell builder.
  Future<_MockAssignmentBloc> pumpAdminShellOnAssignmentsTab(
    WidgetTester tester, {
    required bool hasStagedChanges,
    int stagedCount = 1,
  }) async {
    final assignmentBloc = _MockAssignmentBloc(
      hasStagedChanges: hasStagedChanges,
      stagedCount: stagedCount,
    );
    whenListen(
      assignmentBloc,
      Stream<AssignmentState>.empty(),
      initialState: const AssignmentInitial(),
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
}
