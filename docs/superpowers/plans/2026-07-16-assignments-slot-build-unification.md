# Assignments Slot-Build Unification + Windowed Stage/Save + Load-More-Future — Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Characterization-tests-FIRST; this touches the core render path.

**Goal:** Collapse the two duplicated slot-build implementations in `AssignmentBloc` into one **windowed** shared core, fixing the 11 accidental divergences between them (which cause bug #2 fully and are the prime suspects for the intermittent #1); make Save **fail loud** instead of silently reporting "0 changes"; and add a **"טען עוד" (load more) for future events**, mirroring the existing past-paging, so far-future editing is available on demand.

**Context:** Follow-on to the staged-Save feature (branch `feat/assignments-staged-save`). A final-review diff analysis found 12 behavioral differences between the two builds (11 accidental) and traced bug #3's root cause. Decision (Omer, 2026-07-16): **Option 1 — windowed everywhere + fail-loud Save + load-more-future.**

**Base:** HEAD `76d558c` on `feat/assignments-staged-save`.

## The two paths being unified
- **Path A** — `_buildSlotsFromAssignments(...)` (method ~2107), called from `_onRebuildAssignmentSlots` (~2341, the STAGE/FILTER/REHYDRATE/SAVE rebuild path) with UNBOUNDED one-shot `getAllAssignments()`/`getAllEvents()`/`getActiveTeamMembers()`.
- **Path B** — inline build inside `_onRebuildAssignmentSlotsFromData` (~2385-2643, the LIVE-STREAM path) with the windowed stream payload + `_extraPastAssignments`, re-stamped relations, first-paint gate, `selectedEventIds` filter.

## Divergences to resolve (from the diff analysis; 11 accidental)
1. Assignments source: A unbounded vs B windowed(+extra-past). → **window A**.
2. Events source: A unbounded (no future cap) vs B windowed. → **window A**.
3. Members: A `getActiveTeamMembers()` (active-only) vs B unfiltered stream (`_windowMembersMap`) — an inactive `allowMultipleAssignments` member leaks into B's dropdown. → **filter to active** in the shared core (or at both call boundaries).
4. Same-day member-not-found fallback: A `allMembers.firstWhere(orElse: allMembers.first)` (misattributes to an arbitrary member) vs B null-skip. → **use B's null-skip**.
5. Same-day `otherEvent` lookup respects the `showPastEvents` toggle in A but not B (a display toggle changing availability truth). → **make same-day truth independent of the display toggle; use the full loaded event set**.
6. B-internal: same-day candidate loop uses unfiltered `mergedEvents` while the badge pass uses filtered `filteredEvents`. → **use one consistent event set**.
7. Relation re-stamping: B does `.withRelations(event, teamMember)`, A doesn't. → **re-stamp in the shared core**.
8. Dead `stillExists` guard unique to A (currently inert; latent). → **drop it**.
9. Roles empty-fallback: A `getAllRoles()` fallback vs B `[..._cachedRoles]` (relies on gate). → intentional per invariant; keep whichever fits the unified readiness story.
10. First-paint readiness gate exists only in B → A can emit a beat early (flicker). → **apply the gate to the unified path** (or make A's callers respect readiness).
11. `selectedEventIds` slot filtering exists only in B → A's `.slots` unfiltered, leaks into `_allSlots` double-assignment checks. → **filter uniformly** (callers own it, as B does).
12. Concurrency: A does network I/O in a concurrently-dispatched handler → stale out-of-order emits. → **eliminated by windowing** (no per-call fetch; build from in-memory caches).

## Bug #3 root cause (must be killed)
Path A unbounded but Save's `dbByKey` windowed (`getCurrentAssignments()` + extra-past). Editing an out-of-window assignment → `dbByKey[key]` null → staged clear hits `clear-noop` (0 deletes) but the staged entry is still dropped → **"נשמרו 0 שינויים" + member reappears**. Fixed by windowing the stage/save scope (consistency) AND fail-loud Save (Task 3).

## Global Constraints
- **Language/RTL:** Hebrew UI, RTL. Comments English.
- **Windowed everywhere:** the unified build + the stage/save rebuild path use the SAME 90-days-back / 180-days-forward window (+ paged extras) as the live-stream path. No unbounded `getAllAssignments()`/`getAllEvents()` in the slots view.
- **Behavior-change discipline:** every divergence fix must be reflected as an intentional change to a characterization test written in Task 1.
- **Equatable props use full objects, not IDs** (repo rule; real-time correctness).
- **Analyze gate:** `flutter analyze` stays at **107 issues (0 errors)**; zero NEW.
- **Tests:** mockito + StreamControllers, no blocTest; `pumpEventQueue`; `SharedPreferences.setMockInitialValues`. Do not regress the existing suite (baseline flutter test 285 on this branch before this plan; functions untouched).
- **Load-more-future parity:** the "טען עוד" future button appears ONLY when there is more future to load (mirrors `hasMorePast`); future paging mirrors past paging exactly (fields, handler, cursor, reveal cap, state flags).

---

### Task 1: Characterization tests (pin current behavior BEFORE refactoring)
**Files:** Create `shavtzak/test/presentation/bloc/assignment_slot_build_characterization_test.dart`.
Write tests that pin the CURRENT (pre-refactor) behavior so the unification is a visible diff:
- **Happy path A==B:** in-window data, all active members, no filter/edge → `RebuildAssignmentSlots` (A) and `RebuildAssignmentSlotsFromData` (B) produce grids with the SAME event/role/slotIndex/currentAssignment.id/member-id sets. (This must already pass; it's the baseline the refactor must never break.)
- **Divergence pins (each will be intentionally flipped in Task 2 — assert CURRENT behavior now):** inactive `allowMultipleAssignments` member appears via B but not A (#3); same-day owner absent from active members → A misattributes to `allMembers.first` while B skips (#4); `showPastEvents=false` boundary-day past event → B excludes the member from availability, A doesn't (#5); an out-of-window (>180d) event's assignment appears via A but not B (#1/#2 scope), then a staged clear + Save on it yields 0 writes and drops the staged entry (#3 chain); `RebuildAssignmentSlots` `.slots` NOT filtered by `selectedEventIds` while `RebuildAssignmentSlotsFromData` IS (#11).
- Use the existing harness (mockito repos + StreamControllers + `SharedPreferences.setMockInitialValues` + `pumpEventQueue` + the same-day two-event builder from `assignment_bloc_staged_samedy_availability_test.dart`).
Each test: fail-first not required (pinning existing behavior), but assertions must be specific. Commit. `flutter analyze` 107.

### Task 2: Unify to one windowed shared slot-build + fix the divergences
**Files:** Modify `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart`; update the Task-1 characterization tests to the intended new behavior.
- Extract the per-event/role/slot core loop (A `2148-2293`, B `2459-2595`) into ONE pure helper taking already-resolved `events`, `assignments` (merged + staged-effective as the caller needs), `activeMembers`, `sortedRoles` → `List<AssignmentSlot>` (unannotated/unsorted). Callers own fetch/merge, `annotateDoubleAssignments`/`annotateSameDayOtherEvents`, sort, `selectedEventIds` filter, `_mergeSlotsWithOptimisticUpdates`, reveal-cap (as B already does).
- **Window Path A:** `_onRebuildAssignmentSlots` stops using unbounded `getAllAssignments()`/`getAllEvents()`/`getActiveTeamMembers()`; instead build from the SAME in-memory windowed caches the stream path uses (`_repository.getCurrentAssignments()` + `_extraPastAssignments`, `_windowEventsMap` + `_extraPastEventsMap`, `_windowMembersMap` filtered to active, `_cachedRoles`). Respect the first-paint gate.
- Fix each accidental divergence per the table (#3 active-only members, #4 null-skip, #5/#6 consistent event set for same-day truth, #7 re-stamp relations, #8 drop dead guard, #10 gate, #11 filter uniformly).
- Result: both `_onRebuildAssignmentSlots` and `_onRebuildAssignmentSlotsFromData` produce IDENTICAL grids for identical windowed data.
- Update the Task-1 characterization tests to assert the NEW unified behavior (the far-out event is no longer surfaced for editing on the assignments screen; A==B on all the previously-divergent cases). Full bloc suite green. `flutter analyze` 107.

### Task 3: Fail-loud Save
**Files:** Modify the `_onSaveStagedChanges` handler + relevant state/UI.
- When a staged change's slot has NO DB row in `dbByKey` at save time and the desired op needs one (a staged CLEAR, or a SWAP/notes update), do NOT silently drop it as a no-op. Instead surface it: skip it AND report it in the save outcome (e.g. `'N נשמרו, M דולגו (לא נמצאו)'`), OR treat it as a conflict. Never a bare `'נשמרו 0 שינויים'` while dropping a real staged clear.
- Keep the staged entry for skipped-not-found items (do NOT remove from `_stagedChanges`) so the user can see/retry — OR clearly tell them it was dropped. (Pick one; test it.)
- Test: a staged clear on a slot absent from `dbByKey` → the save reports the skip explicitly and does not falsely claim success-with-0. Full suite green, analyze 107.

### Task 4: "טען עוד" for future events (mirror past-paging)
**Files:** Modify `assignment_bloc.dart` (future-paging fields/handler/state), `assignment_state.dart` (`hasMoreFuture`/`isLoadingMoreFuture`), `assignment_list_screen.dart` (the future load-more button).
- Mirror the past machinery: `_extraFutureEventsMap`, `_extraFutureAssignments`, `_extraFutureRowsRevealed`, `_newestLoadedEventEnd` (forward cursor), `_futurePagingExhausted`, `_loadingMoreFuture`, `_slotsWindowEnd`; event `LoadMoreFutureAssignmentSlots` + handler `_onLoadMoreFutureAssignmentSlots` (fetch events strictly NEWER than the window end / cursor, their assignments, reveal in `_pastLoadMoreRowChunk`-sized chunks); state `hasMoreFuture`/`isLoadingMoreFuture`; extend the reveal-cap (or add a future equivalent) and feed the extra-future into the unified build.
- Screen: a `_buildLoadMoreFutureButton` shown at the BOTTOM of the future rows, ONLY when `state.hasMoreFuture` (unlike past, this shows in the DEFAULT future view, not gated on `showPastEvents`). Label "טען עוד".
- Test: with more future events beyond the window, tapping load-more reveals them; the button hides when `hasMoreFuture` is false. Full suite green, analyze 107.

### Task 5: Final review + full sweep
- Whole-branch review of Tasks 1-4 (focus: no in-window behavior regression; the divergences are all closed; save can't silently lie; future paging mirrors past correctly).
- `cd shavtzak && flutter analyze && flutter test`; `cd functions && npm test` (functions untouched — confirm still green). Report final counts.

## Notes
- Functions are NOT touched by this plan (client-only). No redeploy needed for this work.
- This is a follow-on refactor; it can ship in the same branch/PR as the staged-Save feature or separately — Omer's call at the end.
