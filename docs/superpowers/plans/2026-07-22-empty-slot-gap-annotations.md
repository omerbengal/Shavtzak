# Empty-slot gap annotations (note + label) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin attach a note + label to an empty assignment slot (a role gap), shown in purple on `/admin/assignments` and `/summary` (מסך מנהלים), and carried onto the member when the slot is filled.

**Architecture:** A `SlotAnnotation {note, labelId}` map lives on `Event.slotAnnotations`, keyed by `"<roleKey>#<slotIndex>"`. Both screens derive their slots the same way (shared helper) and read the annotation from the streamed Event. Event writes go through a new side-effect-free backend Cloud Function mutation (clients can't write `events` directly). No first-class-slot refactor, no data migration.

**Tech Stack:** Flutter Web (Dart, `flutter_bloc`, `equatable`), Firebase Firestore, TypeScript Cloud Functions. Tests: `flutter_test` + `fake_cloud_firestore` + `bloc_test`; backend `node --test`.

Design spec: `docs/superpowers/specs/2026-07-22-empty-slot-gap-annotations-design.md`.

## Global Constraints

- Flutter Web app; **all UI text is Hebrew, RTL**; **code comments in English**.
- **Real-time rule:** state/model Equatable `props` use FULL objects, never just ids. Any new field on `Event`/`AssignmentSlot` MUST be added to `props`.
- **`flutter analyze` must stay clean** — zero *new* issues (repo baseline is ~108 pre-existing infos; "clean" = no new ones). Run from the `shavtzak/` directory.
- **Clients cannot write `events` directly** (`firestore.rules`: `allow write: if false`). Event writes go through backend mutations via `FirestoreDatabase._invokeMutation(op, payload)`. New writes require a **Cloud Functions deploy** (`firebase deploy --only functions`) before they work in an environment.
- **Slot-annotation key format:** `slotAnnotationKey(roleKey, slotIndex)` = `"<roleKey>#<slotIndex>"`. Role keys never contain `#`.
- **Display:** notes render in **purple** (reuse the existing note card style) and labels via the existing `AssignmentLabelChip`.
- **Carry-over** copies a gap's note+label onto the assignment when the slot is filled. The **extra phone stays member-level** (on the assignment) — never part of a gap annotation.
- All commands below assume repo root `/Users/omerbengal/Documents/Github Projects/Shavtzak/.claude/worktrees/empty-slot-gap-annotations`. The Flutter app is in `shavtzak/`; the backend is in `functions/`.

---

### Task 1: `SlotAnnotation` value object

**Files:**
- Create: `shavtzak/lib/domain/entities/slot_annotation.dart`
- Test: `shavtzak/test/domain/entities/slot_annotation_test.dart`

**Interfaces:**
- Produces: `class SlotAnnotation extends Equatable { final String note; final String? labelId; const SlotAnnotation({this.note='', this.labelId}); bool get isEmpty; SlotAnnotation copyWith({String? note, String? Function()? labelId}); Map<String,dynamic> toJson(); factory SlotAnnotation.fromJson(Map<String,dynamic>); }`

- [ ] **Step 1: Write the failing test**

```dart
// shavtzak/test/domain/entities/slot_annotation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/slot_annotation.dart';

void main() {
  group('SlotAnnotation', () {
    test('isEmpty is true only when note is blank AND labelId is null', () {
      expect(const SlotAnnotation().isEmpty, isTrue);
      expect(const SlotAnnotation(note: '  ').isEmpty, isTrue);
      expect(const SlotAnnotation(note: 'x').isEmpty, isFalse);
      expect(const SlotAnnotation(labelId: 'L1').isEmpty, isFalse);
    });

    test('value equality via Equatable', () {
      expect(const SlotAnnotation(note: 'a', labelId: 'L1'),
          const SlotAnnotation(note: 'a', labelId: 'L1'));
      expect(const SlotAnnotation(note: 'a'),
          isNot(const SlotAnnotation(note: 'b')));
    });

    test('copyWith can clear labelId via the nullable setter', () {
      const a = SlotAnnotation(note: 'a', labelId: 'L1');
      expect(a.copyWith(labelId: () => null).labelId, isNull);
      expect(a.copyWith(note: 'b').labelId, 'L1'); // unchanged when omitted
    });

    test('JSON round-trips', () {
      const a = SlotAnnotation(note: 'ערב', labelId: 'L2');
      expect(SlotAnnotation.fromJson(a.toJson()), a);
      expect(SlotAnnotation.fromJson(const {'note': 'x'}),
          const SlotAnnotation(note: 'x'));
      expect(SlotAnnotation.fromJson(const {}), const SlotAnnotation());
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shavtzak && flutter test test/domain/entities/slot_annotation_test.dart`
Expected: FAIL — `slot_annotation.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// shavtzak/lib/domain/entities/slot_annotation.dart
import 'package:equatable/equatable.dart';

/// A note + label attached to a single assignment SLOT (a "job"), independent
/// of whether a member is assigned. Stored on `Event.slotAnnotations`, keyed by
/// `slotAnnotationKey(roleKey, slotIndex)`. The label reuses `AssignmentLabel`
/// by id.
class SlotAnnotation extends Equatable {
  final String note;
  final String? labelId;

  const SlotAnnotation({this.note = '', this.labelId});

  /// True when there is nothing worth storing (blank note and no label).
  bool get isEmpty => note.trim().isEmpty && labelId == null;

  SlotAnnotation copyWith({String? note, String? Function()? labelId}) {
    return SlotAnnotation(
      note: note ?? this.note,
      labelId: labelId != null ? labelId() : this.labelId,
    );
  }

  Map<String, dynamic> toJson() => {'note': note, 'labelId': labelId};

  factory SlotAnnotation.fromJson(Map<String, dynamic> json) => SlotAnnotation(
        note: (json['note'] as String?) ?? '',
        labelId: json['labelId'] as String?,
      );

  @override
  List<Object?> get props => [note, labelId];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shavtzak && flutter test test/domain/entities/slot_annotation_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/domain/entities/slot_annotation.dart shavtzak/test/domain/entities/slot_annotation_test.dart
git commit -m "feat(domain): add SlotAnnotation value object"
```

---

### Task 2: `Event.slotAnnotations` field + `EventModel` serialization

**Files:**
- Modify: `shavtzak/lib/domain/entities/event.dart` (constructor, `copyWith`, `props`)
- Modify: `shavtzak/lib/data/models/event_model.dart` (field, all 6 conversion paths, a parse helper)
- Test: `shavtzak/test/data/models/event_model_slot_annotations_test.dart`

**Interfaces:**
- Consumes: `SlotAnnotation` (Task 1).
- Produces: `Event.slotAnnotations` (`Map<String, SlotAnnotation>`, default `const {}`), round-tripped by `EventModel` across `fromEntity/toEntity/fromFirestore/toFirestore/fromJson/toJson`.

- [ ] **Step 1: Write the failing test**

```dart
// shavtzak/test/data/models/event_model_slot_annotations_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/models/event_model.dart';
import 'package:shavtzak/domain/entities/slot_annotation.dart';

Map<String, dynamic> _baseJson() => {
      'id': 'event-1',
      'name': 'טקס פתיחה',
      'startDate': '2026-07-20',
      'endDate': '2026-07-20',
      'startTime': '18:00',
      'endTime': '22:00',
      'assemblyTime': '17:00',
      'requiresArmed': false,
      'roleRequirements': <String, dynamic>{},
      'createdAt': DateTime.utc(2026, 7, 14).toIso8601String(),
      'updatedAt': DateTime.utc(2026, 7, 14).toIso8601String(),
    };

void main() {
  group('EventModel slotAnnotations', () {
    test('reads slotAnnotations from JSON', () {
      final model = EventModel.fromJson({
        ..._baseJson(),
        'slotAnnotations': {
          'entryScreening#0': {'note': 'כניסה B', 'labelId': 'L1'},
          'medic#2': {'note': '', 'labelId': 'L2'},
        },
      });
      expect(model.toEntity().slotAnnotations, {
        'entryScreening#0': const SlotAnnotation(note: 'כניסה B', labelId: 'L1'),
        'medic#2': const SlotAnnotation(labelId: 'L2'),
      });
    });

    test('defaults to empty when absent (legacy docs)', () {
      final model = EventModel.fromJson(_baseJson());
      expect(model.toEntity().slotAnnotations, isEmpty);
    });

    test('toJson round-trips slotAnnotations', () {
      final entity = EventModel.fromJson({
        ..._baseJson(),
        'slotAnnotations': {
          'medic#1': {'note': 'ערב', 'labelId': null},
        },
      }).toEntity();
      final json = EventModel.fromEntity(entity).toJson();
      expect(json['slotAnnotations'], {
        'medic#1': {'note': 'ערב', 'labelId': null},
      });
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shavtzak && flutter test test/data/models/event_model_slot_annotations_test.dart`
Expected: FAIL — `Event`/`EventModel` have no `slotAnnotations`.

- [ ] **Step 3a: Add the field to `Event`** (`shavtzak/lib/domain/entities/event.dart`)

At the top, add the import:
```dart
import 'slot_annotation.dart';
```
Add the field near `roleRequirements` (after the `roleRequirements` declaration ~line 22):
```dart
  final Map<String, int> roleRequirements; // How many people needed per role (role key -> count)
  // Per-slot job annotations (note + label), keyed by "<roleKey>#<slotIndex>".
  // Independent of any assignment; shown on empty gaps and carried onto the
  // member when a gap is filled. See docs/superpowers/specs/2026-07-22-*.
  final Map<String, SlotAnnotation> slotAnnotations;
```
In the constructor, add a defaulted parameter (after `required this.roleRequirements,`):
```dart
    required this.roleRequirements,
    this.slotAnnotations = const {},
```
In `copyWith`, add the parameter and pass-through:
```dart
    Map<String, int>? roleRequirements,
    Map<String, SlotAnnotation>? slotAnnotations,
```
```dart
      roleRequirements: roleRequirements ?? this.roleRequirements,
      slotAnnotations: slotAnnotations ?? this.slotAnnotations,
```
In `props`, add it (after `roleRequirements,`):
```dart
        roleRequirements,
        slotAnnotations,
```

- [ ] **Step 3b: Serialize in `EventModel`** (`shavtzak/lib/data/models/event_model.dart`)

Add the import at the top:
```dart
import '../../domain/entities/slot_annotation.dart';
```
Add the field (after `roleRequirements` ~line 24) and constructor default (after `required this.roleRequirements,`):
```dart
  final Map<String, int> roleRequirements;
  final Map<String, SlotAnnotation> slotAnnotations;
```
```dart
    required this.roleRequirements,
    this.slotAnnotations = const {},
```
Add a parse helper (near `_parseParticipantGroups`):
```dart
  static Map<String, SlotAnnotation> _parseSlotAnnotations(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, SlotAnnotation>{};
    raw.forEach((key, value) {
      if (key is String && value is Map) {
        result[key] = SlotAnnotation.fromJson(Map<String, dynamic>.from(value));
      }
    });
    return result;
  }

  Map<String, dynamic> _slotAnnotationsToJson() => {
        for (final e in slotAnnotations.entries) e.key: e.value.toJson(),
      };
```
Wire all six conversion paths:
- `fromEntity`: `slotAnnotations: Map<String, SlotAnnotation>.from(entity.slotAnnotations),`
- `toEntity`: `slotAnnotations: Map<String, SlotAnnotation>.from(slotAnnotations),`
- `fromFirestore`: `slotAnnotations: _parseSlotAnnotations(data['slotAnnotations']),`
- `toFirestore`: `'slotAnnotations': _slotAnnotationsToJson(),`
- `fromJson`: `slotAnnotations: _parseSlotAnnotations(json['slotAnnotations']),`
- `toJson`: `'slotAnnotations': _slotAnnotationsToJson(),`

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shavtzak && flutter test test/data/models/event_model_slot_annotations_test.dart test/data/models/event_model_participant_groups_test.dart`
Expected: PASS (new file 3 tests; existing participant-groups tests still green).

- [ ] **Step 5: Analyze + commit**

```bash
cd shavtzak && flutter analyze lib/domain/entities/event.dart lib/data/models/event_model.dart
```
Expected: no new issues.
```bash
git add shavtzak/lib/domain/entities/event.dart shavtzak/lib/data/models/event_model.dart shavtzak/test/data/models/event_model_slot_annotations_test.dart
git commit -m "feat(event): persist slotAnnotations map on Event + EventModel"
```

---

### Task 3: Shared derivation helper (`slot_annotations.dart`)

**Files:**
- Create: `shavtzak/lib/core/utils/slot_annotations.dart`
- Test: `shavtzak/test/core/utils/slot_annotations_test.dart`

**Interfaces:**
- Consumes: `SlotAnnotation` (Task 1).
- Produces:
  - `String slotAnnotationKey(String roleKey, int slotIndex)`
  - `({String roleKey, int slotIndex})? parseSlotAnnotationKey(String key)`
  - `List<int> emptySlotIndicesForRole(int requiredCount, Iterable<int> filledSlotIndices)`
  - `typedef ResolvedGapAnnotation = ({SlotAnnotation annotation, String sourceKey});`
  - `Map<int, ResolvedGapAnnotation> reconcileGapAnnotations(Map<String,SlotAnnotation> eventSlotAnnotations, String roleKey, int requiredCount, Iterable<int> filledSlotIndices)`

- [ ] **Step 1: Write the failing test**

```dart
// shavtzak/test/core/utils/slot_annotations_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/slot_annotations.dart';
import 'package:shavtzak/domain/entities/slot_annotation.dart';

void main() {
  group('slotAnnotationKey / parse', () {
    test('builds and parses round-trip', () {
      final key = slotAnnotationKey('entryScreening', 2);
      expect(key, 'entryScreening#2');
      final parsed = parseSlotAnnotationKey(key);
      expect(parsed?.roleKey, 'entryScreening');
      expect(parsed?.slotIndex, 2);
    });
    test('parse rejects malformed keys', () {
      expect(parseSlotAnnotationKey('noindex'), isNull);
      expect(parseSlotAnnotationKey('#3'), isNull);
      expect(parseSlotAnnotationKey('role#'), isNull);
      expect(parseSlotAnnotationKey('role#x'), isNull);
    });
  });

  group('emptySlotIndicesForRole', () {
    test('returns the [0,required) indices not filled, ascending', () {
      expect(emptySlotIndicesForRole(3, {1}), [0, 2]);
      expect(emptySlotIndicesForRole(2, {0, 1}), isEmpty);
      expect(emptySlotIndicesForRole(2, {}), [0, 1]);
    });
  });

  group('reconcileGapAnnotations', () {
    const a0 = SlotAnnotation(note: 'B', labelId: 'L0');
    const a2 = SlotAnnotation(note: 'C', labelId: 'L2');

    test('maps an annotation onto its exact gap index', () {
      final res = reconcileGapAnnotations(
        {'medic#2': a2}, 'medic', 3, {0, 1});
      expect(res[2]!.annotation, a2);
      expect(res[2]!.sourceKey, 'medic#2');
      expect(res.containsKey(0), isFalse);
    });

    test('ignores annotations of other roles and empty ones', () {
      final res = reconcileGapAnnotations(
        {'other#0': a0, 'medic#0': const SlotAnnotation()}, 'medic', 2, {});
      expect(res, isEmpty);
    });

    test('drifted annotation (index now filled) surfaces on a remaining gap', () {
      // a0 stored at index 0, but index 0 is filled → must not vanish; it
      // lands on the first free gap (index 1) so the note stays visible.
      final res = reconcileGapAnnotations({'medic#0': a0}, 'medic', 2, {0});
      expect(res[1]!.annotation, a0);
      expect(res[1]!.sourceKey, 'medic#0');
    });

    test('exact matches win before drifted ones fill leftovers', () {
      final res = reconcileGapAnnotations(
        {'medic#0': a0, 'medic#2': a2}, 'medic', 3, {1});
      // gaps = [0,2]; a0 exact→0, a2 exact→2
      expect(res[0]!.annotation, a0);
      expect(res[2]!.annotation, a2);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shavtzak && flutter test test/core/utils/slot_annotations_test.dart`
Expected: FAIL — `slot_annotations.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// shavtzak/lib/core/utils/slot_annotations.dart
import '../../domain/entities/slot_annotation.dart';

/// The Event.slotAnnotations map key for one slot. Role keys never contain '#'.
String slotAnnotationKey(String roleKey, int slotIndex) => '$roleKey#$slotIndex';

/// Inverse of [slotAnnotationKey]; null for malformed keys. Splits on the LAST
/// '#' so a role key is preserved verbatim.
({String roleKey, int slotIndex})? parseSlotAnnotationKey(String key) {
  final hash = key.lastIndexOf('#');
  if (hash <= 0 || hash == key.length - 1) return null;
  final slot = int.tryParse(key.substring(hash + 1));
  if (slot == null || slot < 0) return null;
  return (roleKey: key.substring(0, hash), slotIndex: slot);
}

/// Indices in [0, requiredCount) that no assignment occupies, ascending.
List<int> emptySlotIndicesForRole(
    int requiredCount, Iterable<int> filledSlotIndices) {
  final filled = filledSlotIndices.toSet();
  return [
    for (var i = 0; i < requiredCount; i++)
      if (!filled.contains(i)) i,
  ];
}

/// An annotation resolved onto a concrete gap index, remembering the stored key
/// it came from (which may differ from the gap after drift — see the design
/// spec §10). `sourceKey` lets the editor self-heal a drifted key.
typedef ResolvedGapAnnotation = ({SlotAnnotation annotation, String sourceKey});

/// Maps a role's stored annotations onto its ACTUAL current gaps so a note
/// never silently vanishes when slots renumber. Exact index matches win; any
/// leftover (drifted) annotations fill the remaining gaps in ascending order.
Map<int, ResolvedGapAnnotation> reconcileGapAnnotations(
  Map<String, SlotAnnotation> eventSlotAnnotations,
  String roleKey,
  int requiredCount,
  Iterable<int> filledSlotIndices,
) {
  final gaps = emptySlotIndicesForRole(requiredCount, filledSlotIndices);
  if (gaps.isEmpty) return const {};

  // This role's non-empty annotations, by their stored slot index.
  final byIndex = <int, SlotAnnotation>{};
  eventSlotAnnotations.forEach((key, value) {
    final parsed = parseSlotAnnotationKey(key);
    if (parsed != null && parsed.roleKey == roleKey && !value.isEmpty) {
      byIndex[parsed.slotIndex] = value;
    }
  });
  if (byIndex.isEmpty) return const {};

  final gapSet = gaps.toSet();
  final result = <int, ResolvedGapAnnotation>{};
  final claimed = <int>{};

  // 1) Exact matches: annotation whose stored index is a current gap.
  for (final gap in gaps) {
    final ann = byIndex[gap];
    if (ann != null) {
      result[gap] = (annotation: ann, sourceKey: slotAnnotationKey(roleKey, gap));
      claimed.add(gap);
    }
  }
  // 2) Drifted annotations (stored index not a current gap) → remaining gaps.
  final leftover = (byIndex.keys.toList()..sort())
      .where((idx) => !gapSet.contains(idx))
      .toList();
  final freeGaps = gaps.where((g) => !claimed.contains(g)).toList();
  for (var i = 0; i < leftover.length && i < freeGaps.length; i++) {
    final idx = leftover[i];
    result[freeGaps[i]] =
        (annotation: byIndex[idx]!, sourceKey: slotAnnotationKey(roleKey, idx));
  }
  return result;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shavtzak && flutter test test/core/utils/slot_annotations_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/core/utils/slot_annotations.dart shavtzak/test/core/utils/slot_annotations_test.dart
git commit -m "feat(utils): shared slot-annotation key + gap reconciliation helper"
```

---

### Task 4: Backend `event.updateSlotAnnotation` mutation (⚠️ requires deploy)

**Files:**
- Create: `functions/src/slot_annotations.ts` (pure `buildSlotAnnotationMerge`)
- Create: `functions/src/slot_annotations.test.ts`
- Modify: `functions/src/index.ts` (new `case 'event.updateSlotAnnotation'` in `executeMutation`'s `switch (operation)`, ~after the `case 'event.update'` block that ends near line 3990; import the helper)

**Interfaces:**
- Produces: backend mutation `event.updateSlotAnnotation` accepting `{eventId, key, note, labelId, staleKey?}`; pure `buildSlotAnnotationMerge(key, value, staleKey?)`.

- [ ] **Step 1: Write the failing test**

```ts
// functions/src/slot_annotations.test.ts
import {test} from 'node:test';
import assert from 'node:assert';
import {FieldValue} from 'firebase-admin/firestore';
import {buildSlotAnnotationMerge} from './slot_annotations';

test('upsert writes only the one key under slotAnnotations', () => {
  const merge = buildSlotAnnotationMerge('medic#2', {note: 'C', labelId: 'L2'});
  assert.deepStrictEqual(merge, {
    slotAnnotations: {'medic#2': {note: 'C', labelId: 'L2'}},
  });
});

test('clear (null value) writes a delete sentinel for the key', () => {
  const merge = buildSlotAnnotationMerge('medic#2', null);
  const inner = (merge.slotAnnotations as Record<string, unknown>)['medic#2'];
  assert.ok(FieldValue.delete().isEqual(inner as never));
});

test('staleKey adds a second delete sentinel (self-heal)', () => {
  const merge = buildSlotAnnotationMerge(
    'medic#1', {note: 'x', labelId: null}, 'medic#3');
  const inner = merge.slotAnnotations as Record<string, unknown>;
  assert.deepStrictEqual(inner['medic#1'], {note: 'x', labelId: null});
  assert.ok(FieldValue.delete().isEqual(inner['medic#3'] as never));
});

test('staleKey equal to key is ignored', () => {
  const merge = buildSlotAnnotationMerge('medic#1', {note: 'x', labelId: null}, 'medic#1');
  const inner = merge.slotAnnotations as Record<string, unknown>;
  assert.deepStrictEqual(inner, {'medic#1': {note: 'x', labelId: null}});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npm run build`
Expected: FAIL — `./slot_annotations` module not found.

- [ ] **Step 3a: Write the pure helper** (`functions/src/slot_annotations.ts`)

```ts
import {FieldValue} from 'firebase-admin/firestore';

export type SlotAnnotationValue = {note: string; labelId: string | null};

/**
 * Builds the nested merge-set payload for one slot annotation. A merge-set with
 * a nested map touches only the listed sub-keys (siblings preserved). `null`
 * value clears the key; an optional `staleKey` (from a drifted stored key) is
 * deleted in the same atomic write so storage self-heals toward display.
 */
export function buildSlotAnnotationMerge(
  key: string,
  value: SlotAnnotationValue | null,
  staleKey?: string | null,
): Record<string, unknown> {
  const inner: Record<string, unknown> = {};
  inner[key] = value === null
    ? FieldValue.delete()
    : {note: value.note, labelId: value.labelId};
  if (staleKey && staleKey !== key) {
    inner[staleKey] = FieldValue.delete();
  }
  return {slotAnnotations: inner};
}
```

- [ ] **Step 3b: Add the mutation case** (`functions/src/index.ts`)

Add the import near the other local imports at the top of the file:
```ts
import {buildSlotAnnotationMerge} from './slot_annotations';
```
Immediately AFTER the `case 'event.update': { … }` block (it `return {ok: true};` then `}` near line 3990) and BEFORE `case 'event.delete':`, insert:
```ts
    case 'event.updateSlotAnnotation': {
      if (!actor.isAdmin) {
        throw new HttpError(403, 'אין הרשאה');
      }
      const eventId = requireString(payload['eventId'], 'eventId');
      const key = requireString(payload['key'], 'key');
      const staleKey = optionalString(payload['staleKey']);
      const note = typeof payload['note'] === 'string'
        ? (payload['note'] as string)
        : '';
      const labelIdRaw = payload['labelId'];
      const labelId = typeof labelIdRaw === 'string' && labelIdRaw.length > 0
        ? labelIdRaw
        : null;
      const eventRef = db.collection(collections.events).doc(eventId);
      const existing = await eventRef.get();
      if (!existing.exists) {
        throw new HttpError(404, 'Event not found');
      }
      const clear = note.trim().length === 0 && labelId === null;
      const merge = buildSlotAnnotationMerge(
        key, clear ? null : {note, labelId}, staleKey);
      // Targeted merge-set: no calendar job, no duplicate check — unlike
      // event.update — so a note edit never triggers calendar/Drive work.
      await eventRef.set(merge, {merge: true});
      await writeAuditLog(db, collections, actor, operation, 'event', eventId, {
        key,
        cleared: clear,
      });
      return {ok: true};
    }
```

- [ ] **Step 4: Build + run the backend test**

Run: `cd functions && npm test`
Expected: build succeeds; `slot_annotations.test.ts` passes (4 tests); existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add functions/src/slot_annotations.ts functions/src/slot_annotations.test.ts functions/src/index.ts
git commit -m "feat(functions): add side-effect-free event.updateSlotAnnotation mutation"
```

> ⚠️ **Deploy reminder:** this backend change only takes effect after `firebase deploy --only functions` (done in Task 10). Until then the client method will fail against the live backend.

---

### Task 5: Client data layer — `updateEventSlotAnnotation`

**Files:**
- Modify: `shavtzak/lib/data/data_sources/database_interface.dart` (abstract method + import)
- Modify: `shavtzak/lib/data/data_sources/firestore_database.dart` (implementation + import)
- Modify: `shavtzak/lib/data/data_sources/logging_database.dart` (forwarding wrapper + import)
- Modify: `shavtzak/lib/data/repositories/event_repository.dart` (passthrough)

**Interfaces:**
- Consumes: `SlotAnnotation` (Task 1).
- Produces: `DatabaseInterface.updateEventSlotAnnotation(String eventId, String key, SlotAnnotation? value, {String? staleKey})`; `EventRepository.updateSlotAnnotation(String eventId, String key, SlotAnnotation? value, {String? staleKey})`.

- [ ] **Step 1: Add the abstract method** (`database_interface.dart`)

Add the import (with the other entity imports):
```dart
import '../../domain/entities/slot_annotation.dart';
```
Add near `updateEvent` (~line 78):
```dart
  /// Upsert (or clear, when [value] is null) a single slot annotation on an
  /// event. Routes through the backend `event.updateSlotAnnotation` mutation
  /// (clients cannot write events directly). [staleKey], when set, deletes a
  /// drifted key in the same write (self-heal).
  Future<void> updateEventSlotAnnotation(
    String eventId,
    String key,
    SlotAnnotation? value, {
    String? staleKey,
  });
```

- [ ] **Step 2: Implement in `FirestoreDatabase`**

Add the import:
```dart
import '../../domain/entities/slot_annotation.dart';
```
Add the method near `updateEvent` (~line 586):
```dart
  @override
  Future<void> updateEventSlotAnnotation(
    String eventId,
    String key,
    SlotAnnotation? value, {
    String? staleKey,
  }) async {
    try {
      await _invokeMutation(
        'event.updateSlotAnnotation',
        payload: {
          'eventId': eventId,
          'key': key,
          'note': value?.note ?? '',
          'labelId': value?.labelId,
          'staleKey': staleKey,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to update slot annotation: $e');
    }
  }
```

- [ ] **Step 3: Forward in `LoggingDatabase`**

Add the import:
```dart
import '../../domain/entities/slot_annotation.dart';
```
Add near its `updateEvent` wrapper:
```dart
  @override
  Future<void> updateEventSlotAnnotation(
    String eventId,
    String key,
    SlotAnnotation? value, {
    String? staleKey,
  }) =>
      _runFuture(
        op: 'updateEventSlotAnnotation',
        ctx: {'collection': 'events', 'id': eventId, 'key': key},
        countOf: (_) => null,
        action: () => _inner.updateEventSlotAnnotation(eventId, key, value,
            staleKey: staleKey),
      );
```

- [ ] **Step 4: Passthrough in `EventRepository`**

Add the import if absent:
```dart
import '../../domain/entities/slot_annotation.dart';
```
Add a method (near the other event mutations):
```dart
  /// Upsert/clear one slot annotation (bypasses [updateEvent]'s duplicate check
  /// + Drive rename; this is a lightweight targeted write).
  Future<void> updateSlotAnnotation(
    String eventId,
    String key,
    SlotAnnotation? value, {
    String? staleKey,
  }) {
    return _database.updateEventSlotAnnotation(eventId, key, value,
        staleKey: staleKey);
  }
```

- [ ] **Step 5: Analyze + commit**

Run: `cd shavtzak && flutter analyze lib/data/data_sources/database_interface.dart lib/data/data_sources/firestore_database.dart lib/data/data_sources/logging_database.dart lib/data/repositories/event_repository.dart`
Expected: no new issues (in particular, no "missing concrete implementation" — both `DatabaseInterface` implementers now have the method).
```bash
git add shavtzak/lib/data/data_sources/database_interface.dart shavtzak/lib/data/data_sources/firestore_database.dart shavtzak/lib/data/data_sources/logging_database.dart shavtzak/lib/data/repositories/event_repository.dart
git commit -m "feat(data): client updateEventSlotAnnotation via backend mutation"
```

---

### Task 6: `EventBloc.UpsertSlotAnnotation` event + handler

**Files:**
- Modify: `shavtzak/lib/presentation/bloc/event/event_event.dart` (new event)
- Modify: `shavtzak/lib/presentation/bloc/event/event_bloc.dart` (register + handler; imports)
- Test: `shavtzak/test/presentation/bloc/event/event_bloc_slot_annotation_test.dart`

**Interfaces:**
- Consumes: `EventRepository.updateSlotAnnotation` (Task 5), `slotAnnotationKey` (Task 3), `SlotAnnotation` (Task 1).
- Produces: `UpsertSlotAnnotation({required String eventId, required String roleKey, required int slotIndex, required String note, required String? labelId, String? staleKey})` handled by `EventBloc`.

- [ ] **Step 1: Write the failing test**

```dart
// shavtzak/test/presentation/bloc/event/event_bloc_slot_annotation_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/data/repositories/event_repository.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/domain/entities/slot_annotation.dart';
import 'package:shavtzak/presentation/bloc/event/event_bloc.dart';
import 'package:shavtzak/presentation/bloc/event/event_event.dart';

import 'event_bloc_slot_annotation_test.mocks.dart';

@GenerateMocks([EventRepository, AssignmentRepository])
void main() {
  late MockEventRepository eventRepo;
  late MockAssignmentRepository assignmentRepo;

  setUp(() {
    eventRepo = MockEventRepository();
    assignmentRepo = MockAssignmentRepository();
    when(eventRepo.watchEvents()).thenAnswer((_) => const Stream.empty());
    when(eventRepo.watchEventCalendarSyncStates())
        .thenAnswer((_) => const Stream.empty());
    when(eventRepo.updateSlotAnnotation(any, any, any,
            staleKey: anyNamed('staleKey')))
        .thenAnswer((_) async {});
  });

  blocTest<EventBloc, dynamic>(
    'UpsertSlotAnnotation with content upserts a SlotAnnotation at the key',
    build: () => EventBloc(eventRepo, assignmentRepo),
    act: (bloc) => bloc.add(const UpsertSlotAnnotation(
      eventId: 'e1', roleKey: 'medic', slotIndex: 2,
      note: 'C', labelId: 'L2',
    )),
    verify: (_) {
      verify(eventRepo.updateSlotAnnotation(
        'e1', 'medic#2', const SlotAnnotation(note: 'C', labelId: 'L2'),
        staleKey: null)).called(1);
    },
  );

  blocTest<EventBloc, dynamic>(
    'UpsertSlotAnnotation with blank note + null label clears (null value)',
    build: () => EventBloc(eventRepo, assignmentRepo),
    act: (bloc) => bloc.add(const UpsertSlotAnnotation(
      eventId: 'e1', roleKey: 'medic', slotIndex: 2,
      note: '   ', labelId: null, staleKey: 'medic#3',
    )),
    verify: (_) {
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#2', null,
          staleKey: 'medic#3')).called(1);
    },
  );
}
```

> Note: the `EventBloc(eventRepo, assignmentRepo)` constructor call must match the real positional order (`this._repository, ...`). Adjust the constructor args in the test if the bloc takes additional required args — read `event_bloc.dart` around line 59.

- [ ] **Step 2: Generate mocks + run test to verify it fails**

Run: `cd shavtzak && dart run build_runner build --delete-conflicting-outputs && flutter test test/presentation/bloc/event/event_bloc_slot_annotation_test.dart`
Expected: FAIL — `UpsertSlotAnnotation` undefined.

- [ ] **Step 3a: Add the event** (`event_event.dart`)

```dart
/// Upsert (or clear, when note is blank and labelId is null) a single slot
/// annotation. [staleKey] self-heals a drifted stored key (see spec §10).
class UpsertSlotAnnotation extends EventEvent {
  final String eventId;
  final String roleKey;
  final int slotIndex;
  final String note;
  final String? labelId;
  final String? staleKey;

  const UpsertSlotAnnotation({
    required this.eventId,
    required this.roleKey,
    required this.slotIndex,
    required this.note,
    required this.labelId,
    this.staleKey,
  });

  @override
  List<Object?> get props =>
      [eventId, roleKey, slotIndex, note, labelId, staleKey];
}
```

- [ ] **Step 3b: Register + handle** (`event_bloc.dart`)

Add imports:
```dart
import '../../../core/utils/slot_annotations.dart';
import '../../../domain/entities/slot_annotation.dart';
```
Register (with the other `on<...>` lines, ~line 82):
```dart
    on<UpsertSlotAnnotation>(_onUpsertSlotAnnotation);
```
Add the handler:
```dart
  Future<void> _onUpsertSlotAnnotation(
      UpsertSlotAnnotation event, Emitter<EventState> emit) async {
    final key = slotAnnotationKey(event.roleKey, event.slotIndex);
    final note = event.note.trim();
    final value = (note.isEmpty && event.labelId == null)
        ? null
        : SlotAnnotation(note: note, labelId: event.labelId);
    try {
      await _repository.updateSlotAnnotation(event.eventId, key, value,
          staleKey: event.staleKey);
      // The event stream re-emits with the new slotAnnotations; both screens
      // rebuild from it. No local state emit needed.
    } catch (e) {
      emit(const EventError('שמירת ההערה נכשלה'));
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shavtzak && flutter test test/presentation/bloc/event/event_bloc_slot_annotation_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Analyze + commit**

Run: `cd shavtzak && flutter analyze lib/presentation/bloc/event`
```bash
git add shavtzak/lib/presentation/bloc/event/event_event.dart shavtzak/lib/presentation/bloc/event/event_bloc.dart shavtzak/test/presentation/bloc/event/
git commit -m "feat(event-bloc): UpsertSlotAnnotation event + handler"
```

---

### Task 7: `AssignmentSlot.gapAnnotation` + populate + carry-over

**Files:**
- Modify: `shavtzak/lib/presentation/screens/assignment/models/assignment_slot.dart` (field + props + copyWith)
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart` (populate in both build sites ~3095 & ~3454; carry-over seed in `_upsertStagedMember` ~1397)
- Test: `shavtzak/test/presentation/bloc/assignment/assignment_bloc_gap_annotation_test.dart` (carry-over unit) — OR a focused pure test of the populate logic if a bloc harness is impractical (see Step 1 note).

**Interfaces:**
- Consumes: `ResolvedGapAnnotation`, `reconcileGapAnnotations` (Task 3); `Event.slotAnnotations` (Task 2).
- Produces: `AssignmentSlot.gapAnnotation` (`ResolvedGapAnnotation?`, empty slots only); carry-over seeds `desiredNotes` + `desiredSemanticLabelId` from `gapAnnotation` when a fresh fill lands on an annotated empty slot.

- [ ] **Step 1: Add the field to `AssignmentSlot`**

Add the import:
```dart
import '../../../../core/utils/slot_annotations.dart';
```
Add the field (after `isOffQuota`):
```dart
  /// For an EMPTY slot: the reconciled gap annotation (note + label) to show,
  /// with the stored key it came from (for self-heal on edit). Null when the
  /// slot is filled or the gap has no annotation.
  final ResolvedGapAnnotation? gapAnnotation;
```
Add to the constructor:
```dart
    this.isOffQuota = false,
    this.gapAnnotation,
```
Add to `copyWith` (param + assignment). Because the type is a record and nullable, use a functional clearer to allow explicit null:
```dart
    bool? isOffQuota,
    ResolvedGapAnnotation? Function()? gapAnnotation,
```
```dart
      isOffQuota: isOffQuota ?? this.isOffQuota,
      gapAnnotation:
          gapAnnotation != null ? gapAnnotation() : this.gapAnnotation,
```
Add to `props` (after `isOffQuota`):
```dart
        isOffQuota,
        gapAnnotation,
```

- [ ] **Step 2: Populate in both build sites** (`assignment_bloc.dart`)

Add the import at the top:
```dart
import '../../../core/utils/slot_annotations.dart';
```
**Build site 1** — in `_buildSlotsFromAssignments`, just BEFORE the `for (int i = 0; i < renderCount; i++) {` loop (~line 2983), compute the role's reconciled annotations once:
```dart
        final gapAnnotations = reconcileGapAnnotations(
          event.slotAnnotations,
          role.key,
          requiredCount,
          roleAssignments.map((a) => a.slotIndex),
        );
```
Then in the `AssignmentSlot(...)` constructed at ~line 3095, add:
```dart
            currentAssignment: assignment,
            gapAnnotation: assignment == null ? gapAnnotations[i] : null,
```
**Build site 2** — in `_onRebuildAssignmentSlotsFromData`, do the same before its `for (int i ...)` loop (the one whose `AssignmentSlot(...)` is at ~line 3454, using `eventData`/`roleAssignments`):
```dart
        final gapAnnotations = reconcileGapAnnotations(
          eventData.slotAnnotations,
          role.key,
          requiredCount,
          roleAssignments.map((a) => a.slotIndex),
        );
```
```dart
              currentAssignment: assignment,
              gapAnnotation: assignment == null ? gapAnnotations[i] : null,
```

> The exact variable names (`requiredCount`, `roleAssignments`, `event` vs `eventData`) differ between the two sites — read each `for`-loop's surrounding scope and use its local names. Both loops already compute `roleAssignments` and a required/render count.

- [ ] **Step 3: Carry-over seed in `_upsertStagedMember`** (~line 1397)

Replace the body of `_upsertStagedMember`:
```dart
  Future<void> _upsertStagedMember(
      AssignmentSlot slot, String? memberId) async {
    final key = _slotKey(slot);
    final existing = _stagedChanges[key];
    final base = existing ?? _seedStaged(slot);
    var next = base.copyWith(desiredMemberId: () => memberId);
    // Carry-over (spec §9): filling a previously-empty, annotated gap seeds the
    // job's note + label onto the new assignment. Only on the FIRST staging of
    // this slot (existing == null), when actually filling (memberId != null),
    // and the slot has no DB occupant.
    final ann = slot.gapAnnotation?.annotation;
    if (existing == null &&
        memberId != null &&
        slot.currentAssignment == null &&
        ann != null &&
        !ann.isEmpty) {
      next = next.copyWith(
        desiredNotes: ann.note,
        desiredSemanticLabelId: () => ann.labelId,
      );
    }
    await _commitStaged(key, next);
  }
```

- [ ] **Step 4: Write + run the carry-over test**

```dart
// shavtzak/test/presentation/bloc/assignment/assignment_bloc_gap_annotation_test.dart
// Focused test: staging a member onto an annotated empty slot seeds the
// staged change's notes + label from the annotation. Build the AssignmentBloc
// with mocked repositories (mirror an existing assignment_bloc test's setup —
// see test/presentation/bloc/assignment/ for the constructor + mock shape),
// seed one AssignmentSlot with gapAnnotation, dispatch StageMemberChange, and
// assert the resulting staged change (exposed via the bloc's staged API used by
// other assignment_bloc tests) carries the note + labelId.
```

> Implementation note for the executor: reuse the existing assignment-bloc test harness in `test/presentation/bloc/assignment/` (there are staged-change tests already — e.g. quota-staging). Construct an `AssignmentSlot` with `gapAnnotation: (annotation: SlotAnnotation(note:'C', labelId:'L2'), sourceKey:'medic#0')`, `currentAssignment: null`, dispatch `StageMemberChange(slot, member)`, and assert the staged change for that slot key has `desiredNotes == 'C'` and `desiredSemanticLabelId == 'L2'`. If the staged list is private, assert via the rebuilt slot's `currentAssignment` (optimistic overlay) notes/label instead.

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment/assignment_bloc_gap_annotation_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

Run: `cd shavtzak && flutter analyze lib/presentation/screens/assignment/models/assignment_slot.dart lib/presentation/bloc/assignment/assignment_bloc.dart`
```bash
git add shavtzak/lib/presentation/screens/assignment/models/assignment_slot.dart shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart shavtzak/test/presentation/bloc/assignment/assignment_bloc_gap_annotation_test.dart
git commit -m "feat(assignments): populate slot gapAnnotation + carry-over on fill"
```

---

### Task 8: מסך שיבוצים — author + display gap annotations

**Files:**
- Modify: `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart`
  - `_buildAssignmentExtraInfo` (~1060): also render an empty slot's `gapAnnotation` (purple note + label chip).
  - The in-quota row `Dismissible` (~1440-1494): allow the right-swipe "edit" gesture on empty slots and open a simplified annotation dialog.
  - Add `_showGapAnnotationDialog(AssignmentSlot slot)`.

**Interfaces:**
- Consumes: `AssignmentSlot.gapAnnotation` (Task 7), `UpsertSlotAnnotation` (Task 6), `slotAnnotationKey`/`ResolvedGapAnnotation` (Task 3), `AssignmentLabel` stream already in `_buildSlotGrid`.

- [ ] **Step 1: Render the annotation for empty slots**

In `_buildSlotRow` (~1196), the `extraInfo` is currently `_buildAssignmentExtraInfo(slot.currentAssignment)` (filled only). Add a gap-annotation branch. Replace:
```dart
    final extraInfo = _buildAssignmentExtraInfo(slot.currentAssignment);
```
with:
```dart
    final extraInfo = slot.isFilled
        ? _buildAssignmentExtraInfo(slot.currentAssignment)
        : _buildGapAnnotationInfo(slot, liveLabels);
```
where `liveLabels` is the `List<AssignmentLabel>` already available in `_buildSlotGrid`'s `StreamBuilder` (thread it into `_buildSlotRow`; it is already used to resolve labels for filled rows). Add the helper (mirrors the purple note card + label chip in `_buildAssignmentExtraInfo`):
```dart
  /// Purple note card + label chip for an EMPTY slot's gap annotation. Mirrors
  /// the filled-row extra-info styling. Returns null when the gap has none.
  Widget? _buildGapAnnotationInfo(
      AssignmentSlot slot, List<AssignmentLabel> labels) {
    final ann = slot.gapAnnotation?.annotation;
    if (ann == null || ann.isEmpty) return null;
    final label = ann.labelId == null
        ? null
        : labels.firstWhereOrNull((l) => l.id == ann.labelId);
    final hasNote = ann.note.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            if (label != null) ...[
              Align(
                alignment: Alignment.center,
                child: AssignmentLabelChip(
                  label: label,
                  fontSize: 10,
                  maxLines: 3,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
              if (hasNote) const SizedBox(height: 4),
            ],
            if (hasNote)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.note_alt_outlined,
                        size: 14, color: Colors.purple.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                          text: 'הערת שיבוץ: ',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.purple.shade800),
                        ),
                        TextSpan(
                          text: ann.note,
                          style: TextStyle(
                              fontSize: 11, color: Colors.purple.shade900),
                        ),
                      ])),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
```
Ensure `collection`'s `firstWhereOrNull` is available (the file already imports `package:collection/collection.dart`).

- [ ] **Step 2: Allow the edit swipe on empty slots**

In `_buildSlotRow`'s `Dismissible` (~1442), change the empty-slot direction from delete-only to horizontal:
```dart
      direction: DismissDirection.horizontal, // edit (right) + delete (left) for filled AND empty
```
In its `confirmDismiss`, the `startToEnd` branch currently guards `if (slot.isFilled && slot.currentAssignment != null)`. Replace that branch so empty slots open the gap dialog:
```dart
        if (direction == DismissDirection.startToEnd) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (slot.isFilled && slot.currentAssignment != null) {
              _showNotesDialog(slot);
            } else if (!slot.isFilled) {
              _showGapAnnotationDialog(slot);
            }
          });
          return false; // never dismiss
        }
```

- [ ] **Step 3: Add the simplified annotation dialog**

```dart
  /// Simplified note+label editor for an EMPTY slot (no phone — that is
  /// member-level). Writes to Event.slotAnnotations via UpsertSlotAnnotation.
  Future<void> _showGapAnnotationDialog(AssignmentSlot slot) async {
    final ann = slot.gapAnnotation?.annotation;
    final noteController = TextEditingController(text: ann?.note ?? '');
    String? selectedLabelId = ann?.labelId;
    // Self-heal: if the shown annotation drifted from this row's own index,
    // delete the stale key when we write the new one.
    final ownKey = slotAnnotationKey(slot.role.key, slot.slotIndex);
    final sourceKey = slot.gapAnnotation?.sourceKey;
    final staleKey = (sourceKey != null && sourceKey != ownKey) ? sourceKey : null;

    final labels = await context
        .read<AssignmentLabelRepository>()
        .watchAssignmentLabels()
        .first;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: Text('הערת שיבוץ — ${slot.role.hebrewName}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'הערה',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: selectedLabelId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'לייבל',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('ללא לייבל')),
                    ...labels.map((l) => DropdownMenuItem<String?>(
                        value: l.id, child: Text(l.hebrewName))),
                  ],
                  onChanged: (v) => setStateDialog(() => selectedLabelId = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('ביטול'),
              ),
              TextButton(
                onPressed: () {
                  context.read<EventBloc>().add(UpsertSlotAnnotation(
                        eventId: slot.event.id,
                        roleKey: slot.role.key,
                        slotIndex: slot.slotIndex,
                        note: noteController.text.trim(),
                        labelId: selectedLabelId,
                        staleKey: staleKey,
                      ));
                  Navigator.of(dialogContext).pop();
                  _showAssignmentSnackBar('ההערה נשמרה',
                      backgroundColor: Colors.green);
                },
                child: const Text('שמירה'),
              ),
            ],
          ),
        ),
      ),
    );
  }
```
Add imports at the top if missing:
```dart
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
```
(`AssignmentLabelRepository`, `AssignmentLabelChip`, `EventBloc` provider are already in scope for this screen.)

- [ ] **Step 4: Analyze**

Run: `cd shavtzak && flutter analyze lib/presentation/screens/assignment/assignment_list_screen.dart`
Expected: no new issues.

- [ ] **Step 5: Manual smoke (the user runs the app) + commit**

Manual checklist to hand to the user (worktree path in the header):
1. On `/admin/assignments`, find an event with an unfilled role (orange empty row).
2. Swipe the empty row right → the annotation dialog opens. Add a note and pick a label → Save.
3. The empty row now shows a **purple** note card + the label chip.
4. Assign a member to that row and Save → the member's row keeps the note + label (carry-over).
5. Remove the member → the empty row shows the annotation again (carry-back).

```bash
git add shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart
git commit -m "feat(assignments-screen): author + display gap annotations on empty rows"
```

---

### Task 9: מסך מנהלים — display annotations + assign carry-over

**Files:**
- Modify: `shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart`
  - `_MissingSlot` (~1323): add `annotation` + use the REAL slot index.
  - `_buildMissingRolesSection` (~354): enumerate real gap indices via the shared helper; pass annotation down.
  - `_buildRoleAssignmentDropdown` (~435): accept `slotIndex` + `annotation`; render purple note + label chip; thread into the confirm dialog.
  - `_showAssignmentConfirmationDialog` (~819): accept `slotIndex` + `annotation`; use the real `slotIndex` and seed `notes`/`semanticLabelId` on the created `Assignment` (carry-over).

**Interfaces:**
- Consumes: `reconcileGapAnnotations`, `emptySlotIndicesForRole`, `ResolvedGapAnnotation` (Task 3); `Event.slotAnnotations` (Task 2); `AssignmentLabelChip`.

- [ ] **Step 1: Enumerate real gaps + annotations** (`_buildMissingRolesSection`, ~380)

Add the import:
```dart
import '../../../../core/utils/slot_annotations.dart';
```
Replace the `_MissingSlot` build loop (currently `for (int i = 0; i < count; i++) { missingSlots.add(_MissingSlot(... slotIndex: i + 1)); }`, ~383-389) with real-index enumeration + annotation lookup:
```dart
            final missingSlots = <_MissingSlot>[];
            for (final roleObj in roles) {
              final required = data.event.getRequiredCountForRole(roleObj.key);
              if (required == 0) continue;
              final filled = allAssignments
                  .where((a) =>
                      a.eventId == data.event.id && a.roleType == roleObj.key)
                  .map((a) => a.slotIndex);
              final resolved = reconcileGapAnnotations(
                  data.event.slotAnnotations, roleObj.key, required, filled);
              for (final gapIndex
                  in emptySlotIndicesForRole(required, filled.toList())) {
                missingSlots.add(_MissingSlot(
                  roleKey: roleObj.key,
                  roleHebrewName: roleObj.hebrewName,
                  slotIndex: gapIndex,
                  annotation: resolved[gapIndex]?.annotation,
                ));
              }
            }
```
Update the sort comparator that follows to keep using `slotIndex` (now the real index — still a valid stable tiebreak). Update the `.map((slot) => _buildRoleAssignmentDropdown(...))` call to pass the new fields:
```dart
                  children: missingSlots.map((slot) {
                    return _buildRoleAssignmentDropdown(
                      outerContext,
                      slot.roleKey,
                      slot.roleHebrewName,
                      slot.slotIndex,
                      slot.annotation,
                      data.event,
                      teamMembers,
                    );
                  }).toList(),
```

- [ ] **Step 2: Extend `_MissingSlot`** (~1323)

```dart
class _MissingSlot {
  final String roleKey;
  final String roleHebrewName;
  final int slotIndex;
  final SlotAnnotation? annotation;

  _MissingSlot({
    required this.roleKey,
    required this.roleHebrewName,
    required this.slotIndex,
    this.annotation,
  });
}
```
Add the import at the top:
```dart
import '../../../../domain/entities/slot_annotation.dart';
```

- [ ] **Step 3: Render annotation + thread through the dropdown** (`_buildRoleAssignmentDropdown`, ~435)

Update the signature to accept `int slotIndex, SlotAnnotation? annotation` (after `hebrewName`):
```dart
  Widget _buildRoleAssignmentDropdown(
    BuildContext outerContext,
    String roleKey,
    String hebrewName,
    int slotIndex,
    SlotAnnotation? annotation,
    Event event,
    List<TeamMember> teamMembers,
  ) {
```
Inside the red chip `Column` (children starting ~465), after the role-name `Row` (~483), insert the annotation display:
```dart
              if (annotation != null && !annotation.isEmpty) ...[
                const SizedBox(height: 4),
                if (annotation.labelId != null)
                  _buildSummaryLabelChip(annotation.labelId!),
                if (annotation.note.trim().isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: Text(
                      annotation.note,
                      style: TextStyle(
                          fontSize: 11, color: Colors.purple.shade900),
                    ),
                  ),
              ],
```
Add a small label-chip resolver that reads the labels stream (mirror how filled assignments resolve labels elsewhere in the summary; if a labels list isn't already in scope, wrap the chip in a `StreamBuilder<List<AssignmentLabel>>` over `context.read<AssignmentLabelRepository>().watchAssignmentLabels()`):
```dart
  Widget _buildSummaryLabelChip(String labelId) {
    return StreamBuilder<List<AssignmentLabel>>(
      stream:
          summaryContext.read<AssignmentLabelRepository>().watchAssignmentLabels(),
      builder: (context, snap) {
        final label =
            (snap.data ?? const []).where((l) => l.id == labelId).firstOrNull;
        if (label == null) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerRight,
          child: AssignmentLabelChip(label: label, fontSize: 10),
        );
      },
    );
  }
```
> Adjust `summaryContext`/imports to match the file's existing access to `AssignmentLabelRepository` and `AssignmentLabelChip`; if the summary already imports/streams labels for another purpose, reuse that stream instead of opening a new one. Add imports for `AssignmentLabelRepository`, `AssignmentLabelChip`, and `package:collection/collection.dart` (`firstOrNull`) if missing.

Update the three `_showAssignmentConfirmationDialog(outerContext, event, roleKey, hebrewName, member.id, member)` calls (~519, 536, 549) to pass `slotIndex` + `annotation`:
```dart
                      _showAssignmentConfirmationDialog(
                        outerContext, event, roleKey, hebrewName,
                        slotIndex, annotation, selectedMember.id, selectedMember,
                      );
```

- [ ] **Step 4: Carry-over on assign** (`_showAssignmentConfirmationDialog`, ~819)

Update its signature to accept `int slotIndex, SlotAnnotation? annotation` (after `hebrewName`). Inside, remove the `slotIndex = existingAssignments.length` derivation (~856) and instead use the passed-in `slotIndex`; and when building the `Assignment` for `CreateAssignment` (~859-865), seed the annotation:
```dart
                      CreateAssignment(
                        Assignment(
                          // ...existing fields...
                          slotIndex: slotIndex,
                          notes: annotation?.note ?? '',
                          semanticLabelId: annotation?.labelId,
                          // ...remaining existing fields (status, timestamps, etc.)...
                        ),
```
> Read the existing `Assignment(...)` construction at that site and change only `slotIndex`, `notes`, and `semanticLabelId`; leave every other field as-is.

- [ ] **Step 5: Analyze, manual smoke, commit**

Run: `cd shavtzak && flutter analyze lib/presentation/screens/summary/widgets/event_summary_tile.dart`
Manual checklist for the user:
1. Add a note+label to an empty slot on `/admin/assignments` (Task 8).
2. Open `/summary` (מסך מנהלים), expand that event → the role's red "missing" chip shows the **purple** note + label.
3. Assign a member from the summary chip → the created assignment keeps the note + label.
```bash
git add shavtzak/lib/presentation/screens/summary/widgets/event_summary_tile.dart
git commit -m "feat(summary): show gap annotations + carry-over on assign"
```

---

### Task 10: Full verification + deploy

**Files:** none (verification only).

- [ ] **Step 1: Full analyze**

Run: `cd shavtzak && flutter analyze`
Expected: no NEW issues vs. the baseline (~108 pre-existing infos). If any new error/warning references this feature, fix before proceeding.

- [ ] **Step 2: Full Dart test suite**

Run: `cd shavtzak && flutter test`
Expected: all tests pass (the pre-existing suite + the new Task 1/2/3/6/7 tests).

- [ ] **Step 3: Backend build + test**

Run: `cd functions && npm test`
Expected: build clean; all backend tests pass (incl. `slot_annotations.test.ts`).

- [ ] **Step 4: Deploy the backend** ⚠️ REQUIRED for the feature to work

The client's `event.updateSlotAnnotation` calls fail until the function is live. Deploy:
```bash
firebase deploy --only functions
```
(Run from the repo root. This deploys the new mutation; `firestore:rules` are unchanged. If the user prefers, they run this themselves — surface the command prominently.)

- [ ] **Step 5: End-to-end manual smoke (user runs the app)**

Hand the user this checklist (worktree: `.claude/worktrees/empty-slot-gap-annotations`, run from its `shavtzak/`):
1. `/admin/assignments`: swipe an empty role row right → add note + label → Save → purple note + label appear on the empty row.
2. `/summary` (מסך מנהלים): the same role's red missing chip shows the purple note + label.
3. Assign a member to that gap (from either screen) + Save → the member's row keeps the note + label (carry-over).
4. Remove the member → the empty row shows the annotation again (carry-back).
5. Edit the note to empty + no label → Save → the annotation disappears from both screens.
6. Confirm no calendar emails/jobs fire from a note edit (annotation writes use the dedicated mutation, not `event.update`).

- [ ] **Step 6: Finalize**

Confirm the branch is clean and all tasks are committed:
```bash
cd "/Users/omerbengal/Documents/Github Projects/Shavtzak/.claude/worktrees/empty-slot-gap-annotations" && git status && git log --oneline origin/main..HEAD
```

---

## Self-review notes (author)

- **Spec coverage:** storage (§4.1-4.3 → T1,T2), backend write (§4.4 → T4,T5), shared derivation (§5 → T3), שיבוצים author+display (§6 → T8), EventBloc (§7 → T6), מנהלים display (§8 → T9), carry-over/back (§9 → T7 fill-seed + T9 create-seed; carry-back is automatic via reconcile+display), stability (§10 → T3 `reconcileGapAnnotations` + self-heal via `staleKey` in T4/T6/T8), real-time (§11 → `slotAnnotations` in `Event.props`, T2). All covered.
- **Deploy:** flagged in Global Constraints, Task 4, and Task 10 Step 4.
- **Type consistency:** `updateEventSlotAnnotation(eventId, key, value, {staleKey})` and `updateSlotAnnotation(...)` identical across interface/impl/logging/repo; `UpsertSlotAnnotation` field names match the bloc handler; `ResolvedGapAnnotation` record shape (`annotation`, `sourceKey`) used consistently in T3/T7/T8.
