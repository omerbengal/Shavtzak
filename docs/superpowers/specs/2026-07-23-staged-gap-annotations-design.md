# Staged gap annotations — design (iteration on the gap-annotations feature)

- **Date:** 2026-07-23
- **Branch:** `feat/empty-slot-gap-annotations` (same branch; not yet merged)
- **Status:** Proposed — awaiting confirmation before implementation
- **Supersedes:** the *immediate-write* edit path and the *immediate auto-normalize* (FF3) from `2026-07-22-empty-slot-gap-annotations-design.md`. Reuses FF1 (`reconcileGapAnnotations` dormant-on-filled fix) and FF2 (`computeSlotAnnotationNormalization`) unchanged.

## Motivation (test feedback)

1. **Bug:** the quota-change auto-normalize doesn't fire deterministically. It's called only inside `_onRebuildAssignmentSlotsFromData`, but a quota edit dispatches `RebuildAssignmentSlots` (the *other* rebuild handler) via `RebaselineQuotasForEvent`; normalize then only runs incidentally when the Firestore listener re-emits. So an orphaned note (`medic#1` after a 2→1 reduction) isn't cleaned right after the edit. (The test also confirmed the backend correctly *preserves* `slotAnnotations` across `event.update` — no wipe.)
2. **Consistency ask:** editing a gap row's note/label should **stage** like editing a filled row's note/label — pending in the "שמור · N" bar, amber dirty marker, per-row undo, Discard, and crash-recovery — not an immediate write.

Chosen direction (**Option A**): make *all* slot-annotation changes — user edits **and** quota-driven cleanups — flow through one staged model, applied on Save.

## Approach: a parallel staged-annotation layer

Gap annotations live on the **event** (`Event.slotAnnotations`), while the staged-Save system is built for **assignments** (`_stagedChanges` of `StagedAssignmentChange`) and actively *drops* member-less staged changes at Save (`clear-noop`, `assignment_bloc.dart:2339-2349`). So we do **not** route gap edits through `_stagedChanges`. Instead, a **parallel** map plugs into the same UI/Save machinery **without touching the assignment-save partition**.

### Model
`StagedSlotAnnotation` (new, `lib/presentation/bloc/assignment/models/staged_slot_annotation.dart`):
```dart
class StagedSlotAnnotation {
  final SlotAnnotation? desired;   // null = the slot should have NO annotation (delete)
  final SlotAnnotation? baseline;  // DB annotation for this slot when first staged (revert target)
  final String? staleKey;          // for a re-key MOVE: the old "<role>#<idx>" key to delete on Save
  bool get isNoop => desired == baseline && staleKey == null; // drop when reverted
  Map<String,dynamic> toJson(); factory fromJson(...); // for crash-recovery cache
}
```
Bloc state: `final Map<String, StagedSlotAnnotation> _stagedSlotAnnotations = {};` keyed by the grid slotKey `"${eventId}_${roleType}_${slotIndex}"` (same format as `_stagedChanges`, so keys union into `stagedSlotKeys` naturally).

### 1. Editing a gap row (the Issue-2 ask)
- The gap dialog (`_showGapAnnotationDialog`) dispatches a new `StageSlotAnnotation(slot, note, labelId)` **instead of** the immediate `UpsertSlotAnnotation`.
- Handler seeds `baseline` from the slot's current *effective* DB annotation and sets `desired` from the dialog (null when note blank + no label), drops the entry if `isNoop`, persists to cache, rebuilds.
- The old `EventBloc.UpsertSlotAnnotation` immediate path is removed from the dialog (kept only if some other caller needs it — none does today).

### 2. Display overlay (staged edits show immediately)
Today `reconcileGapAnnotations` runs against **raw DB** `event.slotAnnotations` (two sites, `assignment_bloc.dart:3022`, `:3469`) with no staged overlay. Add a post-step: when attaching `gapAnnotation` to an empty slot, if `_stagedSlotAnnotations[slotKey]` exists, use its `desired` (or hide it when `desired == null`) instead of the reconciled DB value — mirroring how `_mergeSlotsWithOptimisticUpdates` overlays staged assignment fills. So a pending edit renders instantly, amber-bordered.

### 3. Quota-driven cleanup as staged changes (Issue 1 + Option A)
On the rebuild that actually follows a quota change (**fix the wiring** — compute in a shared step reachable from both `_onRebuildAssignmentSlots` and `_onRebuildAssignmentSlotsFromData`, so an event-form quota edit's `RebuildAssignmentSlots` triggers it), for each (event, role) run `computeSlotAnnotationNormalization` and **stage** each op (don't write):
- **Re-key** (`medic#1`→`medic#0`): stage on the surviving `medic#0` slot `desired = the note`, `baseline = DB medic#0 (none)`, `staleKey = 'medic#1'`. The note shows on the `medic#0` row, amber = pending; Save writes `medic#0` and deletes `medic#1` in one call.
- **Orphan delete** (`medic#1` out-of-quota, no gap): stage `desired = null`, `baseline = the note`, keyed by `medic#1`. Because that slot no longer renders, surface it as an **out-of-quota annotation row** (reuse the off-quota row + the red "יימחק בשמירה" stripe already used for staged deletions) so the note is visible and Save/Discard-able.
- Staging is idempotent (re-running on a later rebuild recomputes the same staged entries; `isNoop`/dedup keeps them stable), and it never fires without a Save.

### 4. Save (additive phase — assignment partition untouched)
In `_onSaveStagedChanges`, **after** partitioning/writing the assignment batch, add a phase: for each `_stagedSlotAnnotations` entry, call `_eventRepository.updateSlotAnnotation(eventId, slotAnnotationKey(roleType, slotIndex), desired, staleKey: staleKey)`. Clear `_stagedSlotAnnotations` on success. These are separate mutations from `assignment.saveBatch` (each independently consistent); an annotation-write failure leaves those entries staged for the next Save while the assignment batch result stands. Save is allowed when *either* staged map is non-empty.

### 5. Dirty markers / count / Discard / cache
- **Union** `_stagedSlotAnnotations.keys` into `stagedSlotKeys` at the three emit sites (`assignment_bloc.dart:3181`, `:3296`, `:3644`) and into the `stagedCount`/`hasStagedChanges` getters — so amber border, the per-row "↩" undo, and the "שמור · N" count all cover annotation edits with no screen-widget changes.
- `DiscardStagedSlot(slotKey)` and `DiscardAllStagedChanges` also clear the matching `_stagedSlotAnnotations` entries.
- `_persistStaged` adds a `'slotAnnotations'` array to its JSON; `_onRehydrateStagedChanges` decodes it back (tolerating its absence for old cache blobs).

## What is removed / reused
- **Removed:** the immediate gap-write (dialog → `UpsertSlotAnnotation` → `event.updateSlotAnnotation` on keystroke-save) and the immediate auto-normalize wiring (`_normalizeSlotAnnotations` fire-and-forget from FF3, plus the `_normalizedSlotAnnotationOps` guard).
- **Reused unchanged:** FF1 `reconcileGapAnnotations` (dormant-on-filled) and FF2 `computeSlotAnnotationNormalization` (now feeds staging instead of firing). The `event.updateSlotAnnotation` backend mutation (already deployed) is the Save-phase writer.

## Non-goals
- **מסך מנהלים (summary)** stays display-only for annotations: it shows the **DB** state, so staged-but-unsaved annotation edits appear there only after Save — consistent with how staged assignment changes already behave. No summary changes.
- **No backend change, no new deploy** (reuses the deployed mutation; ships with the normal web deploy on merge).
- The extra phone stays member-level (unchanged).

## Risks / testing
- The Save handler and the staged-cache format are load-bearing (crash recovery); changes are **additive** (new phase, new JSON key) and must not perturb the assignment partition. Cover with bloc tests: stage an edit → amber + count; Save → `updateSlotAnnotation` called with the right args, staged cleared; Discard → dropped; rehydrate round-trip; quota 2→1 stages a re-key (with staleKey) and an orphan-delete; `flutter analyze` clean; full suite green.
