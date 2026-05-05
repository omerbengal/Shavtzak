import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_card.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_models.dart';

void main() {
  testWidgets('renders event details, names, note refs, and full notes',
      (tester) async {
    final data = EventAssignmentsShareData(
      eventName: 'טקס פתיחה',
      dateLine: 'יום שני 4 במאי',
      timeLine: 'התייצבות - 17:00 | תחילת מופע - 19:30',
      locationLine: 'מיקום: היכל התרבות',
      eventNoteLine: 'נא להביא חולצות ייצוגיות.',
      sections: const [
        EventAssignmentsShareSection(
          title: 'מפקד אירוע',
          rows: [
            EventAssignmentsShareRow(memberName: 'נועה כהן', noteNumber: 1),
            EventAssignmentsShareRow(memberName: 'דניאל לוי'),
          ],
        ),
      ],
      notes: const [
        EventAssignmentsShareNote(
          number: 1,
          memberName: 'נועה כהן',
          text: 'מגיעה ישירות מהכניסה הראשית בלי קיצור של הטקסט.',
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
    expect(find.text('יום שני 4 במאי'), findsOneWidget);
    expect(find.text('התייצבות - 17:00 | תחילת מופע - 19:30'), findsOneWidget);
    expect(find.text('מיקום: היכל התרבות'), findsOneWidget);
    expect(find.text('נא להביא חולצות ייצוגיות.'), findsOneWidget);
    expect(find.text('מפקד אירוע'), findsOneWidget);
    expect(find.text('נועה כהן'), findsOneWidget);
    expect(find.text('(1)'), findsOneWidget);
    expect(
      find.textContaining(
        'נועה כהן: מגיעה ישירות מהכניסה הראשית',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('טלפון'), findsNothing);
    expect(find.textContaining('ממתין'), findsNothing);
    expect(find.textContaining('נדחה'), findsNothing);

    final eventNoteText =
        tester.widget<Text>(find.text('נא להביא חולצות ייצוגיות.'));
    expect(eventNoteText.style?.color, Colors.amber.shade900);

    final notesTitle = tester.widget<Text>(find.text('הערות'));
    expect(notesTitle.style?.color, Colors.purple.shade800);

    expect(find.byType(Divider), findsOneWidget);
  });
}
