import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/task/widgets/assignee_chips.dart';

import '../../../../support/task_fixtures.dart';

void main() {
  final oren =
      buildMember(id: 'oren', name: 'אורן לוי', phoneNumber: '0521234567');
  final adar = buildMember(id: 'adar', name: 'אדר עוז');

  Future<List<String>> pumpChips(WidgetTester tester) async {
    final called = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: AssigneeChips(
            task: buildTask(
              assigneeIds: const ['oren', 'adar'],
              assignees: [oren, adar],
            ),
            viewerId: 'someone-else',
            removedAssigneeIds: const [],
            onCallPhone: called.add,
            keyPrefix: 'task-row',
          ),
        ),
      ),
    ));
    return called;
  }

  Finder chip(String id) => find.byKey(Key('task-row-assignee-t1-$id'));

  testWidgets('a phone shows inside the chip, and tapping the chip calls',
      (tester) async {
    final called = await pumpChips(tester);

    expect(
      find.descendant(of: chip('oren'), matching: find.byIcon(Icons.phone)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chip('adar'), matching: find.byIcon(Icons.phone)),
      findsNothing,
    );
    expect(find.text('052-1234567'), findsNothing);

    await tester.tap(find.text('אורן לוי'));
    await tester.tap(find.text('אדר עוז'));
    expect(called, ['0521234567']);
  });

  testWidgets('a chip without a phone lines up with one that has a phone',
      (tester) async {
    await pumpChips(tester);

    double centreOf(String id) => tester.getCenter(chip(id)).dy;
    expect(find.byKey(const Key('task-row-call-t1-oren')), findsOneWidget);
    expect(find.byKey(const Key('task-row-call-t1-adar')), findsNothing);
    expect(centreOf('adar'), closeTo(centreOf('oren'), 0.5));
  });
}
