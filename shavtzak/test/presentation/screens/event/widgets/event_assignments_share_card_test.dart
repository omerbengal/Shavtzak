import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_card.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_models.dart';

void main() {
  testWidgets(
      'renders event details, names, and each member note under the name',
      (tester) async {
    final data = EventAssignmentsShareData(
      eventName: 'טקס פתיחה',
      dateLine: 'יום שני 4 במאי',
      assemblyLine: 'התייצבות - 17:00',
      timeLine: 'התכנסות קהל - 18:00 | סיום מופע משוער - 22:00',
      participantsLine: 'כמות משתתפים: 500',
      locationLine: 'מיקום: היכל התרבות',
      eventNoteLine: 'נא להביא חולצות ייצוגיות.',
      sections: const [
        EventAssignmentsShareSection(
          title: 'מפקד אירוע',
          rows: [
            EventAssignmentsShareRow(
              memberName: 'נועה כהן',
              noteText: 'מגיעה ישירות מהכניסה הראשית בלי קיצור של הטקסט.',
            ),
            EventAssignmentsShareRow(memberName: 'דניאל לוי'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EventAssignmentsShareCard(data: data),
          ),
        ),
      ),
    );

    expect(find.text('טקס פתיחה'), findsOneWidget);
    // Three lines, in this order, top to bottom.
    final line1 = find
        .text('יום שני 4 במאי | התייצבות - 17:00 | מיקום: היכל התרבות');
    final line2 = find.text('התכנסות קהל - 18:00 | סיום מופע משוער - 22:00');
    final line3 = find.text('כמות משתתפים: 500');
    expect(line1, findsOneWidget);
    expect(line2, findsOneWidget);
    expect(line3, findsOneWidget);
    expect(tester.getTopLeft(line1).dy, lessThan(tester.getTopLeft(line2).dy));
    expect(tester.getTopLeft(line2).dy, lessThan(tester.getTopLeft(line3).dy));
    expect(find.text('נא להביא חולצות ייצוגיות.'), findsOneWidget);
    expect(find.text('מפקד אירוע'), findsOneWidget);
    expect(find.text('נועה כהן'), findsOneWidget);
    final noteFinder =
        find.text('מגיעה ישירות מהכניסה הראשית בלי קיצור של הטקסט.');
    expect(noteFinder, findsOneWidget);
    // The note sits right under its member's name, with no numbered list.
    expect(
      tester.getTopLeft(noteFinder).dy,
      greaterThan(tester.getBottomLeft(find.text('נועה כהן')).dy),
    );
    expect(
      tester.getTopLeft(noteFinder).dy,
      lessThan(tester.getTopLeft(find.text('דניאל לוי')).dy),
    );
    expect(find.text('(1)'), findsNothing);
    expect(find.text('הערות'), findsNothing);
    expect(find.textContaining('טלפון'), findsNothing);
    expect(find.textContaining('ממתין'), findsNothing);
    expect(find.textContaining('נדחה'), findsNothing);

    final eventNoteText =
        tester.widget<Text>(find.text('נא להביא חולצות ייצוגיות.'));
    expect(eventNoteText.style?.color, Colors.amber.shade900);

    final noteText = tester.widget<Text>(noteFinder);
    expect(noteText.style?.color, Colors.purple.shade900);

    expect(find.byType(Divider), findsOneWidget);

    final roleTitle = tester.widget<Text>(find.text('מפקד אירוע'));
    expect(roleTitle.style?.fontWeight, FontWeight.w800);

    final memberName = tester.widget<Text>(find.text('נועה כהן'));
    expect(memberName.style?.fontWeight, FontWeight.w400);

    expect(find.text('•'), findsNWidgets(2));
  });

  testWidgets('shows the items line and the missing roles line',
      (tester) async {
    const data = EventAssignmentsShareData(
      eventName: 'טקס פתיחה',
      dateLine: 'יום שני 4 במאי',
      timeLine: '',
      locationLine: '',
      itemsLine: 'באירוע זה יש: סריקה 🤳🏻, להקה',
      missingRolesLine: 'תפקידים חסרים: 1 נהג | 3 צלם',
      sections: [],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EventAssignmentsShareCard(data: data),
          ),
        ),
      ),
    );

    expect(find.text('באירוע זה יש: סריקה 🤳🏻, להקה'), findsOneWidget);
    expect(find.text('תפקידים חסרים: 1 נהג | 3 צלם'), findsOneWidget);
  });

  group('two columns', () {
    EventAssignmentsShareSection section(String title, int rows) =>
        EventAssignmentsShareSection(
          title: title,
          rows: [
            for (var i = 0; i < rows; i++)
              EventAssignmentsShareRow(memberName: '$title $i'),
          ],
        );

    List<int> sizes(List<List<EventAssignmentsShareSection>> parts) =>
        [for (final part in parts) part.length];

    test('two columns: cut in order where they are most even', () {
      final sections = [
        section('א', 3),
        section('ב', 8),
        section('ג', 6),
        section('ד', 5),
        section('ה', 3),
      ];
      // Heights 5,10,8,7,5: 15 | 20 is the most even in-order cut.
      expect(sizes(EventAssignmentsShareCard.splitColumns(sections, 2)),
          [2, 3]);
    });

    test('three columns keep the order and the tallest as short as can be',
        () {
      final sections = [
        section('א', 3),
        section('ב', 8),
        section('ג', 6),
        section('ד', 5),
        section('ה', 3),
      ];
      // 5,10,8,7,5 → 15 | 8 | 12 (tallest 15; nothing shorter is possible
      // since ב alone with a neighbour already makes 15+).
      final parts = EventAssignmentsShareCard.splitColumns(sections, 3);
      expect(parts.expand((p) => p).toList(), sections);
      expect(parts.length, 3);
      expect(sizes(parts), [2, 1, 2]);
    });

    test('never more columns than cards', () {
      expect(
        EventAssignmentsShareCard.splitColumns(
                [section('א', 2), section('ב', 2)], 4)
            .length,
        2,
      );
    });

    testWidgets('the export stays one column', (tester) async {
      final data = EventAssignmentsShareData(
        eventName: 'אירוע',
        dateLine: 'יום',
        timeLine: '',
        participantsLine: '',
        locationLine: '',
        eventNoteLine: '',
        sections: [section('א', 1), section('ב', 1)],
      );
      await tester.pumpWidget(MaterialApp(
        home: SingleChildScrollView(
          child: FittedBox(child: EventAssignmentsShareCard(data: data)),
        ),
      ));
      // Both role titles share a left edge: stacked, not side by side.
      expect(tester.getTopRight(find.text('א')).dx,
          tester.getTopRight(find.text('ב')).dx);
      expect(find.byIcon(Icons.phone), findsNothing);
    });
  });

  testWidgets('a long detail line stays on one line, shrunk to fit',
      (tester) async {
    const long = 'התכנסות קהל - 16:30 | תחילת מופע - 18:00 | '
        'סיום מופע משוער - 22:30 | סיום צוות משוער - 23:30';
    final data = EventAssignmentsShareData(
      eventName: 'אירוע',
      dateLine: 'יום',
      timeLine: long,
      locationLine: '',
      sections: const [],
    );
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        child: Center(
          child: EventAssignmentsShareCard(data: data, width: 400, columns: 3),
        ),
      ),
    ));
    final text = tester.widget<Text>(find.text(long));
    expect(text.maxLines, 1);
    final box = tester.getRect(find.text(long));
    expect(box.width, lessThanOrEqualTo(400));
    expect(tester.takeException(), isNull);
  });
}
