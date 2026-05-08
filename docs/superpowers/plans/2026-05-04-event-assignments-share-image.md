# Event Assignments Share Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an image-first WhatsApp sharing flow for event assignments, including a compact RTL generated image with numbered full-note footnotes.

**Architecture:** Extract share-specific grouping and formatting into pure data helpers, render that data with a dedicated share-card widget, and capture the visible preview card to PNG with `RepaintBoundary`. Web share and image clipboard support live behind a conditional platform service; when direct sharing/copying is unavailable, the same preview remains as clean screenshot mode.

**Tech Stack:** Flutter Web, Dart, `flutter_bloc`, `flutter_test`, `dart:ui` image capture, conditional `dart:html`/`dart:js_util` web interop, existing Shavtzak repositories and entities.

---

## File Structure

- Create `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_models.dart`
  - Owns `EventAssignmentsGroupingMode`, share-card data classes, and result-free presentation models.
- Create `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_data_builder.dart`
  - Builds ordered share-card data from `Event`, assignments, roles, and labels.
  - Formats event dates, times, and coordinate-stripped location.
  - Assigns note numbers in visual order.
- Create `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_card.dart`
  - Pure RTL widget that renders the generated image content.
  - No phone UI, no assignment status chips, no scroll views, no note truncation.
- Create `shavtzak/lib/core/services/assignment_share_image_service.dart`
  - Public facade for image sharing.
- Create `shavtzak/lib/core/services/assignment_share_image_result.dart`
  - Owns `AssignmentShareImageResult` so platform implementations do not import the facade that conditionally imports them.
- Create `shavtzak/lib/core/services/assignment_share_image_service_stub.dart`
  - Non-web fallback returning `needsManualScreenshot`.
- Create `shavtzak/lib/core/services/assignment_share_image_service_web.dart`
  - Web implementation for Web Share API file sharing and image clipboard writes.
- Create `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_preview_dialog.dart`
  - Full-screen preview/screenshot mode.
  - Captures the visible share card to PNG and triggers the share service.
- Modify `shavtzak/lib/presentation/screens/event/widgets/event_assignments_dialog.dart`
  - Accept full `Event` instead of only `eventId`/`eventName`.
  - Add the share-image header button.
  - Fetch fresh assignments, labels, and roles for the share preview.
- Modify `shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart`
  - Pass `data.event` into `EventAssignmentsDialog.withAssignments(...)`.
- Create `shavtzak/test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart`
  - Pure helper coverage for grouping, event details, and full note numbering.
- Create `shavtzak/test/presentation/screens/event/widgets/event_assignments_share_card_test.dart`
  - Widget coverage for rendered note references and omitted phone/status concepts.

---

### Task 1: Share Data Models And Builder

**Files:**
- Create: `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_models.dart`
- Create: `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_data_builder.dart`
- Test: `shavtzak/test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart`

- [ ] **Step 1: Write failing builder tests**

Create `shavtzak/test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/assignment_label.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/role.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_data_builder.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_models.dart';

void main() {
  group('EventAssignmentsShareDataBuilder', () {
    test('builds role-grouped data with full numbered notes in visual order', () {
      final now = DateTime(2026, 5, 4, 10);
      final event = _event(now);
      final roles = [
        _role('commander', 'מפקד אירוע', 0),
        _role('medic', 'חובשים', 1),
      ];
      final assignments = [
        _assignment(
          id: 'a2',
          roleType: 'medic',
          slotIndex: 0,
          member: _member('m2', 'מיכל ישראלי', phoneNumber: '0501111111'),
          notes: 'הערה מלאה שלא מתקצרת גם כאשר היא ארוכה יחסית.',
          alternativePhoneNumber: '0502222222',
          status: AssignmentStatus.pending,
        ),
        _assignment(
          id: 'a1',
          roleType: 'commander',
          slotIndex: 0,
          member: _member('m1', 'נועה כהן'),
          notes: 'מגיעה מהכניסה הראשית.',
        ),
        _assignment(
          id: 'a3',
          roleType: 'medic',
          slotIndex: 1,
          member: _member('m3', 'אורי ברק'),
        ),
      ];

      final data = EventAssignmentsShareDataBuilder.build(
        event: event,
        assignments: assignments,
        activeRoles: roles,
        labels: const [],
        groupingMode: EventAssignmentsGroupingMode.role,
      );

      expect(data.eventName, 'טקס פתיחה');
      expect(data.dateLine, 'יום שני 4 במאי');
      expect(data.timeLine, 'התייצבות - 17:00 | התכנסות - 18:00 | תחילת מופע - 19:30 | סיום - 22:00');
      expect(data.locationLine, 'היכל התרבות');
      expect(data.sections.map((section) => section.title), ['מפקד אירוע', 'חובשים']);
      expect(data.sections[0].rows.single.memberName, 'נועה כהן');
      expect(data.sections[0].rows.single.noteNumber, 1);
      expect(data.sections[1].rows.map((row) => row.memberName), ['אורי ברק', 'מיכל ישראלי']);
      expect(data.sections[1].rows.last.noteNumber, 2);
      expect(data.notes.map((note) => '${note.number}:${note.memberName}:${note.text}'), [
        '1:נועה כהן:מגיעה מהכניסה הראשית.',
        '2:מיכל ישראלי:הערה מלאה שלא מתקצרת גם כאשר היא ארוכה יחסית.',
      ]);
    });

    test('builds label-grouped data with unlabeled assignments last', () {
      final now = DateTime(2026, 5, 4, 10);
      final roles = [_role('medic', 'חובשים', 0)];
      final vip = AssignmentLabel(
        id: 'label-vip',
        key: 'label-vip',
        hebrewName: 'כניסה ראשית',
        color: '#2563EB',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );
      final assignments = [
        _assignment(
          id: 'a1',
          roleType: 'medic',
          slotIndex: 0,
          member: _member('m1', 'נועה כהן'),
          semanticLabelId: vip.id,
        ),
        _assignment(
          id: 'a2',
          roleType: 'medic',
          slotIndex: 1,
          member: _member('m2', 'אורי ברק'),
        ),
      ];

      final data = EventAssignmentsShareDataBuilder.build(
        event: _event(now),
        assignments: assignments,
        activeRoles: roles,
        labels: [vip],
        groupingMode: EventAssignmentsGroupingMode.label,
      );

      expect(data.sections.map((section) => section.title), ['כניסה ראשית', 'ללא לייבל']);
      expect(data.sections.first.children.single.title, 'חובשים');
      expect(data.sections.first.children.single.rows.single.memberName, 'נועה כהן');
      expect(data.sections.last.children.single.rows.single.memberName, 'אורי ברק');
    });
  });
}

Event _event(DateTime now) {
  return Event(
    id: 'event-1',
    name: 'טקס פתיחה',
    startDate: DateTime(2026, 5, 4),
    endDate: DateTime(2026, 5, 4),
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    actualShowStartTime: '19:30',
    location: 'היכל התרבות||32.1,34.8',
    requiresArmed: false,
    roleRequirements: const {'commander': 1, 'medic': 2},
    createdAt: now,
    updatedAt: now,
  );
}

Role _role(String key, String hebrewName, int sortOrder) {
  final now = DateTime(2026, 5, 4, 10);
  return Role(
    id: key,
    key: key,
    hebrewName: hebrewName,
    sortOrder: sortOrder,
    createdAt: now,
    updatedAt: now,
  );
}

TeamMember _member(String id, String name, {String? phoneNumber}) {
  final now = DateTime(2026, 5, 4, 10);
  return TeamMember(
    id: id,
    name: name,
    isActive: true,
    isPermanent: true,
    constraints: const [],
    roleCapabilities: const {},
    createdAt: now,
    updatedAt: now,
    uniqueKey: 'unique-$id',
    phoneNumber: phoneNumber,
  );
}

Assignment _assignment({
  required String id,
  required String roleType,
  required int slotIndex,
  required TeamMember member,
  String notes = '',
  String? semanticLabelId,
  String? alternativePhoneNumber,
  AssignmentStatus status = AssignmentStatus.confirmed,
}) {
  final now = DateTime(2026, 5, 4, 10);
  return Assignment(
    id: id,
    eventId: 'event-1',
    teamMemberId: member.id,
    roleType: roleType,
    slotIndex: slotIndex,
    status: status,
    notes: notes,
    semanticLabelId: semanticLabelId,
    alternativePhoneNumber: alternativePhoneNumber,
    createdAt: now,
    updatedAt: now,
    teamMember: member,
  );
}
```

- [ ] **Step 2: Run builder tests to verify they fail**

Run from `shavtzak/`:

```bash
flutter test test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart
```

Expected: FAIL because `event_assignments_share_data_builder.dart` and `event_assignments_share_models.dart` do not exist.

- [ ] **Step 3: Add share data models**

Create `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_models.dart`:

```dart
enum EventAssignmentsGroupingMode {
  role,
  label,
}

class EventAssignmentsShareData {
  final String eventName;
  final String dateLine;
  final String timeLine;
  final String locationLine;
  final List<EventAssignmentsShareSection> sections;
  final List<EventAssignmentsShareNote> notes;

  const EventAssignmentsShareData({
    required this.eventName,
    required this.dateLine,
    required this.timeLine,
    required this.locationLine,
    required this.sections,
    required this.notes,
  });
}

class EventAssignmentsShareSection {
  final String title;
  final List<EventAssignmentsShareRow> rows;
  final List<EventAssignmentsShareSection> children;

  const EventAssignmentsShareSection({
    required this.title,
    this.rows = const [],
    this.children = const [],
  });

  bool get hasChildren => children.isNotEmpty;
}

class EventAssignmentsShareRow {
  final String memberName;
  final int? noteNumber;

  const EventAssignmentsShareRow({
    required this.memberName,
    this.noteNumber,
  });
}

class EventAssignmentsShareNote {
  final int number;
  final String memberName;
  final String text;

  const EventAssignmentsShareNote({
    required this.number,
    required this.memberName,
    required this.text,
  });
}
```

- [ ] **Step 4: Add the share data builder**

Create `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_data_builder.dart`:

```dart
import '../../../../domain/entities/assignment.dart';
import '../../../../domain/entities/assignment_label.dart';
import '../../../../domain/entities/event.dart';
import '../../../../domain/entities/role.dart';
import '../../../widgets/map_location_picker.dart';
import 'event_assignments_share_models.dart';

class EventAssignmentsShareDataBuilder {
  static EventAssignmentsShareData build({
    required Event event,
    required List<Assignment> assignments,
    required List<Role> activeRoles,
    required List<AssignmentLabel> labels,
    required EventAssignmentsGroupingMode groupingMode,
  }) {
    final context = _BuildContext();
    final labeledAssignments = _applyAssignmentLabels(assignments, labels);
    final sections = groupingMode == EventAssignmentsGroupingMode.label
        ? _buildLabelSections(context, activeRoles, labeledAssignments)
        : _buildRoleSections(context, activeRoles, labeledAssignments);

    return EventAssignmentsShareData(
      eventName: event.name,
      dateLine: _formatEventDatesHebrew(event),
      timeLine: _formatTimeFields(event),
      locationLine: _formatLocationForDisplay(event.location),
      sections: sections,
      notes: context.notes,
    );
  }

  static List<Assignment> _applyAssignmentLabels(
    List<Assignment> assignments,
    List<AssignmentLabel> labels,
  ) {
    if (assignments.isEmpty || labels.isEmpty) {
      return assignments;
    }

    final labelsById = {for (final label in labels) label.id: label};
    return assignments.map((assignment) {
      return assignment.copyWith(
        semanticLabel: () => assignment.semanticLabelId == null
            ? null
            : labelsById[assignment.semanticLabelId!],
      );
    }).toList();
  }

  static List<EventAssignmentsShareSection> _buildRoleSections(
    _BuildContext context,
    List<Role> activeRoles,
    List<Assignment> assignments,
  ) {
    final assignmentsByRole = <String, List<Assignment>>{};
    for (final assignment in assignments) {
      assignmentsByRole.putIfAbsent(assignment.roleType, () => []);
      assignmentsByRole[assignment.roleType]!.add(assignment);
    }

    final sections = <EventAssignmentsShareSection>[];
    for (final role in activeRoles) {
      final roleAssignments = assignmentsByRole[role.key];
      if (roleAssignments == null || roleAssignments.isEmpty) {
        continue;
      }

      sections.add(
        EventAssignmentsShareSection(
          title: role.hebrewName,
          rows: _sortAssignmentsWithinRoleGroup(roleAssignments)
              .map(context.rowFor)
              .whereType<EventAssignmentsShareRow>()
              .toList(),
        ),
      );
    }
    return sections;
  }

  static List<EventAssignmentsShareSection> _buildLabelSections(
    _BuildContext context,
    List<Role> activeRoles,
    List<Assignment> assignments,
  ) {
    final labeledAssignments = <AssignmentLabel, List<Assignment>>{};
    final unlabeledAssignments = <Assignment>[];

    for (final assignment in assignments) {
      final label = assignment.semanticLabel;
      if (label == null) {
        unlabeledAssignments.add(assignment);
      } else {
        labeledAssignments.putIfAbsent(label, () => []);
        labeledAssignments[label]!.add(assignment);
      }
    }

    final orderedLabels = labeledAssignments.keys.toList()
      ..sort((a, b) {
        final bySortOrder = a.sortOrder.compareTo(b.sortOrder);
        if (bySortOrder != 0) return bySortOrder;
        return a.hebrewName.compareTo(b.hebrewName);
      });

    final sections = <EventAssignmentsShareSection>[
      for (final label in orderedLabels)
        _buildSingleLabelSection(
          context: context,
          title: label.hebrewName,
          assignments: labeledAssignments[label]!,
          activeRoles: activeRoles,
        ),
    ];

    if (unlabeledAssignments.isNotEmpty) {
      sections.add(
        _buildSingleLabelSection(
          context: context,
          title: 'ללא לייבל',
          assignments: unlabeledAssignments,
          activeRoles: activeRoles,
        ),
      );
    }

    return sections;
  }

  static EventAssignmentsShareSection _buildSingleLabelSection({
    required _BuildContext context,
    required String title,
    required List<Assignment> assignments,
    required List<Role> activeRoles,
  }) {
    final roleSections = <EventAssignmentsShareSection>[];

    for (final role in activeRoles) {
      final roleAssignments = assignments
          .where((assignment) => assignment.roleType == role.key)
          .toList();
      if (roleAssignments.isEmpty) {
        continue;
      }

      roleSections.add(
        EventAssignmentsShareSection(
          title: role.hebrewName,
          rows: _sortAssignmentsAlphabetically(roleAssignments)
              .map(context.rowFor)
              .whereType<EventAssignmentsShareRow>()
              .toList(),
        ),
      );
    }

    return EventAssignmentsShareSection(
      title: title,
      children: roleSections,
    );
  }

  static List<Assignment> _sortAssignmentsWithinRoleGroup(
    List<Assignment> assignments,
  ) {
    final sortedAssignments = List<Assignment>.from(assignments);
    sortedAssignments.sort((a, b) {
      final aLabel = a.semanticLabel;
      final bLabel = b.semanticLabel;

      if (aLabel == null && bLabel != null) return 1;
      if (aLabel != null && bLabel == null) return -1;
      if (aLabel != null && bLabel != null) {
        final bySortOrder = aLabel.sortOrder.compareTo(bLabel.sortOrder);
        if (bySortOrder != 0) return bySortOrder;

        final byLabelName = aLabel.hebrewName.compareTo(bLabel.hebrewName);
        if (byLabelName != 0) return byLabelName;
      }

      final byName = (a.teamMember?.name ?? '').compareTo(b.teamMember?.name ?? '');
      if (byName != 0) return byName;

      final bySlotIndex = a.slotIndex.compareTo(b.slotIndex);
      if (bySlotIndex != 0) return bySlotIndex;

      return a.id.compareTo(b.id);
    });
    return sortedAssignments;
  }

  static List<Assignment> _sortAssignmentsAlphabetically(
    List<Assignment> assignments,
  ) {
    final sortedAssignments = List<Assignment>.from(assignments);
    sortedAssignments.sort((a, b) {
      final byName = (a.teamMember?.name ?? '').compareTo(b.teamMember?.name ?? '');
      if (byName != 0) return byName;

      final byRole = a.roleType.compareTo(b.roleType);
      if (byRole != 0) return byRole;

      final bySlotIndex = a.slotIndex.compareTo(b.slotIndex);
      if (bySlotIndex != 0) return bySlotIndex;

      return a.id.compareTo(b.id);
    });
    return sortedAssignments;
  }

  static String _formatEventDatesHebrew(Event event) {
    final isSameDay = event.startDate.year == event.endDate.year &&
        event.startDate.month == event.endDate.month &&
        event.startDate.day == event.endDate.day;

    if (isSameDay) {
      return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} ${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)}';
    }
    return 'יום ${_getFullHebrewDayName(event.startDate.weekday)} ${event.startDate.day} ב${_getHebrewMonthName(event.startDate.month)} - יום ${_getFullHebrewDayName(event.endDate.weekday)} ${event.endDate.day} ב${_getHebrewMonthName(event.endDate.month)}';
  }

  static String _formatTimeFields(Event event) {
    final parts = <String>[];
    if (event.assemblyTime.isNotEmpty) {
      parts.add('התייצבות - ${event.assemblyTime}');
    }
    if (event.startTime.isNotEmpty) {
      parts.add('התכנסות - ${event.startTime}');
    }
    if (event.actualShowStartTime.isNotEmpty) {
      parts.add('תחילת מופע - ${event.actualShowStartTime}');
    }
    if (event.endTime.isNotEmpty) {
      parts.add('סיום - ${event.endTime}');
    }
    return parts.join(' | ');
  }

  static String _formatLocationForDisplay(String location) {
    if (location.contains('||')) {
      final strippedLocation = MapLocationResult.stripCoordinates(location);
      return strippedLocation.isNotEmpty ? strippedLocation : location;
    }
    return location;
  }

  static String _getFullHebrewDayName(int weekday) {
    const days = ['', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת', 'ראשון'];
    return days[weekday];
  }

  static String _getHebrewMonthName(int month) {
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
    return months[month];
  }
}

class _BuildContext {
  final List<EventAssignmentsShareNote> notes = [];

  _BuildContext();

  EventAssignmentsShareRow? rowFor(Assignment assignment) {
    final member = assignment.teamMember;
    if (member == null) {
      return null;
    }

    final trimmedNote = assignment.notes.trim();
    int? noteNumber;
    if (trimmedNote.isNotEmpty) {
      noteNumber = notes.length + 1;
      notes.add(
        EventAssignmentsShareNote(
          number: noteNumber,
          memberName: member.name,
          text: trimmedNote,
        ),
      );
    }

    return EventAssignmentsShareRow(
      memberName: member.name,
      noteNumber: noteNumber,
    );
  }
}
```

- [ ] **Step 5: Run builder tests to verify they pass**

Run from `shavtzak/`:

```bash
flutter test test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit Task 1**

Run from the repository root:

```bash
git add shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_models.dart \
  shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_data_builder.dart \
  shavtzak/test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart
git commit -m "Add event assignments share data builder"
```

---

### Task 2: Share Card Widget

**Files:**
- Create: `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_card.dart`
- Test: `shavtzak/test/presentation/screens/event/widgets/event_assignments_share_card_test.dart`

- [ ] **Step 1: Write failing share-card widget tests**

Create `shavtzak/test/presentation/screens/event/widgets/event_assignments_share_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_card.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_assignments_share_models.dart';

void main() {
  testWidgets('renders event details, names, note refs, and full notes', (tester) async {
    final data = EventAssignmentsShareData(
      eventName: 'טקס פתיחה',
      dateLine: 'יום שני 4 במאי',
      timeLine: 'התייצבות - 17:00 | תחילת מופע - 19:30',
      locationLine: 'היכל התרבות',
      sections: const [
        EventAssignmentsShareSection(
          title: 'מפקד אירוע',
          rows: [
            EventAssignmentsShareRow(memberName: 'נועה כהן', noteNumber: 1),
            EventAssignmentsShareRow(memberName: 'דניאל לוי'),
          ],
        ),
      ],
      notes: const [
        EventAssignmentsShareNote(
          number: 1,
          memberName: 'נועה כהן',
          text: 'מגיעה ישירות מהכניסה הראשית בלי קיצור של הטקסט.',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventAssignmentsShareCard(data: data),
        ),
      ),
    );

    expect(find.text('טקס פתיחה'), findsOneWidget);
    expect(find.text('יום שני 4 במאי'), findsOneWidget);
    expect(find.text('התייצבות - 17:00 | תחילת מופע - 19:30'), findsOneWidget);
    expect(find.text('היכל התרבות'), findsOneWidget);
    expect(find.text('מפקד אירוע'), findsOneWidget);
    expect(find.text('נועה כהן'), findsOneWidget);
    expect(find.text('(1)'), findsOneWidget);
    expect(
      find.textContaining(
        'נועה כהן: מגיעה ישירות מהכניסה הראשית',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('טלפון'), findsNothing);
    expect(find.textContaining('ממתין'), findsNothing);
    expect(find.textContaining('נדחה'), findsNothing);
  });
}
```

- [ ] **Step 2: Run card tests to verify they fail**

Run from `shavtzak/`:

```bash
flutter test test/presentation/screens/event/widgets/event_assignments_share_card_test.dart
```

Expected: FAIL because `event_assignments_share_card.dart` does not exist.

- [ ] **Step 3: Add the share-card widget**

Create `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_card.dart`:

```dart
import 'package:flutter/material.dart';

import 'event_assignments_share_models.dart';

class EventAssignmentsShareCard extends StatelessWidget {
  final EventAssignmentsShareData data;

  const EventAssignmentsShareCard({
    super.key,
    required this.data,
  });

  static const double captureWidth = 1080;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.white,
        child: Container(
          width: captureWidth,
          color: Colors.white,
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 28),
              _buildSections(),
              if (data.notes.isNotEmpty) ...[
                const SizedBox(height: 28),
                _buildNotes(),
              ],
              const SizedBox(height: 18),
              Text(
                'נוצר משבצק',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final detailLines = [
      data.dateLine,
      if (data.timeLine.isNotEmpty) data.timeLine,
      if (data.locationLine.isNotEmpty) data.locationLine,
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          children: [
            Text(
              data.eventName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 12),
            for (final line in detailLines)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  line,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.25,
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSections() {
    return Wrap(
      spacing: 18,
      runSpacing: 18,
      alignment: WrapAlignment.start,
      children: [
        for (final section in data.sections)
          _ShareSectionTile(section: section),
      ],
    );
  }

  Widget _buildNotes() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFDF4FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9D5FF), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'הערות',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B21A8),
              ),
            ),
            const SizedBox(height: 10),
            for (final note in data.notes)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '(${note.number}) ',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(
                        text: '${note.memberName}: ${note.text}',
                      ),
                    ],
                  ),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 21,
                    height: 1.35,
                    color: Color(0xFF4C1D95),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShareSectionTile extends StatelessWidget {
  final EventAssignmentsShareSection section;

  const _ShareSectionTile({required this.section});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: section.hasChildren ? 494 : 238,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                section.title,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(height: 8),
              if (section.hasChildren)
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final child in section.children)
                      SizedBox(
                        width: 218,
                        child: _NestedShareSection(section: child),
                      ),
                  ],
                )
              else
                _ShareRows(rows: section.rows),
            ],
          ),
        ),
      ),
    );
  }
}

class _NestedShareSection extends StatelessWidget {
  final EventAssignmentsShareSection section;

  const _NestedShareSection({required this.section});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          section.title,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1D4ED8),
          ),
        ),
        const SizedBox(height: 5),
        _ShareRows(rows: section.rows),
      ],
    );
  }
}

class _ShareRows extends StatelessWidget {
  final List<EventAssignmentsShareRow> rows;

  const _ShareRows({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: row.memberName),
                  if (row.noteNumber != null)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.top,
                      child: Text(
                        '(${row.noteNumber})',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF7E22CE),
                        ),
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 22,
                height: 1.25,
                color: Color(0xFF111827),
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run card tests to verify they pass**

Run from `shavtzak/`:

```bash
flutter test test/presentation/screens/event/widgets/event_assignments_share_card_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

Run from the repository root:

```bash
git add shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_card.dart \
  shavtzak/test/presentation/screens/event/widgets/event_assignments_share_card_test.dart
git commit -m "Add event assignments share card"
```

---

### Task 3: Web Image Sharing Service

**Files:**
- Create: `shavtzak/lib/core/services/assignment_share_image_service.dart`
- Create: `shavtzak/lib/core/services/assignment_share_image_result.dart`
- Create: `shavtzak/lib/core/services/assignment_share_image_service_stub.dart`
- Create: `shavtzak/lib/core/services/assignment_share_image_service_web.dart`

- [ ] **Step 1: Add the result enum, platform facade, and stub**

Create `shavtzak/lib/core/services/assignment_share_image_result.dart`:

```dart
enum AssignmentShareImageResult {
  shared,
  copiedImage,
  needsManualScreenshot,
}
```

Create `shavtzak/lib/core/services/assignment_share_image_service.dart`:

```dart
import 'dart:typed_data';

export 'assignment_share_image_result.dart';

import 'assignment_share_image_service_stub.dart'
    if (dart.library.html) 'assignment_share_image_service_web.dart'
    as platform;
import 'assignment_share_image_result.dart';

class AssignmentShareImageService {
  Future<AssignmentShareImageResult> sharePng({
    required Uint8List pngBytes,
    required String filename,
    required String title,
    required String text,
  }) {
    return platform.shareAssignmentPng(
      pngBytes: pngBytes,
      filename: filename,
      title: title,
      text: text,
    );
  }
}
```

Create `shavtzak/lib/core/services/assignment_share_image_service_stub.dart`:

```dart
import 'dart:typed_data';

import 'assignment_share_image_result.dart';

Future<AssignmentShareImageResult> shareAssignmentPng({
  required Uint8List pngBytes,
  required String filename,
  required String title,
  required String text,
}) async {
  return AssignmentShareImageResult.needsManualScreenshot;
}
```

- [ ] **Step 2: Add the web implementation**

Create `shavtzak/lib/core/services/assignment_share_image_service_web.dart`:

```dart
import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'assignment_share_image_result.dart';

Future<AssignmentShareImageResult> shareAssignmentPng({
  required Uint8List pngBytes,
  required String filename,
  required String title,
  required String text,
}) async {
  final blob = html.Blob([pngBytes], 'image/png');

  final shared = await _tryNativeShare(
    blob: blob,
    filename: filename,
    title: title,
    text: text,
  );
  if (shared) {
    return AssignmentShareImageResult.shared;
  }

  final copied = await _tryImageClipboard(blob);
  if (copied) {
    return AssignmentShareImageResult.copiedImage;
  }

  return AssignmentShareImageResult.needsManualScreenshot;
}

Future<bool> _tryNativeShare({
  required html.Blob blob,
  required String filename,
  required String title,
  required String text,
}) async {
  try {
    final navigator = html.window.navigator;
    if (!js_util.hasProperty(navigator, 'share')) {
      return false;
    }

    final fileConstructor = js_util.getProperty(html.window, 'File');
    if (fileConstructor == null) {
      return false;
    }

    final file = js_util.callConstructor(fileConstructor, [
      [blob],
      filename,
      {'type': 'image/png'},
    ]);

    final shareData = js_util.jsify({
      'title': title,
      'text': text,
      'files': [file],
    });

    if (js_util.hasProperty(navigator, 'canShare')) {
      final canShare = js_util.callMethod(navigator, 'canShare', [shareData]) == true;
      if (!canShare) {
        return false;
      }
    }

    await js_util.promiseToFuture<void>(
      js_util.callMethod(navigator, 'share', [shareData]),
    );
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _tryImageClipboard(html.Blob blob) async {
  try {
    final navigator = html.window.navigator;
    final clipboard = js_util.getProperty(navigator, 'clipboard');
    if (clipboard == null) {
      return false;
    }

    final clipboardItemConstructor = js_util.getProperty(html.window, 'ClipboardItem');
    if (clipboardItemConstructor == null) {
      return false;
    }

    final item = js_util.callConstructor(clipboardItemConstructor, [
      js_util.jsify({'image/png': blob}),
    ]);

    await js_util.promiseToFuture<void>(
      js_util.callMethod(clipboard, 'write', [
        js_util.jsify([item]),
      ]),
    );
    return true;
  } catch (_) {
    return false;
  }
}
```

- [ ] **Step 3: Run analyzer for the service files**

Run from `shavtzak/`:

```bash
flutter analyze
```

Expected: PASS or only pre-existing unrelated analyzer output. If the web interop code has analyzer errors, fix the signatures in `assignment_share_image_service_web.dart` before continuing.

- [ ] **Step 4: Commit Task 3**

Run from the repository root:

```bash
git add shavtzak/lib/core/services/assignment_share_image_result.dart \
  shavtzak/lib/core/services/assignment_share_image_service.dart \
  shavtzak/lib/core/services/assignment_share_image_service_stub.dart \
  shavtzak/lib/core/services/assignment_share_image_service_web.dart
git commit -m "Add assignment share image service"
```

---

### Task 4: Share Preview Dialog And PNG Capture

**Files:**
- Create: `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_preview_dialog.dart`

- [ ] **Step 1: Add the preview dialog with visible-card capture**

Create `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_preview_dialog.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/services/assignment_share_image_service.dart';
import 'event_assignments_share_card.dart';
import 'event_assignments_share_models.dart';

class EventAssignmentsSharePreviewDialog extends StatefulWidget {
  final EventAssignmentsShareData data;
  final bool autoStartShare;

  const EventAssignmentsSharePreviewDialog({
    super.key,
    required this.data,
    this.autoStartShare = true,
  });

  @override
  State<EventAssignmentsSharePreviewDialog> createState() =>
      _EventAssignmentsSharePreviewDialogState();
}

class _EventAssignmentsSharePreviewDialogState
    extends State<EventAssignmentsSharePreviewDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _isSharing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.autoStartShare) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _shareImage());
    }
  }

  Future<void> _shareImage() async {
    if (_isSharing) return;
    setState(() {
      _isSharing = true;
      _message = 'מכין תמונה לשיתוף...';
    });

    try {
      final pngBytes = await _capturePng();
      final result = await AssignmentShareImageService().sharePng(
        pngBytes: pngBytes,
        filename: _filenameFor(widget.data.eventName),
        title: widget.data.eventName,
        text: widget.data.eventName,
      );

      if (!mounted) return;
      setState(() {
        _isSharing = false;
        _message = switch (result) {
          AssignmentShareImageResult.shared => 'התמונה נשלחה לשיתוף',
          AssignmentShareImageResult.copiedImage => 'התמונה הועתקה ללוח',
          AssignmentShareImageResult.needsManualScreenshot =>
            'אפשר לצלם את המסך הזה כתמונה אחת',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSharing = false;
        _message = 'אפשר לצלם את המסך הזה כתמונה אחת';
      });
    }
  }

  Future<Uint8List> _capturePng() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Share card is not ready for capture');
    }

    final image = await boundary.toImage(pixelRatio: 2.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Could not encode share card PNG');
    }

    return byteData.buffer.asUint8List();
  }

  String _filenameFor(String eventName) {
    final sanitized = eventName
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'\s+'), '-')
        .trim();
    return 'shavtzak-$sanitized-assignments.png';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text('תמונת שיבוצים'),
            actions: [
              IconButton(
                tooltip: 'סגירה',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          body: Column(
            children: [
              if (_message != null || _isSharing)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                    children: [
                      if (_isSharing) ...[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          _message ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.fitWidth,
                      alignment: Alignment.topCenter,
                      child: RepaintBoundary(
                        key: _boundaryKey,
                        child: EventAssignmentsShareCard(data: widget.data),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: FilledButton.icon(
                    onPressed: _isSharing ? null : _shareImage,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('נסה לשתף תמונה'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyzer for the preview dialog**

Run from `shavtzak/`:

```bash
flutter analyze
```

Expected: PASS or only pre-existing unrelated analyzer output. Fix any errors introduced by `event_assignments_share_preview_dialog.dart`.

- [ ] **Step 3: Commit Task 4**

Run from the repository root:

```bash
git add shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_preview_dialog.dart
git commit -m "Add event assignments share preview"
```

---

### Task 5: Wire The Dialog And Event Entry Point

**Files:**
- Modify: `shavtzak/lib/presentation/screens/event/widgets/event_assignments_dialog.dart`
- Modify: `shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart`

- [ ] **Step 1: Update `EventAssignmentsDialog` imports and fields**

In `shavtzak/lib/presentation/screens/event/widgets/event_assignments_dialog.dart`, add imports:

```dart
import '../../../../data/repositories/role_repository.dart';
import '../../../../domain/entities/event.dart';
import 'event_assignments_share_data_builder.dart';
import 'event_assignments_share_models.dart';
import 'event_assignments_share_preview_dialog.dart';
```

Replace the widget fields and constructors with:

```dart
class EventAssignmentsDialog extends StatefulWidget {
  final Event event;
  final List<Assignment>? assignments;

  const EventAssignmentsDialog({
    super.key,
    required this.event,
    this.assignments,
  });

  const EventAssignmentsDialog.withAssignments({
    super.key,
    required this.event,
    required this.assignments,
  }) : assert(assignments != null,
            'assignments cannot be null in withAssignments constructor');

  String get eventId => event.id;
  String get eventName => event.name;

  @override
  State<EventAssignmentsDialog> createState() => _EventAssignmentsDialogState();
}
```

- [ ] **Step 2: Replace direct event id/name reads**

In `EventAssignmentsDialog`, keep existing `widget.eventId` and `widget.eventName` call sites working through the getters added in Step 1. Confirm `initState`, `watchAssignmentsByEvent`, and `LoadAssignmentsByEvent` still refer to `widget.eventId`.

- [ ] **Step 3: Add the share button to the header**

In the header `Row`, before the close `IconButton`, add:

```dart
IconButton(
  tooltip: 'שתף תמונת שיבוצים',
  icon: const Icon(Icons.ios_share),
  onPressed: _openSharePreview,
),
```

Then add this method inside `_EventAssignmentsDialogState`:

```dart
Future<void> _openSharePreview() async {
  try {
    final labels = await context.read<AssignmentLabelRepository>().getAssignmentLabels();
    final assignments = _applyAssignmentLabels(
      await context.read<AssignmentRepository>().getAssignmentsByEvent(widget.eventId),
      labels,
    );
    final activeRoles = await context.read<RoleRepository>().getActiveRoles();

    if (!mounted) return;
    if (assignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אין שיבוצים לשיתוף')),
      );
      return;
    }

    final shareData = EventAssignmentsShareDataBuilder.build(
      event: widget.event,
      assignments: assignments,
      activeRoles: activeRoles,
      labels: labels,
      groupingMode: _sortByLabel
          ? EventAssignmentsGroupingMode.label
          : EventAssignmentsGroupingMode.role,
    );

    await showDialog<void>(
      context: context,
      builder: (_) => EventAssignmentsSharePreviewDialog(data: shareData),
    );
  } catch (error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('שגיאה בהכנת תמונת שיבוצים: $error')),
    );
  }
}
```

- [ ] **Step 4: Update the summary entry point**

In `shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart`, replace:

```dart
builder: (context) => EventAssignmentsDialog.withAssignments(
  eventId: data.event.id,
  eventName: data.event.name,
  assignments: eventAssignments,
),
```

with:

```dart
builder: (context) => EventAssignmentsDialog.withAssignments(
  event: data.event,
  assignments: eventAssignments,
),
```

- [ ] **Step 5: Run targeted tests and analyzer**

Run from `shavtzak/`:

```bash
flutter test test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart
flutter test test/presentation/screens/event/widgets/event_assignments_share_card_test.dart
flutter analyze
```

Expected:

- Both `flutter test` commands: PASS.
- `flutter analyze`: PASS or only pre-existing unrelated analyzer output. Fix all errors introduced by this task.

- [ ] **Step 6: Commit Task 5**

Run from the repository root:

```bash
git add shavtzak/lib/presentation/screens/event/widgets/event_assignments_dialog.dart \
  shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart
git commit -m "Wire event assignments share image flow"
```

---

### Task 6: Final Verification

**Files:**
- Verify: all files changed by Tasks 1-5

- [ ] **Step 1: Run all targeted automated checks**

Run from `shavtzak/`:

```bash
flutter test test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart
flutter test test/presentation/screens/event/widgets/event_assignments_share_card_test.dart
flutter analyze
```

Expected:

- Both share-feature test files pass.
- Analyzer reports no new errors from the share image implementation.

- [ ] **Step 2: Manual mobile-web verification**

Run the app in a browser or ask the user to test on a phone. Verify:

- Role-grouped image opens from the event assignments dialog.
- Label-grouped image opens when the dialog switch is enabled.
- Header shows event date or date range, times, and stripped location.
- Member names with notes show numbered superscript-style markers.
- Notes section includes the full note text.
- Assignment statuses do not appear.
- Phone numbers and alternate phones do not appear.
- Direct share opens a native share sheet on a supported phone browser.
- If direct share/copy is unavailable, the preview remains usable as screenshot mode.

- [ ] **Step 3: Commit verification-only adjustments if needed**

If manual verification reveals UI-only spacing or overflow fixes, make the smallest scoped edit, rerun:

```bash
flutter test test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart
flutter test test/presentation/screens/event/widgets/event_assignments_share_card_test.dart
flutter analyze
```

Then commit from the repository root:

```bash
git add shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_card.dart \
  shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_preview_dialog.dart \
  shavtzak/lib/presentation/screens/event/widgets/event_assignments_dialog.dart
git commit -m "Polish event assignments share image"
```

If no adjustments are needed, do not create a verification-only commit.

---

## Notes For Implementation

- This is a client-only Flutter Web feature. Do not deploy Cloud Functions for this work.
- Keep `.superpowers/` untracked; it contains temporary brainstorming mockups.
- If existing analyzer output appears, record it clearly and distinguish pre-existing issues from share-feature issues.
- Use `apply_patch` for manual edits.
