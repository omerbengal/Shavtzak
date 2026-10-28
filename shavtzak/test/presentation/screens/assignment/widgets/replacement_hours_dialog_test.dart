// ReplacementHoursDialog: asked on the admin assignments screen when a slot is
// filled or its member replaced and custom hours are involved (the previous
// occupant had hours, or the incoming member has hours on another role of the
// event). Each choice shows its own hours and its conflict result for the
// incoming member; nothing is preselected.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/core/utils/custom_hours.dart';
import 'package:shavtzak/core/utils/event_stretch.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/assignment/widgets/replacement_hours_dialog.dart';
import 'package:shavtzak/presentation/widgets/custom_hours_fields.dart';

const String _confirm = 'אישור';
const String _cancel = 'ביטול';
const String _keepDana = 'לשמור את השעות של דנה';
const String _yossiExisting = 'השעות הקיימות של יוסי';
const String _eventHours = 'שעות האירוע הרגילות';
const String _other = 'שעות אחרות…';

final DateTime _stamp = DateTime(2026, 10, 1);

// 27-28.10, stretch 27.10 12:00 to 28.10 23:30.
final Event _event = Event(
  id: 'e1',
  name: 'כנס חורף',
  startDate: DateTime(2026, 10, 27),
  endDate: DateTime(2026, 10, 28),
  startTime: '19:00',
  endTime: '23:00',
  teamEndTime: '23:30',
  assemblyTime: '12:00',
  requiresArmed: false,
  roleRequirements: const {'medic': 1},
  createdAt: _stamp,
  updatedAt: _stamp,
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
      roleCapabilities: const {'medic': true},
      createdAt: _stamp,
      updatedAt: _stamp,
      uniqueKey: 'k-$id',
      allowMultipleAssignments: exempt,
    );

DateConstraint _unavailable(DateTime day, {ConstraintStatus? status}) =>
    DateConstraint(
      id: 'c-${day.day}-${day.month}',
      startDate: day,
      constraintType: ConstraintType.unavailability,
      status: status ?? ConstraintStatus.approved,
    );

WallInterval _wall(int day, int hour, int endDay, int endHour) => WallInterval(
      DateTime.utc(2026, 10, day, hour),
      DateTime.utc(2026, 10, endDay, endHour),
    );

// Dana's hours: 27.10 14:00-23:00.
final WallInterval _danaHours = _wall(27, 14, 27, 23);

// Yossi's hours on his other role: 28.10 08:00-12:00.
final WallInterval _yossiHours = _wall(28, 8, 28, 12);

final TeamMember _dana = _member('m1', 'דנה כהן');

// Yossi cannot work on 28.10.
final TeamMember _yossi = _member('m2', 'יוסי מזרחי', constraints: [
  _unavailable(DateTime(2026, 10, 28)),
]);

class _Opened {
  _Opened(this.result);

  /// Completes with what the dialog returns once it closes.
  final Future<({WallInterval? hours})?> result;
}

void main() {
  Future<_Opened> open(
    WidgetTester tester, {
    TeamMember? incoming,
    TeamMember? previous,
    WallInterval? previousHours,
    WallInterval? incomingExistingHours,
    bool incomingHasOtherRoles = false,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<({WallInterval? hours})?>? pending;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  pending = ReplacementHoursDialog.show(
                    context,
                    event: _event,
                    incoming: incoming ?? _yossi,
                    previous: previous,
                    previousHours: previousHours,
                    incomingExistingHours: incomingExistingHours,
                    incomingHasOtherRoles: incomingHasOtherRoles,
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

  Finder choice(String key) => find.byKey(ValueKey('replacementHours:$key'));

  bool isSelected(WidgetTester tester, String key) =>
      tester.widget<Semantics>(choice(key)).properties.selected ?? false;

  Finder inChoice(String key, String text) =>
      find.descendant(of: choice(key), matching: find.text(text));

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  bool confirmEnabled(WidgetTester tester) =>
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, _confirm))
          .onPressed !=
      null;

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, _confirm));
    await tester.pumpAndSettle();
  }

  Finder hoursTimeField(int index) => find
      .descendant(
        of: find.byType(CustomHoursFields),
        matching: find.byType(TextFormField),
      )
      .at(index);

  group('both hours', () {
    testWidgets(
        'all four choices show, none is selected, and אישור waits for one',
        (tester) async {
      await open(
        tester,
        previous: _dana,
        previousHours: _danaHours,
        incomingExistingHours: _yossiHours,
        incomingHasOtherRoles: true,
      );

      expect(find.text(_keepDana), findsOneWidget);
      expect(find.text(_yossiExisting), findsOneWidget);
      expect(find.text(_eventHours), findsOneWidget);
      expect(find.text(_other), findsOneWidget);
      for (final key in ['keepPrevious', 'incomingExisting', 'eventHours',
          'other']) {
        expect(isSelected(tester, key), isFalse, reason: key);
      }
      expect(confirmEnabled(tester), isFalse);

      await choose(tester, _yossiExisting);

      expect(isSelected(tester, 'incomingExisting'), isTrue);
      expect(isSelected(tester, 'keepPrevious'), isFalse);
      expect(confirmEnabled(tester), isTrue);
    });

    testWidgets('each choice shows its own hours', (tester) async {
      await open(
        tester,
        previous: _dana,
        previousHours: _danaHours,
        incomingExistingHours: _yossiHours,
      );

      expect(inChoice('keepPrevious', '27.10 14:00–23:00'), findsOneWidget);
      expect(inChoice('incomingExisting', '28.10 08:00–12:00'), findsOneWidget);
      expect(inChoice('eventHours', '27.10 12:00 – 28.10 23:30'),
          findsOneWidget);
    });
  });

  group('the conflict result for the incoming member', () {
    testWidgets(
        'each choice shows its own: a conflicting one warns, a free one says '
        'so, and the conflicting one can still be chosen', (tester) async {
      final opened = await open(
        tester,
        previous: _dana,
        previousHours: _danaHours,
      );
      final warning =
          customHoursWarningLines(_yossi, eventStretch(_event)).single;
      expect(warning, '⚠️ מתנגש עם אילוץ מאושר של יוסי: 28.10 (כל היום)');

      expect(inChoice('eventHours', warning), findsOneWidget);
      expect(inChoice('keepPrevious', '✅ אין התנגשות עם אילוצים של יוסי'),
          findsOneWidget);
      expect(inChoice('keepPrevious', warning), findsNothing);

      // Warned, never blocked.
      await choose(tester, _eventHours);
      expect(inChoice('eventHours', warning), findsOneWidget);
      await confirm(tester);
      expect(await opened.result, (hours: null));
    });

    testWidgets('a pending constraint is labelled pending', (tester) async {
      final pending = _member('m2', 'יוסי מזרחי', constraints: [
        _unavailable(DateTime(2026, 10, 28),
            status: ConstraintStatus.pending),
      ]);
      await open(
        tester,
        incoming: pending,
        previous: _dana,
        previousHours: _danaHours,
      );

      expect(
        find.descendant(
          of: choice('eventHours'),
          matching:
              find.textContaining('מתנגש עם אילוץ ממתין לאישור של יוסי'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('other hours are judged as they are typed, once chosen',
        (tester) async {
      // This yossi cannot work 27.10 between 21:30 and 22:30.
      final busy = _member('m2', 'יוסי מזרחי', constraints: [
        DateConstraint(
          id: 'c-busy',
          startDate: DateTime(2026, 10, 27),
          constraintType: ConstraintType.unavailability,
          startTime: '21:30',
          endTime: '22:30',
        ),
      ]);
      await open(
        tester,
        incoming: busy,
        previous: _dana,
        previousHours: _danaHours,
      );
      final warning = customHoursWarningLines(busy, _danaHours).single;
      expect(warning, startsWith('⚠️ מתנגש עם אילוץ מאושר של יוסי'));
      // Not chosen yet: no fields and no result under "שעות אחרות…".
      expect(find.byType(CustomHoursFields), findsNothing);
      expect(inChoice('other', warning), findsNothing);

      await choose(tester, _other);
      // The fields open on dana's hours, which run into the constraint.
      expect(inChoice('other', warning), findsOneWidget);

      // Leaving at 21:00 clears it.
      await tester.enterText(hoursTimeField(1), '2100');
      await tester.pump();
      expect(inChoice('other', warning), findsNothing);
      expect(
          inChoice('other', '✅ אין התנגשות עם אילוצים של יוסי'), findsOneWidget);

      // An unusable interval has no result.
      await tester.enterText(hoursTimeField(1), '1300');
      await tester.pump();
      expect(inChoice('other', '✅ אין התנגשות עם אילוצים של יוסי'),
          findsNothing);
    });
  });

  group('the choices that apply', () {
    testWidgets(
        'without the previous occupant\'s hours: titled after the incoming '
        'member, no "keep" choice', (tester) async {
      await open(
        tester,
        previous: _dana,
        incomingExistingHours: _yossiHours,
        incomingHasOtherRoles: true,
      );

      expect(find.text('⏰ ליוסי יש שעות מותאמות באירוע'), findsOneWidget);
      expect(choice('keepPrevious'), findsNothing);
      expect(find.text(_yossiExisting), findsOneWidget);
      expect(find.text(_eventHours), findsOneWidget);
      expect(find.text(_other), findsOneWidget);
    });

    testWidgets(
        'with the previous occupant\'s hours: titled after her, no "existing" '
        'choice when the incoming member has none', (tester) async {
      await open(tester, previous: _dana, previousHours: _danaHours);

      expect(find.text('⏰ לדנה היו שעות מותאמות'), findsOneWidget);
      expect(find.text(_keepDana), findsOneWidget);
      expect(choice('incomingExisting'), findsNothing);
    });
  });

  testWidgets('a previous occupant without a name is called חבר/ת הצוות',
      (tester) async {
    await open(
      tester,
      previous: _member('m1', '  '),
      previousHours: _danaHours,
    );

    expect(find.text('⏰ לחבר/ת הצוות היו שעות מותאמות'), findsOneWidget);
    expect(find.text('לשמור את השעות של חבר/ת הצוות'), findsOneWidget);
  });

  group('the other roles line', () {
    const line = 'השעות יחולו על כל התפקידים של יוסי באירוע';

    testWidgets('shows when the incoming member holds other roles',
        (tester) async {
      await open(
        tester,
        previous: _dana,
        previousHours: _danaHours,
        incomingHasOtherRoles: true,
      );
      expect(find.text(line), findsOneWidget);
    });

    testWidgets('is absent when they hold no other role', (tester) async {
      await open(tester, previous: _dana, previousHours: _danaHours);
      expect(find.text(line), findsNothing);
    });

    testWidgets('is absent for an exempt member', (tester) async {
      await open(
        tester,
        incoming: _member('m2', 'יוסי מזרחי', exempt: true),
        previous: _dana,
        previousHours: _danaHours,
        incomingHasOtherRoles: true,
      );
      expect(find.text(line), findsNothing);
    });
  });

  group('the result', () {
    testWidgets('keeping the previous hours returns them', (tester) async {
      final opened = await open(
        tester,
        previous: _dana,
        previousHours: _danaHours,
        incomingExistingHours: _yossiHours,
      );
      await choose(tester, _keepDana);
      await confirm(tester);
      expect(await opened.result, (hours: _danaHours));
    });

    testWidgets('the incoming member\'s existing hours return them',
        (tester) async {
      final opened = await open(
        tester,
        previous: _dana,
        previousHours: _danaHours,
        incomingExistingHours: _yossiHours,
      );
      await choose(tester, _yossiExisting);
      await confirm(tester);
      expect(await opened.result, (hours: _yossiHours));
    });

    testWidgets('other hours return what is typed, and wait for a usable '
        'interval', (tester) async {
      final opened = await open(
        tester,
        previous: _dana,
        previousHours: _danaHours,
      );
      await choose(tester, _other);
      expect(find.byType(CustomHoursFields), findsOneWidget);
      // The fields start on the previous occupant's hours.
      expect(
          tester.widget<TextFormField>(hoursTimeField(0)).controller!.text,
          '14:00');
      expect(confirmEnabled(tester), isTrue);

      // Leaving before arriving is not usable.
      await tester.enterText(hoursTimeField(1), '1300');
      await tester.pump();
      expect(confirmEnabled(tester), isFalse);

      await tester.enterText(hoursTimeField(1), '2100');
      await tester.pump();
      expect(confirmEnabled(tester), isTrue);
      await confirm(tester);
      expect(await opened.result, (hours: _wall(27, 14, 27, 21)));
    });

    testWidgets('ביטול returns null', (tester) async {
      final opened = await open(
        tester,
        previous: _dana,
        previousHours: _danaHours,
      );
      await choose(tester, _keepDana);
      await tester.tap(find.text(_cancel));
      await tester.pumpAndSettle();
      expect(await opened.result, isNull);
    });
  });
}
