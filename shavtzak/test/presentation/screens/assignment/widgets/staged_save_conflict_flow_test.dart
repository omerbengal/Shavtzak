// Unit-level contract test for resolveStagedConflictsForSave — the shared
// helper both Save paths (the on-screen Save button in
// assignment_list_screen.dart and the tab-switch leave-guard in
// swipeable_page_view.dart) route their conflict resolution through. Pins its
// 3-way return contract directly at the helper boundary so a future refactor
// of either call site can't silently break it:
//   - no conflicts        -> const {} (empty map, NON-null), no dialog
//   - conflicts + confirm -> the chosen Map<slotKey, ConflictResolution>
//   - conflicts + cancel  -> null (caller must NOT save)
//
// The helper only ever calls bloc.classifyStagedConflicts(slots) and
// showDialog — it never reads bloc.state — so the bloc is a MockBloc with just
// classifyStagedConflicts overridden, and the helper is invoked directly from
// a Builder button (no BlocProvider needed).

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';
import 'package:shavtzak/presentation/bloc/assignment/models/assignment_conflict.dart';
import 'package:shavtzak/presentation/screens/assignment/models/assignment_slot.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/conflict_resolution_dialog.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/staged_save_conflict_flow.dart';

class _MockAssignmentBloc extends MockBloc<AssignmentEvent, AssignmentState>
    implements AssignmentBloc {
  _MockAssignmentBloc(this._conflicts);

  final List<AssignmentConflict> _conflicts;

  @override
  List<AssignmentConflict> classifyStagedConflicts(
          List<AssignmentSlot> currentSlots) =>
      _conflicts;
}

void main() {
  const conflict = AssignmentConflict(
    slotKey: 'e1_medic_0',
    type: AssignmentConflictType.slotTaken,
    description: 'המשרה נתפסה: בינתיים שובץ שם אדם אחר ב-DB.',
  );

  /// Pumps a single button that invokes the helper and records its result via
  /// [onResult]. `resultSet` distinguishes "returned null" from "not yet
  /// returned" (both would leave a nullable `result` == null).
  Future<void> pumpAndInvoke(
    WidgetTester tester,
    List<AssignmentConflict> conflicts, {
    required void Function(Map<String, ConflictResolution>? result) onResult,
  }) async {
    final bloc = _MockAssignmentBloc(conflicts);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final result = await resolveStagedConflictsForSave(
                  context,
                  bloc,
                  const <AssignmentSlot>[],
                );
                onResult(result);
              },
              child: const Text('invoke'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('invoke'));
    await tester.pumpAndSettle();
  }

  testWidgets('no conflicts -> returns an empty (non-null) map, no dialog',
      (tester) async {
    Map<String, ConflictResolution>? result;
    var resultSet = false;
    await pumpAndInvoke(tester, const [], onResult: (r) {
      result = r;
      resultSet = true;
    });

    expect(resultSet, isTrue);
    expect(result, isNotNull);
    expect(result, isEmpty);
    expect(find.byType(ConflictResolutionDialog), findsNothing);
  });

  testWidgets(
      'conflicts + confirm ("שמור") -> returns the chosen resolutions map',
      (tester) async {
    Map<String, ConflictResolution>? result;
    var resultSet = false;
    await pumpAndInvoke(tester, const [conflict], onResult: (r) {
      result = r;
      resultSet = true;
    });

    expect(find.byType(ConflictResolutionDialog), findsOneWidget);
    await tester.tap(find.text('שמור'));
    await tester.pumpAndSettle();

    expect(resultSet, isTrue);
    // Default resolution for a non-discardOnly conflict is overrideDb.
    expect(result, {'e1_medic_0': ConflictResolution.overrideDb});
  });

  testWidgets('conflicts + cancel ("ביטול") -> returns null (do not save)',
      (tester) async {
    Map<String, ConflictResolution>? result;
    var resultSet = false;
    await pumpAndInvoke(tester, const [conflict], onResult: (r) {
      result = r;
      resultSet = true;
    });

    expect(find.byType(ConflictResolutionDialog), findsOneWidget);
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(resultSet, isTrue);
    expect(result, isNull);
  });
}
