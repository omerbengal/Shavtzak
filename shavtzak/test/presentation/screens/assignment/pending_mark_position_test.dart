import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/member_picker_field.dart';

/// In RTL the "!" sits on the right of the name, and the shield stays on
/// the name's left, next to it, as on every other row.
void main() {
  testWidgets('"!" right of the name, shield left of it', (tester) async {
    final now = DateTime(2026, 10, 1);
    final member = TeamMember(
      id: 'm1',
      name: 'מתן סלפטי',
      isActive: true,
      isPermanent: true,
      constraints: const [],
      roleCapabilities: const {},
      createdAt: now,
      updatedAt: now,
      uniqueKey: 'k',
    );
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: MemberPickerField(
                selected: member,
                members: [member],
                actions: const [],
                enabled: true,
                backgroundColor: Colors.white,
                pendingNotes: const {'m1': 'x'},
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));

    final mark = tester.getCenter(find.byIcon(Icons.priority_high)).dx;
    final shield = tester.getCenter(find.byIcon(Icons.verified_user)).dx;
    expect(mark, greaterThan(shield));
  });
}
