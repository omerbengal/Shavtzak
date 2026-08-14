# `assignment.update` duplicate-check edge — options & decision

**Status:** DEFERRED (decided 2026-07-20). No production data can trigger this today.
**Related:** `2026-07-18-assignments-staged-quota-changes-design.md`, `2026-07-15-assignments-staged-save-design.md`
**Fix commits this follows on from:** `6f7a3d5` (backend), `1f6dd28` (client)

---

## Background

On 2026-07-20 the staged-Save feature shipped and immediately broke: every save on
`/admin/assignments` failed with `חבר/ת הצוות כבר משובץ/ת לתפקיד זה באירוע`.

Root cause was in `assignment.saveBatch`: `findBatchDuplicateRoleAssignments` judged the post-batch
per-event occupancy in **absolute** terms, so a `(eventId, roleType, teamMemberId)` group that
already existed and that the batch never touched still aborted the save. Because `saveBatch` derives
`exemptMemberIds` only from members its own creates/updates touch, the shared pool members
(`allowMultipleAssignments: true`) were never exempt — making **17 of 79 events completely
unsaveable**. Fixed by comparing each group against its **pre-batch** count and flagging only groups
the batch actually grew.

A second, independent bug in the same report: `updateAssignmentUnchecked` skipped the *client*
conflict check but left `bypassAvailability` false, so the backend re-validated availability on
untouched rows during slot compaction. Fixed by passing `bypassAvailability: true`.

**This document covers what was deliberately left unfixed.**

---

## The remaining edge

`assignment.update` runs `validateAssignmentPayload`, which includes a **per-item duplicate-role
check** (`functions/src/index.ts:3216-3238`). That check is skipped only when the member has
`allowMultipleAssignments === true`.

Failure scenario:

1. A member **without** `allowMultipleAssignments` somehow holds the same role twice in one event
   (slots 2 and 5) — legacy import, historical bug, or data predating the check.
2. An admin reduces that role's quota in the event form.
3. The compaction loop (`event_form_modal.dart:607,654`) renumbers slots and updates the row at
   slot 5 → slot 3.
4. The backend asks "is this member already in this role in this event, other than this row?" →
   yes, the row at slot 2 → **rejected**.

Same *shape* as the shipped bug — blocked by pre-existing data the admin isn't touching — but a
different code path, and it needs data that does not currently exist.

Note the shipped fix means **staged Save is already immune**: it compares before/after counts rather
than relying on exemption. Only the event-form compaction path (which still issues N individual
`assignment.update` calls) is exposed.

## Evidence: why this is deferred

Full production sweep, 2026-07-20 (Firestore REST + gcloud token, aggregated locally):

| Metric | Value |
|---|---|
| Assignments / events / members scanned | 699 / 79 / 44 |
| Members with `allowMultipleAssignments: true` | **2** — תגבורת לשכת גיוס ירושלים, תגבורת מחלקת מילואים |
| Duplicate `(event, role, member)` groups | **19** |
| …held by exempt members (legitimate) | **19** |
| …held by **non-exempt** members (would trigger this edge) | **0** |
| Events unsaveable before the `saveBatch` fix | **17 of 79 (~22%)** |

**Conclusion: the edge is theoretical. No production row can currently trigger it.**

## Trigger condition — the thing to watch

The one concrete way to make this real is **toggling "שיבוץ מרובה" OFF** for either pool member.
That instantly reclassifies their 19 groups as non-exempt and breaks slot compaction on those
events. Revisit this document before doing that.

---

## Option A — surgical: expose the existing backend flag

`validateAssignmentPayload` **already accepts and honors** `skipDuplicateRoleCheck`
(`index.ts:3170`, `3218`) — `saveBatch` uses it. It simply isn't reachable from `assignment.update`.
`bypassAvailability` already flows through this exact channel, so this is a copy of a proven pattern.

| Layer | File | Change |
|---|---|---|
| Backend | `functions/src/index.ts:4139` | add `skipDuplicateRoleCheck: payload['skipDuplicateRoleCheck'] === true` beside `bypassAvailability` — one line, no new logic |
| Interface | `lib/data/data_sources/database_interface.dart:158` | add `bool skipDuplicateRoleCheck` to `updateAssignment` |
| Impl | `lib/data/data_sources/firestore_database.dart:1084` | add param + `if (...) 'skipDuplicateRoleCheck': true` in payload |
| Logging | `lib/data/data_sources/logging_database.dart:~470` | pass-through + log field |
| Caller | `lib/data/repositories/assignment_repository.dart` | `updateAssignmentUnchecked` passes `skipDuplicateRoleCheck: true` |

**Also needed:** regenerate mockito mocks (the `DatabaseInterface` signature change touches ~6
`.mocks.dart` files); one Dart test mirroring the existing `bypassAvailability` assertion in
`test/data/repositories/assignment_repository_save_batch_test.dart`.

**Effort:** ~30–45 min.
**Deploy:** `firebase deploy --only functions:api` **and** a web push.
**Risk:** genuinely loosens a safety check on the update path. Must be wired **only** into
`updateAssignmentUnchecked` — never the normal edit path, or admins could silently create real
duplicates.

## Option B — better: route compaction through `saveBatch`

Change the two compaction loops in `event_form_modal.dart:607,654` to collect the renumbered rows
and issue **one** `saveAssignmentsBatch` call instead of N sequential `assignment.update` calls.

Stronger for three reasons:

1. **No new bypass flag.** `saveBatch` already has the correct before/after duplicate semantics, so
   it inherits immunity for free. Nothing is loosened.
2. **Atomicity.** The current loop can fail partway and leave slots half-renumbered — a real latent
   bug independent of this edge.
3. It is the natural first step of the **event-form quota staging** work already deferred in
   `2026-07-18-assignments-staged-quota-changes-design.md`, rather than a throwaway patch.

**Effort:** ~1–2 hours. No interface changes, no mock regeneration; needs care around the
quota-set/bump payload.
**Deploy:** client-only — no functions deploy, since `saveBatch` is already correct.

## Option C — cheapest insurance (no backend work)

Add a confirmation warning in the team-member modal when un-toggling **שיבוץ מרובה** for a member
who currently holds any role more than once. A few lines of UI that close the only path into the bad
state, without touching validation at all.

---

## Recommendation

**Do nothing now.** Zero production rows can trigger this, and A and B both carry more risk than the
bug they prevent.

When it is picked up, prefer **Option B** — it fixes the atomicity problem too, needs no backend
deploy, and weakens no check. Sensible triggers:

- "We're about to turn off שיבוץ מרובה for a pool member" (then **C** first, or **B**), or
- "We're picking up event-form quota staging anyway" (then **B** as its first step).

## Why this class of bug escaped testing

Worth carrying forward, since it applies to any future backend validation:

- `/test` contains only **two** team members (`admin`, `non admin`), neither with
  `allowMultipleAssignments` — the triggering shape is structurally unrepresentable there, so no
  amount of manual smoke testing could reproduce it.
- Every original `findBatchDuplicateRoleAssignments` fixture had `existing` with at most **one** row
  per `(event, role, member)`, so the "untouched pre-existing duplicate" region was never covered.

The general lesson: a new backend validation that is **semantically stricter than the one it
replaces** gets applied to data accumulated under the old, looser rule. Payload backward
compatibility does not cover this. The question to ask is *"what does production data already contain
that this rule would now reject?"* — and the cheapest way to answer it is to replay real production
rows through the pure validation function, which is exactly how this bug was diagnosed.
