# Participant Counts per נגלה — Design

**Date**: 2026-07-14
**Branch**: `feat/participant-counts-per-nagla`
**Status**: Approved by Omer (brainstorming session 2026-07-14)

## Overview

Request from Omer's boss, verbatim:

> כמות משתתפים - להוסיף כפתור "+" מתחת כדי להוסיף עוד שדה ועוד שדה - שיהיה ככמות הנגלות.
> ואז, במקום הכמות משתתפים במוצגת - שיוצג סטרינג: "נגלה 1: 500, נגלה 2: 700, …".

An event's audience is not always one crowd. A show can run in several **נגלות**
(waves/showings), each with its own audience size. Today the event form has a single
`כמות משתתפים` number field, and five screens render it as one number. This feature turns
that single number into a list.

Each row is an **optional free-text label plus a count**. When the label is empty the
display falls back to `נגלה N`, where N is the row's position.

This is a data-entry and display feature. It does not touch assignments, quotas,
constraints, or the Google Calendar event description (which never carried the
participant count in the first place).

## Decisions taken during brainstorming

These were open questions; each is now closed and the rest of the spec assumes them.

1. **A נגלה is a label + a count — nothing more.** No per-נגלה time, no per-נגלה
   role quota. The label is optional; when blank, `נגלה N` is used.
2. **Numbering is positional.** The second row is `נגלה 2` even when the first row
   was given a name. It is *not* "the Nth unlabeled row".
3. **A single unlabeled row renders as a bare number**, exactly as today
   (`כמות משתתפים: 500`). The word `נגלה` only appears when it carries information —
   i.e. from two rows up, or when the user typed a label. Every existing event
   therefore looks unchanged.
4. **The legacy `participantCount` scalar is retired**, not mirrored. See
   [Persistence & migration](#persistence--migration).
5. **The calendar-share image shows the full string and lets it wrap** in the day
   cell. No second, compact formatting rule.

## The display rule

One formatter, `Event.participantsSummary`, is the single source of truth. It returns
the **value only** — each screen adds its own `כמות משתתפים: ` prefix (or `👥 `), exactly
as it does today.

| `participantGroups` | `participantsSummary` |
| --- | --- |
| `[]` | `null` (screens render nothing) |
| `[(–, 500)]` | `500` |
| `[(בוקר, 500)]` | `בוקר: 500` |
| `[(–, 500), (–, 700)]` | `נגלה 1: 500, נגלה 2: 700` |
| `[(בוקר, 500), (–, 700)]` | `בוקר: 500, נגלה 2: 700` |
| `[(בוקר, 500), (ערב, 700)]` | `בוקר: 500, ערב: 700` |

(`–` means "no label".)

Segments are joined with `, `. Rendering happens inside the app's RTL
`Directionality`; the numerals and separators are bidi-neutral between Hebrew runs and
resolve correctly. **A Latin label (e.g. `Morning`) introduces a strong-LTR run and is
the one case worth eyeballing during verification** — if it reorders badly, wrap each
segment in an RTL isolate (`U+2067…U+2069`), the same trick
`calendar_share_data_builder.dart:279` already uses for the `מופע` time range.

## Data model

New value object, `shavtzak/lib/domain/entities/participant_group.dart`:

```dart
class ParticipantGroup extends Equatable {
  final String? label; // null or empty ⇒ display falls back to "נגלה N"
  final int count;

  const ParticipantGroup({this.label, required this.count});

  @override
  List<Object?> get props => [label, count];
}
```

On `Event` (`shavtzak/lib/domain/entities/event.dart`):

- **Remove** `final int? participantCount`.
- **Add** `final List<ParticipantGroup> participantGroups` (default `const []`).
- **Remove** the `clearParticipantCount` flag from `copyWith`. An empty list is the
  "unset" representation, so the flag has nothing left to express. It currently has
  zero real callers — the only other hit in the repo is the string
  `'tap:clearParticipantCount'` inside a `Logger.action()` call, which is a log key,
  not an invocation.
- `participantGroups` goes in `props` (per the Equatable rule in CLAUDE.md: the full
  object, never an id or a derived scalar).
- Add the `participantsSummary` getter described above, next to `dateRangeString`.

## Persistence & migration

### Why the scalar can be retired

Verified against the whole repo: **nothing outside the Flutter app reads
`events.participantCount`.** The single non-`lib/` reference is
`functions/src/index.ts:1523`, and that is a *write* path, not a read.
`Google Apps Script/export_to_sheets.js` (Drive folders + sheet export),
`functions/src/drive_export.ts`, `calendar_integration.ts` and
`calendar_sync_backend.ts` never mention the field.

### The write path is an allowlist — this is the trap

Every event write goes:

```
Event (entity)
  → EventModel.fromEntity().toJson()          [Dart]
  → callable  event.insert / event.update / event.insertBatch
  → eventDocFromJson()                         [TS — explicit field allowlist]
  → Firestore
```

Reads go straight from Firestore through `EventModel.fromFirestore()`; the app never
writes event docs directly (`firestore_database.dart:564-585` — `_invokeMutation`).

Because `eventDocFromJson` is an **allowlist**, a `participantGroups` field that is not
added to it is **silently dropped on save**. The feature would look like it works
(optimistic UI, real-time stream still holding the old doc) and then lose the data on
the next reload. See [Deploy](#deploy--this-feature-does-not-work-without-a-functions-deploy).

### Firestore shape

```jsonc
participantGroups: [
  { label: "בוקר", count: 500 },
  { label: null,   count: 700 }
]
```

`label` is written as `null` rather than omitted (the TS `stripUndefined` helper keeps
nulls and strips only `undefined`).

A label is **trimmed** before storage, and an all-whitespace label is stored as `null`
— so it falls back to `נגלה N` like any other empty label.

### The scalar must be nulled, not merely omitted

`event.update` calls `eventRef.update(nextEvent)` — a **partial** merge. A field left out
of `eventDocFromJson` is not removed from the doc; it survives with its old value.

So `eventDocFromJson` must write `participantCount: null` explicitly, not drop the key.
Otherwise an old client that saves a changed count (say 500 → 600) produces a doc with
`participantGroups: [{count: 600}]` alongside a stale `participantCount: 500`, and that
old tab then renders **500** — a *wrong* number, which is worse than a missing one.
Writing `null` also means old docs self-clean the first time they are saved.

`FieldValue.delete()` is not an option here: the same mapper feeds `.set()` in
`event.insert` / `event.insertBatch`, where a delete sentinel is invalid. `null` is the
portable choice.

On the Dart side, `EventModel.toJson()` and `toFirestore()` simply stop emitting
`participantCount` altogether.

### Migration: read-time, no backfill script

A shared helper — `_parseParticipantGroups(groupsRaw, legacyScalar)` — is the entire
migration:

1. If `participantGroups` is a list, map it (coercing each entry, dropping malformed ones).
2. Else if the legacy `participantCount` is a number, hydrate `[ParticipantGroup(count: N)]`.
3. Else `[]`.

Old docs keep working untouched and convert to the new shape the first time they are
saved. Stale copies of the scalar left on old docs are inert: once a doc has a
`participantGroups` array, branch 1 wins and the scalar is never consulted.

`EventModel` must apply this at **all six touchpoints**: `fromEntity`, `toEntity`,
`fromFirestore`, `toFirestore`, `fromJson`, `toJson`.

### The same normalization runs server-side

`eventDocFromJson` performs the identical fallback. This covers the rollout window: a
user sitting on a stale browser tab still posts `participantCount: 500` with no
`participantGroups`, and the function folds it into `[{label: null, count: 500}]`
rather than discarding it. **No data is lost at any point in the rollout.**

The only cost of retiring the scalar: between the Functions deploy and that stale tab's
next refresh, the tab stops *displaying* the count (it reads a field that is now written
as `null`). The data is intact in `participantGroups` and a refresh restores the display.
This was accepted in preference to permanently carrying a derived, drift-prone mirror
field.

### Server-side coercion

The function coerces defensively rather than throwing, so a malformed payload can never
fail a save:

- an entry whose `count` is not a finite number, or is negative, is **dropped**;
- `count` is floored to an integer;
- a `label` that is not a string becomes `null`; a string is trimmed, and an empty
  result becomes `null`;
- the array is clamped to the first **10** entries.

## Form UI (`event_form_modal.dart`)

The single `TextFormField` at `event_form_modal.dart:1844` becomes a `Column` of rows,
with a `+ הוסף נגלה` button beneath:

```
כמות משתתפים (אופציונלי)
┌──────────────────────────────┐
│ [תווית (אופציונלי)] : [ 500 ] │  ✕
├──────────────────────────────┤
│ [תווית (אופציונלי)] : [ 700 ] │  ✕
└──────────────────────────────┘
            [ + הוסף נגלה ]
```

State moves from the one `_participantCountController` to a `List<_ParticipantRow>`,
each holding a label controller and a count controller. **Every controller must be
disposed** in `dispose()`, including rows removed mid-session — the current `dispose()`
at `event_form_modal.dart:218` disposes a fixed set and will need to iterate the list.

The count field keeps the existing input formatters (`digitsOnly`,
`LengthLimitingTextInputFormatter(7)`). The label field is capped at 20 characters so a
single label cannot blow up the display string. Editing any field sets `_isDirty`.

### Validation

- A row is **saved iff it has a count**.
- A **completely empty** row (no label, no count) is **dropped silently** on save —
  that is the "user pressed + and changed their mind" case, and it should not block them.
- A row with a **label but no count** is a **form validation error** (`יש להזין כמות`).
  The user clearly intended something; dropping it silently would look like a bug.
- Max **10** rows. The `+` button disables at the cap.
- Zero is a legal count.

`_parseParticipantCount()` (`event_form_modal.dart:356`) is replaced by
`_parseParticipantGroups()`, returning `List<ParticipantGroup>`.

## Display sites

All five swap to `event.participantsSummary` and render nothing when it is `null`.
None of them formats the value itself.

| File | Line | Change |
| --- | --- | --- |
| `event_list_screen.dart` | 737 | Also switch from `_buildFieldItem` to `_buildFieldItemWithResponsiveFont` — the same helper the `שעות` line already uses — because the string can now be long. |
| `user_assignments_screen.dart` | 1121 | Wrap the value `Text` in `Expanded` so a long string wraps instead of overflowing the `Row`. |
| `event_summary_tile.dart` | 168 | Value swap only; the `Text` already wraps. |
| `event_assignments_share_data_builder.dart` | 291 | `_formatParticipantsLine` returns `'כמות משתתפים: $summary'`. |
| `calendar_share_data_builder.dart` | 291 | `_buildParticipantsLine` returns the bare summary; `calendar_share_card.dart:325` renders `👥 $summary` and lets it wrap in the day cell. |

## Duplicate-event flow

`DuplicateEvent.newParticipantCount` (`event_event.dart:124`, `:143`, `:164`) becomes
`newParticipantGroups` (`List<ParticipantGroup>`), consumed at `event_bloc.dart:426` and
produced at `event_form_modal.dart:530`.

`event_bloc.dart:607` already carries a comment listing the fields that `copyWith`
preserves through the duplicate-conflict path, and it names `participantCount` — update
that comment.

## DB log viewer

`log_document_card_view.dart:1433` maps Firestore field names to Hebrew labels for the
audit-log diff view. Add `'participantGroups': 'כמות משתתפים'` and **keep**
`'participantCount'` — historical audit-log entries still contain it.

How that viewer renders a `List<Map>` value is not yet known; worst case it shows raw
JSON, which is acceptable on a debug screen. Check it while verifying; only fix if it
throws.

## Out of scope

- Reordering rows (drag handles). `+` appends, `✕` removes.
- A total/sum line (`סה"כ 1200`). The boss did not ask for one.
- Per-נגלה times, or per-נגלה role quotas.
- Backfilling existing Firestore docs. The read-time fallback makes it unnecessary.

## Testing

- **Formatter** — the display-rule table above, verbatim, as unit tests on
  `Event.participantsSummary`: empty, single unlabeled, single labeled, multi unlabeled,
  multi mixed, and multi all-labeled. Positional numbering is the case most likely to
  regress.
- **`EventModel` round-trips** — new array in/out; the legacy-scalar fallback
  (`{participantCount: 500}` with no array ⇒ one unlabeled group); both absent ⇒ `[]`;
  a doc holding *both* an array and a stale scalar ⇒ the array wins.
- **`eventDocFromJson` (TS)** — an old-shaped payload (`participantCount`, no
  `participantGroups`) normalizes into one group; a new-shaped payload passes through;
  malformed entries are dropped rather than thrown on; and `participantCount` is written
  as `null` on **every** path, which is what neutralizes the stale scalar under
  `.update()`. `functions/src/*.test.ts` already has the harness.
- **Form widget test** — `+` adds a row, `✕` removes it, an empty row is dropped on
  save, a label-without-count blocks save with `יש להזין כמות`, the cap disables `+`.
- **Update** the existing `event_assignments_share_data_builder_test.dart`, which
  asserts on the participants line.

`flutter analyze` has 108 pre-existing infos; "clean" means **zero new** ones.

## Deploy — order matters, and the wrong order loses data

The Flutter web app auto-builds and deploys to GitHub Pages on push to `main`
(`.github/workflows/web.yml`). **Cloud Functions do not.** So merging the PR ships the
new web client *by itself*, against whatever Functions happen to be live.

**Deploy Functions BEFORE merging to `main`:**

```bash
firebase deploy --only functions
```

### Why the order is not negotiable

**Functions first (correct).** The new function is backward-compatible on its own: it
normalizes an old client's `participantCount` payload into a group, so nothing breaks
while the old web build is still live. Safe to sit in this state indefinitely.

**Web first (data loss).** The old function's allowlist drops the `participantGroups` it
has never heard of, and writes `participantCount: event['participantCount'] ?? null` —
but the new client no longer sends that key. Every save therefore nulls the count. The
UI would look correct (optimistic state, plus a real-time stream still holding the
pre-save doc) and the data would be gone on the next reload.
