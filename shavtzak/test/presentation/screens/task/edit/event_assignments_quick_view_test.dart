import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/assignment_label.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_card.dart';
import 'package:shavtzak/presentation/screens/task/edit/event_assignments_quick_view.dart';

final _now = DateTime(2026, 5, 4, 10);

final _event = Event(
  id: 'event-1',
  name: 'דו יומי מאי',
  startDate: DateTime(2026, 5, 4),
  endDate: DateTime(2026, 5, 5),
  startTime: '08:00',
  endTime: '22:00',
  assemblyTime: '07:30',
  location: 'מצפה רמון',
  comments: '',
  requiresArmed: false,
  roleRequirements: const {'commander': 1, 'medic': 1},
  createdAt: _now,
  updatedAt: _now,
);

Role _role(String key, String name, int order) => Role(
      id: key,
      key: key,
      hebrewName: name,
      sortOrder: order,
      createdAt: _now,
      updatedAt: _now,
    );

TeamMember _member(String id, String name) => TeamMember(
      id: id,
      name: name,
      isActive: true,
      isPermanent: true,
      constraints: const [],
      roleCapabilities: const {},
      createdAt: _now,
      updatedAt: _now,
      uniqueKey: 'unique-$id',
    );

Assignment _assignment(
  String id,
  String role,
  TeamMember member, {
  String notes = '',
  String? customStartAt,
  String? customEndAt,
}) =>
    Assignment(
      id: id,
      eventId: 'event-1',
      teamMemberId: member.id,
      roleType: role,
      slotIndex: 0,
      status: AssignmentStatus.confirmed,
      notes: notes,
      customStartAt: customStartAt,
      customEndAt: customEndAt,
      createdAt: _now,
      updatedAt: _now,
      teamMember: member,
    );

void main() {
  final roles = [_role('commander', 'מפקד', 0), _role('medic', 'חובש', 1)];

  Future<StreamController<List<Assignment>>> pump(
    WidgetTester tester, {
    bool rolesLoaded = true,
    double width = 400,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final assignments = StreamController<List<Assignment>>();
    addTearDown(assignments.close);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EventAssignmentsQuickViewBody(
          event: _event,
          assignments: assignments.stream,
          labels: Stream<List<AssignmentLabel>>.value(const []),
          activeRoles: rolesLoaded ? roles : null,
          onClose: () {},
        ),
      ),
    ));
    return assignments;
  }

  testWidgets('shows the export picture: roles, names, notes and hours',
      (tester) async {
    final assignments = await pump(tester);
    assignments.add([
      _assignment('a1', 'commander', _member('m1', 'דנה'), notes: 'מביאה רכב'),
      _assignment(
        'a2',
        'medic',
        _member('m2', 'יוסי'),
        customStartAt: '2026-05-04T12:00',
        customEndAt: '2026-05-04T18:00',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.byType(EventAssignmentsShareCard), findsOneWidget);
    expect(find.textContaining('דנה'), findsOneWidget);
    expect(find.textContaining('מביאה רכב'), findsOneWidget);
    expect(find.textContaining('יוסי'), findsOneWidget);
    expect(find.textContaining('שעות'), findsOneWidget);
    // All of it inside the panel, no scrolling, roles side by side.
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsNothing);
    final shown = tester.getRect(find.byType(EventAssignmentsShareCard));
    expect(shown.left, greaterThanOrEqualTo(0));
    expect(shown.right, lessThanOrEqualTo(400));
    expect(shown.bottom, lessThanOrEqualTo(900));
    expect(tester.getTopLeft(find.text('מפקד')).dy,
        tester.getTopLeft(find.text('חובש')).dy);
  });

  testWidgets('on a wide window the picture is at most 720 px wide',
      (tester) async {
    final assignments = await pump(tester, width: 1400);
    assignments.add([_assignment('a1', 'commander', _member('m1', 'דנה'))]);
    await tester.pumpAndSettle();
    final shown = tester.getRect(find.byType(EventAssignmentsShareCard));
    expect(shown.width, lessThanOrEqualTo(720));
    expect(shown.width, greaterThan(700));
  });

  testWidgets('the close button is larger on a wide window', (tester) async {
    double iconSize() => tester
        .widget<IconButton>(
            find.byKey(const Key('assignments-quick-view-close')))
        .iconSize!;
    await pump(tester, width: 1400);
    expect(iconSize(), 36);
    await pump(tester, width: 400);
    expect(iconSize(), 24);
  });

  testWidgets('redraws as the assignments change', (tester) async {
    final assignments = await pump(tester);
    assignments.add([_assignment('a1', 'commander', _member('m1', 'דנה'))]);
    await tester.pumpAndSettle();
    expect(find.textContaining('דנה'), findsOneWidget);

    assignments.add([_assignment('a1', 'commander', _member('m3', 'רון'))]);
    await tester.pumpAndSettle();
    expect(find.textContaining('דנה'), findsNothing);
    expect(find.textContaining('רון'), findsOneWidget);
  });

  testWidgets('says so when nobody is assigned', (tester) async {
    final assignments = await pump(tester);
    assignments.add(const []);
    await tester.pumpAndSettle();
    expect(find.text('אין עדיין שיבוצים לאירוע'), findsOneWidget);
    expect(find.byType(EventAssignmentsShareCard), findsNothing);
  });

  testWidgets('waits while the roles are loading', (tester) async {
    final assignments = await pump(tester, rolesLoaded: false);
    assignments.add([_assignment('a1', 'commander', _member('m1', 'דנה'))]);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
