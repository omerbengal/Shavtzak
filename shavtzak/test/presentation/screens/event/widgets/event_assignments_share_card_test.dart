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
      timeLine: 'התייצבות - 17:00 | תחילת מופע - 19:30',
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
    expect(find.text('יום שני 4 במאי'), findsOneWidget);
    expect(find.text('התייצבות - 17:00 | תחילת מופע - 19:30'), findsOneWidget);
    expect(find.text('מיקום: היכל התרבות'), findsOneWidget);
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
}
