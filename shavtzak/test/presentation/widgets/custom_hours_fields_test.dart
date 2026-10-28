// CustomHoursFields: the two rows (arrival, departure) the admin fills to give
// a member hours of their own. The widget owns its fields and reports the whole
// interval, or null while the input is not a usable interval.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/custom_hours.dart';
import 'package:shavtzak/core/utils/event_stretch.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/widgets/custom_hours_fields.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  // Two days: 27.11 08:30 (assembly) to 28.11 17:00 (end).
  final event = Event(
    id: 'e1',
    name: 'כנס חורף',
    startDate: DateTime(2026, 11, 27),
    endDate: DateTime(2026, 11, 28),
    startTime: '09:00',
    endTime: '17:00',
    assemblyTime: '08:30',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );

  final initial = WallInterval(
    DateTime.utc(2026, 11, 27, 14, 0),
    DateTime.utc(2026, 11, 27, 23, 0),
  );

  Future<List<WallInterval?>> pump(
    WidgetTester tester, {
    WallInterval? start,
  }) async {
    final emitted = <WallInterval?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: CustomHoursFields(
                event: event,
                initial: start ?? initial,
                onChanged: emitted.add,
              ),
            ),
          ),
        ),
      ),
    );
    return emitted;
  }

  Finder timeField(int index) => find.byType(TextFormField).at(index);

  String timeText(WidgetTester tester, int index) => tester
      .widget<TextFormField>(timeField(index))
      .controller!
      .text;

  testWidgets('pre-fills both rows from initial and hints at the event hours',
      (tester) async {
    final emitted = await pump(tester);

    expect(find.text('מגיע/ה'), findsOneWidget);
    expect(find.text('עוזב/ת'), findsOneWidget);
    // 27.11.2026 is a Friday.
    expect(find.text('ו׳ 27.11'), findsNWidgets(2));
    expect(timeText(tester, 0), '14:00');
    expect(timeText(tester, 1), '23:00');
    expect(
      find.text('שעות האירוע: ${formatCustomHours(eventStretch(event))}'),
      findsOneWidget,
    );
    expect(find.text('שעות האירוע: 27.11 08:30 – 28.11 17:00'), findsOneWidget);
    // Nothing was touched: nothing is reported and no error shows.
    expect(emitted, isEmpty);
    expect(find.text('יש למלא תאריך ושעה'), findsNothing);
    expect(find.text('העזיבה חייבת להיות אחרי ההגעה'), findsNothing);
  });

  testWidgets('a valid change emits the whole interval as wall-clock values',
      (tester) async {
    final emitted = await pump(tester);

    await tester.enterText(timeField(1), '2130');
    await tester.pump();

    expect(emitted.last, isNotNull);
    expect(emitted.last!.start, DateTime.utc(2026, 11, 27, 14, 0));
    expect(emitted.last!.end, DateTime.utc(2026, 11, 27, 21, 30));
    expect(emitted.last!.start.isUtc, isTrue);
    expect(emitted.last!.end.isUtc, isTrue);
    expect(find.text('העזיבה חייבת להיות אחרי ההגעה'), findsNothing);
  });

  testWidgets('an end before the start emits null and says so',
      (tester) async {
    final emitted = await pump(tester);

    await tester.enterText(timeField(1), '1300');
    await tester.pump();

    expect(emitted.last, isNull);
    expect(find.text('העזיבה חייבת להיות אחרי ההגעה'), findsOneWidget);
    expect(find.text('יש למלא תאריך ושעה'), findsNothing);
  });

  testWidgets('an end equal to the start is not after it', (tester) async {
    final emitted = await pump(tester);

    await tester.enterText(timeField(1), '1400');
    await tester.pump();

    expect(emitted.last, isNull);
    expect(find.text('העזיבה חייבת להיות אחרי ההגעה'), findsOneWidget);
  });

  testWidgets('a missing time emits null and asks to fill date and time',
      (tester) async {
    final emitted = await pump(tester);

    await tester.enterText(timeField(0), '');
    await tester.pump();

    expect(emitted.last, isNull);
    expect(find.text('יש למלא תאריך ושעה'), findsOneWidget);
    expect(find.text('העזיבה חייבת להיות אחרי ההגעה'), findsNothing);
  });

  testWidgets('a half-typed time counts as missing', (tester) async {
    final emitted = await pump(tester);

    await tester.enterText(timeField(1), '21:');
    await tester.pump();

    expect(emitted.last, isNull);
    expect(find.text('יש למלא תאריך ושעה'), findsOneWidget);
  });

  testWidgets('a later departure day makes an overnight stay valid',
      (tester) async {
    final emitted = await pump(
      tester,
      start: WallInterval(
        DateTime.utc(2026, 11, 27, 20, 0),
        DateTime.utc(2026, 11, 28, 2, 0),
      ),
    );

    expect(find.text('ו׳ 27.11'), findsOneWidget);
    expect(find.text('ש׳ 28.11'), findsOneWidget);
    expect(timeText(tester, 0), '20:00');
    expect(timeText(tester, 1), '02:00');
    expect(emitted, isEmpty);
  });

  testWidgets(
      'the date field opens the calendar with the event ends marked, and '
      'a picked day moves that row to the same y/m/d on the wall clock',
      (tester) async {
    final emitted = await pump(tester);

    // The departure date is the second 'ו׳ 27.11' field.
    await tester.tap(find.text('ו׳ 27.11').last);
    await tester.pumpAndSettle();

    expect(find.text('מסגרת = תחילת האירוע וסופו'), findsOneWidget);
    expect(find.text('מסגרת אדומה = יש אירוע בתאריך זה'), findsNothing);

    await tester.tap(find.text('28'));
    await tester.pump();
    await tester.tap(find.text('אישור'));
    await tester.pumpAndSettle();

    expect(find.text('ש׳ 28.11'), findsOneWidget);
    expect(emitted.last, isNotNull);
    expect(emitted.last!.start, DateTime.utc(2026, 11, 27, 14, 0));
    expect(emitted.last!.end, DateTime.utc(2026, 11, 28, 23, 0));
    expect(emitted.last!.end.isUtc, isTrue);
  });

  testWidgets('moving the arrival day past the departure reports the order',
      (tester) async {
    final emitted = await pump(tester);

    await tester.tap(find.text('ו׳ 27.11').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('29'));
    await tester.pump();
    await tester.tap(find.text('אישור'));
    await tester.pumpAndSettle();

    expect(emitted.last, isNull);
    expect(find.text('העזיבה חייבת להיות אחרי ההגעה'), findsOneWidget);
  });
}
