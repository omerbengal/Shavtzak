# Empty-slot gap annotations (note + label) — design

- **Date:** 2026-07-22
- **Branch / worktree:** `feat/empty-slot-gap-annotations` (`.claude/worktrees/empty-slot-gap-annotations`)
- **Status:** Approved for planning

## 1. Motivation

The request (from the product owner, Hebrew):

> לאפשר להוסיף הערה לשורת שיבוץ שאין לה חבר צוות משובץ — וזה יופיע (בנוסף כמובן
> למסך שיבוצים) במסך מנהלים איפה שהחוסר של השיבוץ יהיה — תופיע גם ההערה (בסגול כמובן).

Translation: let an admin attach a note to an assignment **row that has no team member assigned** (an empty slot / gap / חוסר), and have that note appear — in purple — both on the assignments screen (**מסך שיבוצים**, `/admin/assignments`) and on the managers' screen (**מסך מנהלים**, `/summary`) where that role's shortage is shown.

During brainstorming the owner clarified the intent and scope:

- An empty **row is a real slot** in the event — a "job" that exists whether or not it is staffed. Admins want to annotate slots during planning, before anyone is assigned. Example: an event needs 2 × *כניסה/סריקה* (entry screening), one at **entrance B** and one at **entrance C**. That entrance distinction is a property of the **slot/job**, expressible as a **note** *or* a **label**.
- Therefore a slot annotation carries **note + label**. The **label belongs to the slot** (the job), not the person.
- The **extra phone** stays **member-level** (on the assignment), as today — it is genuinely about the specific person.
- Notes/labels are **per individual slot**, not per role (a role may have several gaps, each independently annotatable).

## 2. Key domain facts (why this needs new structure)

- An `Assignment` (`lib/domain/entities/assignment.dart`) requires a non-nullable `teamMemberId` (line 18/36). An **empty slot is not a stored document** — it is derived: the slot-builder loops `for i in [0, requiredCount)` and matches an assignment by `slotIndex`; indices with no assignment are the gaps (`assignment_bloc.dart` `_buildSlotsFromAssignments` ~2931 and `_onRebuildAssignmentSlotsFromData` ~3259). So there is **no data home** for a note on an empty slot today.
- Assignment notes currently live on `Assignment.notes` and render as a **purple** card in `_buildAssignmentExtraInfo` (`assignment_list_screen.dart` ~1060), which returns `null` when `assignment == null` — so empty rows show nothing.
- The label is `Assignment.semanticLabelId` → an `AssignmentLabel` (`{id, hebrewName, sortOrder, …}`), rendered via `AssignmentLabelChip`. Labels are managed independently and streamed via `AssignmentLabelRepository.watchAssignmentLabels()`.
- **מסך מנהלים** = `SummaryScreen` (its AppBar title is literally `מסך מנהלים`, `summary_screen.dart:106`). Its `event_summary_tile.dart` `_buildMissingRolesSection` (~354) already renders one red gap chip per missing person, but using an **anonymous ordinal** (`_MissingSlot.slotIndex = i + 1`, ~387) rather than the real slot index.
- The staged-Save partition is intentionally strict and has a history of P0 bugs; **we keep clear of its internals**. `_assignmentFromStaged` (`assignment_bloc.dart` ~2586) already threads `desiredNotes` and `desiredSemanticLabelId` from the staged change onto the saved doc, which is what makes carry-over cheap.

## 3. Chosen approach: shared derivation (not first-class slots)

We considered making empty slots first-class database objects (member-optional assignments, or a slot table). Rejected for this feature: large blast radius (nullable member ripples through FK validation, staged-Save, calendar sync, conflict detection, user screens) plus a data migration on a mature production app. The reuse benefit the owner wanted (the summary showing real missing-slot rows) does **not** require persisting slots — the summary already derives gaps; it only needs a shared *derivation* and a place to read the annotation.

**Design in one line:** a gap annotation is a small record hung on the **event**, addressed by `role + slotIndex`; both screens derive their slots the same way and read the annotation from the same place, so it displays identically and live.

## 4. Data model

### 4.1 `SlotAnnotation` value object (new)

`lib/domain/entities/slot_annotation.dart`:

```dart
class SlotAnnotation extends Equatable {
  final String note;      // '' when none
  final String? labelId;  // AssignmentLabel.id, null when none

  const SlotAnnotation({this.note = '', this.labelId});

  bool get isEmpty => note.trim().isEmpty && labelId == null;

  SlotAnnotation copyWith({String? note, String? Function()? labelId});

  @override
  List<Object?> get props => [note, labelId];
}
```

### 4.2 `Event.slotAnnotations` (new field)

`lib/domain/entities/event.dart`: add

```dart
// key = slotAnnotationKey(roleKey, slotIndex) = "<roleKey>#<slotIndex>"
final Map<String, SlotAnnotation> slotAnnotations; // default const {}
```

- Added to the constructor (defaulted), `copyWith`, and **`props`** (required for real-time — both screens rebuild from the Event stream).
- **Key format:** `"<roleKey>#<slotIndex>"`. Role keys are enum keys (camelCase) or Firestore-safe role doc ids; neither contains `#`. (Implementation note: assert/sanitize `#`-free role keys; the whole map is written wholesale or via `FieldPath` segments, so the `#` is never parsed as a path separator.)

### 4.3 Serialization — `lib/data/models/event_model.dart`

Mirror the existing `roleRequirements` map handling across all six paths (`fromEntity`, `toEntity`, `fromFirestore`, `toFirestore`, `fromJson`, `toJson`). Each `SlotAnnotation` serializes as a nested map `{ "note": <string>, "labelId": <string|null> }`. Missing/absent → `{}` (backward-compatible; every existing event reads as "no annotations").

Firestore shape:

```json
"slotAnnotations": {
  "entryScreening#0": { "note": "", "labelId": "<label:כניסה B>" },
  "entryScreening#1": { "note": "צד מזרח", "labelId": "<label:כניסה C>" }
}
```

### 4.4 Targeted write — via a new backend mutation (⚠️ requires a Cloud Functions deploy)

**Clients cannot write events directly.** Firestore rules for `events`/`test_events` are `allow write: if false` (`firestore.rules:56-63`); every event write goes through a backend Cloud Function mutation (`FirestoreDatabase._invokeMutation(op, payload)` → `BackendApiService.mutate`). The existing `event.update` mutation is unsuitable for an annotation edit: it runs a same-day **duplicate-name check**, writes an **audit log**, and **enqueues a calendar-sync job** (`functions/src/index.ts:3913-3990` — `markEventCalendarJob` + `enqueueEventCalendarJob`). We must not trigger calendar work for a note edit.

So add a **dedicated, side-effect-free** backend mutation `event.updateSlotAnnotation`:

- **Backend** (`functions/src/index.ts`, new `case 'event.updateSlotAnnotation'` in `executeMutation`'s `switch (operation)`): admin-gated (`actor.isAdmin`, else `HttpError(403)`); verify the event exists; then a **nested merge-set** that touches only the one key (so concurrent edits to *different* slots don't clobber each other) and **no** calendar/duplicate logic:

  ```ts
  const merge = buildSlotAnnotationMerge(key, value); // pure, unit-tested
  await eventRef.set(merge, {merge: true});
  // buildSlotAnnotationMerge:
  //   clear  → { slotAnnotations: { [key]: FieldValue.delete() } }
  //   upsert → { slotAnnotations: { [key]: { note, labelId } } }
  //   (+ optional { [staleKey]: FieldValue.delete() } for self-heal, §10)
  ```

  Merge-set with a nested map updates only the listed sub-keys; siblings are preserved. Keys use `#` (safe as a JS/Firestore map key). A minimal audit-log entry is written for parity with other mutations.

- **`slotAnnotations` is NOT added to `eventDocFromJson`** (the full-event whitelist used by `event.update`/`event.insert`, `index.ts:2744`). Because Firestore `update()`/merge only touches listed fields, leaving it out means a normal full event edit **preserves** existing annotations, and an old client (pre-deploy) can't wipe them. Annotations are only ever written by the targeted mutation.

- **Client** — `DatabaseInterface.updateEventSlotAnnotation(String eventId, String key, SlotAnnotation? value, {String? staleKey})` implemented in `FirestoreDatabase` as `_invokeMutation('event.updateSlotAnnotation', {eventId, key, note, labelId, staleKey})`. `EventRepository` exposes a thin passthrough `updateSlotAnnotation(...)`. **This bypasses `EventRepository.updateEvent`** (duplicate check + Drive rename, `event_repository.dart:132`) entirely.

- **Reads** need no backend change: `EventModel.fromFirestore` reads `slotAnnotations` straight from the doc the mutation wrote.

> **Deploy:** the backend change means `firebase deploy --only functions` is required before the feature works in an environment. Called out again in the plan.

## 5. Shared derivation helper

`lib/core/utils/slot_annotations.dart` (pure, no Flutter deps):

```dart
String slotAnnotationKey(String roleKey, int slotIndex) => '$roleKey#$slotIndex';

/// Indices in [0, required) with no assignment, in ascending order.
List<int> emptySlotIndicesForRole(
  int requiredCount, Iterable<int> filledSlotIndices);

/// Reconcile stored annotations onto the role's ACTUAL gaps (see §8).
/// Returns gapIndex -> SlotAnnotation for the gaps that should show one.
Map<int, SlotAnnotation> reconcileGapAnnotations(
  Map<String, SlotAnnotation> eventSlotAnnotations,
  String roleKey,
  int requiredCount,
  Iterable<int> filledSlotIndices);
```

Both screens call these, so **מסך מנהלים stops using anonymous `i+1` ordinals** and instead enumerates the same real slot indices the assignments screen uses. That alignment is what lets a single annotation surface correctly in both places.

## 6. Behaviour — מסך שיבוצים (author + display)

**Carry the annotation onto the slot object.** `AssignmentSlot` (`models/assignment_slot.dart`) gets a new field `SlotAnnotation? gapAnnotation` (in `props`), populated only for empty slots during slot-building using `reconcileGapAnnotations` at the two build sites in `assignment_bloc.dart` (~3095, ~3454).

**Authoring.** Today empty rows only allow swipe-left (delete); the swipe-right "edit note" and `_showNotesDialog` are gated to `slot.isFilled` (`assignment_list_screen.dart` ~1442-1444, ~1464-1476, guard ~1677). Change:

- Allow the swipe-right "edit" gesture on empty rows.
- It opens a **simplified annotation dialog**: a multiline **note** field + the **label** picker (reuse the existing label-select UI from `_showNotesDialog`), **without** the phone field.
- Saving dispatches `UpsertSlotAnnotation(eventId, roleKey, slotIndex, note, labelId)` (§7). Clearing both fields deletes the annotation.
- This is an **immediate write** to the event, deliberately **outside** the staged-assignment Save/Discard flow (annotations are event metadata, not staged assignment edits). Feedback via snackbar + live stream refresh.

**Display.** For an empty slot with a non-empty `gapAnnotation`, render the **same purple note card** and **`AssignmentLabelChip`** used for filled rows (extend `_buildAssignmentExtraInfo`, or a sibling that takes a `SlotAnnotation` + resolved `AssignmentLabel`). The label object is resolved from the labels already streamed into `_buildSlotGrid` (`watchAssignmentLabels`). Visually identical to existing note/label rendering.

## 7. Behaviour — EventBloc

`event_event.dart`: `UpsertSlotAnnotation extends EventEvent { eventId, roleKey, slotIndex, note, labelId }`.

`event_bloc.dart`: handler builds the `SlotAnnotation` (or `null` if empty) and calls `EventRepository.updateSlotAnnotation`. No optimistic state needed — the event stream re-emits the updated event and both screens rebuild (Equatable `props` now includes `slotAnnotations`). Errors surface as the existing `EventError` snackbar.

## 8. Behaviour — מסך מנהלים (display only)

In `event_summary_tile.dart` `_buildMissingRolesSection` (~354):

- Replace the `_MissingSlot(slotIndex: i+1)` ordinal expansion with **real empty indices** via `emptySlotIndicesForRole` / `reconcileGapAnnotations`, computed from `allAssignments` filtered to this event+role.
- For each gap chip that has a reconciled annotation, render the **note in purple** + the **label chip** beside/under the red chip. **Display-only** here — editing stays on מסך שיבוצים.
- Align the assign-from-gap flow (`_showAssignmentConfirmation`, `slotIndex = existingAssignments.length` ~856, → `CreateAssignment`) to assign into the **specific gap's real slotIndex**, and seed carry-over there too (§9), for consistency with the assignments screen.

## 9. Carry-over / carry-back

**Carry-over (assign → person).** When a member is staged into an annotated empty slot, seed the staged change's `desiredNotes` and `desiredSemanticLabelId` from `slot.gapAnnotation` instead of the current hardcoded `desiredNotes: ''` / `desiredSemanticLabelId: null` (`assignment_bloc.dart` fill site ~1673-1677; also the summary's `CreateAssignment` path). `_assignmentFromStaged` already carries both onto the saved assignment, so the now-filled row shows e.g. *כניסה B* exactly like any labelled assignment. **No change to the staged-Save partition.**

**Carry-back (unassign → slot).** The annotation is **not** deleted on fill; it stays on the event, hidden while the slot is filled (display shows `gapAnnotation` only for empty slots). Removing the member re-exposes it automatically — carry-back for free, no write.

**Accepted edge:** if the admin edits the *assignment's* label after assigning and then unassigns, the slot shows the original annotation, not the later edit (the dormant annotation is not kept in sync with the assignment). Documented; acceptable for v1.

**Dormant/orphaned annotations** (slot filled, or `slotIndex >= required` after a quota cut) are retained (harmless, tiny). No proactive cleanup in v1.

## 10. Stability — annotations never silently vanish

Annotations are keyed by absolute `(roleKey, slotIndex)`. In steady state, gaps sit at stable trailing indices (assignments append at `count`; Save compacts survivors to `[0, filledCount)`, `assignment_bloc.dart` ~2154-2168), so a note stays on its gap. The only drift risk is a specific sequence — delete a *middle* assignment, annotate the resulting hole, then Save — where compaction could move a survivor onto the annotated index.

**Guarantee via render-time reconciliation** (`reconcileGapAnnotations`, pure, both screens): map a role's stored annotations onto its *actual* current gaps in slot-index order, so an annotation always surfaces on a real gap and never disappears while a gap remains. Display and carry-over both read the reconciled `gapAnnotation` carried on the slot (not the raw stored key), so they stay consistent even after drift. To avoid duplicate keys, writes are unambiguous: an **edit** targets the row's real `slotIndex`, and whenever reconciliation surfaces a stored annotation on a gap whose index differs from its stored key, the bloc **opportunistically self-heals** — one targeted write that deletes the drifted key and re-stores it under the reconciled gap index — so storage converges to display. **This lives entirely in pure/display code — the Save/staging internals are untouched.**

## 11. Real-time

Annotations live on the Event; both screens already rebuild from the Event stream, and `slotAnnotations` is in `Event.props`. Writing a note on מסך שיבוצים therefore appears on מסך מנהלים (and vice-versa) with no extra wiring.

## 12. Implementation surface (files)

1. `lib/domain/entities/slot_annotation.dart` — **new** value object.
2. `lib/domain/entities/event.dart` — `slotAnnotations` field + `copyWith` + `props`.
3. `lib/data/models/event_model.dart` — serialize `slotAnnotations` (6 paths).
4. `functions/src/index.ts` — **new** `case 'event.updateSlotAnnotation'` + pure `buildSlotAnnotationMerge` helper (⚠️ deploy).
5. `lib/data/data_sources/database_interface.dart` + `firestore_database.dart` — `updateEventSlotAnnotation` → `_invokeMutation('event.updateSlotAnnotation', …)`.
6. `lib/data/repositories/event_repository.dart` — `updateSlotAnnotation` passthrough.
7. `lib/presentation/bloc/event/event_event.dart` + `event_bloc.dart` — `UpsertSlotAnnotation` + handler.
8. `lib/core/utils/slot_annotations.dart` — **new** key helper, empty-index enumeration, reconciliation.
9. `lib/presentation/screens/assignment/models/assignment_slot.dart` — `gapAnnotation` field.
10. `lib/presentation/bloc/assignment/assignment_bloc.dart` — populate `gapAnnotation` in the 2 build sites; seed carry-over at the fill site (~1673).
11. `lib/presentation/screens/assignment/assignment_list_screen.dart` — enable empty-row edit swipe; simplified annotation dialog; render gap note + label.
12. `lib/presentation/screens/summary/widgets/event_summary_tile.dart` — real gap indices; render annotation; align assign-from-gap slotIndex + carry-over seed.
13. Tests (§13); **deploy** `firebase deploy --only functions`.

## 13. Testing

`flutter analyze` must stay clean (repo baseline: only pre-existing infos; zero **new**). Add:

- **Unit (Dart):** `SlotAnnotation` equality/`copyWith`/`isEmpty`; `EventModel` round-trip incl. `slotAnnotations` (and legacy docs without it); `slotAnnotationKey`; `emptySlotIndicesForRole`; `reconcileGapAnnotations` including the delete-middle drift case.
- **Backend (functions, `node --test`):** `buildSlotAnnotationMerge` pure helper — upsert, clear (`FieldValue.delete()`), and self-heal (optional stale-key delete) shapes.
- **Bloc:** `UpsertSlotAnnotation` → repo call (upsert + delete-on-empty); carry-over seeds `desiredNotes`/`desiredSemanticLabelId` when filling an annotated slot. (Carry-over then persists through the existing `assignment.saveBatch` → `assignmentDocFromJson`, which already writes `notes` + `semanticLabelId` — no backend change.)
- **Widget (light):** empty row renders purple note + label chip from `gapAnnotation`; summary tile renders the annotation on the matching gap.

## 14. Non-goals

- No first-class-slot refactor and **no data migration**.
- No change to how **filled-row** notes/labels behave (they stay on the assignment).
- The **extra phone** stays member-level (assignment only); it is not part of a gap annotation.
- Editing annotations on מסך מנהלים (display-only there for v1).
