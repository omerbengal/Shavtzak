# Staged gap annotations — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make gap note/label edits — and quota-driven cleanups — flow through one **staged** model (Save bar, amber dirty markers, per-row undo, Discard, crash-recovery), applied on Save, replacing the immediate-write path and the buggy immediate auto-normalize.

**Architecture:** A **parallel** staged layer `_stagedSlotAnnotations` (keyed by the grid slotKey `"<eventId>_<roleType>_<slotIndex>"`) that plugs into the existing staging machinery *without touching the assignment-save partition*. Gap edits and quota cleanups both produce `StagedSlotAnnotation` entries; on Save a new phase writes them via the deployed `event.updateSlotAnnotation` mutation, after the assignment batch. Reuses FF1 `reconcileGapAnnotations` + FF2 `computeSlotAnnotationNormalization`.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, `equatable`; tests `flutter_test` + `mockito` + `bloc_test`.

Design spec: `docs/superpowers/specs/2026-07-23-staged-gap-annotations-design.md`.

## Global Constraints

- Hebrew UI text, RTL; English code comments.
- **Do NOT modify the assignment-save partition** (`_onSaveStagedChanges`'s creates/updates/deletes classification, `assignment.saveBatch`). The annotation Save is an ADDITIVE second phase.
- The grid slotKey format is `StagedAssignmentChange.slotKeyFor(eventId, roleType, slotIndex)` = `"<eventId>_<roleType>_<slotIndex>"`. The event-doc annotation key is `slotAnnotationKey(roleType, slotIndex)` = `"<roleType>#<slotIndex>"`. Translate between them explicitly.
- Staged annotations must: contribute to `stagedSlotKeys` (amber + undo), `stagedCount`/`hasStagedChanges` (Save bar + Save-enabled), Discard-all + per-slot Discard, and the crash-recovery cache (`_persistStaged`/rehydrate).
- No backend change, no new deploy (reuses the deployed `event.updateSlotAnnotation`).
- `flutter analyze` must stay clean (baseline 106, 0 new). Full suite must stay green.
- Commands run from repo root `/Users/omerbengal/Documents/Github Projects/Shavtzak/.claude/worktrees/empty-slot-gap-annotations`; Flutter from `shavtzak/`.

---

### Task 1: `StagedSlotAnnotation` model

**Files:**
- Create: `shavtzak/lib/presentation/bloc/assignment/models/staged_slot_annotation.dart`
- Test: `shavtzak/test/presentation/bloc/assignment/models/staged_slot_annotation_test.dart`

**Interfaces produced:** `StagedSlotAnnotation {eventId, roleType, slotIndex, SlotAnnotation? desired, SlotAnnotation? baseline, String? staleKey}`; `bool get isNoop`; `toJson`/`fromJson`; Equatable.

- [ ] **Step 1: Write the failing test**

```dart
// staged_slot_annotation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/slot_annotation.dart';
import 'package:shavtzak/presentation/bloc/assignment/models/staged_slot_annotation.dart';

void main() {
  group('StagedSlotAnnotation', () {
    const a = SlotAnnotation(note: 'x', labelId: 'L');
    StagedSlotAnnotation make({SlotAnnotation? desired, SlotAnnotation? baseline, String? staleKey}) =>
        StagedSlotAnnotation(
          eventId: 'e1', roleType: 'medic', slotIndex: 0,
          desired: desired, baseline: baseline, staleKey: staleKey);

    test('isNoop when desired == baseline and no staleKey', () {
      expect(make(desired: a, baseline: a).isNoop, isTrue);
      expect(make(desired: null, baseline: null).isNoop, isTrue);
      expect(make(desired: a, baseline: null).isNoop, isFalse);
      expect(make(desired: a, baseline: a, staleKey: 'medic#1').isNoop, isFalse); // a move is never a noop
    });

    test('JSON round-trips (incl. null desired = delete)', () {
      final s = make(desired: null, baseline: a, staleKey: 'medic#1');
      expect(StagedSlotAnnotation.fromJson(s.toJson()), s);
      final t = make(desired: a, baseline: null);
      expect(StagedSlotAnnotation.fromJson(t.toJson()), t);
    });
  });
}
```

- [ ] **Step 2: Run — FAIL (class undefined).** `cd shavtzak && flutter test test/presentation/bloc/assignment/models/staged_slot_annotation_test.dart`

- [ ] **Step 3: Implement**

```dart
// staged_slot_annotation.dart
import 'package:equatable/equatable.dart';
import '../../../../domain/entities/slot_annotation.dart';

/// A pending gap-annotation edit for one slot, staged until Save — the
/// annotation-world parallel of `StagedAssignmentChange`. Keyed in the bloc by
/// the grid slotKey "<eventId>_<roleType>_<slotIndex>".
class StagedSlotAnnotation extends Equatable {
  final String eventId;
  final String roleType;
  final int slotIndex;

  /// Desired final annotation for this slot; null = the slot should have NO
  /// annotation (a delete on Save).
  final SlotAnnotation? desired;

  /// The reconciled annotation this slot showed when first staged (revert
  /// target — a revert to it drops the entry).
  final SlotAnnotation? baseline;

  /// For a re-key MOVE: the old "<roleType>#<idx>" annotation key to delete in
  /// the same Save write. Null for a plain edit/delete.
  final String? staleKey;

  const StagedSlotAnnotation({
    required this.eventId,
    required this.roleType,
    required this.slotIndex,
    required this.desired,
    required this.baseline,
    this.staleKey,
  });

  /// Reverts to baseline and carries no move → nothing to save, drop it.
  bool get isNoop => desired == baseline && staleKey == null;

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'roleType': roleType,
        'slotIndex': slotIndex,
        'desired': desired?.toJson(),
        'baseline': baseline?.toJson(),
        'staleKey': staleKey,
      };

  factory StagedSlotAnnotation.fromJson(Map<String, dynamic> json) =>
      StagedSlotAnnotation(
        eventId: json['eventId'] as String,
        roleType: json['roleType'] as String,
        slotIndex: json['slotIndex'] as int,
        desired: json['desired'] == null
            ? null
            : SlotAnnotation.fromJson(
                Map<String, dynamic>.from(json['desired'] as Map)),
        baseline: json['baseline'] == null
            ? null
            : SlotAnnotation.fromJson(
                Map<String, dynamic>.from(json['baseline'] as Map)),
        staleKey: json['staleKey'] as String?,
      );

  @override
  List<Object?> get props =>
      [eventId, roleType, slotIndex, desired, baseline, staleKey];
}
```

- [ ] **Step 4: Run — PASS.** Same command. **Step 5: Analyze + commit.**
```bash
git add shavtzak/lib/presentation/bloc/assignment/models/staged_slot_annotation.dart shavtzak/test/presentation/bloc/assignment/models/staged_slot_annotation_test.dart
git commit -m "feat(assignments): StagedSlotAnnotation model for staged gap edits"
```

---

### Task 2: Staging core — map, event/handler, dirty/count union, Discard, cache

**Files:**
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_event.dart` (new `StageSlotAnnotation`)
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart`
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_state.dart` (only if `stagedCount` needs unioning — see below)
- Test: `shavtzak/test/presentation/bloc/assignment_bloc_staged_annotations_test.dart` (reuse the harness from `assignment_bloc_staging_test.dart` — its mocks + `member`/`futureEvent`/`assignment`/`medicRole` builders)

**Interfaces:** consumes `StagedSlotAnnotation` (Task 1), `slotAnnotationKey`/`ResolvedGapAnnotation` (slot_annotations.dart), `SlotAnnotation`. Produces `_stagedSlotAnnotations` map + `StageSlotAnnotation` handling.

- [ ] **Step 1: Add the event** (`assignment_event.dart`)
```dart
/// Stage a gap-annotation (note/label) edit on an EMPTY slot — the annotation
/// parallel of StageNotesChange. Written on Save, not immediately.
class StageSlotAnnotation extends AssignmentEvent {
  final AssignmentSlot slot;
  final String note;
  final String? labelId;
  const StageSlotAnnotation({required this.slot, required this.note, required this.labelId});
  @override
  List<Object?> get props => [slot, note, labelId];
}
```
(Import `AssignmentSlot` from `../../screens/assignment/models/assignment_slot.dart` if not already imported in this file.)

- [ ] **Step 2: Add the field + register + handler** (`assignment_bloc.dart`)

Field (near `_stagedChanges` ~line 112):
```dart
  /// Pending gap-annotation edits (note/label on empty slots), keyed by the
  /// same slotKey as _stagedChanges. Written on Save (see _onSaveStagedChanges
  /// phase 2); parallel to _stagedChanges, never routed through the assignment
  /// save partition.
  final Map<String, StagedSlotAnnotation> _stagedSlotAnnotations = {};
```
Register (with the other `on<...>` lines): `on<StageSlotAnnotation>(_onStageSlotAnnotation);`

Handler:
```dart
  Future<void> _onStageSlotAnnotation(
      StageSlotAnnotation event, Emitter<AssignmentState> emit) async {
    final slot = event.slot;
    final key = _slotKey(slot);
    final note = event.note.trim();
    final desired = (note.isEmpty && event.labelId == null)
        ? null
        : SlotAnnotation(note: note, labelId: event.labelId);
    final existing = _stagedSlotAnnotations[key];
    // Baseline + staleKey are captured ONCE, on the first stage of this slot,
    // from the slot's reconciled DB annotation (slot.gapAnnotation). On a
    // re-edit (existing != null) they are preserved — never re-read from the
    // now-overlaid display value (see Task 3). staleKey carries a drifted
    // source key so Save self-heals the DB key at the same time.
    final SlotAnnotation? baseline;
    final String? staleKey;
    if (existing != null) {
      baseline = existing.baseline;
      staleKey = existing.staleKey;
    } else {
      final resolved = slot.gapAnnotation;
      baseline = resolved?.annotation;
      final ownKey = slotAnnotationKey(slot.role.key, slot.slotIndex);
      staleKey = (resolved != null && resolved.sourceKey != ownKey)
          ? resolved.sourceKey
          : null;
    }
    final staged = StagedSlotAnnotation(
      eventId: slot.event.id, roleType: slot.role.key, slotIndex: slot.slotIndex,
      desired: desired, baseline: baseline, staleKey: staleKey);
    if (staged.isNoop) {
      _stagedSlotAnnotations.remove(key);
    } else {
      _stagedSlotAnnotations[key] = staged;
    }
    await _persistStaged();
    Logger.action('stage:slotAnnotation', {'slot': key, 'stagedCount': _stagedSlotAnnotations.length});
    add(RebuildAssignmentSlots(preservedFilter: _currentEventFilter));
  }
```

- [ ] **Step 3: Union into dirty-keys, count, hasStagedChanges**

At the THREE `stagedSlotKeys:` emit sites (`assignment_bloc.dart` ~3181, ~3296, ~3644 — grep `stagedSlotKeys: _stagedChanges.keys.toSet()`), change each to:
```dart
        stagedSlotKeys: {..._stagedChanges.keys, ..._stagedSlotAnnotations.keys},
```
The bloc `stagedCount` getter (~line 137, `_stagedChanges.length`) and `hasStagedChanges` getter → count/consider BOTH maps. Read them and change to:
```dart
  int get stagedCount => _stagedChanges.length + _stagedSlotAnnotations.length;
  bool get hasStagedChanges => _stagedChanges.isNotEmpty || _stagedSlotAnnotations.isNotEmpty;
```
The FAB reads `state.stagedSlotKeys.length` (screen ~584) — unioned via the emit sites, so no screen change needed. (Verify `AssignmentSlotsLoaded.stagedCount` in `assignment_state.dart` derives from `stagedSlotKeys.length`; if so it's already unioned.)

- [ ] **Step 4: Discard integration**

`_onDiscardAllStagedChanges` (~1801): after `_stagedChanges.clear();` add `_stagedSlotAnnotations.clear();`.
`_onDiscardStagedSlot` (~1773): after the `_stagedChanges.remove(event.slotKey)` logic, also `_stagedSlotAnnotations.remove(event.slotKey);`.

- [ ] **Step 5: Crash-recovery cache**

`_persistStaged` (~1459): add a key to the payload:
```dart
      'slotAnnotations':
          _stagedSlotAnnotations.values.map((s) => s.toJson()).toList(),
```
`_onRehydrateStagedChanges` (~1829): after restoring `_stagedChanges`, restore the annotations (tolerate absence in old blobs):
```dart
    _stagedSlotAnnotations
      ..clear()
      ..addEntries(((decoded is Map ? decoded['slotAnnotations'] as List? : null) ?? const [])
          .map((e) => StagedSlotAnnotation.fromJson(e as Map<String, dynamic>))
          .map((s) => MapEntry(
              StagedAssignmentChange.slotKeyFor(s.eventId, s.roleType, s.slotIndex), s)));
```

- [ ] **Step 6: Tests** (`assignment_bloc_staged_annotations_test.dart`)

Mirror the harness in `assignment_bloc_staging_test.dart`. Cover: (a) dispatch `StageSlotAnnotation` on an empty medic slot → `AssignmentSlotsLoaded.stagedSlotKeys` contains that slotKey and `bloc.stagedCount == 1`; (b) re-dispatch with the note reverted to baseline → entry dropped, count 0; (c) `DiscardAllStagedChanges` → cleared; (d) construct the bloc, stage, then a fresh bloc with the same `UserCacheService` + `RehydrateStagedChanges` → `_stagedSlotAnnotations` restored (assert via a subsequent stage/save observable, or expose a test-only getter if the existing tests do). Get the empty medic slot from the loaded state the way the existing staging tests do.

- [ ] **Step 7: Analyze + commit.**
```bash
git add -A && git commit -m "feat(assignments): stage gap-annotation edits (map, event, dirty/count, discard, cache)"
```

---

### Task 3: Display overlay — staged edit shows immediately

**Files:**
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart` (both slot-build sites)
- Test: extend `assignment_bloc_staged_annotations_test.dart`

Both build sites set `gapAnnotation: assignment == null ? gapAnnotations[i] : null` (~3141, ~3501, where `gapAnnotations` is `reconcileGapAnnotations(...)`). Wrap the reconciled value with a staged overlay via a helper:

```dart
  /// The gap annotation to render for a slot: the STAGED edit if one exists
  /// (so a pending edit shows immediately), else the reconciled DB value.
  ResolvedGapAnnotation? _effectiveGapAnnotation(
      String eventId, String roleKey, int slotIndex, ResolvedGapAnnotation? reconciled) {
    final key = StagedAssignmentChange.slotKeyFor(eventId, roleKey, slotIndex);
    final staged = _stagedSlotAnnotations[key];
    if (staged == null) return reconciled;
    if (staged.desired == null) return null; // staged delete → show nothing
    final ownKey = slotAnnotationKey(roleKey, slotIndex);
    return (annotation: staged.desired!, sourceKey: staged.staleKey ?? ownKey);
  }
```
At each build site change the `gapAnnotation:` argument to:
```dart
            gapAnnotation: assignment == null
                ? _effectiveGapAnnotation(event.id, role.key, i, gapAnnotations[i])
                : null,
```
(Use each site's own event var — `event` at site 1, `eventData` at site 2.)

Test: stage a note on the empty medic slot → the rebuilt slot's `gapAnnotation?.annotation` equals the staged desired; stage a delete (empty note) on a slot that had a DB annotation → `gapAnnotation` is null. Analyze + commit `feat(assignments): render staged gap annotations immediately (overlay)`.

---

### Task 4: Gap dialog stages instead of writing immediately

**Files:** Modify `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart` (`_showGapAnnotationDialog`).

In `_showGapAnnotationDialog`, the Save button currently does `context.read<EventBloc>().add(UpsertSlotAnnotation(...))` + a "ההערה נשמרה" snackbar. Replace with a staged dispatch (no snackbar — it now shows in the Save bar):
```dart
                onPressed: () {
                  context.read<AssignmentBloc>().add(StageSlotAnnotation(
                        slot: slot,
                        note: noteController.text.trim(),
                        labelId: selectedLabelId,
                      ));
                  Navigator.of(dialogContext).pop();
                },
```
Remove the now-unused `ownKey`/`sourceKey`/`staleKey` computation in the dialog (the bloc handler computes staleKey from `slot.gapAnnotation` now) and the `UpsertSlotAnnotation`/`EventBloc`/`EventEvent` imports if this was their only use in the file (grep first). Add the `StageSlotAnnotation` import. `flutter analyze` clean + existing screen tests pass. Manual smoke: edit a gap → row goes amber, "שמור · N" increments, nothing written until Save. Commit `feat(assignments-screen): gap dialog stages the edit instead of writing immediately`.

---

### Task 5: Save phase 2 — write staged annotations

**Files:** Modify `assignment_bloc.dart` (`_onSaveStagedChanges`); test in `assignment_bloc_staged_annotations_test.dart`.

Insert AFTER the assignment batch is fully committed + `_stagedChanges` applied-keys removed + the existing `await _persistStaged();` (~line 2598), and BEFORE the success message (~2603):
```dart
      // Phase 2: staged gap-annotation edits. Separate event-doc mutations
      // (NOT part of the atomic assignment batch); run only after the batch
      // committed. A failure here leaves these entries staged for the next
      // Save while the assignment write stands.
      for (final s in _stagedSlotAnnotations.values.toList()) {
        await _eventRepository.updateSlotAnnotation(
          s.eventId, slotAnnotationKey(s.roleType, s.slotIndex), s.desired,
          staleKey: s.staleKey);
      }
      _stagedSlotAnnotations.clear();
      await _persistStaged();
```
Save is already enabled when annotations are staged (Task 2 unioned `hasStagedChanges`/count). Verify `_onSavePressed`'s guard uses `bloc.hasStagedChanges` (it does) so an annotation-only Save proceeds.

Tests: (a) stage one annotation, no assignment changes, dispatch `SaveStagedChanges` → `verify(eventRepo.updateSlotAnnotation('e1', 'medic#0', const SlotAnnotation(note:'x', labelId:'L'), staleKey: null)).called(1)` and `_stagedSlotAnnotations` empty after; (b) MIXED — stage an assignment member change AND a gap annotation, Save → the assignment `saveAssignmentsBatch` is called AND `updateSlotAnnotation` is called, both staged maps cleared. Stub `eventRepo.updateSlotAnnotation(...)` → `thenAnswer((_) async {})`. Analyze + commit `feat(assignments): Save writes staged gap annotations after the assignment batch`.

---

### Task 6: Quota-cleanup stages (replaces the immediate normalize) + fires reliably

**Files:** Modify `assignment_bloc.dart` (replace `_normalizeSlotAnnotations`; fix its trigger). Update the FF3/FF4 tests that asserted an immediate `updateSlotAnnotation` call.

Replace the fire-and-forget `_normalizeSlotAnnotations` (~3316-3360) with a STAGING version, and delete the `_normalizedSlotAnnotationOps` field/guard (~167) — the staged map is now the dedup:
```dart
  /// After a quota change, STAGE the annotation cleanup (re-key moved notes,
  /// delete true orphans) so it shows as a pending change and is applied on
  /// Save — never an immediate write. Idempotent: skips a slot the user has
  /// already staged, and re-running recomputes the same entries.
  Future<void> _stageSlotAnnotationCleanup(
      List<Event> events, List<Assignment> assignments) async {
    var changed = false;
    for (final event in events) {
      if (event.slotAnnotations.isEmpty) continue;
      final roleKeys = <String>{};
      for (final k in event.slotAnnotations.keys) {
        final p = parseSlotAnnotationKey(k);
        if (p != null) roleKeys.add(p.roleKey);
      }
      for (final roleKey in roleKeys) {
        final quota = event.roleRequirements[roleKey] ?? 0;
        final filled = assignments
            .where((a) => a.eventId == event.id && a.roleType == roleKey)
            .map((a) => a.slotIndex);
        final ops = computeSlotAnnotationNormalization(
            event.slotAnnotations, roleKey, quota, filled);
        for (final op in ops) {
          final parsed = parseSlotAnnotationKey(op.key);
          if (parsed == null) continue;
          final slotKey = StagedAssignmentChange.slotKeyFor(
              event.id, parsed.roleKey, parsed.slotIndex);
          if (_stagedSlotAnnotations.containsKey(slotKey)) continue; // don't clobber a user edit
          final staged = StagedSlotAnnotation(
            eventId: event.id, roleType: parsed.roleKey, slotIndex: parsed.slotIndex,
            desired: op.value, baseline: event.slotAnnotations[op.key],
            staleKey: op.staleKey);
          if (!staged.isNoop) {
            _stagedSlotAnnotations[slotKey] = staged;
            changed = true;
          }
        }
      }
    }
    if (changed) await _persistStaged();
  }
```

**Trigger (this is the Issue-1 fix — verify against the real flow):** the cleanup must run when the reduced `roleRequirements` is known.
- Keep calling it from `_onRebuildAssignmentSlotsFromData` (replace the old `_normalizeSlotAnnotations(...)` call at ~3441 with `await _stageSlotAnnotationCleanup(filteredEvents, mergedAssignments);`) — this is the live-stream backstop.
- ALSO make an event-form quota reduction fire it deterministically: `_onRebaselineQuotasForEvent` (~1748) receives the new `roleRequirements` for the event. Update the cached event in `_windowEventsMap`/`_extraPastEventsMap` with those new requirements (so a rebuild sees the reduced quota without waiting for the Firestore listener), then call `await _stageSlotAnnotationCleanup([<that updated event>], <raw assignments for it>)` before its `RebuildAssignmentSlots` dispatch. **Read `_onRebaselineQuotasForEvent` and the `_windowEventsMap` update path and wire this so it fires immediately after the modal save.** If updating the cached event in place is awkward, an acceptable alternative is to dispatch `RebuildAssignmentSlotsFromData` (the normalize-carrying handler) after refreshing that event — choose whichever the surrounding code supports cleanly, and note your choice in the report.

**Update FF3/FF4 tests:** the tests in `assignment_bloc_staging_test.dart` that asserted an immediate `updateSlotAnnotation` call on rebuild now assert the cleanup is **staged** instead: after driving the drift (event with `slotAnnotations {'medic#1': ...}`, quota reduced to 1), assert `_stagedSlotAnnotations` has an entry for `medic#0` (re-key, staleKey `medic#1`) or the orphan slot, and that `updateSlotAnnotation` is NOT called until `SaveStagedChanges`. Keep the FF2/FF4 pure-helper tests (`computeSlotAnnotationNormalization`, reconcile) unchanged. Analyze + full suite + commit `feat(assignments): quota-cleanup stages instead of writing immediately`.

---

### Task 7: Show an orphaned annotation as a pending "will be removed" row

**Files:** Modify `assignment_list_screen.dart` (slot rendering) and, if needed, the bloc slot-build to surface orphaned-but-staged annotations as rows.

When a note is orphaned (out of quota, no gap) AND has a staged deletion in `_stagedSlotAnnotations` (desired == null), it has no normal row. Surface it using the existing off-quota row + red "יימחק בשמירה" stripe treatment (`_buildOffQuotaRow` / `_withStripeOverlay`, already used for staged assignment deletions):
- In the bloc slot-build, after building a role's slots, for each `_stagedSlotAnnotations` entry belonging to this (event, role) whose `slotIndex >= requiredCount` and `desired == null` (a staged orphan delete), synthesize a display-only `AssignmentSlot` marked such that the screen renders it as an off-quota annotation row showing `baseline` (the note being removed). Reuse the `isOffQuota` flag; carry the `baseline` note via `gapAnnotation`.
- In the screen, that off-quota annotation row shows the purple note + the "יימחק בשמירה" stripe (reuse `_withStripeOverlay(row, badgeText: 'יימחק בשמירה')`), and its swipe/undo maps to `DiscardStagedSlot(slotKey)` (keeps the note).

> This is the fiddliest UI task; read `_buildOffQuotaRow`, `isOffQuota`, and the `stagedDeletionSlotKeys` stripe path, and mirror them. `flutter analyze` clean + existing screen tests pass. Manual smoke: quota 2→1 with two annotated empty medic slots → the surviving slot shows its note (amber if re-keyed), and the orphaned note shows as a "יימחק בשמירה" row; Save removes it, Discard keeps it. Commit `feat(assignments-screen): show orphaned gap notes as pending-removal rows`.

---

### Task 8: Remove dead paths + full verification

**Files:** `assignment_bloc.dart`, `event_bloc.dart`/`event_event.dart` (if `UpsertSlotAnnotation` is now unused), tests.

- [ ] Grep for `UpsertSlotAnnotation` — if the gap dialog (Task 4) was its only dispatcher and nothing else uses it, remove the `UpsertSlotAnnotation` event + its `EventBloc` handler (and the now-unused `event_bloc_slot_annotation_test.dart` or update it). If anything still uses it, leave it. Grep for `_normalizeSlotAnnotations` / `_normalizedSlotAnnotationOps` — confirm fully removed (replaced by Task 6).
- [ ] `cd shavtzak && flutter analyze` → 106 baseline, 0 new.
- [ ] `cd shavtzak && flutter test` → all green.
- [ ] Manual smoke checklist for the user (worktree `.claude/worktrees/empty-slot-gap-annotations`, from `shavtzak/`):
  1. Edit a gap note/label → row amber, "שמור · N" up, `test_events` unchanged until Save; Save writes it; Discard drops it; refresh mid-edit keeps it staged.
  2. Mix a filled-row change + a gap-note change → one Save applies both.
  3. Quota 2→1 (scenario 2) → surviving slot keeps its note; orphaned note shows "יימחק בשמירה"; Save removes it from `test_events`; Discard keeps it.
  4. Quota 2→1 (scenario 1, one annotated slot) → the note re-keys onto the surviving row on Save (`medic#1`→`medic#0` in `test_events`).
- [ ] Commit `chore(assignments): remove immediate gap-annotation write paths`.

## Self-review notes (author)
- Spec coverage: staging model (T1), staged edits + dirty/count/discard/cache (T2), immediate display (T3), dialog rewire (T4), Save phase (T5), quota-cleanup staged + fixed trigger (T6, Issue 1), orphan visibility (T7), dead-path removal (T8). All spec sections covered.
- Assignment-save partition untouched (T5 is an additive phase after the batch).
- Type consistency: slotKey `"<eventId>_<roleType>_<slotIndex>"` (via `StagedAssignmentChange.slotKeyFor`) vs annotation key `"<roleType>#<slotIndex>"` (via `slotAnnotationKey`) translated explicitly at every hop.
- Known-fiddly: T6 trigger wiring and T7 orphan-row rendering both require reading surrounding bloc/screen code; flagged inline.
