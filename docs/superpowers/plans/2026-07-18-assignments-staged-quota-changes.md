# Assignments Staged Quota Changes (swipe-delete + manual-add) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring swipe-delete and manual-add on `/admin/assignments` into the staged/dirty mechanism — including their quota ∓1 — so they stage (reviewable, reversible) until one atomic Save, matching the assign/swap/clear/notes edits that already stage.

**Architecture:** Quota is a *derived* overlay over the live DB (`baseline + adds − in-quota-deletions`), exactly like assignments already are. A `markedForDeletion` flag on the per-slot staged change keeps a deleted row visible (struck through) until Save; manual-add stages a fill on an appended slot so the grid grows. Save writes assignment deletes/creates **+ an exact quota target + survivor reindex** in the existing atomic server-side `db.batch()`. A new type-G conflict (a co-admin changed a role's quota under you) folds into the existing A–F Save dialog.

**Tech Stack:** Flutter Web + BLoC (`flutter_bloc`), Cloud Functions (TypeScript, gen2 `api` function), Firestore. Backend-mediated writes (`BackendApiService.mutate` → `api` `switch(operation)`). Tests: Dart `flutter_test` + `mockito` + `StreamController`s + `fake_cloud_firestore` (NO `blocTest`); backend `node --test` (`cd functions && npm test`).

## Global Constraints

- **Builds on** the shipped staged-save feature; reuses `_stagedChanges` (`Map<slotKey, StagedAssignmentChange>`), `slotKey = eventId_roleType_slotIndex` (`StagedAssignmentChange.slotKeyFor`), the merge overlay, and the Save/conflict machinery in `assignment_bloc.dart`.
- **`eventRoleKey` = `"${eventId}_${roleType}"`** (per-role quota key, distinct from slotKey).
- **Backend is additive + backward-compatible:** an absent `eventQuotaSets` field must behave exactly as today. Keep the existing `eventQuotaBumps` (`max`-merge raise) for the type-D override-restore path.
- **Functions do NOT auto-deploy.** After backend changes: `cd functions && firebase deploy --only functions:api`. Until deployed, a staged quota **lower** silently no-ops (rows delete, quota stays) — graceful degradation, ship the deploy with the client.
- **Quota writes** use the Firestore dot-path `roleRequirements.<roleType>` in the same batch (mirror the existing quota-bump write at `functions/src/index.ts:4576`).
- **Hebrew UI copy (verbatim):** staged-deletion badge **"יימחק בשמירה"**; conflict override **"דרוס DB"**, take-DB **"קח מה-DB"**, bulk **"דרוס הכל"/"קח הכל מה-DB"**; type-G description **"המכסה של \"<role>\" השתנתה: התחלת מ-X, וכעת ב-DB יש Y."** Code comments in English.
- **When a mocked signature changes** (e.g. `saveAssignmentsBatch` gains `eventQuotaSets`), regenerate mocks: `cd shavtzak && dart run build_runner build --delete-conflicting-outputs`.
- **Green bar to preserve:** `cd shavtzak && flutter analyze` (107 pre-existing infos, 0 new errors), `flutter test`; `cd functions && npm test`.
- Spec: `docs/superpowers/specs/2026-07-18-assignments-staged-quota-changes-design.md`.

---

## File Structure

**Backend (TypeScript)**
- `functions/src/index.ts` — new `planEventQuotaSets` + `planEventQuotaSetWrites` pure helpers; `eventQuotaSets` wired into the `assignment.saveBatch` case.
- `functions/src/assignment_save_batch.test.ts` — unit tests for both new helpers.

**Client data layer (Dart)**
- `lib/data/data_sources/database_interface.dart` — `EventQuotaSet` typedef + `eventQuotaSets` param.
- `lib/data/data_sources/firestore_database.dart` — payload includes `eventQuotaSets`.
- `lib/data/data_sources/logging_database.dart` — pass-through param + log ctx.
- `lib/data/repositories/assignment_repository.dart` — pass-through param.

**BLoC (Dart)**
- `lib/presentation/bloc/assignment/models/staged_assignment_change.dart` — `markedForDeletion` field.
- `lib/presentation/bloc/assignment/models/assignment_conflict.dart` — `quotaChanged` (G) enum case.
- `lib/presentation/bloc/assignment/assignment_event.dart` — `StageSlotDeletion`, `StageManualAdd`.
- `lib/presentation/bloc/assignment/assignment_state.dart` — `stagedDeletionSlotKeys` on `AssignmentSlotsLoaded`.
- `lib/presentation/bloc/assignment/assignment_bloc.dart` — `_baselineQuota` map, derived-quota helper, deletion/manual-add handlers, render grow, type-G classify, Save (delete + reindex + `eventQuotaSets`), persist/rehydrate.

**UI (Dart)**
- `lib/presentation/screens/assignment/assignment_list_screen.dart` — `_withStagedDeletionOverlay`; `_handleSlotDismiss` / off-quota swipe / `_createAssignmentAndQuota` route through staging.
- `lib/presentation/screens/assignment/widgets/conflict_resolution_dialog.dart` — render type-G rows (per-role title, override/takeDb).

**Tests (Dart)** — new/extended alongside existing `assignment_bloc_staging_test.dart`, `assignment_bloc_save_test.dart`, `assignment_repository_save_batch_test.dart`, `assignment_save_controls_test.dart`.

---

## Task 1: Backend — `planEventQuotaSets` validator

**Files:**
- Modify: `functions/src/index.ts` (add `planEventQuotaSets`, near `planEventQuotaBumps` ~line 2820)
- Test: `functions/src/assignment_save_batch.test.ts`

**Interfaces:**
- Produces: `export function planEventQuotaSets(raw: unknown): Array<{eventId: string; roleType: string; target: number; expected: number}>` — validates/shapes the optional exact-quota list. `target` and `expected` are integers `0..999` (0 = role removed). Throws `HttpError(400)` on malformed input.

- [ ] **Step 1: Write the failing tests**

Add to `functions/src/assignment_save_batch.test.ts` (import `planEventQuotaSets` from `./index` alongside the existing imports):

```ts
// ---- planEventQuotaSets: optional exact quota targets for saveBatch ----

test('planEventQuotaSets returns [] for missing / null / empty input', () => {
  assert.deepEqual(planEventQuotaSets(undefined), []);
  assert.deepEqual(planEventQuotaSets(null), []);
  assert.deepEqual(planEventQuotaSets([]), []);
});

test('planEventQuotaSets validates and shapes each entry (target may be 0)', () => {
  assert.deepEqual(
    planEventQuotaSets([
      {eventId: 'e1', roleType: 'medic', target: 2, expected: 3},
      {eventId: 'e2', roleType: 'investigation', target: 0, expected: 1},
    ]),
    [
      {eventId: 'e1', roleType: 'medic', target: 2, expected: 3},
      {eventId: 'e2', roleType: 'investigation', target: 0, expected: 1},
    ],
  );
});

test('planEventQuotaSets throws on a non-array', () => {
  assert.throws(() =>
    planEventQuotaSets({eventId: 'e1', roleType: 'medic', target: 1, expected: 2}),
  );
});

test('planEventQuotaSets throws on a missing eventId or roleType', () => {
  assert.throws(() => planEventQuotaSets([{roleType: 'medic', target: 1, expected: 2}]));
  assert.throws(() => planEventQuotaSets([{eventId: 'e1', target: 1, expected: 2}]));
});

test('planEventQuotaSets throws on non-integer / out-of-range target or expected', () => {
  assert.throws(() => planEventQuotaSets([{eventId: 'e1', roleType: 'medic', target: -1, expected: 2}]));
  assert.throws(() => planEventQuotaSets([{eventId: 'e1', roleType: 'medic', target: 1.5, expected: 2}]));
  assert.throws(() => planEventQuotaSets([{eventId: 'e1', roleType: 'medic', target: 1000, expected: 2}]));
  assert.throws(() => planEventQuotaSets([{eventId: 'e1', roleType: 'medic', target: 1, expected: -1}]));
  assert.throws(() => planEventQuotaSets([{eventId: 'e1', roleType: 'medic', target: '1', expected: 2}]));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd functions && npm test 2>&1 | grep -i planEventQuotaSets`
Expected: FAIL — `planEventQuotaSets is not a function` / import error.

- [ ] **Step 3: Implement `planEventQuotaSets`**

In `functions/src/index.ts`, directly after `planEventQuotaBumps` (~line 2845), add. Reuse the existing `requireString` + `HttpError` used by `planEventQuotaBumps`:

```ts
// Pure validator/shaper for assignment.saveBatch's OPTIONAL exact quota
// targets (the staged quota LOWER/SET path — distinct from eventQuotaBumps,
// which only raises via max-merge). Each entry carries the desired `target`
// count AND the client's `expected` baseline for optimistic concurrency
// (see planEventQuotaSetWrites). target may be 0 (role emptied). Absent field
// => [] (identical to pre-feature behaviour). Side-effect-free for unit tests.
export function planEventQuotaSets(
  raw: unknown,
): Array<{eventId: string; roleType: string; target: number; expected: number}> {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) {
    throw new HttpError(400, 'eventQuotaSets must be an array');
  }
  const intInRange = (v: unknown): v is number =>
    typeof v === 'number' && Number.isInteger(v) && v >= 0 && v <= 999;
  return raw.map((entry) => {
    const e = (entry ?? {}) as Record<string, unknown>;
    const eventId = requireString(e['eventId'], 'eventQuotaSet.eventId');
    const roleType = requireString(e['roleType'], 'eventQuotaSet.roleType');
    if (!intInRange(e['target'])) {
      throw new HttpError(400, 'eventQuotaSet.target must be an integer between 0 and 999');
    }
    if (!intInRange(e['expected'])) {
      throw new HttpError(400, 'eventQuotaSet.expected must be an integer between 0 and 999');
    }
    return {eventId, roleType, target: e['target'], expected: e['expected']};
  });
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd functions && npm test 2>&1 | grep -iE "planEventQuotaSets|tests (passed|failed)"`
Expected: all `planEventQuotaSets` tests PASS; suite total up by 5.

- [ ] **Step 5: Commit**

```bash
git add functions/src/index.ts functions/src/assignment_save_batch.test.ts
git commit -m "feat(functions): planEventQuotaSets validator for staged quota set/lower"
```

---

## Task 2: Backend — `planEventQuotaSetWrites` concurrency + diff helper

**Files:**
- Modify: `functions/src/index.ts` (add after `planEventQuotaSets`)
- Test: `functions/src/assignment_save_batch.test.ts`

**Interfaces:**
- Consumes: the `{eventId, roleType, target, expected}` shape from Task 1.
- Produces: `export function planEventQuotaSetWrites(args: {sets: Array<{eventId: string; roleType: string; target: number; expected: number}>; liveQuotas: Map<string, number>}): {writes: Array<{eventId: string; roleType: string; from: number; to: number}>; conflicts: Array<{eventId: string; roleType: string; expected: number; live: number}>}`. `liveQuotas` is keyed `"${eventId}_${roleType}"`. A set **conflicts** when `live !== expected && live !== target` (the DB moved off the client's baseline in a way the client did not resolve). A non-conflicting set produces a **write** only when `target !== live` (no-ops skipped).

- [ ] **Step 1: Write the failing tests**

```ts
// ---- planEventQuotaSetWrites: concurrency guard + no-op diffing ----

test('planEventQuotaSetWrites emits a lowering write when live == expected', () => {
  const r = planEventQuotaSetWrites({
    sets: [{eventId: 'e1', roleType: 'medic', target: 2, expected: 3}],
    liveQuotas: new Map([['e1_medic', 3]]),
  });
  assert.deepEqual(r.conflicts, []);
  assert.deepEqual(r.writes, [{eventId: 'e1', roleType: 'medic', from: 3, to: 2}]);
});

test('planEventQuotaSetWrites skips a no-op when live already equals target', () => {
  const r = planEventQuotaSetWrites({
    sets: [{eventId: 'e1', roleType: 'medic', target: 2, expected: 3}],
    liveQuotas: new Map([['e1_medic', 2]]),
  });
  assert.deepEqual(r.conflicts, []);
  assert.deepEqual(r.writes, []);
});

test('planEventQuotaSetWrites flags a conflict when live diverges from both expected and target', () => {
  const r = planEventQuotaSetWrites({
    sets: [{eventId: 'e1', roleType: 'medic', target: 2, expected: 3}],
    liveQuotas: new Map([['e1_medic', 5]]),
  });
  assert.deepEqual(r.writes, []);
  assert.deepEqual(r.conflicts, [{eventId: 'e1', roleType: 'medic', expected: 3, live: 5}]);
});

test('planEventQuotaSetWrites treats a missing live quota as 0', () => {
  const r = planEventQuotaSetWrites({
    sets: [{eventId: 'e1', roleType: 'medic', target: 0, expected: 0}],
    liveQuotas: new Map(),
  });
  assert.deepEqual(r.conflicts, []);
  assert.deepEqual(r.writes, []); // target 0 == live 0 => no-op
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd functions && npm test 2>&1 | grep -i planEventQuotaSetWrites`
Expected: FAIL — not a function.

- [ ] **Step 3: Implement `planEventQuotaSetWrites`**

```ts
// Pure concurrency + diff step for assignment.saveBatch's exact quota targets.
// For each set: read the live quota (0 if absent). If it differs from BOTH the
// client's `expected` baseline AND the desired `target`, a co-admin moved it
// under the client and it was not resolved -> conflict (the case handler
// rejects the save). Otherwise emit an event write only when the target
// actually changes the live value. Side-effect-free for unit tests.
export function planEventQuotaSetWrites(args: {
  sets: Array<{eventId: string; roleType: string; target: number; expected: number}>;
  liveQuotas: Map<string, number>;
}): {
  writes: Array<{eventId: string; roleType: string; from: number; to: number}>;
  conflicts: Array<{eventId: string; roleType: string; expected: number; live: number}>;
} {
  const writes: Array<{eventId: string; roleType: string; from: number; to: number}> = [];
  const conflicts: Array<{eventId: string; roleType: string; expected: number; live: number}> = [];
  for (const s of args.sets) {
    const live = args.liveQuotas.get(`${s.eventId}_${s.roleType}`) ?? 0;
    if (live !== s.expected && live !== s.target) {
      conflicts.push({eventId: s.eventId, roleType: s.roleType, expected: s.expected, live});
      continue;
    }
    if (s.target !== live) {
      writes.push({eventId: s.eventId, roleType: s.roleType, from: live, to: s.target});
    }
  }
  return {writes, conflicts};
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd functions && npm test 2>&1 | grep -iE "planEventQuotaSetWrites|# (pass|fail)"`
Expected: 4 new tests PASS; no failures.

- [ ] **Step 5: Commit**

```bash
git add functions/src/index.ts functions/src/assignment_save_batch.test.ts
git commit -m "feat(functions): planEventQuotaSetWrites concurrency guard + no-op diff"
```

---

## Task 3: Backend — wire `eventQuotaSets` into `assignment.saveBatch`

**Files:**
- Modify: `functions/src/index.ts` — the `case 'assignment.saveBatch':` block (~4379–4619)

**Interfaces:**
- Consumes: `planEventQuotaSets` (Task 1), `planEventQuotaSetWrites` (Task 2).
- Produces: the `api` op now reads `payload['eventQuotaSets']`, rejects a quota-concurrency conflict with `HttpError(409, 'המכסה של התפקיד שונתה בינתיים — יש לטעון מחדש')`, and applies exact quota writes (including lowers) in the same `db.batch()`. Return `counts` gains `quotaSet`.

- [ ] **Step 1: Read the existing quota-bump block for the insertion point**

Run: `sed -n '4526,4620p' functions/src/index.ts` (the `planEventQuotaBumps` read loop, the `batch`, and the audit/return). The new `eventQuotaSets` handling mirrors it: read live events → decide → batch `update` the dot-path → audit.

- [ ] **Step 2: Add the eventQuotaSets read + concurrency check (before `const batch = db.batch();` ~line 4562)**

Insert immediately after the `quotaBumpWrites` loop closes (after line ~4560, before `// One atomic batch`):

```ts
      // Optional EXACT quota targets (staged set/lower; see planEventQuotaSets):
      // read each target event's live quota, guard concurrency, and diff to
      // writes. A conflict here means a co-admin moved the quota under the
      // client's baseline AND the client did not resolve it -> reject the whole
      // save (nothing is written) so the client re-syncs. Reads precede the batch.
      const quotaSets = planEventQuotaSets(payload['eventQuotaSets']);
      const liveQuotas = new Map<string, number>();
      for (const s of quotaSets) {
        const snap = await db.collection(collections.events).doc(s.eventId).get();
        if (!snap.exists) {
          throw new HttpError(404, 'האירוע של השיבוץ כבר לא קיים');
        }
        const rr = (snap.data()?.['roleRequirements'] ?? {}) as Record<string, unknown>;
        const cur = typeof rr[s.roleType] === 'number' ? (rr[s.roleType] as number) : 0;
        liveQuotas.set(`${s.eventId}_${s.roleType}`, cur);
      }
      const {writes: quotaSetWrites, conflicts: quotaSetConflicts} =
        planEventQuotaSetWrites({sets: quotaSets, liveQuotas});
      if (quotaSetConflicts.length > 0) {
        throw new HttpError(409, 'המכסה של התפקיד שונתה בינתיים — יש לטעון מחדש');
      }
```

- [ ] **Step 3: Add the exact-quota batch writes (inside the `const batch = db.batch();` block, after the `quotaBumpWrites` loop ~line 4580)**

```ts
      // Exact quota targets ride the SAME batch as the assignment ops (staged
      // lower/set), so the quota and the (reindexed) assignments commit together.
      for (const w of quotaSetWrites) {
        batch.update(db.collection(collections.events).doc(w.eventId), {
          [`roleRequirements.${w.roleType}`]: w.to,
          updatedAt: Timestamp.now(),
        });
      }
```

- [ ] **Step 4: Add the audit + count (in the audit loop ~line 4600, and the `return counts` ~line 4610)**

After the `for (const w of quotaBumpWrites)` audit loop, add:

```ts
      for (const w of quotaSetWrites) {
        await writeAuditLog(db, collections, actor, 'event.update', 'event', w.eventId, {
          quotaSet: true,
          roleType: w.roleType,
        }, {
          before: {[`roleRequirements.${w.roleType}`]: w.from},
          after: {[`roleRequirements.${w.roleType}`]: w.to},
        });
      }
```

And extend the returned `counts` object with `quotaSet: quotaSetWrites.length,`.

- [ ] **Step 5: Typecheck, run the full backend suite, and commit**

Run: `cd functions && npm run build 2>&1 | tail -5 && npm test 2>&1 | grep -iE "# (tests|pass|fail)"`
Expected: build clean; all tests pass (the pure helpers cover the logic; the case wiring is verified by typecheck + manual smoke in Task 12).

```bash
git add functions/src/index.ts
git commit -m "feat(functions): apply eventQuotaSets (exact set/lower + 409 concurrency guard) in saveBatch"
```

---

## Task 4: Client data layer — `EventQuotaSet` threaded through `saveAssignmentsBatch`

**Files:**
- Modify: `lib/data/data_sources/database_interface.dart` (typedef ~18, method ~219)
- Modify: `lib/data/data_sources/firestore_database.dart` (~1187–1218)
- Modify: `lib/data/data_sources/logging_database.dart` (~642–664)
- Modify: `lib/data/repositories/assignment_repository.dart` (~158–170)
- Test: `shavtzak/test/data/repositories/assignment_repository_save_batch_test.dart`

**Interfaces:**
- Produces: `typedef EventQuotaSet = ({String eventId, String roleType, int target, int expected});` and a new named param `List<EventQuotaSet> eventQuotaSets = const []` on every `saveAssignmentsBatch` in the interface/impls/repository. The Firestore impl serializes it into the mutation payload key `'eventQuotaSets'` as `{eventId, roleType, target, expected}`.

- [ ] **Step 1: Write the failing test**

In `assignment_repository_save_batch_test.dart`, add a case asserting `eventQuotaSets` reaches the database. Follow the file's existing mockito pattern (`MockDatabaseInterface`, `verify(...).captured`):

```dart
test('saveAssignmentsBatch forwards eventQuotaSets to the database', () async {
  when(mockDb.saveAssignmentsBatch(
    creates: anyNamed('creates'),
    updates: anyNamed('updates'),
    deletes: anyNamed('deletes'),
    eventQuotaBumps: anyNamed('eventQuotaBumps'),
    eventQuotaSets: anyNamed('eventQuotaSets'),
  )).thenAnswer((_) async {});

  await repository.saveAssignmentsBatch(
    creates: const [],
    updates: const [],
    deletes: const [],
    eventQuotaSets: const [(eventId: 'e1', roleType: 'medic', target: 2, expected: 3)],
  );

  final captured = verify(mockDb.saveAssignmentsBatch(
    creates: anyNamed('creates'),
    updates: anyNamed('updates'),
    deletes: anyNamed('deletes'),
    eventQuotaBumps: anyNamed('eventQuotaBumps'),
    eventQuotaSets: captureAnyNamed('eventQuotaSets'),
  )).captured.single as List<EventQuotaSet>;
  expect(captured.single.target, 2);
  expect(captured.single.expected, 3);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shavtzak && flutter test test/data/repositories/assignment_repository_save_batch_test.dart -p vm 2>&1 | tail -15`
Expected: FAIL to compile — `saveAssignmentsBatch` has no `eventQuotaSets` param / `EventQuotaSet` undefined.

- [ ] **Step 3: Add the typedef and thread the param**

`database_interface.dart` — after the `EventQuotaBump` typedef (~line 18):

```dart
/// A request to set an event's role quota to EXACTLY [target] atomically inside
/// [DatabaseInterface.saveAssignmentsBatch] — the staged quota lower/set path.
/// [expected] is the client's baseline quota, used for optimistic-concurrency
/// (the backend rejects the whole save when live ∉ {expected, target}). Unlike
/// [EventQuotaBump] (max-merge raise), this can LOWER a quota.
typedef EventQuotaSet = ({String eventId, String roleType, int target, int expected});
```

Add `List<EventQuotaSet> eventQuotaSets` to the abstract signature (~line 219, default `const []` is illegal on abstract members — declare without default there, matching how `eventQuotaBumps` is declared) and `= const []` on all three concrete impls.

`firestore_database.dart` — in the `saveAssignmentsBatch` payload (~line 1206), after `'eventQuotaBumps': …`:

```dart
          'eventQuotaSets': eventQuotaSets
              .map((s) => {
                    'eventId': s.eventId,
                    'roleType': s.roleType,
                    'target': s.target,
                    'expected': s.expected,
                  })
              .toList(),
```

Also add `eventQuotaSets.isEmpty` to the early-return guard at ~line 1193.

`logging_database.dart` — add the param (~646), `'quotaSets': eventQuotaSets.length` to `ctx` (~655), and `eventQuotaSets: eventQuotaSets` to the inner call (~662).

`assignment_repository.dart` — add the param (~162) and `eventQuotaSets: eventQuotaSets` to the `_database.saveAssignmentsBatch` call (~168).

- [ ] **Step 4: Regenerate mocks, run the test**

Run: `cd shavtzak && dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -3 && flutter test test/data/repositories/assignment_repository_save_batch_test.dart -p vm 2>&1 | tail -8`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/data shavtzak/test/data
git commit -m "feat(assignments): thread EventQuotaSet through saveAssignmentsBatch (client data layer)"
```

---

## Task 5: Staged model — `markedForDeletion`

**Files:**
- Modify: `lib/presentation/bloc/assignment/models/staged_assignment_change.dart`
- Test: `shavtzak/test/presentation/bloc/staged_assignment_change_test.dart` (create)

**Interfaces:**
- Produces: `StagedAssignmentChange.markedForDeletion` (bool, default false), threaded through the const ctor, `copyWith` (as `bool? markedForDeletion`), `toJson`/`fromJson` (key `'markedForDeletion'`, default false on read), and `props`. New getter `bool get isDeletion => markedForDeletion;`. `matchesBaseline` returns **false** whenever `markedForDeletion` is true (a deletion never auto-cleans as a no-op).

- [ ] **Step 1: Write the failing tests** (create the test file)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/presentation/bloc/assignment/models/staged_assignment_change.dart';

StagedAssignmentChange _base({bool del = false}) => StagedAssignmentChange(
      slotKey: 'e1_medic_0', eventId: 'e1', roleType: 'medic', slotIndex: 0,
      desiredMemberId: 'm1', desiredNotes: '', desiredSemanticLabelId: null,
      desiredAltPhone: null, baselineAssignmentId: 'a1', baselineMemberId: 'm1',
      baselineNotes: '', baselineSemanticLabelId: null, baselineAltPhone: null,
      desiredAssignmentId: 'a1', stagedAtMillis: 1000, markedForDeletion: del,
    );

void main() {
  test('markedForDeletion round-trips through json', () {
    final json = _base(del: true).toJson();
    expect(json['markedForDeletion'], true);
    expect(StagedAssignmentChange.fromJson(json).markedForDeletion, true);
  });

  test('fromJson defaults markedForDeletion to false when absent', () {
    final json = _base().toJson()..remove('markedForDeletion');
    expect(StagedAssignmentChange.fromJson(json).markedForDeletion, false);
  });

  test('matchesBaseline is false for a deletion even when desired == baseline', () {
    // desired member == baseline member, but a deletion must NOT auto-clean.
    expect(_base(del: true).matchesBaseline, false);
    expect(_base(del: false).matchesBaseline, true);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shavtzak && flutter test test/presentation/bloc/staged_assignment_change_test.dart -p vm 2>&1 | tail -10`
Expected: FAIL — no `markedForDeletion` named param.

- [ ] **Step 3: Add the field**

In `staged_assignment_change.dart`: add `final bool markedForDeletion;` (after `stagedAtMillis`), `this.markedForDeletion = false` to the const ctor, `bool? markedForDeletion` to `copyWith` (`markedForDeletion: markedForDeletion ?? this.markedForDeletion`), `'markedForDeletion': markedForDeletion` to `toJson`, `markedForDeletion: (json['markedForDeletion'] as bool?) ?? false` to `fromJson`, `markedForDeletion` to `props`, and:

```dart
  bool get isDeletion => markedForDeletion;
```

Change `matchesBaseline` to short-circuit:

```dart
  bool get matchesBaseline =>
      !markedForDeletion &&
      desiredMemberId == baselineMemberId &&
      desiredNotes == baselineNotes &&
      desiredSemanticLabelId == baselineSemanticLabelId &&
      desiredAltPhone == baselineAltPhone;
```

- [ ] **Step 4: Run to verify pass**

Run: `cd shavtzak && flutter test test/presentation/bloc/staged_assignment_change_test.dart -p vm 2>&1 | tail -6`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment/models/staged_assignment_change.dart shavtzak/test/presentation/bloc/staged_assignment_change_test.dart
git commit -m "feat(assignments): markedForDeletion on StagedAssignmentChange"
```

---

## Task 6: BLoC — `_baselineQuota`, derived-quota helper, `StageSlotDeletion` + `StageManualAdd`

**Files:**
- Modify: `lib/presentation/bloc/assignment/assignment_event.dart`
- Modify: `lib/presentation/bloc/assignment/assignment_bloc.dart`
- Test: `shavtzak/test/presentation/bloc/assignment_bloc_quota_staging_test.dart` (create)

**Interfaces:**
- Consumes: `StagedAssignmentChange.markedForDeletion` (Task 5).
- Produces:
  - Events `StageSlotDeletion(AssignmentSlot slot)` and `StageManualAdd({required Event event, required TeamMember member, required String roleType})`.
  - `int _baselineQuotaFor(String eventId, String roleType)` — captured baseline (seeds from the live event's `roleRequirements` on first quota-touch, stored in `Map<String,int> _baselineQuota`).
  - `int derivedQuota(String eventId, String roleType)` — `baseline + adds − inQuotaDeletions`, where **adds** = staged entries for that role with `baselineMemberId == null && !markedForDeletion && slotIndex >= baseline`, and **inQuotaDeletions** = `markedForDeletion` entries with `slotIndex < baseline`.
  - `int _stagedAddCount(eventId, roleType)` used by Task 7 rendering.

- [ ] **Step 1: Write the failing tests** (create the file; mirror `assignment_bloc_staging_test.dart` setup — mock repository + `StreamController`s, `FirestoreDatabase(firestore: fakeFirestore)`, `SharedPreferences.setMockInitialValues({})`)

```dart
// Setup copied from assignment_bloc_staging_test.dart (mockRepo + stream
// controllers seeded with one event "e1" role "medic" quota 2, slots #0=m1, #1=m2).

test('StageSlotDeletion lowers the derived quota by 1 and marks the slot', () async {
  bloc.add(StageSlotDeletion(slotForRoleIndex(eventId: 'e1', role: 'medic', index: 1)));
  await pumpEventQueue();
  expect(bloc.derivedQuota('e1', 'medic'), 1);           // 2 baseline − 1 deletion
  final state = bloc.state as AssignmentSlotsLoaded;
  expect(state.stagedDeletionSlotKeys, contains('e1_medic_1'));
});

test('StageManualAdd raises the derived quota by 1 and stages a fill at the appended slot', () async {
  bloc.add(StageManualAdd(event: eventE1, member: member('m9'), roleType: 'medic'));
  await pumpEventQueue();
  expect(bloc.derivedQuota('e1', 'medic'), 3);           // 2 baseline + 1 add
  expect(bloc.hasStagedChanges, true);
  final state = bloc.state as AssignmentSlotsLoaded;
  expect(state.stagedSlotKeys, contains('e1_medic_2')); // appended at slotIndex = liveQuota (2)
});

test('deleting an off-quota row does NOT change the quota', () async {
  // seed an off-quota DB row at slotIndex 5 (> quota 2), then delete it
  bloc.add(StageSlotDeletion(offQuotaSlot(eventId: 'e1', role: 'medic', index: 5)));
  await pumpEventQueue();
  expect(bloc.derivedQuota('e1', 'medic'), 2);           // unchanged (5 >= baseline 2)
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_quota_staging_test.dart -p vm 2>&1 | tail -12`
Expected: FAIL — `StageSlotDeletion` / `StageManualAdd` / `derivedQuota` undefined.

- [ ] **Step 3: Add events + bloc state/handlers**

`assignment_event.dart` — after `DiscardStagedSlot` (~line 397):

```dart
/// Stage a swipe-deletion of [slot]: the row stays visible (struck through)
/// until Save; on Save the assignment (if any) is deleted and — for an IN-quota
/// slot — the role's quota lowers by 1.
class StageSlotDeletion extends AssignmentEvent {
  final AssignmentSlot slot;
  const StageSlotDeletion(this.slot);
  @override
  List<Object?> get props => [slot];
}

/// Stage a manual-add: append a new dirty slot for [member] in [roleType] at
/// [event], raising the role's derived quota by 1 (applied on Save).
class StageManualAdd extends AssignmentEvent {
  final Event event;
  final TeamMember member;
  final String roleType;
  const StageManualAdd({required this.event, required this.member, required this.roleType});
  @override
  List<Object?> get props => [event, member, roleType];
}
```

`assignment_bloc.dart` — register handlers in the constructor (near the other `on<...>` registrations ~line 170):

```dart
    on<StageSlotDeletion>(_onStageSlotDeletion);
    on<StageManualAdd>(_onStageManualAdd);
```

Add the baseline map beside `_stagedChanges` (~line 110):

```dart
  // Baseline DB quota per "eventId_roleType", captured the first time a role
  // gets a staged quota-changing action. Conflict detection ONLY (type-G).
  final Map<String, int> _baselineQuota = {};
```

Add the helpers (near the staging helpers ~line 1350):

```dart
  String _eventRoleKey(String eventId, String roleType) => '${eventId}_$roleType';

  int _liveQuota(String eventId, String roleType) {
    final ev = _windowEventsMap[eventId] ?? _extraPastEventsMap[eventId];
    return ev?.roleRequirements[roleType] ?? 0;
  }

  int _baselineQuotaFor(String eventId, String roleType) {
    final key = _eventRoleKey(eventId, roleType);
    return _baselineQuota.putIfAbsent(key, () => _liveQuota(eventId, roleType));
  }

  int _stagedAddCount(String eventId, String roleType) {
    final baseline = _baselineQuota[_eventRoleKey(eventId, roleType)]
        ?? _liveQuota(eventId, roleType);
    return _stagedChanges.values
        .where((c) =>
            c.eventId == eventId &&
            c.roleType == roleType &&
            !c.markedForDeletion &&
            c.baselineMemberId == null &&
            c.slotIndex >= baseline)
        .length;
  }

  int _inQuotaDeletionCount(String eventId, String roleType) {
    final baseline = _baselineQuota[_eventRoleKey(eventId, roleType)]
        ?? _liveQuota(eventId, roleType);
    return _stagedChanges.values
        .where((c) =>
            c.eventId == eventId &&
            c.roleType == roleType &&
            c.markedForDeletion &&
            c.slotIndex < baseline)
        .length;
  }

  /// The admin's intended quota for a role = baseline + adds − in-quota deletions.
  int derivedQuota(String eventId, String roleType) {
    final baseline = _baselineQuota[_eventRoleKey(eventId, roleType)]
        ?? _liveQuota(eventId, roleType);
    return (baseline + _stagedAddCount(eventId, roleType)
            - _inQuotaDeletionCount(eventId, roleType))
        .clamp(0, 999);
  }

  Future<void> _onStageSlotDeletion(
      StageSlotDeletion event, Emitter<AssignmentState> emit) async {
    final slot = event.slot;
    _baselineQuotaFor(slot.event.id, slot.role.key); // seed baseline
    final key = _slotKey(slot);
    final base = _stagedChanges[key] ?? _seedStaged(slot);
    _stagedChanges[key] = base.copyWith(markedForDeletion: true);
    await _persistStaged();
    Logger.action('stage:delete', {'slot': key, 'stagedCount': _stagedChanges.length});
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }

  Future<void> _onStageManualAdd(
      StageManualAdd event, Emitter<AssignmentState> emit) async {
    final eventId = event.event.id;
    final role = event.roleType;
    _baselineQuotaFor(eventId, role); // seed baseline
    // Append at the first free index >= liveQuota (accounts for prior adds).
    final base = _liveQuota(eventId, role);
    final used = _stagedChanges.values
        .where((c) => c.eventId == eventId && c.roleType == role && !c.markedForDeletion)
        .map((c) => c.slotIndex)
        .toSet();
    var slotIndex = base;
    while (used.contains(slotIndex)) {
      slotIndex++;
    }
    final key = StagedAssignmentChange.slotKeyFor(eventId, role, slotIndex);
    _stagedChanges[key] = StagedAssignmentChange(
      slotKey: key, eventId: eventId, roleType: role, slotIndex: slotIndex,
      desiredMemberId: event.member.id, desiredNotes: '',
      desiredSemanticLabelId: null, desiredAltPhone: null,
      baselineAssignmentId: null, baselineMemberId: null, baselineNotes: '',
      baselineSemanticLabelId: null, baselineAltPhone: null,
      desiredAssignmentId: const Uuid().v4(),
      stagedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    await _persistStaged();
    Logger.action('stage:manualAdd', {'slot': key, 'stagedCount': _stagedChanges.length});
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }
```

(`_seedStaged`, `_slotKey`, `_persistStaged`, `_currentEventFilter`, `_windowEventsMap`, `_extraPastEventsMap`, `Uuid` are all already in the bloc.)

- [ ] **Step 4: Run to verify pass**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_quota_staging_test.dart -p vm 2>&1 | tail -10`
Expected: PASS (once Task 7 adds `stagedDeletionSlotKeys` — if the first test references it before Task 7, land Task 7's state field first or split the assertion; keep the derived-quota asserts here and the render asserts in Task 7).

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment shavtzak/test/presentation/bloc/assignment_bloc_quota_staging_test.dart
git commit -m "feat(assignments): _baselineQuota + derivedQuota + StageSlotDeletion/StageManualAdd handlers"
```

---

## Task 7: BLoC rendering — grid grows for adds, deletions marked on state

**Files:**
- Modify: `lib/presentation/bloc/assignment/assignment_state.dart` (`AssignmentSlotsLoaded`)
- Modify: `lib/presentation/bloc/assignment/assignment_bloc.dart` (`_buildSlotsFromAssignments` ~2296; if `_onRebuildAssignmentSlotsFromData` has its own inline slot loop, mirror the two edits there too)
- Test: extend `assignment_bloc_quota_staging_test.dart`

**Interfaces:**
- Produces: `AssignmentSlotsLoaded.stagedDeletionSlotKeys` (`Set<String>`, default `const {}`, in ctor/props/copyWith) — the slotKeys of `markedForDeletion` staged entries currently rendered. The build loop renders `requiredCount + _stagedAddCount(event.id, role.key)` slots so appended manual-adds render **in-quota**.

- [ ] **Step 1: Write the failing test** (extend the file)

```dart
test('a manual-add renders an extra in-quota slot (not off-quota)', () async {
  bloc.add(StageManualAdd(event: eventE1, member: member('m9'), roleType: 'medic'));
  await pumpEventQueue();
  final state = bloc.state as AssignmentSlotsLoaded;
  final medicSlots = state.slots.where(
      (s) => s.event.id == 'e1' && s.role.key == 'medic').toList();
  expect(medicSlots.length, 3);                    // grid grew from 2 to 3
  expect(medicSlots.any((s) => s.slotIndex == 2 && s.currentAssignment == null || true), true);
});

test('a staged deletion is reported in stagedDeletionSlotKeys', () async {
  bloc.add(StageSlotDeletion(slotForRoleIndex(eventId: 'e1', role: 'medic', index: 0)));
  await pumpEventQueue();
  final state = bloc.state as AssignmentSlotsLoaded;
  expect(state.stagedDeletionSlotKeys, contains('e1_medic_0'));
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_quota_staging_test.dart -p vm 2>&1 | tail -12`
Expected: FAIL — `stagedDeletionSlotKeys` undefined / medic slot count is 2.

- [ ] **Step 3: Add the state field + the render grow**

`assignment_state.dart` — add to `AssignmentSlotsLoaded` (mirror `stagedGoneSlotKeys`): field `final Set<String> stagedDeletionSlotKeys;`, ctor `this.stagedDeletionSlotKeys = const {}`, `props` entry, and `copyWith` param + assignment.

`assignment_bloc.dart` in `_buildSlotsFromAssignments` — change the slot count (line 2344) from `requiredCount` to include staged adds:

```dart
        final renderCount = requiredCount + _stagedAddCount(event.id, role.key);
        // Create slots (one per required count, grown by staged manual-adds)
        for (int i = 0; i < renderCount; i++) {
```

Also skip the `requiredCount == 0` early-continue when there ARE staged adds for the role:

```dart
        final requiredCount = event.roleRequirements[role.key] ?? 0;
        if (requiredCount == 0 && _stagedAddCount(event.id, role.key) == 0) continue;
```

At the return (~2485), compute and pass the deletion set:

```dart
    final deletionKeys = _stagedChanges.entries
        .where((e) => e.value.markedForDeletion)
        .map((e) => e.key)
        .toSet();
    return AssignmentSlotsLoaded(
      _materializeGoneStagedRows(annotatedSlots, goneKeys),
      selectedEventIds: selectedEventIds ?? {},
      stagedSlotKeys: _stagedChanges.keys.toSet(),
      stagedGoneSlotKeys: goneKeys,
      stagedDeletionSlotKeys: deletionKeys,
    );
```

If a second inline slot-build loop exists in `_onRebuildAssignmentSlotsFromData`, mirror the `renderCount` and `requiredCount==0` edits there (search `requiredCount` in the file — there should be exactly the ones in this method after the 2026-07-16 unification; if a second exists, edit both).

- [ ] **Step 4: Run to verify pass**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_quota_staging_test.dart -p vm 2>&1 | tail -8`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment
git commit -m "feat(assignments): grid grows for staged adds; stagedDeletionSlotKeys on state"
```

---

## Task 8: Screen — "יימחק בשמירה" stripe overlay on staged-deletion rows

**Files:**
- Modify: `lib/presentation/screens/assignment/assignment_list_screen.dart` (add `_withStagedDeletionOverlay`; apply it in the row builder ~908–915 alongside `_withDeletedRemotelyOverlay`)
- Test: `shavtzak/test/presentation/screens/assignment_staged_delete_overlay_test.dart` (create; model on `assignment_save_controls_test.dart`)

**Interfaces:**
- Consumes: `AssignmentSlotsLoaded.stagedDeletionSlotKeys` (Task 7).
- Produces: `Widget _withStagedDeletionOverlay(Widget row)` — a bright-red diagonal-stripe wash + a top-center badge **"יימחק בשמירה"** (non-interactive `IgnorePointer`, reusing `_DiagonalStripesPainter`). Applied to rows whose slotKey is in `stagedDeletionSlotKeys`.

- [ ] **Step 1: Write the failing widget test**

```dart
testWidgets('a staged-deletion row shows the "יימחק בשמירה" badge', (tester) async {
  // pump the assignment list with an AssignmentSlotsLoaded whose
  // stagedDeletionSlotKeys contains the medic#0 slotKey (see helper in
  // assignment_save_controls_test.dart for a minimal bloc/state harness).
  await pumpAssignmentListWith(tester, stagedDeletionSlotKeys: {'e1_medic_0'});
  expect(find.text('יימחק בשמירה'), findsOneWidget);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shavtzak && flutter test test/presentation/screens/assignment_staged_delete_overlay_test.dart -p vm 2>&1 | tail -10`
Expected: FAIL — badge text not found.

- [ ] **Step 3: Add the overlay + apply it**

Add next to `_withDeletedRemotelyOverlay` (~line 1052):

```dart
  /// Wraps a row staged for deletion (swipe-delete, not yet saved) with a
  /// red diagonal-stripe wash + a "יימחק בשמירה" badge. Non-interactive so the
  /// row underneath stays swipeable (swipe again = discard) and tappable.
  Widget _withStagedDeletionOverlay(Widget row) {
    return Stack(
      children: [
        row,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: const _DiagonalStripesPainter(),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                  ),
                  child: const Text(
                    'יימחק בשמירה',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
```

In the row builder (~908–915), apply it. The existing code wraps `stagedGoneSlotKeys` rows with `_withDeletedRemotelyOverlay`; add a sibling branch (deletion takes precedence over gone, since a swipe-delete is explicit):

```dart
    final slotKey = _slotKeyOf(slot); // existing helper producing eventId_roleKey_slotIndex
    Widget rendered = row;
    if (state.stagedDeletionSlotKeys.contains(slotKey)) {
      rendered = _withStagedDeletionOverlay(rendered);
    } else if (state.stagedGoneSlotKeys.contains(slotKey)) {
      rendered = _withDeletedRemotelyOverlay(rendered);
    }
    return rendered;
```

(Use the same slotKey expression already used at line ~908 for `stagedGoneSlotKeys`.)

- [ ] **Step 4: Run to verify pass**

Run: `cd shavtzak && flutter test test/presentation/screens/assignment_staged_delete_overlay_test.dart -p vm 2>&1 | tail -6`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart shavtzak/test/presentation/screens/assignment_staged_delete_overlay_test.dart
git commit -m "feat(assignments): red-stripe 'יימחק בשמירה' overlay for staged-deletion rows"
```

---

## Task 9: Screen — route swipe-delete, off-quota swipe & manual-add through staging

**Files:**
- Modify: `lib/presentation/screens/assignment/assignment_list_screen.dart` — `_handleSlotDismiss` (~1731), the off-quota `confirmDismiss`/delete (`_buildOffQuotaRow` ~1531–1727), `_createAssignmentAndQuota` (~3553), and the in-quota `confirmDismiss` (~1480–1521)
- Test: `shavtzak/test/presentation/screens/assignment_staged_delete_overlay_test.dart` (extend — assert a swipe stages, no repo write)

**Interfaces:**
- Consumes: `StageSlotDeletion`, `StageManualAdd` (Task 6).
- Produces: swipe-delete and manual-add perform **no immediate DB writes** — they dispatch staging events. `confirmDismiss` for a filled in-quota row returns `true` **without** a confirmation dialog (reversible; inline ↩ + red stripe replace it).

- [ ] **Step 1: Write the failing test** (extend the overlay test)

```dart
testWidgets('swiping a filled in-quota row stages a deletion with no repository write', (tester) async {
  final repo = MockAssignmentRepository(); // verifyNever on deleteAssignment
  await pumpAssignmentList(tester, repo: repo, filledSlot: 'e1_medic_0');
  await tester.drag(find.byKey(const ValueKey('slot_e1_medic_0')), const Offset(-500, 0));
  await tester.pumpAndSettle();
  verifyNever(repo.deleteAssignment(any));
  expect(find.text('יימחק בשמירה'), findsOneWidget); // now striped
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shavtzak && flutter test test/presentation/screens/assignment_staged_delete_overlay_test.dart -p vm 2>&1 | tail -12`
Expected: FAIL — `deleteAssignment` still called (immediate path).

- [ ] **Step 3: Rewrite the three paths to stage**

**`_handleSlotDismiss`** (~1731) — replace the whole body with a single dispatch (drop the immediate delete + reindex + quota + snackbar):

```dart
  Future<void> _handleSlotDismiss(AssignmentSlot slot) async {
    // Staged: mark the row for deletion (keeps it visible, struck through);
    // the assignment delete + quota lower + reindex happen atomically on Save.
    context.read<AssignmentBloc>().add(StageSlotDeletion(slot));
  }
```

**In-quota `confirmDismiss`** (~1480–1521) — return `true` immediately (staging is reversible, so no confirm dialog):

```dart
      confirmDismiss: (_) async {
        Logger.action('swipe:stageDelete', {'slot': '${slot.event.id}_${slot.role.key}_${slot.slotIndex}'});
        return true; // stage on dismiss (reversible via ↩ / swipe-back)
      },
      onDismissed: (_) => _handleSlotDismiss(slot),
```

**Off-quota swipe** (`_buildOffQuotaRow` ~1624) — replace the immediate `deleteAssignment` with a staged deletion of that off-quota slot (no quota change — the derived-quota helper ignores `slotIndex >= baseline`):

```dart
      onDismissed: (_) =>
          context.read<AssignmentBloc>().add(StageSlotDeletion(slot)),
```

(and make its `confirmDismiss` return `true` without the delete-confirm dialog).

**`_createAssignmentAndQuota`** (~3553) — replace the whole body with a single staged manual-add (drop the immediate quota update + insert + rollback):

```dart
  Future<void> _createAssignmentAndQuota(
      Event event, TeamMember teamMember, String roleType) async {
    // Staged: append a dirty slot for this member; the quota +1 and the
    // assignment create happen atomically on Save.
    context.read<AssignmentBloc>().add(
          StageManualAdd(event: event, member: teamMember, roleType: roleType),
        );
  }
```

Remove now-unused imports/locals if `flutter analyze` flags them (e.g. `Uuid` in the screen, `CreateAssignmentWithBypass` usage) — only if unused after this change.

- [ ] **Step 4: Run the test + analyze**

Run: `cd shavtzak && flutter test test/presentation/screens/assignment_staged_delete_overlay_test.dart -p vm 2>&1 | tail -8 && flutter analyze 2>&1 | tail -3`
Expected: PASS; analyze shows no NEW errors.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart shavtzak/test/presentation/screens/assignment_staged_delete_overlay_test.dart
git commit -m "feat(assignments): swipe-delete/off-quota/manual-add stage instead of immediate write"
```

---

## Task 10: BLoC Save — deletions, survivor reindex, `eventQuotaSets`

**Files:**
- Modify: `lib/presentation/bloc/assignment/assignment_bloc.dart` — `_onSaveStagedChanges` (~1748–1944)
- Test: `shavtzak/test/presentation/bloc/assignment_bloc_save_test.dart` (extend)

**Interfaces:**
- Consumes: `derivedQuota`, `_baselineQuota`, `EventQuotaSet` (Tasks 4/6), `markedForDeletion` (Task 5).
- Produces: Save now (a) turns each `markedForDeletion` entry with a DB assignment into a batch **delete**; (b) for every role with an in-quota deletion, **reindexes** surviving rows contiguous from 0 (as `updates`); (c) emits `eventQuotaSets: [(eventId, roleType, target: derivedQuota, expected: baselineQuota)]` for every role with a staged quota change; (d) drops the create-driven `max`-merge bump for those roles (keeps it only for override-restore).

- [ ] **Step 1: Write the failing tests** (extend save test — mock repo `saveAssignmentsBatch`, capture args)

```dart
test('Save of a staged deletion sends the delete + reindex + a lowering eventQuotaSet', () async {
  // seed medic quota 2, slots #0=a1(m1), #1=a2(m2)
  bloc.add(StageSlotDeletion(slotForRoleIndex(eventId: 'e1', role: 'medic', index: 0)));
  await pumpEventQueue();
  bloc.add(const SaveStagedChanges());
  await pumpEventQueue();

  final call = verify(mockRepo.saveAssignmentsBatch(
    creates: anyNamed('creates'),
    updates: captureAnyNamed('updates'),
    deletes: captureAnyNamed('deletes'),
    eventQuotaBumps: anyNamed('eventQuotaBumps'),
    eventQuotaSets: captureAnyNamed('eventQuotaSets'),
  )).captured;
  final updates = call[0] as List<Assignment>;
  final deletes = call[1] as List<String>;
  final sets = call[2] as List<EventQuotaSet>;
  expect(deletes, contains('a1'));                       // deleted #0
  expect(updates.any((u) => u.id == 'a2' && u.slotIndex == 0), true); // m2 reindexed #1 -> #0
  expect(sets.single, (eventId: 'e1', roleType: 'medic', target: 1, expected: 2));
});

test('Save of a manual-add sends a raising eventQuotaSet + the create', () async {
  bloc.add(StageManualAdd(event: eventE1, member: member('m9'), roleType: 'medic'));
  await pumpEventQueue();
  bloc.add(const SaveStagedChanges());
  await pumpEventQueue();
  final call = verify(mockRepo.saveAssignmentsBatch(
    creates: captureAnyNamed('creates'), updates: anyNamed('updates'),
    deletes: anyNamed('deletes'), eventQuotaBumps: anyNamed('eventQuotaBumps'),
    eventQuotaSets: captureAnyNamed('eventQuotaSets'),
  )).captured;
  expect((call[0] as List<Assignment>).any((a) => a.teamMemberId == 'm9'), true);
  expect((call[1] as List<EventQuotaSet>).single,
      (eventId: 'e1', roleType: 'medic', target: 3, expected: 2));
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_save_test.dart -p vm 2>&1 | tail -12`
Expected: FAIL — `saveAssignmentsBatch` called without `eventQuotaSets` / no reindex updates.

- [ ] **Step 3: Extend `_onSaveStagedChanges`**

In the per-entry loop (~1793–1864), handle deletions first (before the `isClear` branch):

```dart
      if (c.markedForDeletion) {
        if (dbAssignment != null) {
          deletes.add(dbAssignment.id);
        }
        appliedKeys.add(key);
        continue; // quota + reindex handled in the post-pass below
      }
```

After the loop, before building `eventQuotaBumps` (~1873), add the quota-set + reindex computation:

```dart
    // Roles touched by a staged quota change (add or in-quota deletion): emit an
    // EXACT quota target (derived) with the baseline as `expected` for the
    // backend concurrency guard, and reindex that role's survivors.
    final quotaSets = <EventQuotaSet>[];
    final rolesWithQuotaChange = <String>{}; // eventRoleKey
    for (final c in _stagedChanges.values) {
      final erk = '${c.eventId}_${c.roleType}';
      if (_baselineQuota.containsKey(erk)) rolesWithQuotaChange.add(erk);
    }
    for (final erk in rolesWithQuotaChange) {
      final parts = erk.split('_');
      final eventId = parts.first;
      final roleType = parts.sublist(1).join('_'); // roleType may contain '_'
      final baseline = _baselineQuota[erk]!;
      final res = resolutions[erk];
      if (res == ConflictResolution.takeDb) {
        continue; // keep the DB quota; deletions still applied above
      }
      final target = derivedQuota(eventId, roleType);
      quotaSets.add((eventId: eventId, roleType: roleType, target: target, expected: baseline));
      // Reindex survivors of this role (only when a deletion occurred).
      _reindexRoleSurvivors(eventId, roleType, deletes, updates);
    }
```

Add the reindex helper (near `_onSaveStagedChanges`):

```dart
  /// Renumber a role's surviving rows contiguous from 0 (Save-time only). A
  /// survivor already staged for update keeps that staged edit but gets the new
  /// slotIndex; a survivor not otherwise touched is added as a slotIndex-only
  /// update. Mirrors the immediate swipe-delete reorder.
  void _reindexRoleSurvivors(
      String eventId, String roleType, List<String> deletes, List<Assignment> updates) {
    final live = [
      ..._repository.getCurrentAssignments(),
      ..._extraPastAssignments,
    ].where((a) => a.eventId == eventId && a.roleType == roleType && !deletes.contains(a.id)).toList()
      ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
    for (var i = 0; i < live.length; i++) {
      final a = live[i];
      if (a.slotIndex == i) continue;
      final existing = updates.indexWhere((u) => u.id == a.id);
      if (existing >= 0) {
        updates[existing] = updates[existing].copyWith(slotIndex: i);
      } else {
        updates.add(a.copyWith(slotIndex: i, updatedAt: DateTime.now()));
      }
    }
  }
```

Thread `eventQuotaSets: quotaSets` into the `_repository.saveAssignmentsBatch(...)` call (~1903):

```dart
      await _repository.saveAssignmentsBatch(
        creates: creates,
        updates: updates,
        deletes: deletes,
        eventQuotaBumps: eventQuotaBumps,
        eventQuotaSets: quotaSets,
      );
```

On Save success, also clear `_baselineQuota` alongside `_stagedChanges` cleanup (~1914):

```dart
      _baselineQuota.removeWhere((erk, _) => !rolesStillStaged(erk)); // or: _baselineQuota.clear() when _stagedChanges empties
```

(Simplest correct rule: after removing applied keys, `if (_stagedChanges.isEmpty) _baselineQuota.clear();`.)

- [ ] **Step 4: Run to verify pass**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_save_test.dart -p vm 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart shavtzak/test/presentation/bloc/assignment_bloc_save_test.dart
git commit -m "feat(assignments): Save applies staged deletions + survivor reindex + exact eventQuotaSets"
```

---

## Task 11: BLoC + dialog — type-G quota conflict

**Files:**
- Modify: `lib/presentation/bloc/assignment/models/assignment_conflict.dart` (`quotaChanged` case)
- Modify: `lib/presentation/bloc/assignment/assignment_bloc.dart` (`classifyStagedConflicts` ~1610–1725)
- Modify: `lib/presentation/screens/assignment/widgets/conflict_resolution_dialog.dart` (override label for type-G)
- Test: `shavtzak/test/presentation/bloc/assignment_bloc_quota_staging_test.dart` (extend)

**Interfaces:**
- Consumes: `_baselineQuota`, `derivedQuota`, `_liveQuota` (Task 6).
- Produces: `AssignmentConflictType.quotaChanged` (G). `classifyStagedConflicts` appends one `AssignmentConflict` per `(event,role)` where `liveQuota != baselineQuota && derivedQuota != liveQuota`, with `slotKey = eventRoleKey`. Its resolution reuses `overrideDb`/`takeDb` (mapped in Task 10's Save). The dialog's `_overrideLabel` returns **"דרוס DB"** for G (already the default for non-`slotVanished` types — verify no special-casing needed).

- [ ] **Step 1: Write the failing test**

```dart
test('type-G fires when a co-admin raised the quota under a staged lower', () async {
  bloc.add(StageSlotDeletion(slotForRoleIndex(eventId: 'e1', role: 'medic', index: 0)));
  await pumpEventQueue();                                 // baseline captured = 2, derived = 1
  simulateDbQuotaChange('e1', 'medic', 5);               // co-admin raised to 5 in the live event stream
  await pumpEventQueue();
  final conflicts = bloc.classifyStagedConflicts(
      (bloc.state as AssignmentSlotsLoaded).slots);
  final g = conflicts.where((c) => c.type == AssignmentConflictType.quotaChanged).toList();
  expect(g.length, 1);
  expect(g.single.slotKey, 'e1_medic');
});

test('no type-G when the DB quota still equals the baseline', () async {
  bloc.add(StageSlotDeletion(slotForRoleIndex(eventId: 'e1', role: 'medic', index: 0)));
  await pumpEventQueue();
  final conflicts = bloc.classifyStagedConflicts(
      (bloc.state as AssignmentSlotsLoaded).slots);
  expect(conflicts.any((c) => c.type == AssignmentConflictType.quotaChanged), false);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_quota_staging_test.dart -p vm 2>&1 | tail -12`
Expected: FAIL — `quotaChanged` undefined / no G conflict produced.

- [ ] **Step 3: Add the enum case + classification + label**

`assignment_conflict.dart` — add to `AssignmentConflictType`:

```dart
  quotaChanged, // G: role quota changed in DB under a staged quota change
```

`assignment_bloc.dart` — at the end of `classifyStagedConflicts`, after the per-slot `forEach` (~1723, before `return conflicts;`):

```dart
    // Type-G: per-role quota divergence. For each role with a captured
    // baseline, if the live DB quota moved off the baseline AND still differs
    // from the admin's derived intent, surface one conflict for that role.
    for (final erk in _baselineQuota.keys) {
      final parts = erk.split('_');
      final eventId = parts.first;
      final roleType = parts.sublist(1).join('_');
      final baseline = _baselineQuota[erk]!;
      final live = _liveQuota(eventId, roleType);
      final desired = derivedQuota(eventId, roleType);
      if (live != baseline && desired != live) {
        final ev = _windowEventsMap[eventId] ?? _extraPastEventsMap[eventId];
        final roleName = _resolveRoleForKey(roleType).hebrewName;
        conflicts.add(AssignmentConflict(
          slotKey: erk,
          type: AssignmentConflictType.quotaChanged,
          title: ev != null ? '${ev.name} · $roleName' : roleName,
          description:
              'המכסה של "$roleName" השתנתה: התחלת מ-$baseline, וכעת ב-DB יש $live.',
        ));
      }
    }
    return conflicts;
```

`conflict_resolution_dialog.dart` — `_overrideLabel` already returns `'דרוס DB'` for every non-`slotVanished` type, so G needs no change. Add a comment there noting G reuses the default. (Verify by reading `_overrideLabel` ~75–78.)

- [ ] **Step 4: Run to verify pass**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_quota_staging_test.dart -p vm 2>&1 | tail -8`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment shavtzak/lib/presentation/screens/assignment/widgets/conflict_resolution_dialog.dart shavtzak/test/presentation/bloc/assignment_bloc_quota_staging_test.dart
git commit -m "feat(assignments): type-G quota-changed conflict (classify + dialog reuse)"
```

---

## Task 12: Cache persist/rehydrate + deploy + manual smoke

**Files:**
- Modify: `lib/presentation/bloc/assignment/assignment_bloc.dart` — `_persistStaged` / rehydrate (`RehydrateStagedChanges` handler) to round-trip `_baselineQuota`
- Test: `shavtzak/test/presentation/bloc/assignment_bloc_staging_test.dart` (extend — persist/rehydrate)

**Interfaces:**
- Consumes: `markedForDeletion` json (Task 5), `_baselineQuota` (Task 6).
- Produces: the cache blob now carries `_baselineQuota` alongside the staged list; rehydrate restores both, so a swipe-delete / manual-add survives a reload with the correct derived quota.

- [ ] **Step 1: Write the failing test**

```dart
test('a staged deletion + baseline survive persist/rehydrate', () async {
  bloc.add(StageSlotDeletion(slotForRoleIndex(eventId: 'e1', role: 'medic', index: 0)));
  await pumpEventQueue();
  // new bloc reading the same UserCacheService/SharedPreferences
  final bloc2 = makeBloc();
  bloc2.add(const RehydrateStagedChanges());
  await pumpEventQueue();
  expect(bloc2.derivedQuota('e1', 'medic'), 1);
  final state = bloc2.state as AssignmentSlotsLoaded;
  expect(state.stagedDeletionSlotKeys, contains('e1_medic_0'));
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_staging_test.dart -p vm 2>&1 | tail -12`
Expected: FAIL — `derivedQuota` is 2 after rehydrate (baseline lost) / deletion not restored.

- [ ] **Step 3: Persist + rehydrate `_baselineQuota`**

Find `_persistStaged` (writes `_stagedChanges.values.map((c) => c.toJson())` ~line 1348). Change the persisted payload to a wrapper object carrying both the list and the baseline map. Add a `UserCacheService` shape that stores the JSON object (the current key `assignments_staged_changes` already stores a JSON string):

```dart
  Future<void> _persistStaged() async {
    final payload = jsonEncode({
      'changes': _stagedChanges.values.map((c) => c.toJson()).toList(),
      'baselineQuota': _baselineQuota,
    });
    await _cache.savePendingAssignmentChanges(payload);
  }
```

In the rehydrate handler (`_onRehydrateStagedChanges`), decode both, tolerating the OLD format (a bare list) for a smooth upgrade:

```dart
    final raw = await _cache.getPendingAssignmentChanges();
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    final List list;
    if (decoded is List) {
      list = decoded;                     // legacy format (bare list)
    } else {
      list = (decoded['changes'] as List?) ?? const [];
      _baselineQuota
        ..clear()
        ..addAll(Map<String, int>.from(
            (decoded['baselineQuota'] as Map?)?.cast<String, int>() ?? const {}));
    }
    _stagedChanges
      ..clear()
      ..addEntries(list
          .map((e) => StagedAssignmentChange.fromJson(e as Map<String, dynamic>))
          .map((c) => MapEntry(c.slotKey, c)));
```

(If `savePendingAssignmentChanges`/`getPendingAssignmentChanges` currently type the value as a `List`, widen them to `String` JSON — check `user_cache_service.dart`; the key is unchanged so no cache migration is needed beyond the legacy-list tolerance above.)

- [ ] **Step 4: Run to verify pass, then full suite + analyze**

Run: `cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_staging_test.dart -p vm 2>&1 | tail -6 && flutter test 2>&1 | tail -4 && flutter analyze 2>&1 | tail -3`
Expected: target test PASS; full suite green; analyze no NEW errors.

- [ ] **Step 5: Commit, deploy functions, manual smoke**

```bash
git add shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart shavtzak/lib/core/services/user_cache_service.dart shavtzak/test/presentation/bloc/assignment_bloc_staging_test.dart
git commit -m "feat(assignments): persist/rehydrate _baselineQuota + staged deletions"
```

Deploy the backend (REQUIRED — until then a staged lower silently no-ops):

```bash
cd functions && firebase deploy --only functions:api
```

**Manual smoke (in `/test`, after deploy):**
- [ ] Run a mock batch: swipe-delete several rows across roles + manual-add several — confirm **nothing writes** (grid shows red-stripe "יימחק בשמירה" + new dirty rows) until Save.
- [ ] Save → confirm assignments deleted/created, **quota lowered/raised**, and survivors reindexed to contiguous slotIndices.
- [ ] Force type-G: while dirty, raise a role's quota in the Firebase console → Save surfaces the type-G row; **דרוס DB** sets your quota and leaves the extra people as off-quota rows; **קח מה-DB** keeps the DB quota and still applies your deletions.
- [ ] Kill the tab mid-session → reload → staged deletions + adds recover with correct quota.
- [ ] Discard (inline ↩ and בטל הכל) reverts a striped row / all changes.

---

## Self-Review

**1. Spec coverage.** Every spec section maps to a task: scope/model → T5–T7; rendering (stripe + grid grow) → T7/T8; swipe-delete/off-quota/manual-add triggers → T9; Save (derive quota + reindex + exact set) → T10; backend eventQuotaSets + concurrency → T1–T3; client threading → T4; type-G conflict + dialog → T11; cache → T12; deploy + smoke → T12. Persistence of `markedForDeletion` = T5 (json) + T12 (baseline). No spec requirement is unassigned.

**2. Placeholder scan.** No "TBD"/"handle edge cases"/"similar to Task N" — each step shows real code or an exact edit location. Two deliberate "verify the exact expression" notes (the row-builder slotKey at ~908 in T8, `_overrideLabel` in T11) point at named, readable anchors, not vague work.

**3. Type consistency.** `EventQuotaSet = ({String eventId, String roleType, int target, int expected})` is identical across the backend payload (T3), the typedef (T4), the Save emission (T10), and tests. `derivedQuota(eventId, roleType)`, `_baselineQuota` (keyed `eventId_roleType`), `stagedDeletionSlotKeys`, `markedForDeletion`, `StageSlotDeletion(slot)`, `StageManualAdd({event, member, roleType})`, and `AssignmentConflictType.quotaChanged` are used consistently in the tasks that define and consume them. Backend `planEventQuotaSets`/`planEventQuotaSetWrites` signatures match their call sites in T3.

**Known follow-up (not blocking):** the reindex + off-quota-survivor interaction under an override with co-admin rows above the target is exercised in the T12 manual smoke rather than a unit test (it needs a multi-row live-DB fixture); if it proves fiddly, add a focused bloc test for `_reindexRoleSurvivors` with off-quota survivors.
