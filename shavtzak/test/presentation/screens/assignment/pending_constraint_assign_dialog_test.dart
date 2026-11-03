import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/pending_constraint_assign_dialog.dart';

void main() {
  final now = DateTime(2026, 10, 1);
  final constraint = DateConstraint(
    id: 'c1',
    startDate: DateTime(2026, 11, 3),
    endDate: DateTime(2026, 11, 3),
    note: 'חתונה',
    status: ConstraintStatus.pending,
    constraintType: ConstraintType.unavailability,
  );
  final member = TeamMember(
    id: 'm1',
    name: 'דנה',
    isActive: true,
    isPermanent: true,
    constraints: [constraint],
    roleCapabilities: const {},
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'k1',
  );

  Future<PendingConstraintAssignChoice?> tapButton(
      WidgetTester tester, String label) async {
    PendingConstraintAssignChoice? result;
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showPendingConstraintAssignDialog(
              context: context,
              member: member,
              constraints: [constraint],
            );
            closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('לדנה יש מגבלה'), findsOneWidget);
    expect(find.textContaining('חתונה'), findsOneWidget);

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    return result;
  }

  testWidgets('ביטול returns null', (tester) async {
    expect(await tapButton(tester, 'ביטול'), isNull);
  });

  testWidgets('שבץ בלי לאשר returns assign', (tester) async {
    expect(await tapButton(tester, 'שבץ בלי לאשר'),
        PendingConstraintAssignChoice.assign);
  });

  testWidgets('שבץ ואשר מגבלה returns assignAndApprove', (tester) async {
    expect(await tapButton(tester, 'שבץ ואשר מגבלה'),
        PendingConstraintAssignChoice.assignAndApprove);
  });
}
