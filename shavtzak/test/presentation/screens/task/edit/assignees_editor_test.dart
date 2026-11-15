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
    final field = tester.widget<TextField>(search);
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);
    // The whole list is back, ready for the next name.
    expect(find.text('דנה'), findsOneWidget);
  });
}
