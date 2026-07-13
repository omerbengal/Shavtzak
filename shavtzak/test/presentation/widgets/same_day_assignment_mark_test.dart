import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/widgets/same_day_assignment_mark.dart';

void main() {
  // Deliberately DIFFERENT start dates: otherEvents arrives sorted by start
  // date then name, and only differing dates make that order observable. This
  // is a real shape, not a contrivance — a multi-day anchor event shares one
  // calendar day with events that start on different days, which is exactly why
  // sameDayOtherEventsByMember sorts by start date at all. Sorted order here is
  // [evening, ceremony]; note that is also the REVERSE of Hebrew name order
  // (ט < מ), so a widget that re-sorted by either key would be caught.
  final evening = _event('evening', 'מופע ערב', DateTime(2026, 7, 12));
  final ceremony = _event('ceremony', 'טקס', DateTime(2026, 7, 13));

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

    // The hover message is the first thing the user sees, before any tap.
    expect(
      find.byTooltip('משובץ/ת גם ב: מופע ערב (12/07), טקס (13/07)'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.event_repeat));
    await tester.pumpAndSettle();

    expect(find.text('שיבוץ באירוע נוסף באותו יום'), findsOneWidget);
    expect(find.text('יוסי כהן משובץ/ת גם באירועים:'), findsOneWidget);
    expect(find.text('• מופע ערב — 12/07/2026'), findsOneWidget);
    expect(find.text('• טקס — 13/07/2026'), findsOneWidget);

    // The caller has already sorted; the widget renders that order as given and
    // must never re-sort it.
    expect(
      tester.getTopLeft(find.text('• מופע ערב — 12/07/2026')).dy,
      lessThan(tester.getTopLeft(find.text('• טקס — 13/07/2026')).dy),
      reason: 'otherEvents must render in the given order, never re-sorted',
    );
  });

  testWidgets('the dialog scrolls rather than overflowing on a phone',
      (tester) async {
    // A phone in portrait is the target device, and at 375px wide these long
    // Hebrew names wrap, so each row is several lines tall. A non-scrollable
    // AlertDialog lets its content overflow rather than shrink it: without
    // scrollable: true this same case overflows by ~550px.
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(
      SameDayAssignmentMark(
        otherEvents: _longNamedEvents(6),
        memberName: 'יוסי כהן',
      ),
    ));

    await tester.tap(find.byIcon(Icons.event_repeat));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'an unbounded event list must scroll, not overflow the dialog',
    );
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

List<Event> _longNamedEvents(int count) => List.generate(
      count,
      (i) => _event(
        'e$i',
        'מופע ערב חגיגי לכבוד יום העצמאות במתחם התרבות העירוני מספר $i',
        DateTime(2026, 7, 12),
      ),
    );
