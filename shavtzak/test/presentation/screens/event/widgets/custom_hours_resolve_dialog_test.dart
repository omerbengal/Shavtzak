// CustomHoursResolveDialog: opens when an event save moves the event in time
// and some members have custom hours. The admin decides each member's hours
// (move with the event, keep, edit, remove) before anything is saved.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/custom_hours.dart';
import 'package:shavtzak/core/utils/event_stretch.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/custom_hours_resolution.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/event/widgets/custom_hours_resolve_dialog.dart';
import 'package:shavtzak/presentation/widgets/custom_hours_fields.dart';

const String _save = 'שמור אירוע';
const String _move = 'להזיז עם האירוע';
const String _keep = 'להשאיר כמו שזה';
const String _keepNoOverlap = 'להשאיר כמו שזה ⚠️ לא חופף לאירוע החדש';
const String _edit = 'לערוך…';
const String _remove = 'להסיר שעות מותאמות';

final DateTime _stamp = DateTime(2026, 10, 1);

Event _event({
  required DateTime startDate,
  required DateTime endDate,
  String assemblyTime = '12:00',
  String teamEndTime = '23:30',
}) =>
    Event(
      id: 'e1',
      name: 'כנס חורף',
      startDate: startDate,
      endDate: endDate,
      startTime: '19:00',
      endTime: '23:00',
      teamEndTime: teamEndTime,
      assemblyTime: assemblyTime,
      requiresArmed: false,
      roleRequirements: const {'medic': 2, 'driver': 1},
      createdAt: _stamp,
      updatedAt: _stamp,
    );

// 27-28.10, stretch 27.10 12:00 to 28.10 23:30.
final Event _oldEvent =
    _event(startDate: DateTime(2026, 10, 27), endDate: DateTime(2026, 10, 28));

// The same event seven days later, stretch 3.11 12:00 to 4.11 23:30.
final Event _movedEvent =
    _event(startDate: DateTime(2026, 11, 3), endDate: DateTime(2026, 11, 4));

// The same days, other times: stretch 27.10 11:00 to 28.10 23:45.
final Event _retimedEvent = _event(
  startDate: DateTime(2026, 10, 27),
  endDate: DateTime(2026, 10, 28),
  assemblyTime: '11:00',
  teamEndTime: '23:45',
);

TeamMember _member(
  String id,
  String name, {
  bool exempt = false,
  List<DateConstraint> constraints = const [],
}) =>
    TeamMember(
      id: id,
      name: name,
      isActive: true,
      isPermanent: true,
      constraints: constraints,
      roleCapabilities: const {},
      createdAt: _stamp,
      updatedAt: _stamp,
      uniqueKey: 'k-$id',
      allowMultipleAssignments: exempt,
    );

Assignment _assignment(
  String id,
  TeamMember? member, {
  String roleType = 'medic',
  int slotIndex = 0,
  String start = '2026-10-27T14:00',
  String end = '2026-10-27T23:00',
  String? memberId,
}) =>
    Assignment(
      id: id,
      eventId: 'e1',
      teamMemberId: member?.id ?? memberId ?? 'm-unknown',
      roleType: roleType,
      slotIndex: slotIndex,
      status: AssignmentStatus.confirmed,
      notes: '',
      customStartAt: start,
      customEndAt: end,
      createdAt: _stamp,
      updatedAt: _stamp,
      teamMember: member,
    );

DateConstraint _unavailable(DateTime day, {ConstraintStatus? status}) =>
    DateConstraint(
      id: 'c-${day.day}-${day.month}',
      startDate: day,
      constraintType: ConstraintType.unavailability,
      status: status ?? ConstraintStatus.approved,
    );

CustomHoursResolution _resolution(String id, String? start, String? end) =>
    CustomHoursResolution(
      assignmentId: id,
      customStartAt: start,
      customEndAt: end,
    );

class _Opened {
  _Opened(this.result);

  /// Completes with what the dialog returns once it closes.
  final Future<List<CustomHoursResolution>?> result;
}

const Map<String, String> _roleNames = {
  'medic': 'חובש/ת',
  'driver': 'נהג/ת',
};

void main() {
  Future<_Opened> open(
    WidgetTester tester, {
    required Event oldEvent,
    required Event newEvent,
    required List<Assignment> withHours,
    Size size = const Size(900, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<List<CustomHoursResolution>?>? pending;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  pending = CustomHoursResolveDialog.show(
                    context,
                    oldEvent: oldEvent,
                    newEvent: newEvent,
                    withHours: withHours,
                    roleNames: _roleNames,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return _Opened(pending!);
  }

  Finder card(String id) => find.byKey(ValueKey('hoursCard:$id'));

  Finder inCard(String id, String text) =>
      find.descendant(of: card(id), matching: find.text(text));

  Future<void> choose(WidgetTester tester, String id, String label) async {
    await tester.tap(inCard(id, label));
    await tester.pumpAndSettle();
  }

  bool saveEnabled(WidgetTester tester) =>
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, _save))
          .onPressed !=
      null;

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, _save));
    await tester.pumpAndSettle();
  }

  group('a move of the first day', () {
    testWidgets(
        'save waits for a choice, and moving shifts both ends by the days '
        'the event moved', (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', dana)],
      );

      expect(saveEnabled(tester), isFalse);
      expect(find.text('נשאר 1 לבחירה'), findsOneWidget);
      // Nothing is preselected: no choice is shown as taken.
      expect(find.text('דנה כהן · חובש/ת'), findsOneWidget);

      await choose(tester, 'm1', _move);

      expect(saveEnabled(tester), isTrue);
      expect(find.textContaining('נשאר'), findsNothing);

      await save(tester);
      expect(await opened.result, [
        _resolution('a1', '2026-11-03T14:00', '2026-11-03T23:00'),
      ]);
    });

    testWidgets('the move option previews the shifted hours', (tester) async {
      final dana = _member('m1', 'דנה כהן');
      await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', dana)],
      );

      expect(inCard('m1', '3.11 14:00–23:00'), findsOneWidget);
    });

    testWidgets('an earlier event shifts back, and the bulk label says so',
        (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final opened = await open(
        tester,
        // The event moves from 3.11-4.11 back to 27-28.10.
        oldEvent: _movedEvent,
        newEvent: _oldEvent,
        withHours: [
          _assignment('a1', dana,
              start: '2026-11-03T14:00', end: '2026-11-03T23:00'),
        ],
      );

      expect(find.text('להזיז את כולם עם האירוע (-7 ימים)'), findsOneWidget);
      await choose(tester, 'm1', _move);
      await save(tester);
      expect(await opened.result, [
        _resolution('a1', '2026-10-27T14:00', '2026-10-27T23:00'),
      ]);
    });

    testWidgets('moving a stay that crosses a month keeps its clock times',
        (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [
          _assignment('a1', dana,
              start: '2026-10-28T20:00', end: '2026-10-29T02:00'),
        ],
      );

      await choose(tester, 'm1', _move);
      await save(tester);
      expect(await opened.result, [
        _resolution('a1', '2026-11-04T20:00', '2026-11-05T02:00'),
      ]);
    });
  });

  group('the header', () {
    testWidgets(
        'names the problem and shows the old and the new dates and '
        'times', (tester) async {
      final dana = _member('m1', 'דנה כהן');
      await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', dana)],
      );

      expect(find.text('⏰ לחלק מהצוות יש שעות מותאמות'), findsOneWidget);
      expect(find.text('כנס חורף'), findsOneWidget);
      expect(
        find.text('27–28.10 · התייצבות 12:00 · התכנסות קהל 19:00 · '
            'סיום המופע 23:00 · סיום הצוות 23:30'),
        findsOneWidget,
      );
      expect(
        find.text('3–4.11 · התייצבות 12:00 · התכנסות קהל 19:00 · '
            'סיום המופע 23:00 · סיום הצוות 23:30'),
        findsOneWidget,
      );
    });

    testWidgets('a range that crosses a month names both months',
        (tester) async {
      final dana = _member('m1', 'דנה כהן');
      await open(
        tester,
        oldEvent: _event(
            startDate: DateTime(2026, 10, 30), endDate: DateTime(2026, 11, 2)),
        newEvent: _event(
            startDate: DateTime(2026, 11, 2), endDate: DateTime(2026, 11, 2)),
        withHours: [_assignment('a1', dana)],
      );

      const times = ' · התייצבות 12:00 · התכנסות קהל 19:00 · '
          'סיום המופע 23:00 · סיום הצוות 23:30';
      expect(find.text('30.10–2.11$times'), findsOneWidget);
      expect(find.text('2.11$times'), findsOneWidget);
    });
  });

  group('only the times changed', () {
    testWidgets('there is nothing to move: no move option, no bulk button',
        (tester) async {
      final dana = _member('m1', 'דנה כהן');
      await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _retimedEvent,
        withHours: [_assignment('a1', dana)],
      );

      expect(find.text(_move), findsNothing);
      expect(find.textContaining('להזיז את כולם'), findsNothing);
      expect(inCard('m1', _keep), findsOneWidget);
      expect(inCard('m1', _edit), findsOneWidget);
      expect(inCard('m1', _remove), findsOneWidget);
    });

    testWidgets('only the last day moved: the first day did not, so no move',
        (tester) async {
      final dana = _member('m1', 'דנה כהן');
      await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _event(
            startDate: DateTime(2026, 10, 27), endDate: DateTime(2026, 10, 29)),
        withHours: [_assignment('a1', dana)],
      );

      expect(find.text(_move), findsNothing);
      expect(find.textContaining('להזיז את כולם'), findsNothing);
    });

    testWidgets('keep reads plain while the hours still overlap the event',
        (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _retimedEvent,
        withHours: [_assignment('a1', dana)],
      );

      expect(find.text(_keepNoOverlap), findsNothing);
      await choose(tester, 'm1', _keep);
      await save(tester);
      expect(await opened.result, [
        _resolution('a1', '2026-10-27T14:00', '2026-10-27T23:00'),
      ]);
    });
  });

  group('hours that no longer touch the event', () {
    testWidgets('keep says so', (tester) async {
      final dana = _member('m1', 'דנה כהן');
      await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', dana)],
      );

      expect(inCard('m1', _keepNoOverlap), findsOneWidget);
      expect(inCard('m1', _keep), findsNothing);
    });

    testWidgets('keep and remove resolve to the old hours and to none',
        (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final avi = _member('m2', 'אבי לוי');
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [
          _assignment('a1', dana),
          _assignment('a2', avi, roleType: 'driver'),
        ],
      );

      await choose(tester, 'm1', _keepNoOverlap);
      await choose(tester, 'm2', _remove);
      await save(tester);

      // Ordered by member name: אבי before דנה.
      expect(await opened.result, [
        _resolution('a2', null, null),
        _resolution('a1', '2026-10-27T14:00', '2026-10-27T23:00'),
      ]);
    });
  });

  group('members with several assignments', () {
    testWidgets('one card for the member, equal hours on each assignment',
        (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [
          _assignment('a1', dana),
          _assignment('a2', dana, roleType: 'driver'),
        ],
      );

      expect(find.text('דנה כהן · חובש/ת, נהג/ת'), findsOneWidget);
      expect(find.text('נשאר 1 לבחירה'), findsOneWidget);

      await choose(tester, 'm1', _move);
      await save(tester);

      final resolutions = (await opened.result)!;
      expect(resolutions.map((r) => r.assignmentId), ['a1', 'a2']);
      expect(resolutions, [
        _resolution('a1', '2026-11-03T14:00', '2026-11-03T23:00'),
        _resolution('a2', '2026-11-03T14:00', '2026-11-03T23:00'),
      ]);
    });

    testWidgets('an exempt member has a card for each assignment',
        (tester) async {
      final pool = _member('m1', 'מאייש', exempt: true);
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [
          _assignment('a1', pool),
          _assignment('a2', pool,
              roleType: 'driver',
              start: '2026-10-28T08:00',
              end: '2026-10-28T12:00'),
        ],
      );

      expect(find.text('מאייש · חובש/ת'), findsOneWidget);
      expect(find.text('מאייש · נהג/ת'), findsOneWidget);
      expect(find.text('נשאר 2 לבחירה'), findsOneWidget);

      await choose(tester, 'a1', _move);
      expect(find.text('נשאר 1 לבחירה'), findsOneWidget);
      await choose(tester, 'a2', _remove);
      await save(tester);

      expect(await opened.result, [
        _resolution('a1', '2026-11-03T14:00', '2026-11-03T23:00'),
        _resolution('a2', null, null),
      ]);
    });
  });

  group('the bulk shortcut', () {
    testWidgets('moves everyone with the event, and cards stay editable',
        (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final avi = _member('m2', 'אבי לוי');
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [
          _assignment('a1', dana),
          _assignment('a2', avi,
              start: '2026-10-28T08:00', end: '2026-10-28T20:00'),
        ],
      );

      expect(saveEnabled(tester), isFalse);
      await tester.tap(find.text('להזיז את כולם עם האירוע (+7 ימים)'));
      await tester.pumpAndSettle();

      expect(saveEnabled(tester), isTrue);
      expect(find.textContaining('נשאר'), findsNothing);

      // One card is switched afterwards.
      await choose(tester, 'm1', _remove);
      await save(tester);

      expect(await opened.result, [
        _resolution('a2', '2026-11-04T08:00', '2026-11-04T20:00'),
        _resolution('a1', null, null),
      ]);
    });
  });

  group('editing the hours', () {
    testWidgets('opens the fields on the current hours, valid as they are',
        (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', dana)],
      );

      expect(find.byType(CustomHoursFields), findsNothing);
      await choose(tester, 'm1', _edit);

      final fields =
          tester.widget<CustomHoursFields>(find.byType(CustomHoursFields));
      expect(fields.event, _movedEvent);
      expect(
        fields.initial,
        WallInterval(
          DateTime.utc(2026, 10, 27, 14),
          DateTime.utc(2026, 10, 27, 23),
        ),
      );
      expect(saveEnabled(tester), isTrue);

      await save(tester);
      expect(await opened.result, [
        _resolution('a1', '2026-10-27T14:00', '2026-10-27T23:00'),
      ]);
    });

    testWidgets('a changed time is what gets saved', (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', dana)],
      );

      await choose(tester, 'm1', _edit);
      await tester.enterText(find.byType(TextFormField).at(1), '2130');
      await tester.pump();
      await save(tester);

      expect(await opened.result, [
        _resolution('a1', '2026-10-27T14:00', '2026-10-27T21:30'),
      ]);
    });

    testWidgets(
        'an unusable interval keeps save off and still counts as '
        'left to settle', (tester) async {
      final dana = _member('m1', 'דנה כהן');
      await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', dana)],
      );

      await choose(tester, 'm1', _edit);
      await tester.enterText(find.byType(TextFormField).at(1), '1300');
      await tester.pump();

      expect(saveEnabled(tester), isFalse);
      expect(find.text('נשאר 1 לבחירה'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(1), '2200');
      await tester.pump();
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('leaving edit for another choice drops the fields',
        (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', dana)],
      );

      await choose(tester, 'm1', _edit);
      await tester.enterText(find.byType(TextFormField).at(1), '1300');
      await tester.pump();
      expect(saveEnabled(tester), isFalse);

      await choose(tester, 'm1', _remove);
      expect(find.byType(CustomHoursFields), findsNothing);
      expect(saveEnabled(tester), isTrue);

      await save(tester);
      expect(await opened.result, [_resolution('a1', null, null)]);
    });
  });

  group('constraint warnings', () {
    // Dana cannot work on 3.11.
    final dana = _member('m1', 'דנה כהן', constraints: [
      _unavailable(DateTime(2026, 11, 3)),
    ]);

    String warningFor(WallInterval window) =>
        customHoursWarningLines(dana, window).single;

    testWidgets('show up for the choice made, and only then', (tester) async {
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', dana)],
      );
      final movedHours = WallInterval(
        DateTime.utc(2026, 11, 3, 14),
        DateTime.utc(2026, 11, 3, 23),
      );
      final warning = warningFor(movedHours);
      expect(warning, startsWith('⚠️ מתנגש עם אילוץ מאושר של דנה'));

      expect(find.text(warning), findsNothing);

      await choose(tester, 'm1', _move);
      expect(find.text(warning), findsOneWidget);

      // Kept hours are on 27.10: no conflict there.
      await choose(tester, 'm1', _keepNoOverlap);
      expect(find.text(warning), findsNothing);

      // Warned, never blocked.
      await choose(tester, 'm1', _move);
      await save(tester);
      expect(await opened.result, [
        _resolution('a1', '2026-11-03T14:00', '2026-11-03T23:00'),
      ]);
    });

    testWidgets('remove is judged against the new event hours', (tester) async {
      await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', dana)],
      );

      await choose(tester, 'm1', _remove);

      expect(
        find.text(warningFor(eventStretch(_movedEvent))),
        findsOneWidget,
      );
    });

    testWidgets('an edit is judged against the hours typed', (tester) async {
      // Dana cannot work 27.10 between 15:00 and 16:00.
      final busy = _member('m1', 'דנה כהן', constraints: [
        DateConstraint(
          id: 'c-busy',
          startDate: DateTime(2026, 10, 27),
          constraintType: ConstraintType.unavailability,
          startTime: '15:00',
          endTime: '16:00',
        ),
      ]);
      await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', busy)],
      );
      final warning = customHoursWarningLines(
        busy,
        WallInterval(
            DateTime.utc(2026, 10, 27, 14), DateTime.utc(2026, 10, 27, 23)),
      ).single;

      await choose(tester, 'm1', _edit);
      expect(find.text(warning), findsOneWidget);

      // Leaving at 14:30 clears the 15:00 hour.
      await tester.enterText(find.byType(TextFormField).at(1), '1430');
      await tester.pump();
      expect(find.text(warning), findsNothing);

      // An unusable interval has no window to judge: no warning either.
      await tester.enterText(find.byType(TextFormField).at(1), '1300');
      await tester.pump();
      expect(find.textContaining('מתנגש'), findsNothing);
    });

    testWidgets('a pending constraint is labelled pending', (tester) async {
      final pending = _member('m1', 'דנה כהן', constraints: [
        _unavailable(DateTime(2026, 11, 3), status: ConstraintStatus.pending),
      ]);
      await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', pending)],
      );

      await choose(tester, 'm1', _move);
      expect(find.textContaining('מתנגש עם אילוץ ממתין לאישור של דנה'),
          findsOneWidget);
    });
  });

  group('cards', () {
    testWidgets('are ordered by member name', (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final avi = _member('m2', 'אבי לוי');
      final noa = _member('m3', 'נועה ברק');
      await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [
          _assignment('a1', dana),
          _assignment('a3', noa),
          _assignment('a2', avi),
        ],
      );

      double top(String id) => tester.getTopLeft(card(id)).dy;
      expect(top('m2'), lessThan(top('m1')));
      expect(top('m1'), lessThan(top('m3')));
    });

    testWidgets('a member the form could not load still gets a card',
        (tester) async {
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', null, memberId: 'gone')],
      );

      expect(card('gone'), findsOneWidget);
      expect(find.text('חבר/ת צוות · חובש/ת'), findsOneWidget);
      await choose(tester, 'gone', _remove);
      await save(tester);
      expect(await opened.result, [_resolution('a1', null, null)]);
    });
  });

  group('on a phone', () {
    testWidgets(
        'the cards, the edit fields and the buttons fit without '
        'overflow, and the list scrolls', (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final avi = _member('m2', 'אבי לוי');
      final noa = _member('m3', 'נועה ברק');
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [
          _assignment('a1', dana),
          _assignment('a2', avi),
          _assignment('a3', noa),
        ],
        size: const Size(360, 640),
      );

      // Dana's edit fields open inside her card.
      await tester.ensureVisible(card('m1'));
      await choose(tester, 'm1', _edit);
      expect(find.byType(CustomHoursFields), findsOneWidget);

      // The save button stays on screen while the cards scroll beneath it.
      expect(find.widgetWithText(ElevatedButton, _save), findsOneWidget);
      expect(
        tester.getBottomLeft(find.widgetWithText(ElevatedButton, _save)).dy,
        lessThanOrEqualTo(640),
      );

      final bulk = find.text('להזיז את כולם עם האירוע (+7 ימים)');
      await tester.ensureVisible(bulk);
      await tester.tap(bulk);
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      await save(tester);
      expect((await opened.result)!, hasLength(3));
      expect(tester.takeException(), isNull);
    });
  });

  group('cancel', () {
    testWidgets('returns null and nothing else', (tester) async {
      final dana = _member('m1', 'דנה כהן');
      final opened = await open(
        tester,
        oldEvent: _oldEvent,
        newEvent: _movedEvent,
        withHours: [_assignment('a1', dana)],
      );

      await choose(tester, 'm1', _move);
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      expect(await opened.result, isNull);
      expect(find.text(_save), findsNothing);
    });
  });
}
