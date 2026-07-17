# Assignments Screen — Staged "Save" Batch — Design

**Date**: 2026-07-15
**Branch**: `feat/assignments-staged-save`
**Status**: Approved by Omer (brainstorming session 2026-07-15)

## Overview

Today, every edit on `/admin/assignments` (assign a member, swap, clear, edit notes)
writes to Firestore **immediately** and **blocks** the UI with a "מעדכן שיבוץ…"
overlay while it does. The real-world workflow is a **1–2 hour batch meeting** with the
events general manager where **most of the season's assignments are filled in one
sitting** — so that per-edit blocking write is paid hundreds of times in an hour.

This feature converts the screen to a **stage-then-save** model: assign/swap/clear/notes
edits become **instant, in-memory changes layered on top of the live DB view**, and are
written to Firestore only when the admin presses **Save** — as a **single atomic batch**.
Staged changes are mirrored to the browser cache so an accidental close/refresh does not
lose them.

Two motivations:

1. **Speed.** The batch meeting stops paying a blocking round-trip per assignment. The
   whole session is instant until one Save.
2. **Google Calendar.** The previous calendar sync hit provider quota because **every
   single assignment triggered a queue call** (see `Google_Calendar_Problem_History/`).
   Sync is currently OFF with all invitees removed. When it returns (future work, not
   this spec), "sync on Save" instead of "sync per assignment" collapses the storm to
   one burst per meeting.

This spec covers **only** the staging/save/cache/conflict/leave-guard machinery.
Re-enabling calendar sync is explicitly out of scope and called out where it will hook in.

## Goals / Non-goals

**Goals**

- Stage assign / swap / clear / notes edits; apply to the DB only on **Save**.
- Screen stays **live with the DB** and renders staged changes **on top** (requirement #3).
- **Instant** per-edit UX — no blocking overlay per change; the overlay appears only on Save.
- **Atomic** Save (all-or-nothing); cache cleared **only** on full success so a failed Save
  can simply be retried.
- **Crash recovery** — staged changes survive an accidental app close/refresh (per-browser).
- **Conflict handling** when the live DB diverges from what the admin edited over.
- **Leave-guard** reminder when navigating away dirty (in-app exits).
- **Discard** — per-slot (inline) and all-at-once.

**Non-goals (explicitly out of scope)**

- Staging **quota / event** mutations. Swipe-delete-a-slot (delete + quota↓), the
  manual-add wizard (create + quota↑), and the event-form modal keep their **current
  immediate-write** behavior. See "Scope" for the deliberate mixed model.
- Re-enabling Google Calendar sync (future; hook point noted).
- Multi-device sync of staged changes (cache is per-browser, per-environment).
- Making Save a server read-transaction (`runTransaction`). A server-side atomic `db.batch()`
  is used; the tiny window between conflict-resolution and commit is acceptable for a
  single-editor meeting. Noted as future hardening only.

## Scope — staged vs. immediate

| Action | DB effect | Behavior under this feature |
|---|---|---|
| Assign member to empty slot | create assignment | **Staged** |
| Swap member in filled slot | update assignment | **Staged** |
| Clear a filled slot | delete assignment | **Staged** |
| Edit notes / label / alt-phone | update assignment | **Staged** |
| Swipe-delete a slot | delete assignment **+ quota↓ + re-index** | **Immediate** (unchanged) |
| Manual-add wizard | create assignment **+ quota↑** | **Immediate** (unchanged) |
| Event-form modal (times/location/quota) | update event | **Immediate** (unchanged; its own Save) |

**Deliberate mixed model.** Assign/swap/clear/notes touch **only** assignment documents,
which is why they batch cleanly and why calendar sync will hinge on them. Quota-changing
actions mutate the **Event** document and are lower-frequency and structural, so they keep
today's immediate write (and today's brief spinner). The admin will experience "most edits
are instant + staged, but deleting a slot or using the + wizard writes right away." This is
intended.

**Derived rule (entanglement):** swipe-deleting a slot that currently has a **staged** edit
**drops that staged entry** along with the slot (the slot is gone; there is nothing left to
save). Likewise, an immediate quota reduction via the event modal can turn a staged fill
into a **type-D conflict** (slot vanished) — handled at Save (see Conflicts).

## Architecture

### Approach: revive & repurpose the dormant overlay

`AssignmentBloc` **already contains** a complete "pending operations overlay": a
`Map<String, PendingOperation> _pendingOperations` keyed by `slotKey`, plus a merge routine
(around `assignment_bloc.dart:974`) that renders **live DB slots with pending changes
layered on top** — exactly requirement #3. It is fully built but **dormant**: nothing
dispatches the `OptimisticCreate/Update/DeleteAssignment` events, and the active edit path
uses the blocking immediate-write instead.

We **keep the merge/render logic** and **replace the lifecycle**:

| | Dormant optimistic system (today) | Staging (this feature) |
|---|---|---|
| Created by | (never dispatched) | every assign/swap/clear/notes edit |
| Expires | after 5 min (`isExpired`) | **never** |
| Cleared when | DB stream confirms the op | **only** on Save-success, Discard, or revert-to-baseline |
| Persisted | no | **yes** — mirrored to cache |
| Baseline snapshot | no | **yes** — required for conflict detection |

Rejected alternatives: (B) build a fresh staging layer — re-derives the merge that already
exists; (C) working-copy snapshot — violates requirement #3 (screen must stay live).

### Staging model: per-slot desired-state (not an op-log)

Staged edits are stored **keyed by slot**, one entry per slot
(`slotKey = eventId_roleType_slotIndex`). Editing the same slot repeatedly updates its one
entry. This yields three properties for free:

1. **Revert = clean.** If a slot's staged value returns to its DB baseline (assign Dan,
   then put Ron back), the entry is **dropped** and the slot is no longer dirty. (Mirrors
   the existing `constraints_screen` compare-to-original pattern.)
2. **Deterministic Save.** Save diffs *desired vs baseline* per slot → exactly one
   create / update / delete each.
3. **Conflict detection** works by comparing the stored **baseline** against the *current* DB.

### Data shape

```
StagedAssignmentChange {
  slotKey            // identity: eventId_roleType_slotIndex
  eventId, roleType, slotIndex
  // desired state:
  desiredMemberId?         // null => staged-clear; set => staged fill/swap
  desiredNotes, desiredLabelId, desiredAltPhone
  // baseline snapshot (DB state at first touch of this slot):
  baselineAssignmentId?    // DB assignment doc id at first touch (null if slot was empty)
  baselineMemberId?        // DB member at first touch — drives conflict classification
  baselineNotes, baselineLabelId, baselineAltPhone
  stagedAt
}
```

- Held in `Map<slotKey, StagedAssignmentChange>` on the BLoC. **Dirty ⇔ map non-empty.**
- Exposed as `hasStagedChanges` / `stagedCount` on the state so the screen (Save FAB) and
  the nav wrapper (leave-guard) can read dirtiness.

### BLoC surface (new)

Events:
- `StageAssignmentEdit(slotKey, desired…, baseline…)` — upsert one slot; auto-drops if
  desired == baseline.
- `DiscardStagedSlot(slotKey)` — drop one slot's entry (inline ↩; also the per-row
  "קח מה-DB" resolution).
- `DiscardAllStaged` — clear the map.
- `RehydrateStagedFromCache(list)` — on screen init.
- `SaveStagedChanges(resolutions?)` — run the atomic batch (see Save flow).

State (`AssignmentSlotsLoaded` additions): the staged map (or a derived
`stagedCount` + a per-slot `pending`/`conflict` annotation used by the overlay merge so the
screen can render indicators without re-deriving).

## Per-edit interaction changes

- `_handleAssignmentChange` / `_handleAssignmentChangeWithBypass` / `_handleClearAssignment`
  and the notes dialog **stop dispatching** `CreateAssignment` / `UpdateAssignment` /
  `DeleteAssignment` / `UpdateAssignmentNotes` and instead dispatch `StageAssignmentEdit`.
- **No `_runBlockingMutation`** for these — the edit is in-memory + cache, instant. The
  "מעדכן שיבוץ…" overlay is gone from the per-edit path; it reappears only during Save.
- Notes on a **not-yet-saved** fill just update that slot's staged `desiredNotes` (there is
  no DB doc to write yet — this is why notes had to be in scope, not immediate).
- Immediate actions (swipe-delete slot, manual-add, event modal) are **untouched**, except
  swipe-delete also fires `DiscardStagedSlot` for the removed slot.

## Cache

- **Key:** `${EnvironmentService.cachePrefix}assignments_staged_changes`
  (`assignments_staged_changes` in prod, `test_assignments_staged_changes` in test).
- **Format:** `jsonEncode` of the staged list — copying the exact
  `ConfigCacheService.saveDriveConfig` pattern (`jsonEncode` → `setString`; read via
  `jsonDecode`). Add `savePendingAssignmentChanges` / `getPendingAssignmentChanges` /
  `clearPendingAssignmentChanges` to `UserCacheService`.
- **Write:** on every staging change (debounce-free; the list is small).
- **Read:** on screen init → `RehydrateStagedFromCache` → overlay renders immediately.
- **Clear:** **only** on Save-**success** (and on Discard-all). A failed Save leaves it intact.
- **Properties:** per-browser (`localStorage`), per-environment (prefix isolates test/prod),
  string-only, async reads. ~5 MB origin quota — a meeting's worth of changes is trivial.

## Conflict handling

### Definition

A staged slot **conflicts** whenever its stored **baseline ≠ the current DB** for that slot
— i.e. something (a co-admin, an immediate quota change, a member edit) changed the slot
since the admin first touched it. If `baseline == currentDB`, the staged change applies
cleanly, no conflict. **Conflicts are detected and surfaced ONLY at Save** (in the resolution
dialog) — there is **no** live conflict marker on the grid.

### Dirty marker (the yellow border)

The **bright, thick yellow border** marks a **dirty row** — any row that has a staged change —
**not** a conflict. It is the "you edited this, it isn't saved yet" indicator: it appears the
moment a slot is staged and clears when the slot is saved, discarded, or reverted to baseline.
The grid does **not** compare baseline vs live DB for rendering. The stored baseline snapshot
exists **solely** to classify conflicts **at Save time**.

### Taxonomy

For each conflicting slot, classify by (staged action) × (how the DB diverged):

| # | Type (Hebrew) | Situation | **דרוס DB** (yours wins) | **קח מה-DB** (drop yours) |
|---|---|---|---|---|
| **A** | המשרה נתפסה | filled/swapped to *M*; DB now shows a different member *X* | write *M* over *X* | keep *X* |
| **B** | השיבוץ נמחק | swap/notes points at an assignment DB no longer has (now empty) | re-create as *M* | accept the deletion |
| **C** | התנגשות בניקוי | cleared *B*; DB now holds a different member *X* | delete *X* (apply clear) | keep *X* |
| **D** | המשרה בוטלה | quota shrank; your slotIndex no longer exists | **צור מחוץ למכסה** (create an off-quota row) | drop your change |
| **E** | החבר לא זמין | member you assigned was deactivated/deleted | assign anyway *(deactivated only)* | drop your change |
| **F** | הערות/שיבוץ שונו | your notes edit collides with a DB notes change, or the member changed under your notes edit | apply your notes | keep DB |

**D (slot vanished)** keeps **two** buttons: **צור מחוץ למכסה** — create the assignment as an
**off-quota row** (the app already supports these via `_buildOffQuotaRow`; the Save batch just
creates the assignment doc and it renders off-quota) — vs discard.

**Single-button special case** (no valid write target — one button *"הבנתי — בטל את
השינוי"*, which discards): **E** where the member **record was fully deleted**. A merely-
*deactivated* member keeps both buttons, since the app can still render/assign a deactivated
member.

**Silent non-conflict:** a staged **clear** whose slot is *already* empty in the DB is
satisfied — dropped silently, no dialog entry.

### Resolution dialog (on Save)

If any conflicts exist when Save is pressed, show **one consolidated dialog** (RTL):

- A scrollable list, **one entry per conflict**, each with its Hebrew description and its
  two buttons (or single button for D / E-deleted).
- **Bulk shortcuts** at the top: **דרוס הכל** / **קח הכל מה-DB**.
- **Default** per two-button row = **דרוס DB** (the admin's edits are intentional).
- Choosing **קח מה-DB** on a row is identical to discarding that slot.
- A confirm button applies the resolutions and proceeds to the batch write.

## Save flow

1. Admin presses **שמור**.
2. Recompute conflicts (baseline vs current DB) across all staged slots.
3. **If conflicts →** show the resolution dialog; admin resolves each. **If none →** skip.
4. Build **one atomic `WriteBatch`** from the resolved decisions:
   - staged fill on empty slot → **create** assignment
   - staged swap / notes on existing slot → **update** assignment
   - staged clear → **delete** assignment
   - "קח מה-DB" / discarded / D / E-deleted → **omitted** from the batch
   - all writes target **only** the assignments collection (no event/quota writes — scope).
5. Commit, with a **progress overlay showing a progress bar** (the existing overlay style,
   upgraded from a bare spinner). Because the write is a single atomic `WriteBatch`, Firestore
   emits no per-record commit callbacks, so progress is **phased**, not per-DB-write:
   - **בודק שינויים** — the client-side validate + conflict-scan iterates the N staged slots →
     a **real, determinate** percentage here (this is the part that scales with size).
   - **שומר…** — the atomic commit itself is one opaque await → **indeterminate** (bar
     animates); it is fast.
   - **Success →** clear the staging map **and** the cache; success snackbar
     (*"נשמרו N שינויים"*); the live stream already reflects the writes.
   - **Failure →** keep staging **and** cache **fully intact**; error snackbar; Save stays
     enabled → press again. (Directly satisfies "be able to save again.")
   - *(A true per-record percentage would require chunking into sequential sub-batches, which
     breaks the all-or-nothing guarantee — explicitly not done.)*
6. **The write path is backend-mediated** — all assignment writes go through
   `BackendApiService.mutate(operation, payload)` → the `api` Cloud Function's `switch(operation)`
   in `functions/src/index.ts` (client Firestore is never written directly). Existing handlers
   (`assignment.insert/update/delete/insertBatch/deleteBatch`) do no mixed atomic write, so
   atomicity is achieved **server-side**:
   - **Backend (new):** `case 'assignment.saveBatch'` — `requireAdmin`, validate every create/update
     via `validateAssignmentPayload`, then commit ONE server-side `db.batch()` (creates + updates +
     deletes), mirroring the existing `assignment.deleteByEvent` batch pattern; write audit logs;
     return `{ok, counts}`. Atomic all-or-nothing (Firestore batch ≤500 ops — a meeting is far under).
   - **Client (new):** `AssignmentRepository.saveAssignmentsBatch(creates, updates, deletes)` →
     `FirestoreDatabase.saveAssignmentsBatch` → `_invokeMutation('assignment.saveBatch', payload)`.
   - **Deploy:** functions do **not** auto-deploy — after the backend change run
     `cd functions && firebase deploy --only functions`. (The Flutter web app auto-deploys on merge
     to main; the Cloud Function does not — see [[web-auto-deploys-on-merge]] / [[feedback-flag-redeploy-needs]].)

**Availability enforcement (deliberate, approved):** `assignment.saveBatch` validates foreign keys,
role-capability, and same-role uniqueness (batch-aware), but passes `bypassAvailability: true` — matching
the existing "שבץ בכל זאת" (assign-anyway) path. Staged fills/swaps therefore skip the server-side
date-availability check that `assignment.insert`/`update` apply as defense-in-depth. This is an accepted
call for the single-editor batch-meeting workflow (the admin is deliberately assigning; the client already
warns at assign time). Consequence: if a member's availability changes *between* staging and Save, the
assignment is written without a warning; availability-drift is not surfaced as a conflict type
(`memberGone` (E) covers deactivation/deletion only, and is itself deferred).

**Atomicity caveat:** a server-side `db.batch()` is atomic on commit but is not a read-transaction,
so there is a small window between the client resolving conflicts and the server committing where the
DB could change again. Acceptable for a single-editor meeting; a server `runTransaction` is noted as
future hardening only.

**Calendar hook (future, not built here):** the Save-success step is the single place where
a future calendar sync would enqueue one batch — the whole reason the mixed-immediate scope
keeps calendar-relevant writes (assignments) inside Save.

## Discard

- **Per-slot (inline):** every dirty (yellow-bordered) row carries a small **↩ undo** icon →
  `DiscardStagedSlot(slotKey)` drops that entry and the row snaps back to DB. (Same operation
  as the row's "קח מה-DB" at Save.)
- **All-at-once:** a **בטל הכל** control with the Save cluster → confirm
  (*"לבטל את כל N השינויים שלא נשמרו?"*) → `DiscardAllStaged` + clear cache.

## Leave-guard

The prompt is a **courtesy reminder**, not data-protection — the cache already recovers
staged changes on reload. Guard **in-app exits only**:

- **Hook points:**
  - `swipeable_page_view.dart:_onBottomNavTapped` (line ~134) — make it async; when leaving
    the **assignments** branch (`navigationShell.currentIndex == 3`) **and** dirty, `await`
    the dialog **before** `goBranch`.
  - assignments screen **home** button (`assignment_list_screen.dart` ~464,
    `context.go('$prefix/admin')`) — guard.
  - assignments screen **logout** (~3527) — guard.
- **Wiring:** the nav wrapper reads dirtiness via `AssignmentBloc`'s `hasStagedChanges`
  (the BLoC is app-scoped, above the shell). Note `SwipeablePageView` is shared by all admin
  tabs — the guard must be gated on `currentIndex == 3`.
- **Dialog** (RTL): title **שינויי שיבוצים לא נשמרו**, body *"יש לך N שינויים שלא נשמרו."*
  - **שמור והמשך** → run the full Save flow (may raise the conflict dialog first); navigate
    **only** on save-success, stay on failure.
  - **צא בלי לשמור** — with a second line of clarifying subtext:
    *"השינויים לא נמחקים, ניתן לשמור אחר כך"* → navigate; staging stays in cache (still dirty
    on return).
  - **ביטול** → stay.
- **Not hooked:** browser back / forward / refresh / tab-close. No `PopScope`/`beforeunload`
  — cache recovers on reload. (There is no `PopScope` anywhere in the app today.)

## UI controls

- **Bottom-right cluster.** The existing round blue **+** (manual-add) stays exactly where it
  is. A **Save button** sits **next to** it (does **not** replace it), matching requirement #1:
  - **Clean:** Save is **visible but disabled** (greyed); no count, no discard shown. The
    screen otherwise looks exactly as today.
  - **Dirty:** Save is **enabled** and shows the count — **"שמור · N"** — and a small
    **בטל הכל** appears beside it.
  - (Whether Save renders as an extended FAB or a bar button is an implementation nicety;
    "visible-but-disabled when clean, enabled+count when dirty" is the requirement.)
- **Per row:** every dirty (staged) row → **bright thick yellow border** + inline **↩ undo**.
  Conflicts are **not** marked on the grid — they surface only in the Save-time resolution
  dialog. `N` counts **all** staged changes, including any on events hidden by the current
  filter or the past-events window, so nothing dirty is invisible.

## Edge cases

- **Dirty rows hidden by filter / search / past-window:** still counted in `N`, still saved.
  The count is the safety net for off-screen dirt.
- **Staged change on an event outside the loaded window:** stored/keyed by IDs, so it saves
  regardless of what is currently rendered; it just may not have a visible row until its
  event is in view.
- **Notes on a not-yet-saved fill:** updates the staged `desiredNotes`; the Save create
  carries them.
- **Immediate action racing a staged edit:** e.g. staged fills for Medic#0/#1, then the
  event modal reduces Medic quota to 1 → Medic#1 becomes a **type-D** conflict at Save.
- **Deactivated assignee rendering:** unchanged; the grid already renders deactivated
  members' assignments.

## Affected files (implementation surface)

- `lib/presentation/bloc/assignment/assignment_bloc.dart` — repurpose overlay lifecycle;
  staging map + baseline; conflict classification; `hasStagedChanges`; save-batch handler.
- `lib/presentation/bloc/assignment/assignment_event.dart` — new staging/discard/save events.
- `lib/presentation/bloc/assignment/assignment_state.dart` — staged map / count / per-slot
  pending+conflict annotation in `AssignmentSlotsLoaded`.
- `lib/presentation/screens/assignment/assignment_list_screen.dart` — route edits through
  staging; Save/Discard cluster next to FAB; per-row ↩ + yellow dirty-border; resolution
  dialog (built at Save from baseline-vs-DB); notes dialog stages; guard home/logout.
- `lib/presentation/screens/assignment/models/assignment_slot.dart` — (likely) an `isDirty`
  flag for the yellow border. No live-conflict flag — conflicts are computed only at Save.
- `lib/presentation/widgets/swipeable_page_view.dart` — async tab-switch leave-guard.
- `lib/core/services/user_cache_service.dart` — pending-changes JSON cache methods.
- `functions/src/index.ts` — new `assignment.saveBatch` backend handler (atomic mixed `db.batch()`
  + audit logs), plus a `functions/src/*.test.ts` test. **Requires `firebase deploy --only functions`.**
- `lib/data/data_sources/database_interface.dart` + `firestore_database.dart` +
  `lib/data/repositories/assignment_repository.dart` — client `saveAssignmentsBatch` that calls
  `_invokeMutation('assignment.saveBatch', {creates, updates, deletes})`.
- Likely new: a resolution-dialog widget and a shared leave-guard dialog helper.

## Testing considerations

- **Unit:** overlay merge (staged desired on top of DB + dirty flag), conflict classification
  A–F computed **at Save** (incl. D two-button off-quota-create, E-deleted single-button,
  silent-clear), revert-to-baseline auto-clean, cache JSON round-trip, batch builder
  (creates/updates/deletes + off-quota creates from resolved decisions).
- **Widget:** dirty indicator (yellow border) + count (incl. filtered rows), inline ↩,
  resolution dialog (bulk + per-row), leave-guard on all three in-app exits, Save
  success/failure (cache cleared vs preserved).
- **Manual smoke (test env):** run a mock batch meeting; force a conflict by editing the DB in
  the Firebase console mid-session; confirm the **Save-time** resolution dialog surfaces it
  (there is **no** live conflict marker — only the yellow dirty-border); kill the tab
  mid-session and confirm cache recovery on reload.

## Open questions

None — all resolved in the 2026-07-15 brainstorming session. The only deferred items are the
explicit non-goals (calendar sync re-enable; `runTransaction` hardening).
