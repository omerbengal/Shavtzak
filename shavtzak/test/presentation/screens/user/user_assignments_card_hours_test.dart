// Tests for the member's own assignment card on /user/assignments when the
// member has custom hours (partial attendance):
//  * the pure wording of the date, arrival and departure rows
//    ([memberCardTimeRows]);
//  * the card itself, rendered from a stubbed AssignmentBloc.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/core/utils/event_stretch.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';
import 'package:shavtzak/presentation/bloc/role/role_bloc.dart';
import 'package:shavtzak/presentation/bloc/role/role_event.dart';
import 'package:shavtzak/presentation/bloc/role/role_state.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_event.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';
import 'package:shavtzak/presentation/screens/user/user_assignments_screen.dart';

class MockAssignmentBloc extends MockBloc<AssignmentEvent, AssignmentState>
    implements AssignmentBloc {}

class MockUserSelectionBloc
    extends MockBloc<UserSelectionEvent, UserSelectionState>
    implements UserSelectionBloc {}

class MockRoleBloc extends MockBloc<RoleEvent, RoleState> implements RoleBloc {}

final DateTime _stamp = DateTime(2026, 1, 1);

TeamMember _dana() => TeamMember(
      id: 'dana',
      name: 'דנה כהן',
      isActive: true,
      isPermanent: true,
      constraints: const [],
      roleCapabilities: const {},
      createdAt: _stamp,
      updatedAt: _stamp,
      uniqueKey: 'uk-dana',
    );

final Role _medic = Role(
  id: 'medic',
  key: 'medic',
  hebrewName: 'חובש/ת',
  sortOrder: 0,
  createdAt: _stamp,
  updatedAt: _stamp,
);

final Role _driver = Role(
  id: 'driver',
  key: 'driver',
  hebrewName: 'נהג/ת',
  sortOrder: 1,
  createdAt: _stamp,
  updatedAt: _stamp,
);

void main() {
  // The card sorts events into upcoming and past against the real clock, so
  // the widget tests place the event [daysAhead] days from today.
  const daysAhead = 20;
  final today = DateTime.now();
  DateTime day(int offset) =>
      DateTime(today.year, today.month, today.day + daysAhead + offset);
  String dm(DateTime date) => '${date.day}.${date.month}';
  String wall(DateTime date, int hour, [int minute = 0]) => formatWallMoment(
      DateTime.utc(date.year, date.month, date.day, hour, minute));

  Event event({
    int lastDayOffset = 1,
    String assemblyTime = '12:00',
    String teamEndTime = '23:30',
  }) =>
      Event(
        id: 'evt',
        name: 'כנס חורף',
        startDate: day(0),
        endDate: day(lastDayOffset),
        startTime: '19:00',
        actualShowStartTime: '20:00',
        endTime: '22:30',
        teamEndTime: teamEndTime,
        assemblyTime: assemblyTime,
        location: 'היכל התרבות',
        requiresArmed: false,
        roleRequirements: const {'medic': 1},
        createdAt: _stamp,
        updatedAt: _stamp,
      );

  Assignment assignment(
    Event event, {
    String id = 'a1',
    String roleType = 'medic',
    String notes = '',
    String? customStartAt,
    String? customEndAt,
  }) =>
      Assignment(
        id: id,
        eventId: event.id,
        teamMemberId: 'dana',
        roleType: roleType,
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: notes,
        customStartAt: customStartAt,
        customEndAt: customEndAt,
        createdAt: _stamp,
        updatedAt: _stamp,
        event: event,
        teamMember: _dana(),
      );

  late MockAssignmentBloc assignmentBloc;
  late MockUserSelectionBloc userBloc;
  late MockRoleBloc roleBloc;

  setUp(() {
    assignmentBloc = MockAssignmentBloc();
    userBloc = MockUserSelectionBloc();
    roleBloc = MockRoleBloc();
    whenListen(
      userBloc,
      const Stream<UserSelectionState>.empty(),
      initialState: UserAuthenticated(_dana()),
    );
    whenListen(
      roleBloc,
      const Stream<RoleState>.empty(),
      initialState: RolesLoaded([_medic, _driver]),
    );
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    List<Assignment> assignments,
  ) async {
    whenListen(
      assignmentBloc,
      const Stream<AssignmentState>.empty(),
      initialState: AssignmentsLoaded(assignments),
    );
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AssignmentBloc>.value(value: assignmentBloc),
            BlocProvider<UserSelectionBloc>.value(value: userBloc),
            BlocProvider<RoleBloc>.value(value: roleBloc),
          ],
          child: const UserAssignmentsScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  /// Every string the card puts on screen, in tree order.
  List<String> cardTexts(WidgetTester tester) {
    final texts = <String>[];
    for (final widget in tester.widgetList<Text>(find.byType(Text))) {
      final data = widget.data ?? widget.textSpan?.toPlainText();
      if (data != null) texts.add(data);
    }
    return texts;
  }

  String weekdayPhrase(DateTime date) {
    const days = ['', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת', 'ראשון'];
    const months = [
      '',
      'ינואר',
      'פברואר',
      'מרץ',
      'אפריל',
      'מאי',
      'יוני',
      'יולי',
      'אוגוסט',
      'ספטמבר',
      'אוקטובר',
      'נובמבר',
      'דצמבר',
    ];
    return 'יום ${days[date.weekday]} ${date.day} ב${months[date.month]}';
  }

  /// The card's strings, in tree order, for the default two-day [event] with
  /// no usable hours: what the screen showed before custom hours existed.
  List<String> todaysCard() => [
        'האירועים שלי',
        'כאן מופיעים כל האירועים שאליהם שובצת',
        'אירועים קרובים',
        '1',
        'כנס חורף',
        'חובש/ת',
        'תאריך התחלה:',
        weekdayPhrase(day(0)),
        'תאריך סיום:',
        weekdayPhrase(day(1)),
        'מיקום:',
        'היכל התרבות',
        'שעת התייצבות:',
        '12:00',
        'התכנסות קהל:',
        '19:00',
        'תחילת המופע:',
        '20:00',
        'סיום מופע משוער:',
        '22:30',
        'סיום צוות משוער:',
        '23:30',
        'מי איתי באירוע?',
        'אירועים שעברו',
        '0',
      ];

  group('a card without usable hours', () {
    testWidgets('renders exactly as before', (tester) async {
      await pumpScreen(tester, [assignment(event())]);

      expect(cardTexts(tester), todaysCard());
    });
  });

  group('a card with the member\'s own hours', () {
    testWidgets(
        'day 1 of 2: arrival, departure and the event\'s end replace the '
        'usual rows and nothing else changes', (tester) async {
      final twoDays = event();
      await pumpScreen(tester, [
        assignment(
          twoDays,
          customStartAt: wall(day(0), 14),
          customEndAt: wall(day(0), 23),
        ),
      ]);

      expect(cardTexts(tester), [
        'האירועים שלי',
        'כאן מופיעים כל האירועים שאליהם שובצת',
        'אירועים קרובים',
        '1',
        'כנס חורף',
        'חובש/ת',
        'תאריך:',
        '${weekdayPhrase(day(0))} (האירוע עד ${dm(day(1))})',
        'מיקום:',
        'היכל התרבות',
        'ההגעה שלך:',
        '14:00 (התייצבות צוות 12:00)',
        'התכנסות קהל:',
        '19:00',
        'תחילת המופע:',
        '20:00',
        'סיום מופע משוער:',
        '22:30',
        'היציאה שלך:',
        '${dm(day(0))} 23:00 (סיום צוות משוער ${dm(day(1))} 23:30)',
        'מי איתי באירוע?',
        'אירועים שעברו',
        '0',
      ]);
    });

    testWidgets(
        'day 2 of 2: the arrival carries its day and the date row names the '
        'event\'s start', (tester) async {
      await pumpScreen(tester, [
        assignment(
          event(),
          customStartAt: wall(day(1), 9),
          customEndAt: wall(day(1), 20),
        ),
      ]);

      final texts = cardTexts(tester);
      expect(texts, contains('תאריך:'));
      expect(
          texts, contains('${weekdayPhrase(day(1))} (האירוע מ-${dm(day(0))})'));
      expect(texts, contains('ההגעה שלך:'));
      expect(texts, contains('${dm(day(1))} 09:00 (התייצבות צוות 12:00)'));
      expect(texts,
          contains('${dm(day(1))} 20:00 (סיום צוות משוער ${dm(day(1))} 23:30)'));
      expect(texts, isNot(contains('תאריך התחלה:')));
    });

    testWidgets(
        'hours that cover every day of the event keep both date rows and add '
        'no bracket to them', (tester) async {
      await pumpScreen(tester, [
        assignment(
          event(),
          customStartAt: wall(day(0), 14),
          customEndAt: wall(day(1), 20),
        ),
      ]);

      final texts = cardTexts(tester);
      expect(
          texts,
          containsAllInOrder([
            'תאריך התחלה:',
            weekdayPhrase(day(0)),
            'תאריך סיום:',
            weekdayPhrase(day(1)),
          ]));
      expect(texts, contains('14:00 (התייצבות צוות 12:00)'));
      expect(texts,
          contains('${dm(day(1))} 20:00 (סיום צוות משוער ${dm(day(1))} 23:30)'));
      expect(texts.where((t) => t.contains('(האירוע')), isEmpty);
    });

    testWidgets('an event with no assembly time shows the arrival alone',
        (tester) async {
      await pumpScreen(tester, [
        assignment(
          event(assemblyTime: ''),
          customStartAt: wall(day(0), 14),
          customEndAt: wall(day(0), 23),
        ),
      ]);

      final texts = cardTexts(tester);
      expect(texts, contains('ההגעה שלך:'));
      expect(texts, contains('14:00'));
      expect(texts.where((t) => t.contains('התייצבות צוות')), isEmpty);
    });

    testWidgets('hours on the member\'s second role are shown for the card',
        (tester) async {
      final twoDays = event();
      await pumpScreen(tester, [
        assignment(twoDays, id: 'a1', roleType: 'medic'),
        assignment(
          twoDays,
          id: 'a2',
          roleType: 'driver',
          customStartAt: wall(day(0), 14),
          customEndAt: wall(day(0), 23),
        ),
      ]);

      final texts = cardTexts(tester);
      expect(texts, contains('14:00 (התייצבות צוות 12:00)'));
      expect(texts, isNot(contains('שעת התייצבות:')));
    });

    testWidgets('hours that cannot be read leave the card as it was',
        (tester) async {
      await pumpScreen(tester, [
        assignment(
          event(),
          customStartAt: wall(day(0), 23),
          customEndAt: wall(day(0), 14),
        ),
      ]);

      expect(cardTexts(tester), todaysCard());
    });

    testWidgets(
        'a middle day of three names both ends of the event on the one date '
        'row', (tester) async {
      await pumpScreen(tester, [
        assignment(
          event(lastDayOffset: 2),
          customStartAt: wall(day(1), 9),
          customEndAt: wall(day(1), 20),
        ),
      ]);

      final texts = cardTexts(tester);
      expect(
        texts,
        contains('${weekdayPhrase(day(1))} (האירוע מ-${dm(day(0))}) '
            '(האירוע עד ${dm(day(2))})'),
      );
      expect(texts, contains('${dm(day(1))} 09:00 (התייצבות צוות 12:00)'));
    });
  });

  group('memberCardTimeRows', () {
    final firstDay = DateTime(2026, 10, 27);
    final lastDay = DateTime(2026, 10, 28);

    Event fixed({
      DateTime? last,
      String assemblyTime = '12:00',
      String endTime = '22:30',
      String teamEndTime = '23:30',
    }) =>
        Event(
          id: 'evt',
          name: 'כנס חורף',
          startDate: firstDay,
          endDate: last ?? lastDay,
          startTime: '19:00',
          endTime: endTime,
          teamEndTime: teamEndTime,
          assemblyTime: assemblyTime,
          requiresArmed: false,
          roleRequirements: const {'medic': 1},
          createdAt: _stamp,
          updatedAt: _stamp,
        );

    WallInterval hours(String start, String end) =>
        WallInterval(parseWallMoment(start)!, parseWallMoment(end)!);

    test('day 1 of 2 days: the example from the spec', () {
      final rows = memberCardTimeRows(
          fixed(), hours('2026-10-27T14:00', '2026-10-27T23:00'));

      expect(rows.hasCustomHours, isTrue);
      expect(rows.arrivalLine, 'ההגעה שלך: 14:00 (התייצבות צוות 12:00)');
      expect(rows.departureLine,
          'היציאה שלך: 27.10 23:00 (סיום צוות משוער 28.10 23:30)');
      expect(rows.firstDay, firstDay);
      expect(rows.lastDay, firstDay);
      expect(rows.firstDayNote, '');
      expect(rows.lastDayNote, ' (האירוע עד 28.10)');
    });

    test('day 2 of 2 days: arrival on a later day carries its day', () {
      final rows = memberCardTimeRows(
          fixed(), hours('2026-10-28T09:00', '2026-10-28T20:00'));

      expect(rows.arrivalLine, 'ההגעה שלך: 28.10 09:00 (התייצבות צוות 12:00)');
      expect(rows.departureLine,
          'היציאה שלך: 28.10 20:00 (סיום צוות משוער 28.10 23:30)');
      expect(rows.firstDay, lastDay);
      expect(rows.lastDay, lastDay);
      expect(rows.firstDayNote, ' (האירוע מ-27.10)');
      expect(rows.lastDayNote, '');
    });

    test('the middle day of three names both ends of the event', () {
      final rows = memberCardTimeRows(
        fixed(last: DateTime(2026, 10, 29)),
        hours('2026-10-28T09:00', '2026-10-28T20:00'),
      );

      expect(rows.firstDayNote, ' (האירוע מ-27.10)');
      expect(rows.lastDayNote, ' (האירוע עד 29.10)');
    });

    test('hours across all of the event\'s days add no brackets', () {
      final rows = memberCardTimeRows(
          fixed(), hours('2026-10-27T14:00', '2026-10-28T20:00'));

      expect(rows.firstDay, firstDay);
      expect(rows.lastDay, lastDay);
      expect(rows.firstDayNote, '');
      expect(rows.lastDayNote, '');
      expect(rows.arrivalLine, 'ההגעה שלך: 14:00 (התייצבות צוות 12:00)');
    });

    test(
        'hours ending at midnight stay on the day before but leave at the '
        'next day\'s 00:00', () {
      final rows = memberCardTimeRows(
        fixed(last: firstDay),
        hours('2026-10-27T18:00', '2026-10-28T00:00'),
      );

      expect(rows.firstDay, firstDay);
      expect(rows.lastDay, firstDay);
      expect(rows.lastDayNote, '');
      expect(rows.departureLine,
          'היציאה שלך: 28.10 00:00 (סיום צוות משוער 27.10 23:30)');
    });

    test('hours that start before the event\'s first day are marked', () {
      final rows = memberCardTimeRows(
          fixed(), hours('2026-10-26T20:00', '2026-10-27T02:00'));

      expect(rows.firstDay, DateTime(2026, 10, 26));
      expect(rows.lastDay, firstDay);
      expect(rows.firstDayNote, ' (האירוע מ-27.10)');
      expect(rows.lastDayNote, ' (האירוע עד 28.10)');
      expect(rows.arrivalLine, 'ההגעה שלך: 26.10 20:00 (התייצבות צוות 12:00)');
    });

    test('no assembly time: the arrival has no bracket', () {
      final rows = memberCardTimeRows(fixed(assemblyTime: ''),
          hours('2026-10-27T14:00', '2026-10-27T23:00'));

      expect(rows.arrivalLine, 'ההגעה שלך: 14:00');
    });

    test('no team end or show end: the departure has no bracket', () {
      final rows = memberCardTimeRows(
        fixed(endTime: '', teamEndTime: ''),
        hours('2026-10-27T14:00', '2026-10-27T23:00'),
      );

      expect(rows.departureLine, 'היציאה שלך: 27.10 23:00');
    });

    test('a team end: the bracket names the team end', () {
      final rows = memberCardTimeRows(
        fixed(),
        hours('2026-10-27T14:00', '2026-10-27T22:00'),
      );

      expect(rows.departureLine,
          'היציאה שלך: 27.10 22:00 (סיום צוות משוער 28.10 23:30)');
    });

    test(
        'no team end: the bracket reads the stretch, which falls back to the '
        'show end, and names the show end', () {
      final rows = memberCardTimeRows(
        fixed(teamEndTime: ''),
        hours('2026-10-27T14:00', '2026-10-27T22:00'),
      );

      expect(rows.departureLine,
          'היציאה שלך: 27.10 22:00 (סיום מופע משוער 28.10 22:30)');
    });

    test(
        'a team end the stretch cannot read counts as none: the bracket names '
        'the show end', () {
      final rows = memberCardTimeRows(
        fixed(teamEndTime: '24:00'),
        hours('2026-10-27T14:00', '2026-10-27T22:00'),
      );

      expect(rows.departureLine,
          'היציאה שלך: 27.10 22:00 (סיום מופע משוער 28.10 22:30)');
    });

    test('without hours: the rows are the ones the card always had', () {
      final event = fixed();
      final rows = memberCardTimeRows(event, null);

      expect(rows.hasCustomHours, isFalse);
      expect(rows.firstDay, event.startDate);
      expect(rows.lastDay, event.endDate);
      expect(rows.firstDayNote, '');
      expect(rows.lastDayNote, '');
      expect(rows.arrivalLine, 'שעת התייצבות: 12:00');
      expect(rows.departureLine, 'סיום צוות משוער: 23:30');
    });

    test(
        'without hours: a missing assembly time reads "טרם נקבעה" and a '
        'missing team end hides the row', () {
      final rows =
          memberCardTimeRows(fixed(assemblyTime: '', teamEndTime: ''), null);

      expect(rows.arrivalLine, 'שעת התייצבות: טרם נקבעה');
      expect(rows.departureLine, isNull);
    });
  });
}
