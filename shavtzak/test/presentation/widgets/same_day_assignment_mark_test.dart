import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/widgets/same_day_assignment_mark.dart';

void main() {
  final evening = _event('evening', 'מופע ערב', DateTime(2026, 7, 12));
  final ceremony = _event('ceremony', 'טקס', DateTime(2026, 7, 12));

  Widget wrap(Widget child) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('renders nothing when the member is not double-booked',
      (tester) async {
    await tester.pumpWidget(wrap(
      const SameDayAssignmentMark(otherEvents: [], memberName: 'יוסי כהן'),
    ));

    expect(find.byIcon(Icons.event_repeat), findsNothing);
  });

  testWidgets('renders the mark when the member is double-booked',
      (tester) async {
    await tester.pumpWidget(wrap(
      SameDayAssignmentMark(otherEvents: [evening], memberName: 'יוסי כהן'),
    ));

    expect(find.byIcon(Icons.event_repeat), findsOneWidget);
  });

  testWidgets('tapping the mark lists every other event', (tester) async {
    await tester.pumpWidget(wrap(
      SameDayAssignmentMark(
        otherEvents: [evening, ceremony],
        memberName: 'יוסי כהן',
      ),
    ));

    await tester.tap(find.byIcon(Icons.event_repeat));
    await tester.pumpAndSettle();

    expect(find.text('שיבוץ באירוע נוסף באותו יום'), findsOneWidget);
    expect(find.text('יוסי כהן משובץ/ת גם באירועים:'), findsOneWidget);
    expect(find.text('• מופע ערב — 12/07/2026'), findsOneWidget);
    expect(find.text('• טקס — 12/07/2026'), findsOneWidget);
  });
}

Event _event(String id, String name, DateTime start) {
  final now = DateTime(2026, 7, 1);
  return Event(
    id: id,
    name: name,
    startDate: start,
    endDate: start,
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}
