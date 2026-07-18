# Assignments Screen — Staged Quota Changes (swipe-delete + manual-add) — Design

**Date**: 2026-07-18
**Branch**: `feat/assignments-staged-save`
**Status**: Approved by Omer (brainstorming session 2026-07-18)
**Builds on**: [2026-07-15 Assignments Staged "Save" Batch](2026-07-15-assignments-staged-save-design.md) (shipped/merged)

## Overview

The staged-save feature converted assign / swap / clear / notes edits on `/admin/assignments`
to a **stage-then-Save** model. It deliberately left the two **quota-changing** grid actions —
**swipe-delete a row** and the **manual-add wizard** — as **immediate** writes (each mutates the
`Event.roleRequirements` document, not just an assignment doc). During the 1–2 hour batch meeting
those two actions therefore still pay a blocking, non-atomic, non-reviewable round-trip, and they
break the "nothing hits the DB until Save" mental model the rest of the screen now has.

This feature brings **both** into staging: swiping a filled row and adding a person via the wizard
become **instant, reversible, in-memory changes** — *including* their ∓1 quota effect — written to
Firestore only on **Save**, inside the same **single atomic batch** as the assignment edits.

The quota (`roleRequirements`) is modeled as a **derived overlay on top of the live DB view**,
exactly like assignments already are: the grid stays live and renders staged deletions / additions
on top. Save converges the DB to the desired assignments **and** the desired quota atomically, and
**re-indexes survivors** so slot indices stay contiguous.

Because quota is now staged, a co-admin can change a role's quota in the DB *after* you staged a
change to it — a new **type-G ("quota changed underneath you")** conflict, folded into the existing
Save-time A–F resolution dialog.

## Goals / Non-goals

**Goals**

- **Swipe-delete a row** becomes staged: the row stays visible, struck through, until Save; the
  role's quota lowers by 1 on Save (not before).
- **Manual-add wizard** becomes staged: the chosen person appears in a new dirty slot immediately;
  the role's quota rises by 1 on Save (not before).
- Save writes the assignment deletes/creates **+ the exact new quota + survivor re-index** as one
  **atomic** server-side batch.
- **Crash recovery**, **discard** (inline ↩ + all-at-once), **leave-guard**, and the **"שמור · N"**
  count all extend to cover staged quota changes and deletions — no half-covered surface.
- **Type-G conflict** (concurrent quota edit) is surfaced and resolved in the existing Save dialog,
  **non-destructively** (never silently clobbers a co-admin's rows).

**Non-goals (explicitly out of scope)**

- **Event-form quota editing** (`EventFormModal` `_roleRequirements` + `QuotaReductionAnalyzer` /
  `QuotaReductionDialog`). This stays **immediate**, exactly as today. It is a shared modal used on
  the events screen too (no staging context there); staging it is a separate future spec.
- Re-enabling Google Calendar sync (unchanged; still hooks at Save-success).
- Multi-device sync of staged changes (cache stays per-browser, per-environment).
- A server read-transaction (`runTransaction`). The atomic server-side `db.batch()` is kept; the
  tiny resolve→commit window remains acceptable for a single-editor meeting.

## Scope — staged vs. immediate (delta from the 2026-07-15 spec)

| Action | DB effect | 2026-07-15 | **This feature** |
|---|---|---|---|
| Assign / swap / clear / notes | assignment doc | Staged | Staged (unchanged) |
| **Swipe-delete a filled in-quota row** | delete assignment **+ quota↓ + re-index** | Immediate | **Staged** |
| **Swipe-delete an empty in-quota slot** | **quota↓ + re-index** (no assignment) | Immediate | **Staged** |
| **Manual-add wizard** | create assignment **+ quota↑** | Immediate | **Staged** |
| **Swipe-delete an off-quota row** | delete assignment (no quota change) | Immediate | **Staged** (delete only, no quota) |
| Event-form modal (times/location/**quota**) | update event | Immediate | **Immediate (unchanged)** |

**Mixed model, tightened.** The only remaining immediate quota path is the event-form modal.
Everything reachable *directly on the assignments grid* is now staged.

## Architecture — quota as a derived overlay

The staged-save feature stores per-slot desired state in
`Map<slotKey, StagedAssignmentChange> _stagedChanges` (`slotKey = eventId_roleType_slotIndex`) and
renders it over the live DB via the pending-operations merge. This feature adds **two** things:

1. A **per-slot "staged deletion" state** — a row you swiped to delete. Distinct from a staged
   *clear* (which empties a slot but keeps it): a deletion keeps the **person visible, struck
   through** ("יימחק בשמירה"), and removes the whole slot on Save.
2. A **per-`(event,role)` baseline quota snapshot** — the DB quota captured the first time you take
   a quota-changing action on that role. Used **only** to detect the type-G conflict at Save.

### Desired quota is DERIVED, not stored

There is **no** separately stored "desired quota" number to drift out of sync. For any role, the
intended quota is a pure function of the staged per-slot state and the captured baseline:

```
desiredQuota(event, role) = baselineQuota(event, role)
                          + (# staged ADDS in that role)      // appended slots (manual-add)
                          − (# staged DELETIONS in that role) // marked-for-deletion slots
```

- A **staged add** is a staged fill on a **previously-empty** slot (`baselineMemberId == null`) whose
  `slotIndex >= baselineQuota` — a slot the wizard appended beyond the quota. Filling an *existing*
  empty in-quota slot (`slotIndex < baselineQuota`) is a normal fill, **not** an add, and does not
  raise the quota. Editing an existing off-quota DB row is an update, not an add.
- A **staged deletion** is a slot flagged marked-for-deletion.

This keeps the model closed-form and consistent: reverting the last add or un-deleting a row moves
the derived quota back exactly, with nothing to reconcile.

### Rendering: the grid never shrinks while staged

- Rendered slot count for a role = **liveDBQuota (from the live event stream) + staged adds**.
- Staged deletions render **in place**, struck through (the existing red diagonal-stripe overlay
  `_DiagonalStripesPainter`, badge **"יימחק בשמירה"**), still showing the person + note/label/phone.
- Manual-added slots render as normal **dirty (yellow-border)** rows.
- Nothing collapses or re-indexes on screen. **Only Save** lowers the quota, deletes the rows, and
  closes ranks.

## Data shape

Extend the existing `StagedAssignmentChange` with a deletion flag, and add one map on the BLoC:

```
StagedAssignmentChange {
  … existing fields …
  markedForDeletion   // NEW: true => this row is staged to be deleted (row + slot removed on Save)
}
```

- `markedForDeletion == true` keeps `desiredMemberId` = the row's current member so the striped row
  still shows the person. The **auto-drop on revert-to-baseline** (`matchesBaseline`) is **suppressed**
  while `markedForDeletion` is set — a deletion is an intentional divergence, not a no-op.
- An empty in-quota slot swiped for deletion is a `markedForDeletion` entry with no member (there is
  no assignment doc to delete on Save — it only lowers the quota).

```
_baselineQuota: Map<eventRoleKey, int>   // eventRoleKey = "eventId_roleType"
```

- Seeded lazily from the live event's `roleRequirements` the **first** time a role gets a staged
  add/deletion; never overwritten while dirty. Cleared with the rest of staging on Save-success.
- Persisted alongside the staged list (see Cache).

**Dirty ⇔** `_stagedChanges` non-empty (adds, edits, and deletions all live there). The derived
quota and `_baselineQuota` produce **no** dirtiness on their own — they are consequences of staged
slot state.

## BLoC surface (new / changed)

- `StageSlotDeletion(slotKey)` — mark a row for deletion (seed `_baselineQuota` for its role if
  first touch). Renders striped; contributes −1 to the derived quota.
- `DiscardStagedSlot(slotKey)` (existing) — also un-marks a deletion / removes a staged add,
  restoring the row to its DB state (or removing the appended slot).
- Manual-add routes through the existing **`StageAssignmentEdit`** at `slotIndex = liveDBQuota`
  (an append) — no bespoke event; the +1 falls out of the derived-quota formula.
- `SaveStagedChanges(resolutions?)` (existing) — extended to compute per-role final quota, emit the
  exact quota target + survivor re-index into the batch, and detect/resolve type-G.
- `classifyStagedConflicts(currentSlots)` (existing) — extended to emit **type-G** rows per
  `(event,role)` in addition to the per-slot A–F rows.

## Per-trigger interaction changes

- **Swipe-delete (filled in-quota row)** — `_handleSlotDismiss` stops doing its immediate
  `deleteAssignment` + reindex + `EventBloc.UpdateEvent(quota−1)`. Instead it dispatches
  `StageSlotDeletion(slotKey)`. **No confirm dialog** (it is reversible; matches how staged edits
  already work) — the row stripes over with an inline **↩ undo**.
- **Swipe-delete (empty in-quota slot)** — same `StageSlotDeletion`, no assignment to delete;
  lowers the derived quota by 1.
- **Swipe-delete (off-quota row)** — `_buildOffQuotaRow`'s swipe stages a plain deletion (delete the
  assignment doc on Save); **no** quota change (off-quota rows are already outside the quota).
- **Manual-add wizard** — `_createAssignmentAndQuota` stops doing its immediate
  `EventBloc.UpdateEvent(quota+1)` + `CreateAssignmentWithBypass`. Instead it stages a fill at the
  next appended slot (`slotIndex = liveDBQuota`); the grid grows by one dirty slot; the +1 is applied
  on Save. **Append-only** — a manual-add never reuses a marked-for-deletion slot.
- **Entanglement:** swipe-deleting a slot that currently holds a **staged add** cancels the add
  (removes the appended slot) rather than creating a deletion. Swipe-deleting a slot that holds a
  staged **fill/edit over a DB row** converts it to a `markedForDeletion` entry.

## Save flow (delta)

Between conflict resolution and the atomic write, per affected role:

1. **Derive the final quota** for each role touched by a staged add/deletion:
   `final = baselineQuota + adds − deletions`, adjusted by the role's type-G resolution
   (override → this value; takeDb → keep the live DB quota).
2. **Apply deletions** — every `markedForDeletion` entry with an assignment → a batch `delete`
   (an empty-slot deletion contributes only to the quota).
3. **Re-index survivors** — for **every role that had a deletion**, take the surviving rows for that
   role (in- and off-quota alike), order by current `slotIndex`, and renumber them **contiguous from
   0** (batch `update`s carrying each survivor's staged edits, if any). The role's final quota then
   determines which indices are in-quota (`< quota`) vs off-quota (`>= quota`). This mirrors today's
   immediate swipe-delete reorder — **Save-time only, invisible in the grid**.
4. **Write the exact quota** — one event write per affected `(event,role)` setting
   `roleRequirements.<role>` to the final value, **in the same batch**.
5. **Commit** one atomic server-side `db.batch()` (assignment creates/updates/deletes + event quota
   sets + survivor reindex). Success → clear staging + `_baselineQuota` + cache; failure → keep all
   intact, Save stays enabled.

Manual-add's +1 no longer needs the pre-existing `max`-merge `eventQuotaBumps`: a role with staged
quota changes always ships an **exact quota target** (step 4). The `max`-merge bump stays **only**
for the type-D override-restore path (re-creating a row whose slot vanished under a *co-admin's*
shrink); if a role is subject to both, the exact target wins (reconciled to `max(intent, restore)`).

## Backend changes (`functions/src/index.ts`, `assignment.saveBatch`)

The op currently accepts an optional `eventQuotaBumps` and applies `to = max(current, count)`
(raise-only). Extend it to also **set/lower** a quota atomically, with optimistic concurrency:

- **New payload:** an exact-target quota list, e.g. `eventQuotaSets: [{eventId, roleType, target,
  expected}]`, where `target` is the desired count and `expected` is the client's `baselineQuota`.
- **Concurrency (type-G, server side):** in the pre-batch read phase, read each event's live quota.
  If `live !== expected` **and** `live !== target`, the DB moved off the client's baseline in a way
  the client did **not** already resolve → reject with a specific error (`409`-style) so a
  never-shown-the-dialog race fails loud instead of clobbering. When the client sends a **resolved**
  target (override), `expected` is updated to the live value so the intended set applies. (Primary
  detection is client-side, in `classifyStagedConflicts`, before Save; this is the belt-and-suspenders
  server guard for the resolve→commit window.)
- **Apply:** write `roleRequirements.<roleType>` = `target` (a real set — may lower) in the same
  `db.batch()`, audited. A no-op (`target === live`) is skipped.
- Keep `eventQuotaBumps` (`max`-merge) for the type-D override-restore path. Validators stay pure and
  unit-tested (`planEventQuotaSets` alongside `planEventQuotaBumps` in `assignment_save_batch.test.ts`).
- **Additive + backward-compatible:** absent field = today's behavior. Client threads an
  `EventQuotaSet` typedef through `DatabaseInterface` / `FirestoreDatabase` / `LoggingDatabase` /
  `AssignmentRepository.saveAssignmentsBatch`.
- **Requires `cd functions && firebase deploy --only functions:api`** — functions do not auto-deploy.
  Until deployed, the new client sends `eventQuotaSets` that the old backend ignores → a staged quota
  **lower would silently not apply** (rows delete, quota stays). Ship the deploy with the client.

## Conflict handling — type G

### Definition & detection

At Save, for each `(event,role)` with a staged quota change, compare the captured
`baselineQuota` to the **live DB quota** (from the event stream, already in `_windowEventsMap` /
`_extraPastEventsMap` — no fetch). Type-G fires when **`liveDBQuota != baselineQuota`** *and*
`desiredQuota != liveDBQuota` (a genuine unresolved divergence). If they have converged
(`desired == live`), there is no conflict.

Per-slot A–F still fire independently: a co-admin who *lowered* a quota by deleting rows also
surfaces as per-slot D (`slotVanished`) / B (`targetRemoved`) on any slots you staged. Type-G is the
piece A–F miss: a co-admin who **raised** the quota (adding rows at higher indices you never touched)
against your staged **lower**, which your exact-set would otherwise clobber.

**Convergent deletion:** a staged deletion whose slot has *already* vanished from the DB (the
co-admin removed the same slot) is **satisfied** — dropped silently, no dialog row, like a
clear-over-empty.

### Taxonomy row (added to the existing A–F table)

| # | Type (Hebrew) | Situation | **דרוס DB** (yours wins) | **קח מה-DB** (drop yours) |
|---|---|---|---|---|
| **G** | המכסה שונתה | You staged a quota change for a role; the DB quota moved off your baseline | **exact-SET** the role to your derived quota. DB rows above it that you did **not** mark for deletion **survive as off-quota rows** (nothing auto-deleted). Your marked deletions apply. | Keep the co-admin's DB quota. Your explicit row deletions still apply (may leave an unfilled in-quota slot). |

- **One row per `(event,role)`**, keyed by `eventId_roleType` (not a slotKey), with a
  `"<event name> · <role>"` title, rendered in the **same** `ConflictResolutionDialog`, two buttons,
  default **דרוס DB**. The **bulk** "דרוס הכל / קח הכל מה-DB" shortcuts cover it.
- **Non-destructive guarantee:** neither resolution ever deletes a row the co-admin added. Override
  merely re-labels over-quota rows as off-quota (the app's existing `_buildOffQuotaRow` concept).

### Resolution → write mapping

- **דרוס DB (override):** the exact-set (step 4) uses your derived quota; the server's `expected` is
  bumped to live so the set applies. Reindex + your deletions proceed.
- **קח מה-DB (takeDb):** no `eventQuotaSet` is emitted for that role (quota stays at DB). Your
  `markedForDeletion` rows still delete and survivors still reindex; the role may end with an
  unfilled in-quota slot — which is a legitimate "still needs someone here" state.

## Cache

Extend the existing `assignments_staged_changes` blob (env-prefixed) written via
`UserCacheService`:

- The staged list already serializes each `StagedAssignmentChange` — add `markedForDeletion` to its
  `toJson`/`fromJson`.
- Add `_baselineQuota` (a `Map<eventRoleKey,int>`) to the same JSON blob.
- **Written** on every staging change; **cleared only on Save-success** (and Discard-all). A failed
  Save leaves it fully intact. Retry-safe.

## UI controls

- The **"שמור · N"** count includes staged **deletions** and manual-**adds** (each is a
  `_stagedChanges` entry, so `stagedCount` already covers them once deletions live in that map).
- **בטל הכל** (discard-all) and the inline per-row **↩** already dispatch `DiscardStagedSlot` — for a
  striped deletion, ↩ un-deletes (restores the row); for an appended add, ↩ removes the slot.
- No new live conflict marker: type-G, like A–F, surfaces **only** in the Save dialog. The grid shows
  only dirty (yellow) and staged-delete (red-stripe) states.

## Edge cases / entanglement

- **Manual-add then swipe-delete the same new row** → nets to nothing (the add is discarded, the
  appended slot disappears), quota unchanged.
- **Swipe-delete then Save then a co-admin had raised the quota** → type-G at Save; override leaves
  their extra people as off-quota rows.
- **Event-form (immediate) quota reduction racing a staged add/deletion** → the immediate write can
  make a staged slot vanish → existing type-D (or convergent-deletion) handling applies.
- **Deleting more rows than the quota** cannot happen: deletions come from real slots, so
  `deletions <= baselineQuota + adds`, and the derived quota floors at 0.
- **Dirty rows hidden by filter / past-window** are still counted in `N` and still saved (unchanged).
- **allowMultipleAssignments members / same-role swaps** — the backend's batch-aware duplicate check
  is unaffected; deletions and quota sets do not introduce new duplicates.

## Affected files (implementation surface)

- `lib/presentation/bloc/assignment/models/staged_assignment_change.dart` — `markedForDeletion` field
  + json + props + revert-suppression.
- `lib/presentation/bloc/assignment/assignment_bloc.dart` — `_baselineQuota` map; `StageSlotDeletion`;
  derived-quota helper; slot-build renders striped deletions + appended adds; `classifyStagedConflicts`
  emits type-G; `_onSaveStagedChanges` computes final quota + reindex + `eventQuotaSets`; persist/rehydrate.
- `lib/presentation/bloc/assignment/assignment_event.dart` — `StageSlotDeletion`.
- `lib/presentation/bloc/assignment/models/assignment_conflict.dart` — `AssignmentConflictType.quotaChanged` (G).
- `lib/presentation/screens/assignment/assignment_list_screen.dart` — `_handleSlotDismiss` /
  off-quota swipe / `_createAssignmentAndQuota` route through staging (drop immediate writes + confirm);
  red-stripe "יימחק בשמירה" on staged deletions; count/undo already wired.
- `lib/presentation/screens/assignment/widgets/conflict_resolution_dialog.dart` — render type-G rows
  (per-role title + override/takeDb).
- `functions/src/index.ts` — `assignment.saveBatch` accepts `eventQuotaSets` (exact set/lower +
  `expected` concurrency guard); `planEventQuotaSets` validator. **Requires functions deploy.**
- `functions/src/assignment_save_batch.test.ts` — `planEventQuotaSets` unit tests.
- `lib/data/data_sources/database_interface.dart` + `firestore_database.dart` +
  `lib/data/data_sources/logging_database.dart` + `lib/data/repositories/assignment_repository.dart` —
  thread `EventQuotaSet` through `saveAssignmentsBatch`.
- `lib/core/services/user_cache_service.dart` — no signature change (same blob), just the extended shape.

## Testing considerations

- **Backend unit (`node --test`):** `planEventQuotaSets` validation (shape, integer, range,
  missing fields); `expected`-vs-live concurrency (reject when live ∉ {expected, target}); set that
  **lowers** a quota; no-op skip; batch stays atomic with quota + deletes + reindex together.
- **BLoC unit (mockito + StreamControllers, `fake_cloud_firestore`):** derived-quota formula
  (add/delete/mixed); marked-for-deletion rendering + revert-suppression; append slot on manual-add;
  type-G classification (raise-vs-lower divergence; convergent-deletion silent-drop); Save builds
  correct deletes + reindex updates + `eventQuotaSets`; override (off-quota survivors) vs takeDb
  (quota kept, deletion applied); cache round-trip incl. `markedForDeletion` + `_baselineQuota`.
- **Widget:** swipe-delete stripes the row (no confirm) + inline ↩ restores; manual-add grows the
  grid with a dirty row; "שמור · N" counts deletions/adds; type-G row renders in the dialog with
  bulk + per-row controls.
- **Manual smoke (test env, `/test`):** mock batch meeting — delete several rows + add several via
  the wizard across roles; confirm nothing writes until Save; force type-G by raising a role's quota
  in the Firebase console mid-session and confirm the Save dialog surfaces it; verify survivor
  reindex (contiguous slotIndices) and off-quota survivors after override; kill the tab mid-session
  and confirm cache recovery. **After deploying functions**, verify a staged quota **lower** actually
  persists (pre-deploy it silently no-ops).

## Open questions

None — all resolved in the 2026-07-18 brainstorming session (scope = swipe-delete + manual-add only,
event-form deferred; type-G = Option 1, per-role non-destructive resolution). Deferred items are the
explicit non-goals (event-form quota staging; calendar re-enable; `runTransaction` hardening).
