import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/task/edit/value_editors.dart';

import '../../../../support/task_fixtures.dart';

void main() {
  final dana = buildMember(id: 'm1', name: 'דנה');
  final yossi = buildMember(id: 'm2', name: 'יוסי');

  Future<void> pump(WidgetTester tester, List<List<String>> reports) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: AssigneesEditor(
            initial: const [],
            offered: [dana, yossi],
            current: const [],
            onChanged: reports.add,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('ticking a searched name empties the search and keeps it focused', (tester) async {
    final reports = <List<String>>[];
    await pump(tester, reports);
    final search = find.byKey(const Key('edit-assignee-search'));
    await tester.enterText(search, 'יוס');
    await tester.pump();
    expect(find.text('דנה'), findsNothing);
    await tester.tap(find.byKey(const Key('edit-assignee-m2')));
    await tester.pump();
    await tester.pump();
    expect(reports.last, ['m2']);
    final field = tester.widget<TextField>(
        find.descendant(of: search, matching: find.byType(TextField)));
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);
    // The whole list is back, ready for the next name.
    expect(find.text('דנה'), findsOneWidget);
  });

  testWidgets('pickedFirst: the picked on top, a divider, the rest; each by name', (tester) async {
    final avi = buildMember(id: 'm3', name: 'אבי');
    final tal = buildMember(id: 'm4', name: 'טל').copyWith(isPermanent: true);
    final reports = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: AssigneesEditor(
            initial: const ['m2', 'm4'],
            offered: [dana, yossi, avi, tal],
            current: const [],
            onChanged: reports.add,
            pickedFirst: true,
            showPermanentMark: true,
          ),
        ),
      ),
    ));
    await tester.pump();
    double top(String id) => tester.getTopLeft(find.byKey(Key('edit-assignee-$id'))).dy;
    final divider = tester.getTopLeft(find.byKey(const Key('edit-assignee-divider'))).dy;
    // Picked: טל, יוסי. Then: אבי, דנה.
    expect(top('m4'), lessThan(top('m2')));
    expect(top('m2'), lessThan(divider));
    expect(divider, lessThan(top('m3')));
    expect(top('m3'), lessThan(top('m1')));
    // Only the permanent member carries the mark.
    expect(
      find.descendant(
          of: find.byKey(const Key('edit-assignee-m4')), matching: find.byIcon(Icons.verified_user)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.verified_user), findsOneWidget);
    // Ticking moves the member up to the picked part.
    await tester.tap(find.byKey(const Key('edit-assignee-m1')));
    await tester.pump();
    expect(top('m1'), lessThan(tester.getTopLeft(find.byKey(const Key('edit-assignee-divider'))).dy));
  });
}
