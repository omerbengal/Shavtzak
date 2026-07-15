import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/participant_group.dart';
import 'package:shavtzak/presentation/screens/event/widgets/participant_group_rows.dart';

void main() {
  group('participant group rows', () {
    testWidgets('a new event starts with one empty row and an add button',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.byType(ParticipantGroupRows), findsOneWidget);
      expect(find.text('כמות'), findsOneWidget);
      expect(find.text('הוסף סבב'), findsOneWidget);
    });

    testWidgets('the add button appends a row', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('הוסף סבב'));
      await tester.pumpAndSettle();

      expect(find.text('כמות'), findsNWidgets(2));
    });

    testWidgets('the remove button drops a row', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('הוסף סבב'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('הסר סבב').first);
      await tester.pumpAndSettle();

      expect(find.text('כמות'), findsOneWidget);
    });

    testWidgets('an existing event hydrates one row per group', (tester) async {
      final rowsKey = GlobalKey<ParticipantGroupRowsState>();
      await tester.pumpWidget(_host(
        rowsKey: rowsKey,
        initialGroups: const [
          ParticipantGroup(label: 'בוקר', count: 500),
          ParticipantGroup(count: 700),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('כמות'), findsNWidgets(2));
      expect(find.text('בוקר'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(rowsKey.currentState!.toGroups(), const [
        ParticipantGroup(label: 'בוקר', count: 500),
        ParticipantGroup(count: 700),
      ]);
    });

    testWidgets('the add button disappears at the 10-row cap', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      for (var i = 0; i < 9; i++) {
        await tester.tap(find.text('הוסף סבב'));
        await tester.pumpAndSettle();
      }

      expect(find.text('כמות'), findsNWidgets(10));
      expect(find.text('הוסף סבב'), findsNothing);
    });

    testWidgets('a label with no count blocks submission', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(_host(formKey: key));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'בוקר');
      await tester.pumpAndSettle();

      expect(key.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('יש להזין כמות'), findsOneWidget);
    });

    testWidgets('a count with no label passes validation', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(_host(formKey: key));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), '500');
      await tester.pumpAndSettle();

      expect(key.currentState!.validate(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('יש להזין כמות'), findsNothing);
    });

    testWidgets('rows collect into groups, dropping the empty ones',
        (tester) async {
      final rowsKey = GlobalKey<ParticipantGroupRowsState>();
      await tester.pumpWidget(_host(rowsKey: rowsKey));
      await tester.pumpAndSettle();

      await tester.tap(find.text('הוסף סבב'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('הוסף סבב'));
      await tester.pumpAndSettle();

      final labels = find.byType(TextFormField);
      // Row 0: label "בוקר", count 500. Row 1: count only. Row 2: left empty.
      await tester.enterText(labels.at(0), 'בוקר');
      await tester.enterText(labels.at(1), '500');
      await tester.enterText(labels.at(3), '700');
      await tester.pumpAndSettle();

      expect(rowsKey.currentState!.toGroups(), const [
        ParticipantGroup(label: 'בוקר', count: 500),
        ParticipantGroup(count: 700),
      ]);
    });
  });
}

Widget _host({
  GlobalKey<FormState>? formKey,
  GlobalKey<ParticipantGroupRowsState>? rowsKey,
  List<ParticipantGroup> initialGroups = const [],
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Form(
          key: formKey ?? GlobalKey<FormState>(),
          child: SingleChildScrollView(
            child: ParticipantGroupRows(
              key: rowsKey,
              initialGroups: initialGroups,
              onChanged: () {},
            ),
          ),
        ),
      ),
    ),
  );
}
