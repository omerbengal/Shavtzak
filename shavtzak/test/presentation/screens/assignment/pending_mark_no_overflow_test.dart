import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/member_picker_field.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/pending_constraint_assign_dialog.dart';

void main() {
  final now = DateTime(2026, 10, 1);
  final c = DateConstraint(
    id: 'c1',
    startDate: DateTime(2026, 11, 26),
    endDate: DateTime(2026, 11, 26),
    startTime: '16:00',
    endTime: '20:00',
    note: 'אזכרה - יום השלושים לפטירתו של סבא\nבטווח שעות אלו האזכרה מתקיימת.',
    status: ConstraintStatus.pending,
    constraintType: ConstraintType.unavailability,
  );
  final m = TeamMember(
    id: 'm1',
    name: 'מתן סלפטי',
    isActive: true,
    isPermanent: true,
    constraints: [c],
    roleCapabilities: const {},
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'k',
  );
  for (final w in [320.0, 390.0]) {
    testWidgets('dialog at $w', (tester) async {
      tester.view.physicalSize = Size(w, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showPendingConstraintAssignDialog(
                context: context, member: m, constraints: [c]),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    for (final cell in [60.0, 90.0]) {
      testWidgets('picker field $cell wide at $w', (tester) async {
        tester.view.physicalSize = Size(w, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: cell,
                child: MemberPickerField(
                  selected: m,
                  members: [m],
                  actions: const [],
                  enabled: true,
                  dense: true,
                  backgroundColor: Colors.white,
                  pendingNotes: const {'m1': 'x'},
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
