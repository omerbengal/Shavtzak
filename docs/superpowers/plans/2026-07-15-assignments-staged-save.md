# Assignments Staged "Save" Batch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `/admin/assignments` from immediate-write-per-edit to a stage-then-Save batch: assign/swap/clear/notes edits become instant in-memory changes layered over the live DB, cached for crash-recovery, and written as one atomic server-side batch on Save.

**Architecture:** Revive the dormant "pending operations overlay" already in `AssignmentBloc` (persist-until-Save instead of auto-confirm). A `Map<slotKey, StagedAssignmentChange>` in the bloc is the single source of truth (mirrored to `localStorage`); at render it is converted to the existing `_mergeSlotsWithOptimisticUpdates` overlay. Save converges each staged slot to its desired state via a new atomic backend handler `assignment.saveBatch`. A leave-guard reminds on in-app navigation while dirty.

**Tech Stack:** Flutter Web + `flutter_bloc` 8.x, `equatable`, `shared_preferences`; Firebase Cloud Functions (TypeScript, `functions/src/index.ts`, Firestore Admin SDK); tests via `flutter test` (mockito + `fake_cloud_firestore`, no `blocTest`) and backend `npm test` (`node --test`).

## Global Constraints

- **Language/RTL:** all new UI strings are Hebrew; wrap any new screen/dialog subtree in `Directionality(textDirection: TextDirection.rtl, …)`.
- **Comments in English; UI copy in Hebrew.**
- **Scope = fills + notes only.** Stage: assign / swap / clear a member, and notes/label/alt-phone edits. Do NOT change: swipe-delete-slot, the manual-add wizard, or the event-form modal — these keep their current immediate writes.
- **Equatable props use full objects, never IDs** (existing repo rule; required for real-time updates).
- **Environment prefixing:** cache keys use `EnvironmentService.instance.cachePrefix`; backend collections use `getCollections(environment).assignments`.
- **Write path is backend-mediated:** never write assignment docs from client Firestore; always go through `_invokeMutation(operation, payload)` → the `api` Cloud Function.
- **Atomic Save:** the batch is all-or-nothing. On failure, write nothing and keep the staging map + cache intact (retry-safe). Clear the cache ONLY on full success.
- **Cloud Functions do NOT auto-deploy.** Any `functions/` change requires `firebase deploy --only functions`.
- **Analyze gate:** `cd shavtzak && flutter analyze` must pass. Baseline (measured 2026-07-16 on branch tip) = **107 issues (36 warnings + 71 infos, 0 errors)**; "clean" = zero NEW issues and zero errors. Do not flag the 36 pre-existing warnings as introduced. Do not run the app — the user tests it. (Baselines: flutter test 242 passing; functions npm test 102 passing.)
- **Constructor:** `AssignmentBloc(assignmentRepo, eventRepo, teamRepo, roleRepo, calendarSyncBloc)` is positional; the 5th arg is nullable (`null` in tests). A new nullable 6th arg `userCacheService` is added by this plan (default `UserCacheService()`).

---

### Task 1: `StagedAssignmentChange` model

The per-slot staged edit. Pure Dart + Equatable + JSON; the source-of-truth unit that is cached and drives the overlay.

**Files:**
- Create: `shavtzak/lib/presentation/bloc/assignment/models/staged_assignment_change.dart`
- Test: `shavtzak/test/presentation/bloc/staged_assignment_change_test.dart`

**Interfaces:**
- Produces: `StagedAssignmentChange` with fields `slotKey, eventId, roleType, slotIndex, desiredMemberId (String?), desiredNotes (String), desiredSemanticLabelId (String?), desiredAltPhone (String?), baselineAssignmentId (String?), baselineMemberId (String?), baselineNotes (String), baselineSemanticLabelId (String?), baselineAltPhone (String?), desiredAssignmentId (String), stagedAtMillis (int)`; getters `bool get isClear`, `bool get matchesBaseline`; `Map<String,dynamic> toJson()`; `factory StagedAssignmentChange.fromJson(Map<String,dynamic>)`; static `String slotKeyFor(String eventId, String roleType, int slotIndex)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/bloc/assignment/models/staged_assignment_change.dart';

void main() {
  StagedAssignmentChange fill() => StagedAssignmentChange(
        slotKey: 'e1_medic_0',
        eventId: 'e1',
        roleType: 'medic',
        slotIndex: 0,
        desiredMemberId: 'm2',
        desiredNotes: '',
        desiredSemanticLabelId: null,
        desiredAltPhone: null,
        baselineAssignmentId: null,
        baselineMemberId: null,
        baselineNotes: '',
        baselineSemanticLabelId: null,
        baselineAltPhone: null,
        desiredAssignmentId: 'new-a1',
        stagedAtMillis: 1000,
      );

  test('slotKeyFor composes the canonical key', () {
    expect(StagedAssignmentChange.slotKeyFor('e1', 'medic', 0), 'e1_medic_0');
  });

  test('isClear is true only when desiredMemberId is null', () {
    expect(fill().isClear, isFalse);
    expect(fill().copyWith(desiredMemberId: () => null).isClear, isTrue);
  });

  test('matchesBaseline detects a revert to the original DB state', () {
    // fill over an empty slot never matches its (empty) baseline
    expect(fill().matchesBaseline, isFalse);
    // a swap back to the same member + same notes DOES match baseline
    final swap = fill().copyWith(
      baselineAssignmentId: () => 'a1',
      baselineMemberId: () => 'm2',
      desiredMemberId: () => 'm2',
    );
    expect(swap.matchesBaseline, isTrue);
  });

  test('toJson/fromJson round-trips every field', () {
    final original = fill();
    final restored = StagedAssignmentChange.fromJson(original.toJson());
    expect(restored, original);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shavtzak && flutter test test/presentation/bloc/staged_assignment_change_test.dart`
Expected: FAIL — `staged_assignment_change.dart` does not exist / `StagedAssignmentChange` undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'package:equatable/equatable.dart';

/// One staged (not-yet-saved) edit to a single assignment slot, keyed by
/// [slotKey]. Holds the DESIRED state (what the admin wants) and the BASELINE
/// snapshot (the DB state when the slot was first touched). Baseline is used
/// ONLY for conflict detection at Save; the actual write converges the current
/// DB to [desired…]. Persisted to localStorage for crash recovery.
class StagedAssignmentChange extends Equatable {
  final String slotKey;
  final String eventId;
  final String roleType;
  final int slotIndex;

  // Desired state (null desiredMemberId => staged clear).
  final String? desiredMemberId;
  final String desiredNotes;
  final String? desiredSemanticLabelId;
  final String? desiredAltPhone;

  // Baseline snapshot (DB state at first touch). Null member => slot was empty.
  final String? baselineAssignmentId;
  final String? baselineMemberId;
  final String baselineNotes;
  final String? baselineSemanticLabelId;
  final String? baselineAltPhone;

  /// Stable id to use if this staged change creates a new assignment doc.
  final String desiredAssignmentId;
  final int stagedAtMillis;

  const StagedAssignmentChange({
    required this.slotKey,
    required this.eventId,
    required this.roleType,
    required this.slotIndex,
    required this.desiredMemberId,
    required this.desiredNotes,
    required this.desiredSemanticLabelId,
    required this.desiredAltPhone,
    required this.baselineAssignmentId,
    required this.baselineMemberId,
    required this.baselineNotes,
    required this.baselineSemanticLabelId,
    required this.baselineAltPhone,
    required this.desiredAssignmentId,
    required this.stagedAtMillis,
  });

  static String slotKeyFor(String eventId, String roleType, int slotIndex) =>
      '${eventId}_${roleType}_$slotIndex';

  bool get isClear => desiredMemberId == null;

  /// True when the desired state equals the baseline (a full revert) — the
  /// change is then dropped so the slot is no longer dirty.
  bool get matchesBaseline =>
      desiredMemberId == baselineMemberId &&
      desiredNotes == baselineNotes &&
      desiredSemanticLabelId == baselineSemanticLabelId &&
      desiredAltPhone == baselineAltPhone;

  StagedAssignmentChange copyWith({
    String? Function()? desiredMemberId,
    String? desiredNotes,
    String? Function()? desiredSemanticLabelId,
    String? Function()? desiredAltPhone,
    String? Function()? baselineAssignmentId,
    String? Function()? baselineMemberId,
    int? stagedAtMillis,
  }) {
    return StagedAssignmentChange(
      slotKey: slotKey,
      eventId: eventId,
      roleType: roleType,
      slotIndex: slotIndex,
      desiredMemberId:
          desiredMemberId != null ? desiredMemberId() : this.desiredMemberId,
      desiredNotes: desiredNotes ?? this.desiredNotes,
      desiredSemanticLabelId: desiredSemanticLabelId != null
          ? desiredSemanticLabelId()
          : this.desiredSemanticLabelId,
      desiredAltPhone:
          desiredAltPhone != null ? desiredAltPhone() : this.desiredAltPhone,
      baselineAssignmentId: baselineAssignmentId != null
          ? baselineAssignmentId()
          : this.baselineAssignmentId,
      baselineMemberId:
          baselineMemberId != null ? baselineMemberId() : this.baselineMemberId,
      baselineNotes: baselineNotes,
      baselineSemanticLabelId: baselineSemanticLabelId,
      baselineAltPhone: baselineAltPhone,
      desiredAssignmentId: desiredAssignmentId,
      stagedAtMillis: stagedAtMillis ?? this.stagedAtMillis,
    );
  }

  Map<String, dynamic> toJson() => {
        'slotKey': slotKey,
        'eventId': eventId,
        'roleType': roleType,
        'slotIndex': slotIndex,
        'desiredMemberId': desiredMemberId,
        'desiredNotes': desiredNotes,
        'desiredSemanticLabelId': desiredSemanticLabelId,
        'desiredAltPhone': desiredAltPhone,
        'baselineAssignmentId': baselineAssignmentId,
        'baselineMemberId': baselineMemberId,
        'baselineNotes': baselineNotes,
        'baselineSemanticLabelId': baselineSemanticLabelId,
        'baselineAltPhone': baselineAltPhone,
        'desiredAssignmentId': desiredAssignmentId,
        'stagedAtMillis': stagedAtMillis,
      };

  factory StagedAssignmentChange.fromJson(Map<String, dynamic> json) =>
      StagedAssignmentChange(
        slotKey: json['slotKey'] as String,
        eventId: json['eventId'] as String,
        roleType: json['roleType'] as String,
        slotIndex: json['slotIndex'] as int,
        desiredMemberId: json['desiredMemberId'] as String?,
        desiredNotes: (json['desiredNotes'] as String?) ?? '',
        desiredSemanticLabelId: json['desiredSemanticLabelId'] as String?,
        desiredAltPhone: json['desiredAltPhone'] as String?,
        baselineAssignmentId: json['baselineAssignmentId'] as String?,
        baselineMemberId: json['baselineMemberId'] as String?,
        baselineNotes: (json['baselineNotes'] as String?) ?? '',
        baselineSemanticLabelId: json['baselineSemanticLabelId'] as String?,
        baselineAltPhone: json['baselineAltPhone'] as String?,
        desiredAssignmentId: json['desiredAssignmentId'] as String,
        stagedAtMillis: json['stagedAtMillis'] as int,
      );

  @override
  List<Object?> get props => [
        slotKey,
        eventId,
        roleType,
        slotIndex,
        desiredMemberId,
        desiredNotes,
        desiredSemanticLabelId,
        desiredAltPhone,
        baselineAssignmentId,
        baselineMemberId,
        baselineNotes,
        baselineSemanticLabelId,
        baselineAltPhone,
        desiredAssignmentId,
        stagedAtMillis,
      ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shavtzak && flutter test test/presentation/bloc/staged_assignment_change_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment/models/staged_assignment_change.dart shavtzak/test/presentation/bloc/staged_assignment_change_test.dart
git commit -m "feat(assignments): add StagedAssignmentChange model"
```

---

### Task 2: Cache pending staged changes (`UserCacheService`)

Persist/restore the staged list as JSON in `localStorage`, env-prefixed. Kept as `List<Map<String,dynamic>>` at the cache boundary so `core/` never depends on the presentation-layer model (the bloc maps to/from `StagedAssignmentChange`).

**Files:**
- Modify: `shavtzak/lib/core/services/user_cache_service.dart`
- Test: `shavtzak/test/core/services/user_cache_service_staged_test.dart`

**Interfaces:**
- Produces: `Future<void> savePendingAssignmentChanges(List<Map<String,dynamic>> changes)`, `Future<List<Map<String,dynamic>>> getPendingAssignmentChanges()` (empty list when none), `Future<void> clearPendingAssignmentChanges()`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shavtzak/core/services/user_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('returns empty list when nothing cached', () async {
    expect(await UserCacheService().getPendingAssignmentChanges(), isEmpty);
  });

  test('round-trips a list of change maps', () async {
    final service = UserCacheService();
    final changes = [
      {'slotKey': 'e1_medic_0', 'desiredMemberId': 'm2', 'slotIndex': 0},
      {'slotKey': 'e1_medic_1', 'desiredMemberId': null, 'slotIndex': 1},
    ];
    await service.savePendingAssignmentChanges(changes);
    expect(await service.getPendingAssignmentChanges(), changes);
  });

  test('clear removes the cached changes', () async {
    final service = UserCacheService();
    await service.savePendingAssignmentChanges([
      {'slotKey': 'e1_medic_0'}
    ]);
    await service.clearPendingAssignmentChanges();
    expect(await service.getPendingAssignmentChanges(), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shavtzak && flutter test test/core/services/user_cache_service_staged_test.dart`
Expected: FAIL — methods `savePendingAssignmentChanges` etc. undefined.

- [ ] **Step 3: Write minimal implementation**

Add `import 'dart:convert';` at the top of `user_cache_service.dart` (below the existing imports), and add this key getter next to `_selectedUserKey`:

```dart
  String get _pendingAssignmentChangesKey =>
      '${EnvironmentService.instance.cachePrefix}assignments_staged_changes';
```

Then add these methods inside the class (e.g. after `clearSelection`):

```dart
  /// Persist the staged assignment-change list (as decoded JSON maps) for
  /// crash recovery. Per-browser, env-prefixed.
  Future<void> savePendingAssignmentChanges(
      List<Map<String, dynamic>> changes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingAssignmentChangesKey, jsonEncode(changes));
    } catch (e) {
      throw UserCacheException('Failed to save pending assignment changes: $e');
    }
  }

  /// Read the staged assignment-change list. Returns an empty list when none
  /// is cached or the payload is unreadable (never throws on decode).
  Future<List<Map<String, dynamic>>> getPendingAssignmentChanges() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_pendingAssignmentChangesKey);
      if (cached == null || cached.isEmpty) return const [];
      final decoded = jsonDecode(cached);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Remove all cached staged changes (called on Save-success / discard-all).
  Future<void> clearPendingAssignmentChanges() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingAssignmentChangesKey);
    } catch (e) {
      throw UserCacheException('Failed to clear pending assignment changes: $e');
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shavtzak && flutter test test/core/services/user_cache_service_staged_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/core/services/user_cache_service.dart shavtzak/test/core/services/user_cache_service_staged_test.dart
git commit -m "feat(assignments): cache staged assignment changes in UserCacheService"
```

---

### Task 3: Backend `assignment.saveBatch` handler

Atomic mixed create+update+delete in one server-side `db.batch()`. Mirrors the existing `assignment.deleteByEvent` batch + `assignment.insert/update` validation.

**Files:**
- Modify: `functions/src/index.ts` (add a `case 'assignment.saveBatch':` in the same `switch(operation)` that contains `case 'assignment.insertBatch':` — around line 4182; the surrounding function already has `db`, `collections`, `actor`, `operation`, `payload` in scope)
- Test: `functions/src/assignment_save_batch.test.ts`

**Interfaces:**
- Consumes (existing helpers, already in `index.ts`): `requireAdmin(actor)`, `requireString(v, name)`, `assignmentDocFromJson(map)`, `validateAssignmentPayload(db, collections, assignment, assignmentId?, {bypassAvailability})`, `writeAuditLog(db, collections, actor, operation, entity, id, meta, {before?, after?})`, `getCollections(environment)`.
- Produces: operation `'assignment.saveBatch'` accepting `payload = { creates: object[], updates: object[], deletes: string[] }`; returns `{ ok: true, counts: { created, updated, deleted } }`.

- [ ] **Step 1: Write the failing test**

Backend tests run against compiled JS via `node --test`. Follow the existing `functions/src/*.test.ts` style (they import from the compiled module and use the Firestore emulator OR admin mocks — inspect a sibling test such as `functions/src/participant_groups.test.ts` for the exact harness this repo uses, and mirror its `db`/`collections` construction). The test must assert:

```ts
import {test} from 'node:test';
import assert from 'node:assert';
// Mirror the import + Firestore test-harness setup used by the sibling
// *.test.ts files in this folder (participant_groups.test.ts is the closest
// analogue — copy how it obtains a `db` and seeds collections).
import {handleMutation} from './index'; // adjust to the actual exported entry the sibling tests call

test('assignment.saveBatch applies creates, updates and deletes atomically', async () => {
  // GIVEN a seeded event E1 and an existing assignment a-old (medic slot 0)
  // WHEN saveBatch is called with:
  //   creates: [assignment a-new for E1 medic slot 1]
  //   updates: [a-old with a new teamMemberId]
  //   deletes: [] (or an id to remove)
  // THEN the result is {ok:true, counts:{created:1,updated:1,deleted:0}}
  // AND the assignments collection reflects exactly those changes.
  // (Construct db/collections/actor exactly as participant_groups.test.ts does.)
});

test('assignment.saveBatch rejects a non-admin actor', async () => {
  // WHEN called with a non-admin actor THEN it throws (requireAdmin).
});

test('assignment.saveBatch writes nothing when a create fails validation', async () => {
  // GIVEN a create with an eventId that does not exist
  // WHEN saveBatch runs THEN it throws AND no partial docs are written.
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npm test`
Expected: FAIL — `assignment.saveBatch` is not a known operation (default case throws / assertion fails).

- [ ] **Step 3: Write minimal implementation**

Add this case inside the `switch (operation)` block, immediately after `case 'assignment.insertBatch': { … }` (near line 4260). Validate all creates/updates BEFORE opening the batch (reads outside the batch), then commit one atomic batch:

```ts
    case 'assignment.saveBatch': {
      requireAdmin(actor);
      const creates = (payload['creates'] as Record<string, unknown>[]) ?? [];
      const updates = (payload['updates'] as Record<string, unknown>[]) ?? [];
      const deletes = (payload['deletes'] as string[]) ?? [];

      // Validate every create/update up-front (reads happen before the batch).
      for (const a of creates) {
        requireString(a['id'], 'assignment.id');
        await validateAssignmentPayload(db, collections, a, undefined, {
          bypassAvailability: true,
        });
      }
      for (const a of updates) {
        const id = requireString(a['id'], 'assignment.id');
        await validateAssignmentPayload(db, collections, a, id, {
          bypassAvailability: true,
        });
      }

      // Capture "before" state of updated/deleted docs for audit.
      const before = new Map<string, Record<string, unknown>>();
      for (const a of updates) {
        const id = requireString(a['id'], 'assignment.id');
        const snap = await db.collection(collections.assignments).doc(id).get();
        if (snap.exists) before.set(id, snap.data() ?? {});
      }
      for (const id of deletes) {
        const snap = await db.collection(collections.assignments).doc(id).get();
        if (snap.exists) before.set(id, snap.data() ?? {});
      }

      // One atomic batch (≤500 ops — a meeting is far under).
      const batch = db.batch();
      for (const a of creates) {
        const id = requireString(a['id'], 'assignment.id');
        batch.create(
          db.collection(collections.assignments).doc(id),
          assignmentDocFromJson(a),
        );
      }
      for (const a of updates) {
        const id = requireString(a['id'], 'assignment.id');
        batch.update(
          db.collection(collections.assignments).doc(id),
          assignmentDocFromJson(a),
        );
      }
      for (const id of deletes) {
        batch.delete(db.collection(collections.assignments).doc(id));
      }
      await batch.commit();

      // Audit each op (best-effort, after the atomic commit succeeded).
      for (const a of creates) {
        const id = requireString(a['id'], 'assignment.id');
        await writeAuditLog(db, collections, actor, 'assignment.insert',
          'assignment', id, {}, {after: assignmentDocFromJson(a)});
      }
      for (const a of updates) {
        const id = requireString(a['id'], 'assignment.id');
        await writeAuditLog(db, collections, actor, 'assignment.update',
          'assignment', id, {}, {
            before: before.get(id) ?? {},
            after: assignmentDocFromJson(a),
          });
      }
      for (const id of deletes) {
        await writeAuditLog(db, collections, actor, 'assignment.delete',
          'assignment', id, {}, {before: before.get(id) ?? {}});
      }

      return {
        ok: true,
        counts: {
          created: creates.length,
          updated: updates.length,
          deleted: deletes.length,
        },
      };
    }
```

Note on `batch.update`: if `assignmentDocFromJson` omits `createdAt` for an update, prefer `batch.set(ref, doc, {merge: true})` to avoid clobbering. Inspect `assignmentDocFromJson` (line 2761) — if it always emits a full doc including `createdAt`, `batch.update` is correct; otherwise switch those two lines to `batch.set(ref, doc)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npm test`
Expected: PASS (the three new tests, plus the existing suite still green).

- [ ] **Step 5: Commit**

```bash
git add functions/src/index.ts functions/src/assignment_save_batch.test.ts
git commit -m "feat(functions): add atomic assignment.saveBatch mutation"
```

> **Deploy is deferred to Task 13** (after the client is wired), but note now: this handler is inert until `firebase deploy --only functions` runs.

---

### Task 4: Client `saveAssignmentsBatch` (data layer)

Thin client that ships the staged batch to the new backend op.

**Files:**
- Modify: `shavtzak/lib/data/data_sources/database_interface.dart` (add abstract method near the other batch ops, ~line 197)
- Modify: `shavtzak/lib/data/data_sources/firestore_database.dart` (implement near `insertAssignmentsBatch`, ~line 1173; reuse `_assignmentEntityToMap` and `_invokeMutation`)
- Modify: `shavtzak/lib/data/repositories/assignment_repository.dart` (expose + `clearCache()` after)
- Test: `shavtzak/test/data/repositories/assignment_repository_save_batch_test.dart`

**Interfaces:**
- Produces: `Future<void> saveAssignmentsBatch({required List<Assignment> creates, required List<Assignment> updates, required List<String> deletes})` on `DatabaseInterface`, `FirestoreDatabase`, and `AssignmentRepository`.

- [ ] **Step 1: Write the failing test** (repository passes through to the data source; mockito)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/data_sources/database_interface.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/domain/entities/assignment.dart';

import 'assignment_repository_save_batch_test.mocks.dart';

@GenerateMocks([DatabaseInterface])
void main() {
  Assignment a(String id) => Assignment(
        id: id, eventId: 'e1', teamMemberId: 'm1', roleType: 'medic',
        slotIndex: 0, status: AssignmentStatus.confirmed, notes: '',
        createdAt: DateTime(2026), updatedAt: DateTime(2026),
      );

  test('saveAssignmentsBatch forwards creates/updates/deletes to the database', () async {
    final db = MockDatabaseInterface();
    when(db.saveAssignmentsBatch(
      creates: anyNamed('creates'),
      updates: anyNamed('updates'),
      deletes: anyNamed('deletes'),
    )).thenAnswer((_) async {});
    final repo = AssignmentRepository(db);

    await repo.saveAssignmentsBatch(
      creates: [a('c1')], updates: [a('u1')], deletes: ['d1'],
    );

    verify(db.saveAssignmentsBatch(
      creates: argThat(hasLength(1), named: 'creates'),
      updates: argThat(hasLength(1), named: 'updates'),
      deletes: ['d1'],
    )).called(1);
  });
}
```

Confirm `AssignmentRepository`'s constructor arg name/shape by opening the file; adjust `AssignmentRepository(db)` if it takes a named param. Regenerate mocks:

- [ ] **Step 2: Generate mocks + run test to verify it fails**

Run:
```bash
cd shavtzak && dart run build_runner build --delete-conflicting-outputs && flutter test test/data/repositories/assignment_repository_save_batch_test.dart
```
Expected: FAIL — `saveAssignmentsBatch` undefined on `DatabaseInterface`/`AssignmentRepository`.

- [ ] **Step 3: Write minimal implementation**

In `database_interface.dart` (Batch Operations section):

```dart
  /// Atomically create + update + delete assignments in one server-side batch.
  Future<void> saveAssignmentsBatch({
    required List<Assignment> creates,
    required List<Assignment> updates,
    required List<String> deletes,
  });
```

In `firestore_database.dart` (near `insertAssignmentsBatch`):

```dart
  @override
  Future<void> saveAssignmentsBatch({
    required List<Assignment> creates,
    required List<Assignment> updates,
    required List<String> deletes,
  }) async {
    if (creates.isEmpty && updates.isEmpty && deletes.isEmpty) return;
    try {
      await _invokeMutation(
        'assignment.saveBatch',
        payload: {
          'creates': creates.map(_assignmentEntityToMap).toList(),
          'updates': updates.map(_assignmentEntityToMap).toList(),
          'deletes': deletes,
        },
      );
    } catch (e) {
      throw DatabaseException('Failed to save assignments batch: $e');
    }
  }
```

In `assignment_repository.dart` (near `deleteAssignmentsBatch`):

```dart
  /// Atomically persist a staged batch of assignment changes, then invalidate
  /// the relation cache so the next read repopulates.
  Future<void> saveAssignmentsBatch({
    required List<Assignment> creates,
    required List<Assignment> updates,
    required List<String> deletes,
  }) async {
    await _database.saveAssignmentsBatch(
      creates: creates,
      updates: updates,
      deletes: deletes,
    );
    clearCache();
  }
```

(Confirm the private field name for the data source in `AssignmentRepository` — it may be `_database` or `_databaseInterface`; match the file.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shavtzak && flutter test test/data/repositories/assignment_repository_save_batch_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/data/ shavtzak/test/data/repositories/assignment_repository_save_batch_test.dart
git commit -m "feat(assignments): client saveAssignmentsBatch through backend mutation"
```

---

### Task 5: Make `PendingOperation` persist (no auto-expire)

The overlay merge drops ops via `isExpired`. Staged ops must never expire. Add an opt-in `persistent` flag.

**Files:**
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_state.dart` (the `PendingOperation` class, ~line 202)
- Test: `shavtzak/test/presentation/bloc/pending_operation_persistent_test.dart`

**Interfaces:**
- Produces: `PendingOperation(..., bool persistent = false)`; `isExpired` returns `false` whenever `persistent` is true.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';

void main() {
  test('a persistent operation never expires', () {
    final op = PendingOperation(
      id: 'op1',
      type: PendingOperationType.createAssignment,
      slotKey: 'e1_medic_0',
      timestamp: DateTime(2000), // ancient
      persistent: true,
    );
    expect(op.isExpired, isFalse);
  });

  test('a non-persistent operation still expires after 5 minutes', () {
    final op = PendingOperation(
      id: 'op1',
      type: PendingOperationType.createAssignment,
      slotKey: 'e1_medic_0',
      timestamp: DateTime(2000),
    );
    expect(op.isExpired, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shavtzak && flutter test test/presentation/bloc/pending_operation_persistent_test.dart`
Expected: FAIL — `persistent` named param undefined.

- [ ] **Step 3: Write minimal implementation**

In `PendingOperation`: add `final bool persistent;`, default it in the constructor (`this.persistent = false`), add `persistent` to `props`, and change `isExpired`:

```dart
  bool get isExpired =>
      !persistent && DateTime.now().difference(timestamp).inMinutes > 5;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shavtzak && flutter test test/presentation/bloc/pending_operation_persistent_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment/assignment_state.dart shavtzak/test/presentation/bloc/pending_operation_persistent_test.dart
git commit -m "feat(assignments): add persistent flag to PendingOperation"
```

---

### Task 6: Bloc staging — events, state, handlers, cache, overlay wiring

The core. Staging map is the source of truth; it derives persistent `PendingOperation`s fed to the existing merge, is mirrored to cache, and exposes dirtiness on the state.

**Files:**
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_event.dart` (new events)
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_state.dart` (`AssignmentSlotsLoaded.stagedSlotKeys`)
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart` (staging map, handlers, cache, merge wiring, `hasStagedChanges`, constructor arg)
- Modify: `shavtzak/lib/core/services/service_locator.dart` and `shavtzak/lib/main.dart` (pass `UserCacheService` into the bloc factory) — only if the bloc gains a required dep; keep it **nullable defaulting to `UserCacheService()`** so these call sites need no change.
- Test: `shavtzak/test/presentation/bloc/assignment_bloc_staging_test.dart`

**Interfaces:**
- Consumes: `StagedAssignmentChange` (Task 1), `UserCacheService.savePendingAssignmentChanges/getPendingAssignmentChanges/clearPendingAssignmentChanges` (Task 2), `PendingOperation(persistent: true)` (Task 5).
- Produces on the bloc: events `StageMemberChange({required AssignmentSlot slot, required TeamMember? member})`, `StageNotesChange({required AssignmentSlot slot, required String notes, String? semanticLabelId, String? alternativePhoneNumber})`, `DiscardStagedSlot(String slotKey)`, `DiscardAllStagedChanges()`, `RehydrateStagedChanges()`; getter `bool get hasStagedChanges`; `AssignmentSlotsLoaded.stagedSlotKeys` (`Set<String>`, default `{}`) + `int get stagedCount`.

- [ ] **Step 1: Write the failing test** (staging a fill shows on the slot and marks it dirty; revert clears it)

```dart
// Reuse the harness from test/presentation/bloc/assignment_bloc_slots_refetch_test.dart
// (mockito repo mocks + StreamControllers + entity builders). Add UserCacheService
// mock init via SharedPreferences.setMockInitialValues({}) in setUp.
//
// buildBloc() now passes a real UserCacheService (backed by the SharedPreferences
// mock): AssignmentBloc(assignmentRepo, eventRepo, teamRepo, roleRepo, null,
//   userCacheService: UserCacheService());

test('staging a member fill marks the slot filled and dirty', () async {
  final bloc = buildBloc();
  addTearDown(() async => bloc.close());
  bloc.add(const LoadAssignmentSlots());
  await pumpEventQueue();
  eventStream.add([futureEvent('e1', medicQuota: 1)]);
  roleStream.add([medicRole()]);
  assignmentStream.add(const <Assignment>[]);
  await pumpEventQueue();

  final loaded = bloc.state as AssignmentSlotsLoaded;
  final emptyMedicSlot = loaded.slots.firstWhere(
      (s) => s.role.key == 'medic' && s.slotIndex == 0);
  expect(emptyMedicSlot.isFilled, isFalse);

  bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
  await pumpEventQueue();

  final after = bloc.state as AssignmentSlotsLoaded;
  final medicSlot = after.slots.firstWhere(
      (s) => s.role.key == 'medic' && s.slotIndex == 0);
  expect(medicSlot.isFilled, isTrue);
  expect(medicSlot.currentAssignment!.teamMemberId, 'm1');
  expect(after.stagedSlotKeys, contains('e1_medic_0'));
  expect(bloc.hasStagedChanges, isTrue);
});

test('discarding the staged slot reverts to the DB (empty) and clears dirty', () async {
  // ...stage as above, then:
  bloc.add(const DiscardStagedSlot('e1_medic_0'));
  await pumpEventQueue();
  final after = bloc.state as AssignmentSlotsLoaded;
  expect(after.stagedSlotKeys, isEmpty);
  expect(bloc.hasStagedChanges, isFalse);
  expect(after.slots.firstWhere((s) => s.role.key == 'medic').isFilled, isFalse);
});
```

(If the existing `futureEvent(...)` builder has no `medicQuota` param, extend it to set `roleRequirements: {'medic': 1}`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_staging_test.dart`
Expected: FAIL — events/`hasStagedChanges`/`stagedSlotKeys` undefined.

- [ ] **Step 3: Write minimal implementation**

**a. `assignment_event.dart`** — add:

```dart
/// Stage a member fill/swap/clear on [slot] (member == null => clear).
class StageMemberChange extends AssignmentEvent {
  final AssignmentSlot slot;
  final TeamMember? member;
  const StageMemberChange({required this.slot, required this.member});
  @override
  List<Object?> get props => [slot, member];
}

/// Stage a notes/label/alt-phone edit on [slot].
class StageNotesChange extends AssignmentEvent {
  final AssignmentSlot slot;
  final String notes;
  final String? semanticLabelId;
  final String? alternativePhoneNumber;
  const StageNotesChange({
    required this.slot,
    required this.notes,
    this.semanticLabelId,
    this.alternativePhoneNumber,
  });
  @override
  List<Object?> get props => [slot, notes, semanticLabelId, alternativePhoneNumber];
}

class DiscardStagedSlot extends AssignmentEvent {
  final String slotKey;
  const DiscardStagedSlot(this.slotKey);
  @override
  List<Object?> get props => [slotKey];
}

class DiscardAllStagedChanges extends AssignmentEvent {
  const DiscardAllStagedChanges();
}

class RehydrateStagedChanges extends AssignmentEvent {
  const RehydrateStagedChanges();
}
```

Add `import '../../screens/assignment/models/assignment_slot.dart';` to `assignment_event.dart` (for the `AssignmentSlot` param).

**b. `assignment_state.dart`** — add `stagedSlotKeys` to `AssignmentSlotsLoaded`:
- add field `final Set<String> stagedSlotKeys;`
- default it in both the constructor (`this.stagedSlotKeys = const {}`) and `copyWith` (accept `Set<String>? stagedSlotKeys` and pass through)
- add `stagedSlotKeys` to `props`
- add getter `int get stagedCount => stagedSlotKeys.length;`

**c. `assignment_bloc.dart`**:
- Add field `final Map<String, StagedAssignmentChange> _stagedChanges = {};`
- Add constructor param `UserCacheService? userCacheService` (nullable, last) → store `_userCache = userCacheService ?? UserCacheService();` (add the import). Register handlers in the constructor body:
  ```dart
  on<StageMemberChange>(_onStageMemberChange);
  on<StageNotesChange>(_onStageNotesChange);
  on<DiscardStagedSlot>(_onDiscardStagedSlot);
  on<DiscardAllStagedChanges>(_onDiscardAllStagedChanges);
  on<RehydrateStagedChanges>(_onRehydrateStagedChanges);
  ```
- Add getter `bool get hasStagedChanges => _stagedChanges.isNotEmpty;`
- Add the staging helpers + handlers:

```dart
  String _slotKey(AssignmentSlot slot) =>
      StagedAssignmentChange.slotKeyFor(slot.event.id, slot.role.key, slot.slotIndex);

  /// Seed a fresh staged change from the slot's current DB occupant, which
  /// becomes the baseline (null occupant => the slot started empty).
  StagedAssignmentChange _seedStaged(AssignmentSlot slot) {
    final db = slot.currentAssignment;
    return StagedAssignmentChange(
      slotKey: _slotKey(slot),
      eventId: slot.event.id,
      roleType: slot.role.key,
      slotIndex: slot.slotIndex,
      desiredMemberId: db?.teamMemberId,
      desiredNotes: db?.notes ?? '',
      desiredSemanticLabelId: db?.semanticLabelId,
      desiredAltPhone: db?.alternativePhoneNumber,
      baselineAssignmentId: db?.id,
      baselineMemberId: db?.teamMemberId,
      baselineNotes: db?.notes ?? '',
      baselineSemanticLabelId: db?.semanticLabelId,
      baselineAltPhone: db?.alternativePhoneNumber,
      desiredAssignmentId: db?.id ?? const Uuid().v4(),
      stagedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Store [change] under [key], or drop it if it reverts to baseline; then
  /// mirror to cache.
  void _commitStaged(String key, StagedAssignmentChange change) {
    if (change.matchesBaseline) {
      _stagedChanges.remove(key);
    } else {
      _stagedChanges[key] = change;
    }
    _persistStaged();
  }

  /// Stage a member fill/swap/clear (memberId == null => clear).
  void _upsertStagedMember(AssignmentSlot slot, String? memberId) {
    final key = _slotKey(slot);
    final base = _stagedChanges[key] ?? _seedStaged(slot);
    _commitStaged(key, base.copyWith(desiredMemberId: () => memberId));
  }

  /// Stage a notes/label/alt-phone edit (member left unchanged).
  void _upsertStagedNotes(
      AssignmentSlot slot, String notes, String? labelId, String? altPhone) {
    final key = _slotKey(slot);
    final base = _stagedChanges[key] ?? _seedStaged(slot);
    _commitStaged(
      key,
      base.copyWith(
        desiredNotes: notes,
        desiredSemanticLabelId: () => labelId,
        desiredAltPhone: () => altPhone,
      ),
    );
  }
```

```dart
  Future<void> _onStageMemberChange(
      StageMemberChange event, Emitter<AssignmentState> emit) async {
    _upsertStagedMember(event.slot, event.member?.id);
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  Future<void> _onStageNotesChange(
      StageNotesChange event, Emitter<AssignmentState> emit) async {
    _upsertStagedNotes(event.slot, event.notes, event.semanticLabelId,
        event.alternativePhoneNumber);
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  Future<void> _onDiscardStagedSlot(
      DiscardStagedSlot event, Emitter<AssignmentState> emit) async {
    _stagedChanges.remove(event.slotKey);
    await _persistStaged();
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  Future<void> _onDiscardAllStagedChanges(
      DiscardAllStagedChanges event, Emitter<AssignmentState> emit) async {
    _stagedChanges.clear();
    await _userCache.clearPendingAssignmentChanges();
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  Future<void> _onRehydrateStagedChanges(
      RehydrateStagedChanges event, Emitter<AssignmentState> emit) async {
    final maps = await _userCache.getPendingAssignmentChanges();
    _stagedChanges
      ..clear()
      ..addEntries(maps
          .map(StagedAssignmentChange.fromJson)
          .map((c) => MapEntry(c.slotKey, c)));
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  Future<void> _persistStaged() async {
    await _userCache.savePendingAssignmentChanges(
        _stagedChanges.values.map((c) => c.toJson()).toList());
  }

  /// Convert staged changes to persistent PendingOperations for the merge.
  Map<String, PendingOperation> _stagedAsPendingOperations() {
    final ops = <String, PendingOperation>{};
    _stagedChanges.forEach((key, c) {
      final PendingOperationType type;
      Assignment? optimistic;
      if (c.isClear) {
        type = PendingOperationType.deleteAssignment;
      } else {
        type = c.baselineMemberId == null
            ? PendingOperationType.createAssignment
            : PendingOperationType.updateAssignment;
        optimistic = Assignment(
          id: c.desiredAssignmentId,
          eventId: c.eventId,
          teamMemberId: c.desiredMemberId!,
          roleType: c.roleType,
          slotIndex: c.slotIndex,
          status: AssignmentStatus.confirmed,
          notes: c.desiredNotes,
          semanticLabelId: c.desiredSemanticLabelId,
          alternativePhoneNumber: c.desiredAltPhone,
          createdAt: DateTime.fromMillisecondsSinceEpoch(c.stagedAtMillis),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(c.stagedAtMillis),
          teamMember: _windowMembersMap[c.desiredMemberId],
        );
      }
      ops[key] = PendingOperation(
        id: key,
        type: type,
        slotKey: key,
        optimisticAssignment: optimistic,
        timestamp: DateTime.fromMillisecondsSinceEpoch(c.stagedAtMillis),
        persistent: true,
      );
    });
    return ops;
  }
```

Implement `_upsertStagedMember(slot, memberId)` and `_upsertStagedNotes(slot, notes, label, phone)` as the two concrete versions described in the note above (each builds/updates the slot's `StagedAssignmentChange`, drops on `matchesBaseline`, then `_persistStaged()`).

- **Wire the overlay:** at each merge call site on the slots-view path (`_onRebuildAssignmentSlotsFromData` ~line 2028 and the site ~line 1782), assign `_pendingOperations = _stagedAsPendingOperations();` immediately before calling `_mergeSlotsWithOptimisticUpdates(...)`. In **every** `AssignmentSlotsLoaded(...)` construction on the slots-view path (rebuild-from-data, `_onRebuildAssignmentSlots`, and the load-more emit), pass `stagedSlotKeys: _stagedChanges.keys.toSet()` — otherwise a later emit with the `const {}` default would flicker the dirty borders off. (Grep `AssignmentSlotsLoaded(` in the bloc and add the arg to each slots-view emission.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_staging_test.dart`
Expected: PASS. Then run the full bloc suite to catch regressions in the merge path:
`cd shavtzak && flutter test test/presentation/bloc/`
Expected: PASS (all existing bloc tests still green).

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment/ shavtzak/test/presentation/bloc/assignment_bloc_staging_test.dart
git commit -m "feat(assignments): stage member/notes edits in AssignmentBloc with cache"
```

---

### Task 7: Bloc conflict classification

Compute the A–F conflicts by comparing each staged change's baseline against the current DB slots.

**Files:**
- Create: `shavtzak/lib/presentation/bloc/assignment/models/assignment_conflict.dart`
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart` (add `List<AssignmentConflict> classifyStagedConflicts(List<AssignmentSlot> currentSlots)`)
- Test: `shavtzak/test/presentation/bloc/assignment_conflict_test.dart`

**Interfaces:**
- Produces: `enum AssignmentConflictType { slotTaken, targetRemoved, clearCollision, slotVanished, memberGone, notesChanged }`; `enum ConflictResolution { overrideDb, takeDb }`; `class AssignmentConflict { final String slotKey; final AssignmentConflictType type; final String description; final bool discardOnly; }`; bloc method `List<AssignmentConflict> classifyStagedConflicts(List<AssignmentSlot> currentSlots)`.

- [ ] **Step 1: Write the failing test** (one case per type; here: slotTaken)

```dart
// Harness as in Task 6. Stage a fill on an empty medic slot, then emit a DB
// snapshot where that same slot is now filled by a DIFFERENT member.

test('classifies a concurrently-filled slot as slotTaken', () async {
  // stage m1 into e1 medic 0 (baseline empty)
  bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
  await pumpEventQueue();
  // DB now shows m9 in that slot
  assignmentStream.add([assignment('a9', 'e1', 'm9', role: 'medic', slotIndex: 0)]);
  await pumpEventQueue();

  final loaded = bloc.state as AssignmentSlotsLoaded;
  final conflicts = bloc.classifyStagedConflicts(loaded.slots);
  expect(conflicts, hasLength(1));
  expect(conflicts.single.type, AssignmentConflictType.slotTaken);
  expect(conflicts.single.slotKey, 'e1_medic_0');
});
```

Add analogous tests for `clearCollision` (stage clear of m1; DB now m9), `slotVanished` (stage fill; DB quota removes the slot → not present in `currentSlots`), and `noConflict` (stage fill; DB unchanged → empty list). Use a `test` per case.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_conflict_test.dart`
Expected: FAIL — `classifyStagedConflicts` / `AssignmentConflict` undefined.

- [ ] **Step 3: Write minimal implementation**

`assignment_conflict.dart`:

```dart
enum AssignmentConflictType {
  slotTaken,       // A: fill/swap; DB now a different member
  targetRemoved,   // B: swap/notes; DB assignment gone (now empty)
  clearCollision,  // C: clear; DB now a different member
  slotVanished,    // D: quota shrank; slot no longer exists
  memberGone,      // E: assigned member deactivated/deleted
  notesChanged,    // F: notes edit collides with a DB notes change
}

enum ConflictResolution { overrideDb, takeDb }

class AssignmentConflict {
  final String slotKey;
  final AssignmentConflictType type;
  final String description; // Hebrew, human-readable
  final bool discardOnly;   // true => single-button (E fully-deleted only). D is two-button.
  const AssignmentConflict({
    required this.slotKey,
    required this.type,
    required this.description,
    this.discardOnly = false,
  });
}
```

In `assignment_bloc.dart`:

```dart
  /// Compare each staged change's baseline to the current DB slots and return
  /// the conflicts to resolve at Save. A slot conflicts when its current DB
  /// occupant differs from the baseline captured at first touch.
  List<AssignmentConflict> classifyStagedConflicts(
      List<AssignmentSlot> currentSlots) {
    final byKey = {for (final s in currentSlots) _getSlotKey(s): s};
    final conflicts = <AssignmentConflict>[];

    _stagedChanges.forEach((key, c) {
      final slot = byKey[key];

      // D: slot no longer exists (quota shrank / role removed). Two-button:
      // override = create off-quota (handled in Save), takeDb = discard.
      if (slot == null) {
        conflicts.add(AssignmentConflict(
          slotKey: key,
          type: AssignmentConflictType.slotVanished,
          description:
              'המכסה של "${c.roleType}" באירוע קטנה, והמשרה ששיבצת אליה כבר לא קיימת.',
          discardOnly: false,
        ));
        return;
      }

      final dbMemberId = slot.currentAssignment?.teamMemberId;
      final dbNotes = slot.currentAssignment?.notes ?? '';
      final baselineMember = c.baselineMemberId;

      // No divergence from baseline (member + notes) => no conflict.
      final memberDiverged = dbMemberId != baselineMember;
      final notesDiverged = dbNotes != c.baselineNotes;
      if (!memberDiverged && !notesDiverged) return;

      if (c.isClear) {
        // C: you cleared baseline B, DB now holds a different member.
        if (dbMemberId != null && dbMemberId != baselineMember) {
          conflicts.add(AssignmentConflict(
            slotKey: key,
            type: AssignmentConflictType.clearCollision,
            description: 'ניקית שיבוץ שקיים, אך בינתיים שובץ שם אדם אחר ב-DB.',
          ));
        }
        return; // clear + already-empty is satisfied, not a conflict
      }

      if (dbMemberId == null && baselineMember != null) {
        // B: your swap/notes target was deleted.
        conflicts.add(AssignmentConflict(
          slotKey: key,
          type: AssignmentConflictType.targetRemoved,
          description: 'השיבוץ ששינית נמחק בינתיים ב-DB.',
        ));
        return;
      }

      if (memberDiverged) {
        // A: slot taken by a different member than your baseline.
        conflicts.add(AssignmentConflict(
          slotKey: key,
          type: AssignmentConflictType.slotTaken,
          description: 'המשרה נתפסה: בינתיים שובץ שם אדם אחר ב-DB.',
        ));
        return;
      }

      // F: notes changed underneath a notes-only edit.
      conflicts.add(AssignmentConflict(
        slotKey: key,
        type: AssignmentConflictType.notesChanged,
        description: 'ההערות/הלייבל של השיבוץ שונו בינתיים ב-DB.',
      ));
    });

    return conflicts;
  }
```

(Member-gone type E — if `_windowMembersMap[c.desiredMemberId]` is null/inactive — can be added as a follow-up refinement; the four core cases above are what the tests cover. Keep the description strings final and stable.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_conflict_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment/models/assignment_conflict.dart shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart shavtzak/test/presentation/bloc/assignment_conflict_test.dart
git commit -m "feat(assignments): classify staged-vs-DB conflicts"
```

---

### Task 8: Bloc `SaveStagedChanges` handler

Converge each applied staged slot to its desired state against the current DB, build the create/update/delete lists, call `saveAssignmentsBatch`, and clear staging+cache only on success.

**Files:**
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_event.dart` (`SaveStagedChanges`)
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart` (`_onSaveStagedChanges`)
- Test: `shavtzak/test/presentation/bloc/assignment_bloc_save_test.dart`

**Interfaces:**
- Consumes: `AssignmentRepository.saveAssignmentsBatch` (Task 4); `Map<String, ConflictResolution>` (Task 7); `CrudActionCompleter` (existing).
- Produces: event `SaveStagedChanges({Map<String, ConflictResolution>? resolutions, CrudActionCompleter? completion})`; handler `_onSaveStagedChanges`.

- [ ] **Step 1: Write the failing test**

```dart
// Harness as in Task 6, but capture calls to assignmentRepo.saveAssignmentsBatch.
test('Save writes the staged fill and clears staging on success', () async {
  when(assignmentRepo.saveAssignmentsBatch(
    creates: anyNamed('creates'),
    updates: anyNamed('updates'),
    deletes: anyNamed('deletes'),
  )).thenAnswer((_) async {});

  // stage m1 into empty e1 medic 0
  bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
  await pumpEventQueue();

  bloc.add(const SaveStagedChanges());
  await pumpEventQueue();

  final captured = verify(assignmentRepo.saveAssignmentsBatch(
    creates: captureAnyNamed('creates'),
    updates: anyNamed('updates'),
    deletes: anyNamed('deletes'),
  )).captured.single as List<Assignment>;
  expect(captured, hasLength(1));
  expect(captured.single.teamMemberId, 'm1');
  expect(bloc.hasStagedChanges, isFalse); // cleared on success
});

test('Save keeps staging intact when the batch throws', () async {
  when(assignmentRepo.saveAssignmentsBatch(
    creates: anyNamed('creates'), updates: anyNamed('updates'), deletes: anyNamed('deletes'),
  )).thenThrow(Exception('boom'));
  bloc.add(StageMemberChange(slot: emptyMedicSlot, member: member('m1')));
  await pumpEventQueue();
  bloc.add(const SaveStagedChanges());
  await pumpEventQueue();
  expect(bloc.hasStagedChanges, isTrue); // retry-safe
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_save_test.dart`
Expected: FAIL — `SaveStagedChanges` undefined.

- [ ] **Step 3: Write minimal implementation**

`assignment_event.dart`:

```dart
class SaveStagedChanges extends AssignmentEvent {
  final Map<String, ConflictResolution>? resolutions; // slotKey -> decision
  final CrudActionCompleter? completion;
  const SaveStagedChanges({this.resolutions, this.completion});
  @override
  List<Object?> get props => [resolutions];
}
```

(Import `assignment_conflict.dart` in the event file for `ConflictResolution`.)

`assignment_bloc.dart` — register `on<SaveStagedChanges>(_onSaveStagedChanges);` and implement. Converge-to-desired against the current DB slots:

```dart
  Future<void> _onSaveStagedChanges(
      SaveStagedChanges event, Emitter<AssignmentState> emit) async {
    if (_stagedChanges.isEmpty) {
      _completeActionSuccess(event.completion, 'אין שינויים לשמירה');
      return;
    }
    final resolutions = event.resolutions ?? const {};
    final currentSlots =
        state is AssignmentSlotsLoaded ? (state as AssignmentSlotsLoaded).slots : <AssignmentSlot>[];
    final byKey = {for (final s in currentSlots) _getSlotKey(s): s};

    final creates = <Assignment>[];
    final updates = <Assignment>[];
    final deletes = <String>[];
    final appliedKeys = <String>[];

    for (final entry in _stagedChanges.entries) {
      final key = entry.key;
      final c = entry.value;
      // takeDb => skip this slot entirely (drop the change on success path too).
      if (resolutions[key] == ConflictResolution.takeDb) {
        appliedKeys.add(key); // resolved by taking DB => remove from staging
        continue;
      }
      final slot = byKey[key];
      final dbAssignment = slot?.currentAssignment;

      if (c.isClear) {
        if (dbAssignment != null) deletes.add(dbAssignment.id);
      } else if (dbAssignment == null) {
        // create (fresh, or off-quota for a vanished slot resolved override)
        creates.add(_assignmentFromStaged(c, id: c.desiredAssignmentId));
      } else {
        // converge current DB doc to desired
        updates.add(_assignmentFromStaged(c, id: dbAssignment.id));
      }
      appliedKeys.add(key);
    }

    _emitOrLog(emit, const AssignmentOperating('saving'));
    try {
      await _repository.saveAssignmentsBatch(
          creates: creates, updates: updates, deletes: deletes);
      for (final k in appliedKeys) {
        _stagedChanges.remove(k);
      }
      await _userCache.clearPendingAssignmentChanges(); // cleared ONLY on success
      _completeActionSuccess(event.completion,
          'נשמרו ${creates.length + updates.length + deletes.length} שינויים');
      add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
    } catch (e) {
      // Keep staging + cache intact for retry.
      _completeActionFailure(event.completion, 'שמירה נכשלה: $e');
      add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
    }
  }

  Assignment _assignmentFromStaged(StagedAssignmentChange c, {required String id}) {
    final now = DateTime.now();
    return Assignment(
      id: id,
      eventId: c.eventId,
      teamMemberId: c.desiredMemberId!,
      roleType: c.roleType,
      slotIndex: c.slotIndex,
      status: AssignmentStatus.confirmed,
      notes: c.desiredNotes,
      semanticLabelId: c.desiredSemanticLabelId,
      alternativePhoneNumber: c.desiredAltPhone,
      createdAt: now,
      updatedAt: now,
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_save_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment/ shavtzak/test/presentation/bloc/assignment_bloc_save_test.dart
git commit -m "feat(assignments): SaveStagedChanges handler (atomic, retry-safe)"
```

---

### Task 9: Screen — route edits through staging

Redirect the three edit paths to dispatch staging events; remove their blocking overlays; drop the staged entry on swipe-delete.

**Files:**
- Modify: `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart`
- Test: manual (widget-driving the 3595-line screen for this is impractical; covered by the bloc tests above + the Task 13 smoke). Add `initState` rehydrate.

**Changes (exact):**
- [ ] In `initState` (after the existing `LoadAssignmentSlots`), add: `context.read<AssignmentBloc>().add(const RehydrateStagedChanges());`
- [ ] `_handleAssignmentChange` (~3165) and `_handleAssignmentChangeWithBypass` (~3109): replace the `_runBlockingMutation(... CreateAssignment/UpdateAssignment ...)` body with a single dispatch and no overlay:
  ```dart
  context.read<AssignmentBloc>().add(
        StageMemberChange(slot: slot, member: selectedMember),
      );
  ```
- [ ] `_handleClearAssignment` (~2757): replace the `DeleteAssignment` blocking mutation with:
  ```dart
  context.read<AssignmentBloc>().add(
        StageMemberChange(slot: slot, member: null),
      );
  ```
- [ ] `_showNotesDialog` save action (~1569+): instead of dispatching `UpdateAssignmentNotes` and writing immediately, dispatch:
  ```dart
  context.read<AssignmentBloc>().add(StageNotesChange(
        slot: slot,
        notes: notesController.text.trim(),
        semanticLabelId: selectedSemanticLabelId,
        alternativePhoneNumber: phoneController.text.trim().isEmpty
            ? null
            : phoneController.text.trim(),
      ));
  ```
  then close the dialog. (Leave the dialog's own field UX untouched.)
- [ ] `_handleSlotDismiss` (~1474) — swipe-delete a slot stays IMMEDIATE (per scope), but first drop any staged entry for that slot so it doesn't resurrect:
  ```dart
  context.read<AssignmentBloc>().add(DiscardStagedSlot(
      '${slot.event.id}_${slot.role.key}_${slot.slotIndex}'));
  ```
  (Place this at the top of the method, before the existing quota/delete logic.)

- [ ] **Verify:** `cd shavtzak && flutter analyze` → zero NEW issues. Commit:

```bash
git add shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart
git commit -m "feat(assignments): route slot edits through staging (no per-edit write)"
```

---

### Task 10: Screen — Save/Discard cluster, dirty border, inline undo

**Files:**
- Modify: `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart`
- Test: `shavtzak/test/presentation/screens/assignment_save_controls_test.dart` (widget test of a small extracted `AssignmentSaveBar` widget — extract it so it's testable in isolation)

**Changes:**
- [ ] Extract a small stateless widget `AssignmentSaveBar({required int stagedCount, required VoidCallback onSave, required VoidCallback onDiscardAll})` into `shavtzak/lib/presentation/screens/assignment/widgets/assignment_save_bar.dart`. Save is **visible-but-disabled** when `stagedCount == 0`, enabled with `שמור · N` when `> 0`; discard-all shown only when `> 0`; RTL. Write a widget test asserting: at `stagedCount:0` a disabled "שמור" is present and "בטל הכל" is absent; at `stagedCount:3` "שמור · 3" is enabled and tapping it calls `onSave`, tapping "בטל הכל" calls `onDiscardAll`.
- [ ] In the screen's `Scaffold`, place the Save cluster **next to** the existing manual-add FAB (do not replace it). Use `floatingActionButton: Row(mainAxisSize: .min, children: [saveCluster, SizedBox(width:12), theExistingFab])` (or a `Column`), reading `stagedCount` from `context.watch<AssignmentBloc>().state` (`AssignmentSlotsLoaded.stagedSlotKeys.length`). `onSave` → `_onSavePressed()` (Task 11); `onDiscardAll` → confirm dialog (*"לבטל את כל N השינויים שלא נשמרו?"*) then `add(DiscardAllStagedChanges())`.
- [ ] In `_buildSlotRow` (~865): wrap the row's outer `Container` decoration so that when the slot's key is in `state.stagedSlotKeys`, it gets a **bright, thick yellow border** (e.g. `Border.all(color: Colors.amber, width: 3)`), and render a small inline **↩** `IconButton` in the assignment cell (near the clear button, ~2736) that calls `add(DiscardStagedSlot(slotKey))`. Both gated on membership in `stagedSlotKeys` (thread it into `_buildSlotRow`/`_buildAssignmentCell`).

- [ ] **Verify:** `cd shavtzak && flutter test test/presentation/screens/assignment_save_controls_test.dart` PASS; `flutter analyze` zero NEW. Commit:

```bash
git add shavtzak/lib/presentation/screens/assignment/ shavtzak/test/presentation/screens/assignment_save_controls_test.dart
git commit -m "feat(assignments): Save/Discard cluster, dirty border, inline undo"
```

---

### Task 11: Screen — Save flow + conflict resolution dialog

**Files:**
- Create: `shavtzak/lib/presentation/screens/assignment/widgets/conflict_resolution_dialog.dart`
- Modify: `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart` (`_onSavePressed`)
- Test: `shavtzak/test/presentation/screens/conflict_resolution_dialog_test.dart`

**Changes:**
- [ ] Build `ConflictResolutionDialog(conflicts)` returning `Map<String, ConflictResolution>?` (null = cancel). RTL. One scrollable list; each row shows `conflict.description` and, unless `discardOnly`, two buttons — **דרוס DB** (`overrideDb`) / **קח מה-DB** (`takeDb`), default `overrideDb`. **Special-case `type == AssignmentConflictType.slotVanished` (D):** label the override button **צור מחוץ למכסה** instead of **דרוס DB** — it still records `overrideDb`, and the Save handler already emits a create for a vanished slot resolved as override (renders off-quota). `discardOnly` rows (E fully-deleted) show one **הבנתי — בטל את השינוי** (records `takeDb`). Bulk **דרוס הכל / קח הכל מה-DB** at top. Widget test: a two-conflict list renders both descriptions; tapping **קח הכל מה-DB** then confirm returns both keys mapped to `takeDb`; a `slotVanished` row shows **צור מחוץ למכסה**.
- [ ] `_onSavePressed()`:
  ```dart
  final bloc = context.read<AssignmentBloc>();
  final state = bloc.state;
  if (state is! AssignmentSlotsLoaded) return;
  final conflicts = bloc.classifyStagedConflicts(state.slots);
  Map<String, ConflictResolution>? resolutions = const {};
  if (conflicts.isNotEmpty) {
    resolutions = await showDialog<Map<String, ConflictResolution>>(
      context: context,
      builder: (_) => ConflictResolutionDialog(conflicts: conflicts),
    );
    if (resolutions == null) return; // cancelled
  }
  final result = await _runBlockingMutation(   // reuse existing overlay/progress
    message: 'שומר שינויים...',
    dispatch: (completion) => bloc.add(
        SaveStagedChanges(resolutions: resolutions, completion: completion)),
  );
  if (result.isSuccess && mounted) {
    _showAssignmentSnackBar(result.message ?? 'נשמר', backgroundColor: Colors.green);
  }
  ```
  (Progress bar: the existing `_buildMutationDialogOverlay` shows a spinner + message; upgrade its message to reflect phases if desired — the phased "בודק שינויים N/M → שומר…" bar is a nice-to-have, not required for correctness.)

- [ ] **Verify:** dialog widget test PASS; `flutter analyze` zero NEW. Commit:

```bash
git add shavtzak/lib/presentation/screens/assignment/ shavtzak/test/presentation/screens/conflict_resolution_dialog_test.dart
git commit -m "feat(assignments): Save flow with conflict-resolution dialog"
```

---

### Task 12: Leave-guard on in-app exits

Remind when leaving the assignments tab dirty: bottom-nav tab-switch, in-screen home, logout.

**Files:**
- Create: `shavtzak/lib/presentation/screens/assignment/widgets/unsaved_changes_dialog.dart` (helper returning an enum `LeaveDecision { save, leave, cancel }`)
- Modify: `shavtzak/lib/presentation/widgets/swipeable_page_view.dart` (guard `_onBottomNavTapped` before `goBranch`)
- Modify: `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart` (guard the home button ~464 and logout ~3527)
- Test: `shavtzak/test/presentation/screens/unsaved_changes_dialog_test.dart`

**Changes:**
- [ ] `showUnsavedChangesDialog(context, {required int count})` → RTL `AlertDialog`, title **שינויי שיבוצים לא נשמרו**, body *"יש לך N שינויים שלא נשמרו."*, actions:
  - **שמור והמשך** → `LeaveDecision.save`
  - **צא בלי לשמור** with a second line *"השינויים לא נמחקים, ניתן לשמור אחר כך"* → `LeaveDecision.leave`
  - **ביטול** → `LeaveDecision.cancel`
  Widget test: each button returns the right enum.
- [ ] In `swipeable_page_view.dart`, make `_onBottomNavTapped` async. Before `goBranch`, if leaving assignments (`widget.navigationShell.currentIndex == 3`) and dirty (`context.read<AssignmentBloc>().hasStagedChanges`), show the dialog:
  - `save` → dispatch `SaveStagedChanges` (await via completion; on success continue to `goBranch`; on failure stay),
  - `leave` → `goBranch`,
  - `cancel` → return without switching.
  (Guard `BuildContext` across async gaps with `if (!mounted) return;` / captured `navigationShell`.)
- [ ] In `assignment_list_screen.dart`, wrap the home-button and logout `onPressed` bodies with the same guard (extract a `Future<bool> _confirmLeaveIfDirty()` returning whether to proceed) before `context.go(...)`.

- [ ] **Verify:** dialog widget test PASS; `flutter analyze` zero NEW. Commit:

```bash
git add shavtzak/lib/presentation/ shavtzak/test/presentation/screens/unsaved_changes_dialog_test.dart
git commit -m "feat(assignments): unsaved-changes leave-guard on in-app exits"
```

---

### Task 13: Deploy backend + full verification + manual smoke

**Files:** none (ops + verification).

- [ ] **Step 1: Full analyze + test sweep**

Run:
```bash
cd shavtzak && flutter analyze && flutter test
cd ../functions && npm test
```
Expected: analyze zero NEW issues (baseline 108 infos); all Flutter tests PASS; all backend tests PASS.

- [ ] **Step 2: Deploy the Cloud Function** (functions do NOT auto-deploy)

Run:
```bash
cd functions && firebase deploy --only functions
```
Expected: `api` function updates successfully. Until this runs, Save fails with a backend error (`assignment.saveBatch` unknown) — the client keeps staging intact, so no data loss, but Save cannot complete.

- [ ] **Step 3: Manual smoke (user-run, in TEST env `/test/admin/assignments`)**

Confirm:
1. Assign several members → rows get the yellow border, Save shows **שמור · N**, no per-edit spinner.
2. Reload the tab mid-session → staged changes recover from cache (still dirty).
3. Switch tabs / press home / logout while dirty → **שינויי שיבוצים לא נשמרו** dialog appears.
4. Edit a staged slot in the Firebase console to force a conflict → press Save → the consolidated resolution dialog lists it with **דרוס DB / קח מה-DB**.
5. Press Save with no conflicts → **נשמרו N שינויים**, rows persist, borders clear, DB reflects the batch.
6. Force a Save failure (offline) → error shown, staging + cache intact, Save works again when back online.

- [ ] **Step 4: Final commit (if any doc/notes updates) & summary**

```bash
git add -A && git commit -m "chore(assignments): deploy notes + smoke checklist for staged Save" || true
```

---

## Notes for the implementer

- **Do not** touch the manual-add wizard, swipe-delete quota logic, or the event-form modal write paths — they stay immediate by design.
- The existing `_mergeSlotsWithOptimisticUpdates` is subtle (member-availability recompute, `sameDayOtherEvents` handling). You are only *feeding* it a persistent op map — do not rewrite it.
- Keep all Hebrew copy exactly as written here (they double as the spec's agreed strings).
- After each task: `flutter analyze` must show zero NEW issues before committing.
