// The "משובץ/ת לאירוע!" mark in the overlap warning shown when an admin
// approves a constraint (ConstraintEventWarningDialog): an overlapping event
// the member is assigned to shows it on the left of the event's name row, in
// bold dark green; an event they are not assigned to shows nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/constraint_event_overlap.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/utils/constraint_warning_actions.dart';
import 'package:shavtzak/presentation/widgets/constraint_event_warning_dialog.dart';

const String _label = 'משובץ/ת לאירוע!';

void main() {
  test('the label is exactly the requested text', () {
    expect(ConstraintEventWarningDialog.assignedLabel, _label);
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<Event> events,
    Set<String> assignedEventIds = const {},
  }) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConstraintEventWarningDialog(
          title: 'אזהרה לפני אישור מגבלה',
          message: 'שים לב: במועדים הללו קיימים אירועים:',
          confirmText: 'אשר בכל זאת',
          showMissingTimeNote: true,
          assignedEventIds: assignedEventIds,
          overlaps: [
            for (final event in events)
              EventOverlapInfo(
                event: event,
                eventHasMissingTime: false,
                overlapReason: 'date_time_overlap',
              ),
          ],
        ),
      ),
    ));
  }

  testWidgets('assigned: the mark is on the left of the event row, bold dark '
      'green', (tester) async {
    final event = _event('e1', 'הופעה בבאר שבע');
    await pumpDialog(tester, events: [event], assignedEventIds: {'e1'});

    final mark = find.text(_label);
    expect(mark, findsOneWidget);

    final style = tester.widget<Text>(mark).style!;
    expect(style.fontWeight, FontWeight.bold);
    expect(style.color, Colors.green.shade800);

    // Same row as the event name, and to its left (RTL: the row's end).
    final name = find.text('הופעה בבאר שבע');
    final markRect = tester.getRect(mark);
    final nameRect = tester.getRect(name);
    expect(markRect.top, nameRect.top);
    expect(markRect.right, lessThanOrEqualTo(nameRect.left));
  });

  testWidgets('not assigned: no mark', (tester) async {
    await pumpDialog(tester,
        events: [_event('e1', 'הופעה')], assignedEventIds: {'other'});
    expect(find.text(_label), findsNothing);
  });

  testWidgets('no assignments passed (the default): no mark', (tester) async {
    await pumpDialog(tester, events: [_event('e1', 'הופעה')]);
    expect(find.text(_label), findsNothing);
  });

  testWidgets('several events: only the assigned ones are marked',
      (tester) async {
    await pumpDialog(
      tester,
      events: [
        _event('e1', 'אירוע א'),
        _event('e2', 'אירוע ב'),
        _event('e3', 'אירוע ג'),
      ],
      assignedEventIds: {'e1', 'e3'},
    );
    expect(find.text(_label), findsNWidgets(2));

    final markTops = {
      for (var i = 0; i < 2; i++) tester.getRect(find.text(_label).at(i)).top,
    };
    double nameTop(String name) => tester.getRect(find.text(name)).top;
    expect(markTops, {nameTop('אירוע א'), nameTop('אירוע ג')});
    expect(markTops, isNot(contains(nameTop('אירוע ב'))));
  });

  group('assignedEventIdsOf', () {
    test('every assignment counts, one id per event', () {
      final ids = assignedEventIdsOf([
        _assignment('a1', 'e1', AssignmentStatus.pending),
        _assignment('a2', 'e2', AssignmentStatus.confirmed),
        _assignment('a3', 'e2', AssignmentStatus.pending),
      ]);
      expect(ids, {'e1', 'e2'});
    });

    test('no assignments: no events', () {
      expect(assignedEventIdsOf(const []), isEmpty);
    });
  });
}

Event _event(String id, String name) {
  final day = DateTime(2026, 10, 27);
  final now = DateTime(2026, 1, 1);
  return Event(
    id: id,
    name: name,
    startDate: day,
    endDate: day,
    assemblyTime: '17:00',
    startTime: '19:00',
    endTime: '20:30',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: now,
    updatedAt: now,
  );
}

Assignment _assignment(String id, String eventId, AssignmentStatus status) {
  final now = DateTime(2026, 1, 1);
  return Assignment(
    id: id,
    eventId: eventId,
    teamMemberId: 'm1',
    roleType: 'medic',
    slotIndex: 0,
    status: status,
    notes: '',
    createdAt: now,
    updatedAt: now,
  );
}
