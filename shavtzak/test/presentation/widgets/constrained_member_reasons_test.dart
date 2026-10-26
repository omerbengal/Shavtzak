// The reason lines and the leading icon of a row in the "בעלי מגבלות / לא
// זמינים" lists: approved in red with the calendar, pending in orange with an
// hourglass, the same-day line first.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/constraint_status.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/widgets/constrained_member_reasons.dart';

// The event is the whole of Wednesday 2026-10-28 (no hours given).
final Event _event = Event(
  id: 'e1',
  name: 'כנס חורף',
  startDate: DateTime(2026, 10, 28),
  endDate: DateTime(2026, 10, 28),
  startTime: '',
  endTime: '',
  assemblyTime: '',
  requiresArmed: false,
  roleRequirements: const {'medic': 1},
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

DateConstraint _blocking(
  String id, {
  required ConstraintStatus status,
  DateTime? day,
  String? startTime,
  String? endTime,
}) {
  return DateConstraint(
    id: id,
    startDate: day ?? DateTime(2026, 10, 28),
    status: status,
    constraintType: ConstraintType.unavailability,
    startTime: startTime,
    endTime: endTime,
  );
}

TeamMember _member({
  bool isPermanent = true,
  List<DateConstraint> constraints = const [],
  List<String> availableEventIds = const [],
}) {
  return TeamMember(
    id: 'm1',
    name: 'אבי כהן',
    isActive: true,
    isPermanent: isPermanent,
    constraints: constraints,
    roleCapabilities: const {'medic': true},
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    uniqueKey: 'key-m1',
    availableEventIds: availableEventIds,
  );
}

Widget _wrap(Widget child) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: child)),
      ),
    );

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  const approvedLine = 'אילוץ מאושר: 28.10 (כל היום)';
  const pendingLine = 'אילוץ ממתין לאישור: 28.10 (כל היום)';

  group('ConstrainedMemberReasons', () {
    testWidgets('approved only: one red line', (tester) async {
      final member = _member(constraints: [
        _blocking('a', status: ConstraintStatus.approved),
      ]);

      await tester.pumpWidget(
          _wrap(ConstrainedMemberReasons(member: member, event: _event)));

      expect(find.byType(Text), findsOneWidget);
      expect(find.text(approvedLine), findsOneWidget);
      expect(_colorOf(tester, approvedLine), Colors.red.shade600);
    });

    testWidgets('pending only: one orange line', (tester) async {
      final member = _member(constraints: [
        _blocking('p', status: ConstraintStatus.pending),
      ]);

      await tester.pumpWidget(
          _wrap(ConstrainedMemberReasons(member: member, event: _event)));

      expect(find.byType(Text), findsOneWidget);
      expect(find.text(pendingLine), findsOneWidget);
      expect(_colorOf(tester, pendingLine), Colors.orange.shade800);
    });

    testWidgets('pending line carries its hours', (tester) async {
      final member = _member(constraints: [
        _blocking(
          'p',
          status: ConstraintStatus.pending,
          startTime: '17:00',
          endTime: '20:00',
        ),
      ]);

      await tester.pumpWidget(
          _wrap(ConstrainedMemberReasons(member: member, event: _event)));

      expect(find.text('אילוץ ממתין לאישור: 28.10 17:00–20:00'),
          findsOneWidget);
    });

    testWidgets('both: two lines, approved first', (tester) async {
      // The pending one is listed first on purpose: the order on screen must
      // not follow the order the constraints are stored in.
      final member = _member(constraints: [
        _blocking('p', status: ConstraintStatus.pending),
        _blocking('a', status: ConstraintStatus.approved),
      ]);

      await tester.pumpWidget(
          _wrap(ConstrainedMemberReasons(member: member, event: _event)));

      expect(find.byType(Text), findsNWidgets(2));
      expect(tester.getTopLeft(find.text(approvedLine)).dy,
          lessThan(tester.getTopLeft(find.text(pendingLine)).dy));
      expect(_colorOf(tester, approvedLine), Colors.red.shade600);
      expect(_colorOf(tester, pendingLine), Colors.orange.shade800);
    });

    testWidgets('same-day first, then the pending line', (tester) async {
      final member = _member(constraints: [
        _blocking('p', status: ConstraintStatus.pending),
      ]);

      await tester.pumpWidget(_wrap(ConstrainedMemberReasons(
        member: member,
        event: _event,
        sameDayEvents: const ['הופעה בחיפה'],
      )));

      expect(find.byType(Text), findsNWidgets(2));
      expect(find.text('משובצ/ת ב: הופעה בחיפה'), findsOneWidget);
      expect(tester.getTopLeft(find.text('משובצ/ת ב: הופעה בחיפה')).dy,
          lessThan(tester.getTopLeft(find.text(pendingLine)).dy));
      expect(_colorOf(tester, 'משובצ/ת ב: הופעה בחיפה'), Colors.red.shade600);
    });

    testWidgets('several same-day events are joined', (tester) async {
      await tester.pumpWidget(_wrap(ConstrainedMemberReasons(
        member: _member(),
        event: _event,
        sameDayEvents: const ['הופעה בחיפה', 'טקס'],
      )));

      expect(find.text('משובצ/ת ב: הופעה בחיפה, טקס'), findsOneWidget);
    });

    testWidgets('same-day only, no constraint: just the same-day line',
        (tester) async {
      await tester.pumpWidget(_wrap(ConstrainedMemberReasons(
        member: _member(),
        event: _event,
        sameDayEvents: const ['הופעה בחיפה'],
      )));

      expect(find.byType(Text), findsOneWidget);
      expect(find.text('משובצ/ת ב: הופעה בחיפה'), findsOneWidget);
    });

    testWidgets('a constraint that does not reach the event is not listed',
        (tester) async {
      final member = _member(constraints: [
        _blocking('far',
            status: ConstraintStatus.approved, day: DateTime(2026, 11, 20)),
        _blocking('p', status: ConstraintStatus.pending),
      ]);

      await tester.pumpWidget(
          _wrap(ConstrainedMemberReasons(member: member, event: _event)));

      expect(find.byType(Text), findsOneWidget);
      expect(find.text(pendingLine), findsOneWidget);
    });

    testWidgets('a rejected constraint is not listed', (tester) async {
      final member = _member(constraints: [
        _blocking('r', status: ConstraintStatus.rejected),
        _blocking('a', status: ConstraintStatus.approved),
      ]);

      await tester.pumpWidget(
          _wrap(ConstrainedMemberReasons(member: member, event: _event)));

      expect(find.byType(Text), findsOneWidget);
      expect(find.text(approvedLine), findsOneWidget);
    });

    testWidgets('non-permanent without availability: לא ציין/ה זמינות',
        (tester) async {
      await tester.pumpWidget(_wrap(ConstrainedMemberReasons(
        member: _member(isPermanent: false),
        event: _event,
      )));

      expect(find.byType(Text), findsOneWidget);
      expect(find.text('לא ציין/ה זמינות'), findsOneWidget);
      expect(_colorOf(tester, 'לא ציין/ה זמינות'), Colors.red.shade600);
    });

    testWidgets(
        'non-permanent who did give availability is not told otherwise, '
        'only the same-day line shows', (tester) async {
      await tester.pumpWidget(_wrap(ConstrainedMemberReasons(
        member: _member(isPermanent: false, availableEventIds: ['e1']),
        event: _event,
        sameDayEvents: const ['הופעה בחיפה'],
      )));

      expect(find.byType(Text), findsOneWidget);
      expect(find.text('משובצ/ת ב: הופעה בחיפה'), findsOneWidget);
    });

    testWidgets('non-permanent, same-day and no availability: both lines, '
        'same-day first', (tester) async {
      await tester.pumpWidget(_wrap(ConstrainedMemberReasons(
        member: _member(isPermanent: false),
        event: _event,
        sameDayEvents: const ['הופעה בחיפה'],
      )));

      expect(find.byType(Text), findsNWidgets(2));
      expect(tester.getTopLeft(find.text('משובצ/ת ב: הופעה בחיפה')).dy,
          lessThan(tester.getTopLeft(find.text('לא ציין/ה זמינות')).dy));
    });

    testWidgets('lays out as a ListTile subtitle', (tester) async {
      final member = _member(constraints: [
        _blocking('a', status: ConstraintStatus.approved),
        _blocking('p',
            status: ConstraintStatus.pending, day: DateTime(2026, 10, 28)),
      ]);

      await tester.pumpWidget(_wrap(ListTile(
        title: const Text('אבי כהן'),
        subtitle: ConstrainedMemberReasons(member: member, event: _event),
        trailing: ElevatedButton(onPressed: () {}, child: const Text('שבץ')),
      )));

      expect(tester.takeException(), isNull);
      expect(find.text(approvedLine), findsOneWidget);
      expect(find.text(pendingLine), findsOneWidget);
    });
  });

  group('constrainedMemberIcon and constrainedMemberIconColor', () {
    final approvedMember = _member(constraints: [
      _blocking('a', status: ConstraintStatus.approved),
    ]);
    final pendingMember = _member(constraints: [
      _blocking('p', status: ConstraintStatus.pending),
    ]);
    final bothMember = _member(constraints: [
      _blocking('p', status: ConstraintStatus.pending),
      _blocking('a', status: ConstraintStatus.approved),
    ]);

    test('approved: the calendar, in today\'s red', () {
      expect(
          constrainedMemberIcon(approvedMember, _event, sameDayAssigned: false),
          Icons.event_busy);
      expect(
          constrainedMemberIconColor(approvedMember, _event,
              sameDayAssigned: false),
          Colors.red.shade400);
    });

    test('pending only: the hourglass, in orange', () {
      expect(
          constrainedMemberIcon(pendingMember, _event, sameDayAssigned: false),
          Icons.hourglass_top);
      expect(
          constrainedMemberIconColor(pendingMember, _event,
              sameDayAssigned: false),
          Colors.orange.shade700);
    });

    test('both: the calendar, because one is approved', () {
      expect(constrainedMemberIcon(bothMember, _event, sameDayAssigned: false),
          Icons.event_busy);
      expect(
          constrainedMemberIconColor(bothMember, _event,
              sameDayAssigned: false),
          Colors.red.shade400);
    });

    test('same-day wins over a pending constraint', () {
      expect(constrainedMemberIcon(pendingMember, _event, sameDayAssigned: true),
          Icons.event);
      expect(
          constrainedMemberIconColor(pendingMember, _event,
              sameDayAssigned: true),
          Colors.red.shade400);
    });

    test('non-permanent: the clock', () {
      final member = _member(isPermanent: false);
      expect(constrainedMemberIcon(member, _event, sameDayAssigned: false),
          Icons.schedule);
      expect(constrainedMemberIconColor(member, _event, sameDayAssigned: false),
          Colors.red.shade400);
    });

    test('permanent with no blocking constraint keeps today\'s calendar', () {
      final member = _member();
      expect(constrainedMemberIcon(member, _event, sameDayAssigned: false),
          Icons.event_busy);
    });
  });
}
