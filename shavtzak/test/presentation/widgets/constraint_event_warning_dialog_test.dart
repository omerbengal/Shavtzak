// The "שעה:" row of the warning shown when a constraint is saved or approved
// (ConstraintEventWarningDialog). It shows the stretch the conflict check
// judges with — assembly (else show start) to team end (else show end) — and
// says the time is not defined exactly when the stretch had to fall back to a
// day edge (eventStretchFellBack, the same test as 'missing_event_time').
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/constraint_event_overlap.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/widgets/constraint_event_warning_dialog.dart';

const String _notDefined = 'שעת האירוע לא מוגדרת';

void main() {
  final day = DateTime(2026, 10, 27);

  /// Pumps the dialog with one overlap for [event] and returns the text of
  /// its "שעה:" row, without the prefix.
  Future<String> timeRowFor(WidgetTester tester, Event event) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConstraintEventWarningDialog(
          title: 'אזהרה',
          message: 'האילוץ מתנגש עם:',
          confirmText: 'שמור',
          overlaps: [
            EventOverlapInfo(
              event: event,
              eventHasMissingTime: false,
              overlapReason: 'date_time_overlap',
            ),
          ],
        ),
      ),
    ));

    final rows = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((data) => data.startsWith('שעה: '))
        .toList();
    expect(rows, hasLength(1));
    return rows.single.substring('שעה: '.length);
  }

  testWidgets('starts at assembly when it is before the show (E5)',
      (tester) async {
    final row = await timeRowFor(
      tester,
      _event(day, day,
          assemblyTime: '17:00', startTime: '19:00', endTime: '20:30'),
    );
    expect(row, '17:00 - 20:30');
  });

  testWidgets('ends at team end when there is one (E2)', (tester) async {
    final row = await timeRowFor(
      tester,
      _event(day, day,
          assemblyTime: '17:00',
          startTime: '19:00',
          endTime: '20:30',
          teamEndTime: '22:00'),
    );
    expect(row, '17:00 - 22:00');
  });

  testWidgets(
      'team end with an empty show end shows the time, not "not defined" '
      '(E4)', (tester) async {
    final row = await timeRowFor(
      tester,
      _event(day, day, startTime: '19:00', teamEndTime: '22:00'),
    );
    expect(row, '19:00 - 22:00');
    expect(row, isNot(_notDefined));
  });

  testWidgets('a one-day event past midnight shows its own end time',
      (tester) async {
    final row = await timeRowFor(
      tester,
      _event(day, day, assemblyTime: '20:00', teamEndTime: '01:00'),
    );
    expect(row, '20:00 - 01:00');
  });

  testWidgets('a multi-day event says which day each end is on',
      (tester) async {
    final row = await timeRowFor(
      tester,
      _event(day, DateTime(2026, 10, 28),
          assemblyTime: '18:00', teamEndTime: '23:00'),
    );
    expect(row, '27.10 18:00 – 28.10 23:00');
  });

  testWidgets('no assembly and no show start: not defined', (tester) async {
    final row = await timeRowFor(
      tester,
      _event(day, day, endTime: '20:30', teamEndTime: '22:00'),
    );
    expect(row, _notDefined);
  });

  testWidgets('no team end and no show end: not defined', (tester) async {
    final row = await timeRowFor(
      tester,
      _event(day, day, assemblyTime: '17:00', startTime: '19:00'),
    );
    expect(row, _notDefined);
  });

  testWidgets('a time the stretch cannot read counts as missing',
      (tester) async {
    final row = await timeRowFor(
      tester,
      _event(day, day, startTime: '19:00', endTime: '24:00'),
    );
    expect(row, _notDefined);
  });
}

Event _event(
  DateTime startDate,
  DateTime endDate, {
  String assemblyTime = '',
  String startTime = '',
  String endTime = '',
  String teamEndTime = '',
}) {
  final now = DateTime(2026, 1, 1);
  return Event(
    id: 'e1',
    name: 'הופעה',
    startDate: startDate,
    endDate: endDate,
    assemblyTime: assemblyTime,
    startTime: startTime,
    endTime: endTime,
    teamEndTime: teamEndTime,
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}
