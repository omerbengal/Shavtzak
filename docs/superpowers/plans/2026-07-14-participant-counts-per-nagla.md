# Participant Counts per נגלה — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace an event's single `participantCount` number with a list of *(optional label, count)* groups, rendered as `נגלה 1: 500, נגלה 2: 700`.

**Architecture:** Expand/contract. Tasks 1–5 **add** `participantGroups` alongside the existing `participantCount` so the app compiles and every test passes at every commit; Task 6 **removes** the scalar. A read-time fallback in `EventModel` hydrates old Firestore docs (`participantCount: 500` ⇒ one unlabeled group), which means displays are correct from Task 3 onward with no backfill script. A single formatter, `Event.participantsSummary`, is the only place the string is built.

**Tech Stack:** Flutter Web (Dart, BLoC, Equatable) · Firebase Firestore · Cloud Functions (TypeScript, `node:test`)

**Spec:** `docs/superpowers/specs/2026-07-14-participant-counts-per-nagla-design.md` (commit `cf3eaef`)

## Global Constraints

- **Branch:** `feat/participant-counts-per-nagla`, cut from `main`.
- **UI text is Hebrew. Code comments are English.** (CLAUDE.md)
- **Equatable props take full objects, never ids or derived scalars** — required for real-time stream updates to fire. (CLAUDE.md)
- **Do not run the app.** Omer runs it. `flutter analyze` + `flutter test` are your verification.
- **Measured baselines on `main` (verified 2026-07-14, before any task):**
  - `flutter analyze` → **107 issues**, all infos, zero warnings/errors. "Clean" means **107, not 0**.
  - `flutter test` → **216 passing**
  - `cd functions && npm test` → **63 passing**
- **Never `git add -A`.** Omer has unrelated uncommitted work (`AGENTS.md`, two `Google_Calendar_Problem_part_*.txt`). Stage only the exact paths each task names.
- **Max 10 participant groups.** Label max 20 characters. Count is a non-negative integer; 0 is legal.
- **Positional numbering:** the fallback label is `נגלה {position}`, where position is the row's 1-based index in the list — *not* a count of unlabeled rows.
- **⚠ Cloud Functions do not auto-deploy; the web app does (on merge to `main`).** `firebase deploy --only functions` MUST run **before the PR is merged**. See "Deploy" at the end.

---

### Task 1: `ParticipantGroup` entity + `Event.participantsSummary` formatter

Purely additive. `Event.participantCount` is left alone, so nothing else in the app changes.

**Files:**
- Create: `shavtzak/lib/domain/entities/participant_group.dart`
- Modify: `shavtzak/lib/domain/entities/event.dart`
- Test: `shavtzak/test/domain/entities/event_participants_summary_test.dart`

**Interfaces:**
- Produces: `ParticipantGroup({String? label, required int count})` — a **pure** entity with `String? get normalizedLabel` and Equatable `props`, and **no serialization** (that lives in `ParticipantGroupModel`, Task 2). On `Event`: `final List<ParticipantGroup> participantGroups` (default `const []`) and `String? get participantsSummary`.

- [ ] **Step 1: Confirm you are on the feature branch**

The branch already exists — the controller created it. Just verify:

```bash
cd "/Users/omerbengal/Documents/Github Projects/Shavtzak"
git rev-parse --abbrev-ref HEAD    # must print: feat/participant-counts-per-nagla
```

If it prints anything else, `git checkout feat/participant-counts-per-nagla`. Do **not**
create a new branch and do **not** touch `main`.

- [ ] **Step 2: Write the failing test**

Create `shavtzak/test/domain/entities/event_participants_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/participant_group.dart';

void main() {
  group('Event.participantsSummary', () {
    test('is null when there are no groups', () {
      expect(_eventWith(const []).participantsSummary, isNull);
    });

    test('a lone unlabeled group renders as a bare number', () {
      expect(
        _eventWith(const [ParticipantGroup(count: 500)]).participantsSummary,
        '500',
      );
    });

    test('a lone labeled group renders as "label: count"', () {
      expect(
        _eventWith(const [ParticipantGroup(label: 'בוקר', count: 500)])
            .participantsSummary,
        'בוקר: 500',
      );
    });

    test('two unlabeled groups fall back to נגלה numbering', () {
      expect(
        _eventWith(const [
          ParticipantGroup(count: 500),
          ParticipantGroup(count: 700),
        ]).participantsSummary,
        'נגלה 1: 500, נגלה 2: 700',
      );
    });

    test('numbering is positional, not a count of unlabeled groups', () {
      expect(
        _eventWith(const [
          ParticipantGroup(label: 'בוקר', count: 500),
          ParticipantGroup(count: 700),
        ]).participantsSummary,
        'בוקר: 500, נגלה 2: 700',
      );
    });

    test('all-labeled groups use their labels', () {
      expect(
        _eventWith(const [
          ParticipantGroup(label: 'בוקר', count: 500),
          ParticipantGroup(label: 'ערב', count: 700),
        ]).participantsSummary,
        'בוקר: 500, ערב: 700',
      );
    });

    test('a blank label counts as unset', () {
      expect(
        _eventWith(const [ParticipantGroup(label: '   ', count: 500)])
            .participantsSummary,
        '500',
      );
    });

    test('zero is a legal count', () {
      expect(
        _eventWith(const [ParticipantGroup(count: 0)]).participantsSummary,
        '0',
      );
    });
  });
}

Event _eventWith(List<ParticipantGroup> groups) {
  final now = DateTime(2026, 7, 14);
  return Event(
    id: 'event-1',
    name: 'טקס פתיחה',
    startDate: DateTime(2026, 7, 20),
    endDate: DateTime(2026, 7, 20),
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    participantGroups: groups,
    requiresArmed: false,
    roleRequirements: const {},
    createdAt: now,
    updatedAt: now,
  );
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd shavtzak && flutter test test/domain/entities/event_participants_summary_test.dart`
Expected: FAIL to compile — `Target of URI doesn't exist: 'package:shavtzak/domain/entities/participant_group.dart'`.

- [ ] **Step 4: Create the `ParticipantGroup` entity**

Create `shavtzak/lib/domain/entities/participant_group.dart`:

```dart
import 'package:equatable/equatable.dart';

/// One audience group ("נגלה") of an event: an optional label plus a headcount.
///
/// A null or blank [label] means the UI falls back to "נגלה N", where N is the
/// group's 1-based position in Event.participantGroups.
class ParticipantGroup extends Equatable {
  final String? label;
  final int count;

  const ParticipantGroup({this.label, required this.count});

  /// The label with surrounding whitespace removed, or null when absent/blank.
  /// Blank and absent are the same thing everywhere, so this is what both
  /// display and equality use.
  String? get normalizedLabel {
    final trimmed = label?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  List<Object?> get props => [normalizedLabel, count];
}
```

> **No serialization here.** Domain entities in this codebase are pure business objects; the
> data layer mirrors them with a `*Model` (see `VehicleInfoModel` / `DateConstraintModel` in
> `lib/data/models/team_member_model.dart`). Task 2 adds `ParticipantGroupModel`. Do **not** put
> `toMap`/`fromMap` on this entity — an earlier draft of this plan did, and it was reverted.

- [ ] **Step 5: Add `participantGroups` and the formatter to `Event`**

In `shavtzak/lib/domain/entities/event.dart`:

Add the import below the existing `equatable` import:

```dart
import 'package:equatable/equatable.dart';
import 'participant_group.dart';
```

Add the field immediately after `participantCount` (line 14):

```dart
  final int? participantCount; // Number of participants/audience (כמות משתתפים); null = unset
  final List<ParticipantGroup> participantGroups; // Audience per נגלה; empty = unset
```

Add to the constructor, right after `this.participantCount,`:

```dart
    this.participantCount,
    this.participantGroups = const [],
```

Add to `copyWith` — a parameter right after `bool clearParticipantCount = false,`:

```dart
    bool clearParticipantCount = false,
    List<ParticipantGroup>? participantGroups,
```

…and the assignment right after the `participantCount:` line inside the returned `Event(`:

```dart
      participantGroups: participantGroups ?? this.participantGroups,
```

Add to `props`, right after `participantCount,`:

```dart
        participantCount,
        participantGroups,
```

Add the formatter next to `dateRangeString` (after the `_isSameDay` helper, before `hasDriveFolder`):

```dart
  /// Formatted audience size, or null when no groups are set.
  ///
  /// A lone unlabeled group renders as a bare number ("500"), so events created
  /// before נגלות existed look exactly as they did. Otherwise each group is
  /// prefixed by its label, falling back to its 1-based position ("נגלה 2").
  String? get participantsSummary {
    if (participantGroups.isEmpty) return null;

    if (participantGroups.length == 1 &&
        participantGroups.first.normalizedLabel == null) {
      return '${participantGroups.first.count}';
    }

    final segments = <String>[];
    for (var i = 0; i < participantGroups.length; i++) {
      final group = participantGroups[i];
      final label = group.normalizedLabel ?? 'נגלה ${i + 1}';
      segments.add('$label: ${group.count}');
    }
    return segments.join(', ');
  }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd shavtzak && flutter test test/domain/entities/event_participants_summary_test.dart`
Expected: PASS — 8 tests.

- [ ] **Step 7: Verify no new analyzer findings**

Run: `cd shavtzak && flutter analyze`
Expected: still **107 issues**, all infos — zero new ones, and zero warnings/errors.

- [ ] **Step 8: Commit**

```bash
git add shavtzak/lib/domain/entities/participant_group.dart \
        shavtzak/lib/domain/entities/event.dart \
        shavtzak/test/domain/entities/event_participants_summary_test.dart
git commit -m "feat(events): add ParticipantGroup and the participantsSummary formatter"
```

---

### Task 2: Persist `participantGroups` through `EventModel`, with the legacy fallback

Still additive: `participantCount` keeps being read and written. The new part is that **every** event loaded from Firestore now arrives with `participantGroups` populated — old docs included, via the fallback — which is what lets Task 3's displays work with no backfill.

**Files:**
- Modify: `shavtzak/lib/data/models/event_model.dart`
- Test: `shavtzak/test/data/models/event_model_participant_groups_test.dart`

**Interfaces:**
- Consumes: `ParticipantGroup` (Task 1) — a **pure** entity: `label`, `count`, `normalizedLabel`, `props`. It has **no** `toMap`/`fromMap`; do not add any.
- Produces: `ParticipantGroupModel` (in `event_model.dart`) with `fromEntity` / `toEntity` / `toJson` / `static tryFromJson`; `EventModel.participantGroups` typed `List<ParticipantGroupModel>`; Firestore/JSON key `participantGroups` holding `[{label: String?, count: int}]`.

> **Convention (established, do not deviate):** domain entities in this codebase carry zero
> serialization. Every nested value object is mirrored by a `*Model` in the data layer that does
> the converting, and the parent model holds the **model**, not the entity — see `VehicleInfoModel`
> and `DateConstraintModel` in `lib/data/models/team_member_model.dart`, and how `TeamMemberModel`
> declares `final VehicleInfoModel? vehicleInfo` and calls `VehicleInfoModel.fromEntity(...)` /
> `vehicleInfo?.toEntity()` / `vehicleInfo?.toJson()`. `ParticipantGroupModel` follows that shape
> exactly. Like those two, it is a plain class — **not** `Equatable` — which is why the tests below
> assert through `model.toEntity().participantGroups` (entities, which *are* Equatable) rather than
> comparing models directly.

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/data/models/event_model_participant_groups_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/models/event_model.dart';
import 'package:shavtzak/domain/entities/participant_group.dart';

void main() {
  group('EventModel participant groups', () {
    test('reads the participantGroups array when present', () async {
      final model = await _modelFromDoc({
        ..._baseDoc(),
        'participantGroups': [
          {'label': 'בוקר', 'count': 500},
          {'label': null, 'count': 700},
        ],
      });

      expect(model.toEntity().participantGroups, const [
        ParticipantGroup(label: 'בוקר', count: 500),
        ParticipantGroup(count: 700),
      ]);
    });

    test('falls back to the legacy participantCount scalar', () async {
      final model = await _modelFromDoc({
        ..._baseDoc(),
        'participantCount': 500,
      });

      expect(model.toEntity().participantGroups, const [ParticipantGroup(count: 500)]);
    });

    test('the array wins over a stale legacy scalar', () async {
      final model = await _modelFromDoc({
        ..._baseDoc(),
        'participantCount': 500,
        'participantGroups': [
          {'label': null, 'count': 600},
        ],
      });

      expect(model.toEntity().participantGroups, const [ParticipantGroup(count: 600)]);
    });

    test('an empty array does NOT fall back to the scalar', () async {
      final model = await _modelFromDoc({
        ..._baseDoc(),
        'participantCount': 500,
        'participantGroups': <Map<String, dynamic>>[],
      });

      expect(model.toEntity().participantGroups, isEmpty);
    });

    test('is empty when neither field is set', () async {
      final model = await _modelFromDoc(_baseDoc());
      expect(model.toEntity().participantGroups, isEmpty);
    });

    test('malformed entries are dropped, not thrown on', () async {
      final model = await _modelFromDoc({
        ..._baseDoc(),
        'participantGroups': [
          {'label': 'תקין', 'count': 100},
          {'label': 'ללא כמות'},
          {'label': 'שלילי', 'count': -5},
          'not a map',
        ],
      });

      expect(model.toEntity().participantGroups,
          const [ParticipantGroup(label: 'תקין', count: 100)]);
    });

    test('toJson serializes groups and trims labels', () {
      final json = _model(const [
        ParticipantGroup(label: '  בוקר  ', count: 500),
        ParticipantGroup(count: 700),
      ]).toJson();

      expect(json['participantGroups'], [
        {'label': 'בוקר', 'count': 500},
        {'label': null, 'count': 700},
      ]);
    });

    test('toEntity carries the groups through', () {
      expect(
        _model(const [ParticipantGroup(label: 'ערב', count: 700)])
            .toEntity()
            .participantGroups,
        const [ParticipantGroup(label: 'ערב', count: 700)],
      );
    });
  });
}

EventModel _model(List<ParticipantGroup> groups) {
  final now = DateTime(2026, 7, 14);
  return EventModel(
    id: 'event-1',
    name: 'טקס פתיחה',
    startDate: DateTime(2026, 7, 20),
    endDate: DateTime(2026, 7, 20),
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    participantGroups:
        groups.map(ParticipantGroupModel.fromEntity).toList(),
    location: '',
    requiresArmed: false,
    roleRequirements: const {},
    createdAt: now,
    updatedAt: now,
  );
}

Map<String, dynamic> _baseDoc() {
  final stamp = Timestamp.fromDate(DateTime.utc(2026, 7, 14));
  return {
    'name': 'טקס פתיחה',
    'startDate': Timestamp.fromDate(DateTime.utc(2026, 7, 20)),
    'endDate': Timestamp.fromDate(DateTime.utc(2026, 7, 20)),
    'startTime': '18:00',
    'endTime': '22:00',
    'assemblyTime': '17:00',
    'requiresArmed': false,
    'roleRequirements': <String, dynamic>{},
    'createdAt': stamp,
    'updatedAt': stamp,
  };
}

Future<EventModel> _modelFromDoc(Map<String, dynamic> data) async {
  final fake = FakeFirebaseFirestore();
  await fake.collection('events').doc('event-1').set(data);
  final doc = await fake.collection('events').doc('event-1').get();
  return EventModel.fromFirestore(doc);
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd shavtzak && flutter test test/data/models/event_model_participant_groups_test.dart`
Expected: FAIL to compile — `No named parameter with the name 'participantGroups'`.

- [ ] **Step 3: Add the field and the parse helper to `EventModel`**

In `shavtzak/lib/data/models/event_model.dart`:

Add the import after the `event.dart` import:

```dart
import '../../domain/entities/event.dart';
import '../../domain/entities/participant_group.dart';
```

Add the `ParticipantGroupModel` class at the **bottom of the file**, after `EventModel` closes — mirroring how `VehicleInfoModel` and `DateConstraintModel` sit at the bottom of `team_member_model.dart`:

```dart
/// Data model for ParticipantGroup
class ParticipantGroupModel {
  final String? label;
  final int count;

  const ParticipantGroupModel({this.label, required this.count});

  factory ParticipantGroupModel.fromEntity(ParticipantGroup entity) {
    return ParticipantGroupModel(
      label: entity.normalizedLabel,
      count: entity.count,
    );
  }

  ParticipantGroup toEntity() => ParticipantGroup(label: label, count: count);

  /// Parse one stored group, returning null for anything malformed so a single
  /// bad entry is dropped instead of breaking the whole event. Not a `fromJson`
  /// factory, because a factory cannot report "this entry is garbage".
  static ParticipantGroupModel? tryFromJson(Object? raw) {
    if (raw is! Map) return null;

    final rawCount = raw['count'];
    final count = rawCount is num ? rawCount.toInt() : null;
    if (count == null || count < 0) return null;

    final label = raw['label'];
    final trimmed = label is String ? label.trim() : null;
    return ParticipantGroupModel(
      label: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      count: count,
    );
  }

  Map<String, dynamic> toJson() => {'label': label, 'count': count};
}
```

Add the field right after `final int? participantCount;`:

```dart
  final int? participantCount;
  final List<ParticipantGroupModel> participantGroups;
```

Add to the constructor right after `this.participantCount,`:

```dart
    this.participantCount,
    this.participantGroups = const [],
```

Add this helper next to the other `static` parse helpers (below `_formatDateOnly`):

```dart
  /// Hydrate participant groups, falling back to the retired `participantCount`
  /// scalar for docs written before נגלות existed. An explicitly empty array
  /// means "no groups" and must NOT fall back — otherwise clearing every group
  /// would resurrect the old scalar.
  static List<ParticipantGroupModel> _parseParticipantGroups(
    Object? groupsRaw,
    Object? legacyCount,
  ) {
    if (groupsRaw is List) {
      return groupsRaw
          .map(ParticipantGroupModel.tryFromJson)
          .whereType<ParticipantGroupModel>()
          .toList();
    }

    final legacy = legacyCount is num ? legacyCount.toInt() : null;
    if (legacy != null && legacy >= 0) {
      return [ParticipantGroupModel(count: legacy)];
    }
    return const [];
  }
```

> **Count reads must never use `x as num?`.** That cast throws `TypeError` on a non-null
> non-num value (e.g. a String from a console edit); inside `fromFirestore` that throw
> rides `watchEvents()`'s stream `.map()` and fails the WHOLE event batch. Always
> `x is num ? x.toInt() : null`. This applies to the two `participantCount` direct reads
> below as well — the plan's fromFirestore/fromJson touchpoints already carry the
> hardened form.

- [ ] **Step 4: Wire the field through all six touchpoints**

In `fromEntity`, after `participantCount: entity.participantCount,`:

```dart
      participantGroups: entity.participantGroups
          .map(ParticipantGroupModel.fromEntity)
          .toList(),
```

In `toEntity`, after `participantCount: participantCount,`:

```dart
      participantGroups:
          participantGroups.map((group) => group.toEntity()).toList(),
```

In `fromFirestore`, after the `participantCount:` line — and change that line to the null-safe
form `participantCount: data['participantCount'] is num ? (data['participantCount'] as num).toInt() : null,`
(a bare `data[...] as num?` throws on a String; see the box above):

```dart
      participantGroups: _parseParticipantGroups(
        data['participantGroups'],
        data['participantCount'],
      ),
```

In `toFirestore`, after `'participantCount': participantCount,`:

```dart
      'participantGroups':
          participantGroups.map((group) => group.toJson()).toList(),
```

In `fromJson`, after the `participantCount:` line — and change that line to the null-safe
form `participantCount: json['participantCount'] is num ? (json['participantCount'] as num).toInt() : null,`:

```dart
      participantGroups: _parseParticipantGroups(
        json['participantGroups'],
        json['participantCount'],
      ),
```

In `toJson`, after `'participantCount': participantCount,`:

```dart
      'participantGroups':
          participantGroups.map((group) => group.toJson()).toList(),
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd shavtzak && flutter test test/data/models/event_model_participant_groups_test.dart`
Expected: PASS — 8 tests.

- [ ] **Step 6: Run the full Dart suite and the analyzer**

Run: `cd shavtzak && flutter test && flutter analyze`
Expected: all tests pass; no new analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add shavtzak/lib/data/models/event_model.dart \
        shavtzak/test/data/models/event_model_participant_groups_test.dart
git commit -m "feat(events): serialize participantGroups, hydrating legacy docs from the scalar"
```

---

### Task 3: Switch all five display sites to `participantsSummary`

After Task 2 every loaded event has `participantGroups` populated (old docs via the fallback), so these screens render identical values to today — until someone actually adds a second נגלה.

**Files:**
- Modify: `shavtzak/lib/presentation/screens/event/event_list_screen.dart:736-740`
- Modify: `shavtzak/lib/presentation/screens/user/user_assignments_screen.dart:1120-1154`
- Modify: `shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart:167-175`
- Modify: `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_data_builder.dart:291-296`
- Modify: `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_data_builder.dart:291-296`
- Test: `shavtzak/test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart` (existing — add a case)

**Interfaces:**
- Consumes: `Event.participantsSummary` (Task 1).

- [ ] **Step 1: Write the failing test**

Append this test inside the existing `group('EventAssignmentsShareDataBuilder', ...)` block in `shavtzak/test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart`:

```dart
    test('participants line lists every נגלה', () {
      final event = _event(DateTime(2026, 5, 4, 10)).copyWith(
        participantGroups: const [
          ParticipantGroup(label: 'בוקר', count: 500),
          ParticipantGroup(count: 700),
        ],
      );

      final data = EventAssignmentsShareDataBuilder.build(
        event: event,
        assignments: const [],
        activeRoles: const [],
        labels: const [],
        groupingMode: EventAssignmentsGroupingMode.role,
      );

      expect(data.participantsLine, 'כמות משתתפים: בוקר: 500, נגלה 2: 700');
    });

    test('participants line is empty when no groups are set', () {
      final data = EventAssignmentsShareDataBuilder.build(
        event: _event(DateTime(2026, 5, 4, 10)),
        assignments: const [],
        activeRoles: const [],
        labels: const [],
        groupingMode: EventAssignmentsGroupingMode.role,
      );

      expect(data.participantsLine, '');
    });
```

Add the import at the top of that file (`EventAssignmentsGroupingMode` already comes in via the existing `event_assignments_share_models.dart` import):

```dart
import 'package:shavtzak/domain/entities/participant_group.dart';
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd shavtzak && flutter test test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart`
Expected: FAIL — `participantsLine` is `''` for the first test, because `_formatParticipantsLine` still reads the scalar (which is null on this event).

- [ ] **Step 3: Update the two share data builders**

In `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_data_builder.dart`, replace `_formatParticipantsLine` (line 291):

```dart
  static String _formatParticipantsLine(Event event) {
    final summary = event.participantsSummary;
    if (summary == null) {
      return '';
    }
    return 'כמות משתתפים: $summary';
  }
```

In `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_data_builder.dart`, replace `_buildParticipantsLine` (line 291):

```dart
  static String _buildParticipantsLine(Event event) {
    return event.participantsSummary ?? '';
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd shavtzak && flutter test test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart`
Expected: PASS.

- [ ] **Step 5: Update the three screen widgets**

In `shavtzak/lib/presentation/screens/event/event_list_screen.dart`, replace lines 736-740. Note the switch to `_buildFieldItemWithResponsiveFont` — the same helper the `שעות` line above it uses — because the string can now be long:

```dart
                    // Line 4: Participant count (hidden when unset)
                    if (event.participantsSummary != null)
                      _buildFieldItemWithResponsiveFont(
                          'כמות משתתפים', event.participantsSummary!,
                          isDeactivated: event.isDeactivated),
```

In `shavtzak/lib/presentation/screens/user/user_assignments_screen.dart`, replace lines 1120-1154. The value `Text` is now wrapped in `Expanded` so a long string wraps instead of overflowing the `Row`:

```dart
            // 5. Participant count (כמות משתתפים)
            if (event.participantsSummary != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.groups,
                      size: _getResponsiveIconSize(context,
                          minSize: 16.0, maxSize: 18.0),
                      color: iconColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'כמות משתתפים:',
                      style: TextStyle(
                        fontSize: _getResponsiveFontSize(context,
                            minSize: 13.0, maxSize: 14.0),
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        event.participantsSummary!,
                        style: TextStyle(
                          fontSize: _getResponsiveFontSize(context,
                              minSize: 13.0, maxSize: 14.0),
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
```

In `shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart`, replace lines 167-175:

```dart
              // Participant count (hidden when unset)
              if (data.event.participantsSummary != null)
                Text(
                  'כמות משתתפים: ${data.event.participantsSummary}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
```

- [ ] **Step 6: Run the full suite and the analyzer**

Run: `cd shavtzak && flutter test && flutter analyze`
Expected: all tests pass; no new analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add shavtzak/lib/presentation/screens/event/event_list_screen.dart \
        shavtzak/lib/presentation/screens/user/user_assignments_screen.dart \
        shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart \
        shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_data_builder.dart \
        shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_data_builder.dart \
        shavtzak/test/presentation/screens/event/widgets/event_assignments_share_data_builder_test.dart
git commit -m "feat(events): render participants from participantsSummary on all five surfaces"
```

---

### Task 4: Cloud Function — persist `participantGroups`, neutralize the scalar

**This must land before the form starts writing groups (Task 5), or the groups are silently dropped on save.** `eventDocFromJson` is an explicit allowlist: a field it doesn't name never reaches Firestore.

**Files:**
- Create: `functions/src/participant_groups.ts`
- Modify: `functions/src/index.ts:1512-1539` (`eventDocFromJson`)
- Modify: `shavtzak/lib/presentation/screens/db/widgets/log_document_card_view.dart:1433`
- Test: `functions/src/participant_groups.test.ts`

**Interfaces:**
- Produces: `normalizeParticipantGroups(groupsRaw: unknown, legacyCount: unknown): ParticipantGroup[]` where `ParticipantGroup = {label: string | null; count: number}`.

The normalizer lives in its own module rather than inside `index.ts` because `index.ts` initializes `firebase-admin` on import — a test that imported it would need the whole Firebase environment. This matches how `drive_export.ts` is structured.

- [ ] **Step 1: Write the failing test**

Create `functions/src/participant_groups.test.ts`:

```ts
import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeParticipantGroups} from './participant_groups';

test('an old-client payload with only participantCount becomes one unlabeled group', () => {
  assert.deepEqual(normalizeParticipantGroups(undefined, 500), [
    {label: null, count: 500},
  ]);
});

test('a participantGroups array passes through, trimming labels', () => {
  assert.deepEqual(
    normalizeParticipantGroups(
      [
        {label: '  בוקר  ', count: 500},
        {label: '', count: 700},
      ],
      null,
    ),
    [
      {label: 'בוקר', count: 500},
      {label: null, count: 700},
    ],
  );
});

test('the array wins over a stale legacy scalar', () => {
  assert.deepEqual(
    normalizeParticipantGroups([{label: null, count: 600}], 500),
    [{label: null, count: 600}],
  );
});

test('an empty array stays empty and does not fall back to the scalar', () => {
  assert.deepEqual(normalizeParticipantGroups([], 500), []);
});

test('malformed entries are dropped, not thrown on', () => {
  assert.deepEqual(
    normalizeParticipantGroups(
      [
        {label: 'תקין', count: 100},
        {label: 'ללא כמות'},
        {label: 'שלילי', count: -5},
        {label: 'לא מספר', count: 'abc'},
        null,
      ],
      null,
    ),
    [{label: 'תקין', count: 100}],
  );
});

test('counts are floored to integers', () => {
  assert.deepEqual(normalizeParticipantGroups([{label: null, count: 12.7}], null), [
    {label: null, count: 12},
  ]);
});

test('the array is clamped to 10 groups', () => {
  const many = Array.from({length: 14}, (_, i) => ({label: null, count: i}));
  assert.equal(normalizeParticipantGroups(many, null).length, 10);
});

test('nothing set yields no groups', () => {
  assert.deepEqual(normalizeParticipantGroups(undefined, null), []);
});

test('zero is a legal count', () => {
  assert.deepEqual(normalizeParticipantGroups([{label: null, count: 0}], null), [
    {label: null, count: 0},
  ]);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd functions && npm test`
Expected: FAIL — `tsc` errors with `Cannot find module './participant_groups'`.

- [ ] **Step 3: Create the normalizer**

Create `functions/src/participant_groups.ts`:

```ts
export type ParticipantGroup = {
  label: string | null;
  count: number;
};

const MAX_PARTICIPANT_GROUPS = 10;

/**
 * Coerce an event payload's participant groups into the shape stored in Firestore.
 *
 * Falls back to the retired `participantCount` scalar so an old web client — one
 * that has never heard of participantGroups — does not lose its audience size
 * during the rollout window.
 *
 * Coerces rather than throws: a malformed entry is dropped, never a failed save.
 */
export function normalizeParticipantGroups(
  groupsRaw: unknown,
  legacyCount: unknown,
): ParticipantGroup[] {
  if (Array.isArray(groupsRaw)) {
    const groups: ParticipantGroup[] = [];
    for (const entry of groupsRaw) {
      if (groups.length === MAX_PARTICIPANT_GROUPS) break;
      const group = toParticipantGroup(entry);
      if (group != null) {
        groups.push(group);
      }
    }
    return groups;
  }

  const legacy = toCount(legacyCount);
  return legacy == null ? [] : [{label: null, count: legacy}];
}

function toParticipantGroup(entry: unknown): ParticipantGroup | null {
  if (entry == null || typeof entry !== 'object') return null;
  const record = entry as Record<string, unknown>;
  const count = toCount(record['count']);
  if (count == null) return null;
  return {label: toLabel(record['label']), count};
}

function toCount(value: unknown): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    return null;
  }
  return Math.floor(value);
}

function toLabel(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd functions && npm test`
Expected: PASS — the 9 new tests, plus the pre-existing suites.

- [ ] **Step 5: Wire it into the write allowlist**

In `functions/src/index.ts`, add the import alongside the other local module imports near the top of the file:

```ts
import {normalizeParticipantGroups} from './participant_groups';
```

Then in `eventDocFromJson` (line 1512), replace the single `participantCount` line (line 1523) with:

```ts
    participantGroups: normalizeParticipantGroups(
      event['participantGroups'],
      event['participantCount'],
    ),
    // Retired, superseded by participantGroups. Written as null rather than
    // omitted: event.update is a partial merge, so an omitted key would leave
    // the stale value on the doc for old clients to render as a WRONG number.
    participantCount: null,
```

- [ ] **Step 6: Verify the function still builds**

Run: `cd functions && npm run build`
Expected: `tsc` exits 0, no output.

- [ ] **Step 7: Teach the DB-log viewer the new field name**

In `shavtzak/lib/presentation/screens/db/widgets/log_document_card_view.dart`, at the label map (line 1433), keep the old key — historical audit-log entries still contain it — and add the new one:

```dart
      'participantCount': 'כמות משתתפים',
      'participantGroups': 'כמות משתתפים',
```

- [ ] **Step 8: Commit**

```bash
git add functions/src/participant_groups.ts \
        functions/src/participant_groups.test.ts \
        functions/src/index.ts \
        shavtzak/lib/presentation/screens/db/widgets/log_document_card_view.dart
git commit -m "feat(functions): persist participantGroups and neutralize the legacy scalar"
```

---

### Task 5: Form — a row per נגלה, with `+` and `✕`

**Files:**
- Modify: `shavtzak/lib/presentation/screens/event/widgets/event_form_modal.dart`
- Modify: `shavtzak/lib/presentation/bloc/event/event_event.dart:124,143,164`
- Modify: `shavtzak/lib/presentation/bloc/event/event_bloc.dart:426,607`
- Test: `shavtzak/test/presentation/screens/event/widgets/event_form_participant_groups_test.dart`

**Interfaces:**
- Consumes: `ParticipantGroup` (Task 1), `Event.participantGroups` (Task 1).
- Produces: `DuplicateEvent.newParticipantGroups` (`List<ParticipantGroup>`, defaults to `const []`), replacing `newParticipantCount`.

- [ ] **Step 1: Write the failing widget test**

Create `shavtzak/test/presentation/screens/event/widgets/event_form_participant_groups_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/participant_group.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_form_modal.dart';

void main() {
  group('participant group rows', () {
    testWidgets('a new event starts with one empty row and an add button',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.byType(ParticipantGroupRows), findsOneWidget);
      expect(find.text('כמות'), findsOneWidget);
      expect(find.text('הוסף נגלה'), findsOneWidget);
    });

    testWidgets('the add button appends a row', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('הוסף נגלה'));
      await tester.pumpAndSettle();

      expect(find.text('כמות'), findsNWidgets(2));
    });

    testWidgets('the remove button drops a row', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('הוסף נגלה'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('הסר נגלה').first);
      await tester.pumpAndSettle();

      expect(find.text('כמות'), findsOneWidget);
    });

    testWidgets('an existing event hydrates one row per group', (tester) async {
      final rowsKey = GlobalKey<ParticipantGroupRowsState>();
      await tester.pumpWidget(_host(
        rowsKey: rowsKey,
        initialGroups: const [
          ParticipantGroup(label: 'בוקר', count: 500),
          ParticipantGroup(count: 700),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('כמות'), findsNWidgets(2));
      expect(find.text('בוקר'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(rowsKey.currentState!.toGroups(), const [
        ParticipantGroup(label: 'בוקר', count: 500),
        ParticipantGroup(count: 700),
      ]);
    });

    testWidgets('the add button disappears at the 10-row cap', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      for (var i = 0; i < 9; i++) {
        await tester.tap(find.text('הוסף נגלה'));
        await tester.pumpAndSettle();
      }

      expect(find.text('כמות'), findsNWidgets(10));
      expect(find.text('הוסף נגלה'), findsNothing);
    });

    testWidgets('a label with no count blocks submission', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(_host(formKey: key));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'בוקר');
      await tester.pumpAndSettle();

      expect(key.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('יש להזין כמות'), findsOneWidget);
    });

    testWidgets('rows collect into groups, dropping the empty ones',
        (tester) async {
      final rowsKey = GlobalKey<ParticipantGroupRowsState>();
      await tester.pumpWidget(_host(rowsKey: rowsKey));
      await tester.pumpAndSettle();

      await tester.tap(find.text('הוסף נגלה'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('הוסף נגלה'));
      await tester.pumpAndSettle();

      final labels = find.byType(TextFormField);
      // Row 0: label "בוקר", count 500. Row 1: count only. Row 2: left empty.
      await tester.enterText(labels.at(0), 'בוקר');
      await tester.enterText(labels.at(1), '500');
      await tester.enterText(labels.at(3), '700');
      await tester.pumpAndSettle();

      expect(rowsKey.currentState!.toGroups(), const [
        ParticipantGroup(label: 'בוקר', count: 500),
        ParticipantGroup(count: 700),
      ]);
    });
  });
}

Widget _host({
  GlobalKey<FormState>? formKey,
  GlobalKey<ParticipantGroupRowsState>? rowsKey,
  List<ParticipantGroup> initialGroups = const [],
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Form(
          key: formKey ?? GlobalKey<FormState>(),
          child: SingleChildScrollView(
            child: ParticipantGroupRows(
              key: rowsKey,
              initialGroups: initialGroups,
              onChanged: () {},
            ),
          ),
        ),
      ),
    ),
  );
}
```

> **Why a separate widget:** `EventFormModal` needs a `BlocProvider` for `EventBloc`, `CategoryBloc` and repositories, which makes it painful to pump in a test. Extracting the rows into their own public `ParticipantGroupRows` widget makes them directly testable *and* keeps `event_form_modal.dart` — already ~2000 lines — from growing further. The modal then just hosts it.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd shavtzak && flutter test test/presentation/screens/event/widgets/event_form_participant_groups_test.dart`
Expected: FAIL to compile — `Undefined class 'ParticipantGroupRows'`.

- [ ] **Step 3: Create the `ParticipantGroupRows` widget**

Create `shavtzak/lib/presentation/screens/event/widgets/participant_group_rows.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/debug/logger.dart';
import '../../../../domain/entities/participant_group.dart';

const int _maxParticipantRows = 10;
const int _maxLabelLength = 20;

/// The "כמות משתתפים" section of the event form: one row per נגלה, each an
/// optional label plus a count, with a "+" to append and a "✕" to remove.
///
/// Call [ParticipantGroupRowsState.toGroups] on save to collect the rows.
class ParticipantGroupRows extends StatefulWidget {
  final List<ParticipantGroup> initialGroups;

  /// Fired on any edit, so the host form can mark itself dirty.
  final VoidCallback onChanged;

  const ParticipantGroupRows({
    super.key,
    required this.initialGroups,
    required this.onChanged,
  });

  @override
  State<ParticipantGroupRows> createState() => ParticipantGroupRowsState();
}

class ParticipantGroupRowsState extends State<ParticipantGroupRows> {
  final List<_ParticipantRow> _rows = [];

  @override
  void initState() {
    super.initState();
    for (final group in widget.initialGroups) {
      final row = _ParticipantRow();
      row.label.text = group.normalizedLabel ?? '';
      row.count.text = group.count.toString();
      _rows.add(row);
    }
    // Always show at least one row, so the common single-number case needs no
    // extra tap. An untouched empty row is dropped by toGroups().
    if (_rows.isEmpty) {
      _rows.add(_ParticipantRow());
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  /// Collect the rows into groups. A row with no count is dropped — a row that
  /// has a label but no count is caught first by the count field's validator.
  List<ParticipantGroup> toGroups() {
    final groups = <ParticipantGroup>[];
    for (final row in _rows) {
      final count = int.tryParse(row.count.text.trim());
      if (count == null) continue;
      final label = row.label.text.trim();
      groups.add(ParticipantGroup(
        label: label.isEmpty ? null : label,
        count: count,
      ));
    }
    return groups;
  }

  void _addRow() {
    Logger.action('tap:addParticipantRow', {'count': _rows.length});
    setState(() => _rows.add(_ParticipantRow()));
    widget.onChanged();
  }

  void _removeRow(int index) {
    Logger.action('tap:removeParticipantRow', {'index': index});
    final removed = _rows.removeAt(index);
    if (_rows.isEmpty) {
      _rows.add(_ParticipantRow());
    }
    setState(() {});
    widget.onChanged();
    // Dispose only after the rebuild has detached the field: during the current
    // frame a live EditableText still holds these controllers.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'כמות משתתפים (אופציונלי)',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            // Keyed by row identity so removing a middle row does not leave the
            // field below it holding the removed row's form state.
            key: ObjectKey(_rows[i]),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _rows[i].label,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(_maxLabelLength),
                    ],
                    onChanged: (_) {
                      // Rebuild so the count validator re-reads this label.
                      setState(() {});
                      widget.onChanged();
                    },
                    decoration: InputDecoration(
                      labelText: 'תווית (אופציונלי)',
                      hintText: 'נגלה ${i + 1}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _rows[i].count,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(7),
                    ],
                    onChanged: (_) => widget.onChanged(),
                    validator: (value) {
                      final hasCount = (value ?? '').trim().isNotEmpty;
                      final hasLabel = _rows[i].label.text.trim().isNotEmpty;
                      // A fully empty row is fine — it is dropped on save. A
                      // labeled row without a count is a mistake worth flagging.
                      if (hasLabel && !hasCount) {
                        return 'יש להזין כמות';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'כמות',
                      hintText: '500',
                      prefixIcon: Icon(Icons.groups),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  tooltip: 'הסר נגלה',
                  onPressed: () => _removeRow(i),
                ),
              ],
            ),
          ),
        if (_rows.length < _maxParticipantRows)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add),
              label: const Text('הוסף נגלה'),
            ),
          ),
      ],
    );
  }
}

class _ParticipantRow {
  final TextEditingController label = TextEditingController();
  final TextEditingController count = TextEditingController();

  void dispose() {
    label.dispose();
    count.dispose();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd shavtzak && flutter test test/presentation/screens/event/widgets/event_form_participant_groups_test.dart`
Expected: PASS — 7 tests.

- [ ] **Step 5: Commit the widget**

```bash
git add shavtzak/lib/presentation/screens/event/widgets/participant_group_rows.dart \
        shavtzak/test/presentation/screens/event/widgets/event_form_participant_groups_test.dart
git commit -m "feat(events): add the ParticipantGroupRows form section"
```

- [ ] **Step 6: Host the widget in the event form**

In `shavtzak/lib/presentation/screens/event/widgets/event_form_modal.dart`:

Add two imports next to the existing `../../../../domain/entities/event.dart` import:

```dart
import '../../../../domain/entities/participant_group.dart';
import 'participant_group_rows.dart';
```

Delete the `_participantCountController` field (line 67), its `initState` assignment (lines 144-145), and its `dispose()` call (line 218). Add a key in its place among the state fields:

```dart
  final _participantRowsKey = GlobalKey<ParticipantGroupRowsState>();
```

Replace `_parseParticipantCount()` (lines 355-360) with:

```dart
  /// Collect the participant rows. Empty rows are dropped; a labeled row with
  /// no count is already blocked by the form validator.
  List<ParticipantGroup> _parseParticipantGroups() {
    return _participantRowsKey.currentState?.toGroups() ?? const [];
  }
```

Replace the participant-count `TextFormField` (lines 1843-1880 — the whole block from the `// Participant count (כמות משתתפים)` comment through its closing `),`) with:

```dart
                                        // Participant counts, one row per נגלה
                                        ParticipantGroupRows(
                                          key: _participantRowsKey,
                                          initialGroups: widget.event
                                                  ?.participantGroups ??
                                              const [],
                                          onChanged: () => _isDirty = true,
                                        ),
```

In the save path, replace `participantCount: _parseParticipantCount(),` (line 701) with:

```dart
      participantGroups: _parseParticipantGroups(),
```

In the duplication dispatch, replace `newParticipantCount: _parseParticipantCount(),` (line 530) with:

```dart
            newParticipantGroups: _parseParticipantGroups(),
```

- [ ] **Step 7: Rename the field on `DuplicateEvent`**

In `shavtzak/lib/presentation/bloc/event/event_event.dart`, add the import:

```dart
import '../../../domain/entities/participant_group.dart';
```

Replace `final int? newParticipantCount;` (line 124) with:

```dart
  final List<ParticipantGroup> newParticipantGroups;
```

Replace `this.newParticipantCount,` (line 143) with:

```dart
    this.newParticipantGroups = const [],
```

Replace `newParticipantCount,` in `props` (line 164) with:

```dart
        newParticipantGroups,
```

In `shavtzak/lib/presentation/bloc/event/event_bloc.dart`, replace `participantCount: event.newParticipantCount,` (line 426) with:

```dart
        participantGroups: event.newParticipantGroups,
```

…and update the stale comment at line 607:

```dart
    // Adjust only the quotas + timestamp; copyWith preserves every other field
    // (times incl. teamEndTime/actualShowStartTime, participantGroups, parking,
    // isDeactivated, inviteAllPermanentWhenUnassigned, Drive fields, ...).
```

- [ ] **Step 8: Run the full suite and the analyzer**

Run: `cd shavtzak && flutter test && flutter analyze`
Expected: all tests pass; no new analyzer issues. `_parseParticipantCount` and `_participantCountController` should now be gone — if the analyzer reports either as unused, you missed a deletion.

- [ ] **Step 9: Commit**

```bash
git add shavtzak/lib/presentation/screens/event/widgets/event_form_modal.dart \
        shavtzak/lib/presentation/bloc/event/event_event.dart \
        shavtzak/lib/presentation/bloc/event/event_bloc.dart
git commit -m "feat(events): edit and duplicate participant counts per נגלה"
```

---

### Task 6: Contract — delete `Event.participantCount`

Everything now reads and writes `participantGroups`. The scalar's only remaining job is the read-time fallback for old docs, which lives inside `EventModel`'s parse helpers and stays. The **entity field** and the **write path** go.

**Files:**
- Modify: `shavtzak/lib/domain/entities/event.dart`
- Modify: `shavtzak/lib/data/models/event_model.dart`

**Interfaces:**
- Removes: `Event.participantCount`, `Event.copyWith(clearParticipantCount:)`, `EventModel.participantCount`.
- Keeps: the `data['participantCount']` / `json['participantCount']` reads inside `EventModel._parseParticipantGroups` — that IS the migration and must survive.

- [ ] **Step 1: Delete the field from `Event`**

In `shavtzak/lib/domain/entities/event.dart` remove all four references:

- the field `final int? participantCount; // Number of participants...` (line 14)
- the constructor parameter `this.participantCount,`
- the `copyWith` parameters `int? participantCount,` and `bool clearParticipantCount = false,`, plus the two-line `participantCount:` assignment inside the returned `Event(`
- the `participantCount,` entry in `props`

`clearParticipantCount` has no callers — the only other hit in the repo is the string `'tap:clearParticipantCount'` inside a `Logger.action()` call, which Task 5 already deleted along with the old field.

- [ ] **Step 2: Delete the field from `EventModel` — but KEEP the legacy reads**

In `shavtzak/lib/data/models/event_model.dart` remove:

- the field `final int? participantCount;`
- the constructor parameter `this.participantCount,`
- `participantCount: entity.participantCount,` in `fromEntity`
- `participantCount: participantCount,` in `toEntity`
- the `participantCount:` line in `fromFirestore` (now the null-safe
  `participantCount: data['participantCount'] is num ? (data['participantCount'] as num).toInt() : null,`)
- the `participantCount:` line in `fromJson` (now the null-safe
  `participantCount: json['participantCount'] is num ? (json['participantCount'] as num).toInt() : null,`)
- `'participantCount': participantCount,` in `toFirestore`
- `'participantCount': participantCount,` in `toJson`

**Do NOT touch** the two `_parseParticipantGroups(..., data['participantCount'])` / `(..., json['participantCount'])` call sites. Those read the legacy value straight from the raw map and are the entire migration.

- [ ] **Step 3: Run the full suite**

Run: `cd shavtzak && flutter test`
Expected: PASS. The legacy-fallback test from Task 2 (`falls back to the legacy participantCount scalar`) still passes — that is the proof the migration survived the contract.

- [ ] **Step 4: Run the analyzer**

Run: `cd shavtzak && flutter analyze`
Expected: no new issues, and zero references to `participantCount` remain outside the two fallback reads:

```bash
cd "/Users/omerbengal/Documents/Github Projects/Shavtzak"
git grep -n "participantCount" -- shavtzak/lib
```

Expected output: exactly two lines, both inside `event_model.dart`'s `_parseParticipantGroups` call sites, plus the `'participantCount': 'כמות משתתפים'` label-map entry in `log_document_card_view.dart` (kept for historical audit logs).

- [ ] **Step 5: Run the function tests once more**

Run: `cd functions && npm test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/domain/entities/event.dart shavtzak/lib/data/models/event_model.dart
git commit -m "refactor(events): retire the participantCount scalar"
```

---

## Verification before hand-off

Run the `/verify` skill, or drive it manually. `flutter analyze` and `flutter test` are necessary but **not** sufficient here — the write path crosses a Cloud Function that unit tests do not exercise end-to-end. Omer runs the app; give him this list:

1. **Old event, untouched** — an event created before this change still shows `כמות משתתפים: 500` in the admin list, the user's assignments card, and the summary tile. (Proves the read-time fallback.)
2. **Add a second נגלה** — edit that event, press `+ הוסף נגלה`, enter `700`, save, **reload the page**. It must now read `כמות משתתפים: נגלה 1: 500, נגלה 2: 700`. **A reload is mandatory** — an optimistic UI would show the right thing even if the Function dropped the field.
3. **Label one row** — set row 1's label to `בוקר`; it becomes `בוקר: 500, נגלה 2: 700` (positional numbering: row 2 stays "נגלה 2").
4. **Latin label** — type `Morning` as a label and check the RTL string does not scramble. This is the one bidi case the spec flags. If it reorders, wrap each segment in an RTL isolate (`⁧…⁩`), as `calendar_share_data_builder.dart:279` already does for the `מופע` time range.
5. **Validation** — a row with a label and no count blocks save with `יש להזין כמות`; a fully empty row saves fine and vanishes.
6. **Share images** — the event-assignments share image and the summary calendar-share image both show the full string; the calendar day cell wraps it onto two lines.
7. **Duplicate an event** — the נגלות carry over to the copy.

## Deploy

**Deploy Functions BEFORE merging the PR.** Merging to `main` auto-deploys the web app on its own (`.github/workflows/web.yml`); Cloud Functions never auto-deploy.

```bash
cd "/Users/omerbengal/Documents/Github Projects/Shavtzak"
git status --short          # ⚠ see below before you run the deploy
firebase deploy --only functions
```

**⚠ `firebase deploy` ships the WORKING TREE, not `HEAD`.** Omer keeps unrelated
uncommitted edits in the repo (`AGENTS.md`, `Google_Calendar_Problem_part_*.txt` today).
Anything dirty under `functions/` at deploy time goes to production. Check `git status`
and stash or commit first — this bit us on the previous branch.

- **Functions first (correct).** The new function normalizes an old client's `participantCount` payload into a group, so the currently-live web build keeps working. This state is safe to sit in indefinitely.
- **Web first (data loss).** The old function's allowlist drops the `participantGroups` it has never heard of, and writes `participantCount: event['participantCount'] ?? null` — a key the new client no longer sends. Every save would null the count, and the UI would look correct until the next reload.
