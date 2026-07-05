# Assignments — Past Look‑Back: "Load More" + Faithful History

**Date:** 2026-07-05
**Status:** Design — awaiting review
**Screen:** `/admin/assignments` (`AssignmentListScreen`) and `AssignmentBloc`

## 1. Problem & Motivation

The `/admin/assignments` screen doesn't render assignment documents — it builds a grid of **slots** from `events × role quotas` and drops each assignment into a matching slot. Two consequences make historical assignments disappear even though they exist in `/db`:

1. **The 90‑day fetch window.** Slots are built only from events fetched in `[now − 90d, now + 180d]`. Assignments on events older than ~3 months are never loaded, so they can't appear. Example the user hit: assignment `0471a3ff-b6e8-4cc8-adcc-854a53e9f557`.
2. **Off‑quota (orphaned) assignments.** An assignment with no matching slot is invisible: the event's quota was later reduced below the assignment's `slotIndex`, two assignments share a `slotIndex`, or the role was **permanently deleted** (note: *archived* roles already show, because the roles cache uses `getAllRoles()` which includes archived).

The `/admin/assignments` past view (the "אירועי עבר" toggle) is meant to let an admin **look back** on assignments. This feature makes that look‑back complete and navigable.

## 2. Goals

- Keep the 90‑day window as the initial load (performance), but add a **"טען עוד"** button that fetches **25 more rows** of older history per tap, on demand.
- When looking at the past, order the grid so "load older" reads naturally.
- Guarantee that **every assignment on a visible event appears as a row**, including off‑quota ones, clearly marked and deletable.
- Always show a human name on filled rows, even for now‑inactive members or deleted roles.

## 3. Non‑Goals

- No "X מתוך Y" counter on the button (would require a full count query over all history).
- No pagination of the **future** side (the +180d window is unchanged).
- No change to archived‑role handling (already works).
- Off‑quota rows are **not** editable/reassignable — they are display + delete only.
- Loaded past rows are not fully live streams (snapshot + mutation‑splice; see §9).

## 4. Decisions (locked with user)

| # | Decision |
|---|----------|
| Sort | **Conditional flip.** Past OFF → oldest→newest (unchanged). Past ON → newest→oldest, so "טען עוד" is at the bottom and loads older history downward. |
| Load unit | **25 rows per tap** (a "row" = one on‑screen slot, filled or empty, incl. off‑quota rows). |
| Load mechanism | **Incremental fetch (Approach A)** — fetch only the next older events/assignments on demand; never re‑read the whole window. |
| When | Load‑more only appears when **past toggle is ON** and more history exists. |
| Off‑quota rows | **Yes**, applied **everywhere** (past + future), marked "מחוץ למכסה", delete‑only. |
| Names | Filled + off‑quota rows resolve member name from the **full** member list (incl. inactive); availability/dropdowns stay **active‑only**. |
| Filters | Screen filters (search / filled‑unfilled / label) apply on top; "25 more" counts **raw** rows pre‑filter. |

## 5. Detailed Design

### 5.1 Sort flip (BLoC)

In `AssignmentBloc._compareAssignmentSlots`, make **only the event‑level comparison** direction depend on `FilterPersistence.showPastEvents`:

- Past ON → `compareEventsChronologicallyDescending(a.event, b.event)`.
- Past OFF → `compareEventsChronologically(a.event, b.event)` (current).

Role `sortOrder`, `slotIndex`, and member tie‑breaks stay ascending in both modes (roles within an event keep their normal order). The screen's `_sortSlotsForDisplay` already preserves the BLoC's cross‑event order, so no direction change is needed there.

### 5.2 Load‑more pagination (Approach A — incremental)

**Constant:** `pastLoadMoreRowChunk = 25`.

**New BLoC event:** `LoadMorePastAssignmentSlots`.

**New state fields on `AssignmentSlotsLoaded`** (added to `props`): `bool hasMorePast`, `bool isLoadingMorePast`.

**New internal BLoC fields:**
- `DateTime _slotsWindowStart` — the `now − 90d` boundary, stored at load time.
- `Map<String, Event> _extraPastEventsMap` — events older than the window, fetched on demand.
- `List<Assignment> _extraPastAssignments` — their assignments.
- `int _extraPastRowsRevealed` (default `0`).
- `DateTime? _oldestLoadedEventStart` — pagination cursor (min `startDate` across window + extra events).
- `bool _pastPagingExhausted` (default `false`).

**`_onLoadAssignmentSlots`** (existing): also store `_slotsWindowStart`, reset all `_extraPast*` fields, `_extraPastRowsRevealed = 0`, `_pastPagingExhausted = false`, and seed `_oldestLoadedEventStart` from the window's events. (This runs on the past toggle too, so toggling resets pagination — acceptable.)

**`_onLoadMorePastAssignmentSlots`:**
1. If `_pastPagingExhausted` and everything already revealed → no‑op.
2. Emit current slots with `isLoadingMorePast = true`.
3. `target = _extraPastRowsRevealed + 25`.
4. While `availableExtraRows() < target && !_pastPagingExhausted`:
   - Fetch `getEventsBeforeDate(_oldestLoadedEventStart, limit = pastEventFetchBatch)` (batch e.g. 15 events).
   - Dedupe by id into `_extraPastEventsMap`; if the batch is empty → `_pastPagingExhausted = true`.
   - Fetch their assignments via `getAssignmentsByEventIds(newIds)`; append to `_extraPastAssignments`.
   - Update `_oldestLoadedEventStart` to the new minimum.
5. `_extraPastRowsRevealed = min(target, availableExtraRows())`.
6. `hasMorePast = _extraPastRowsRevealed < availableExtraRows() || !_pastPagingExhausted`.
7. Trigger a rebuild (§5.4) and set `isLoadingMorePast = false`.

`availableExtraRows()` = the number of display rows the loaded extra‑past events would produce (quota slots + off‑quota rows), for non‑deactivated events.

**Cursor caveat:** `getEventsBeforeDate` uses `startDate < cursor`; events sharing the exact same boundary `startDate` could be skipped. We dedupe by id, and accept this minor edge case; it can be upgraded to a document‑snapshot cursor if it ever bites.

### 5.3 Off‑quota (orphaned) rows

During slot building for an event, track the set of assignment IDs that were **placed** into a normal quota slot. After building that event's quota slots, any assignment for the event whose id is **not** placed is **off‑quota**. For each, emit an extra `AssignmentSlot` with:

- `isOffQuota = true` (new field, default `false`, added to `props`).
- `currentAssignment` = the orphaned assignment (filled).
- `role` = resolved role (§5.5). `slotIndex` = the assignment's own `slotIndex` (used only for display/keys, not slot matching).
- Empty `availableMembers` / `alreadyAssignedMembers` (not reassignable).

**Ordering:** off‑quota rows sort **with their event, after that event's normal rows** (extend `_compareAssignmentSlots`: off‑quota after non‑off‑quota within the same event; tie‑break by `slotIndex` then assignment id).

**Scope:** everywhere (window, extra‑past, and future events). An off‑quota row on a past event hides/show with the past toggle exactly like any other row on that event.

**Counts toward load‑more:** off‑quota rows are rows, so they count toward the 25.

### 5.4 Rebuild merge + reveal cap (both rebuild paths)

Rows for events with `startDate < _slotsWindowStart` are **"extra‑past rows."** The reveal cap keeps all window rows plus the first `_extraPastRowsRevealed` extra‑past rows in display (descending) order. Because extra‑past events are strictly older than the window, in descending sort they always come last, so the cap is a clean suffix slice. When past is OFF, extra‑past rows are dropped by the existing `showPastEvents` date filter anyway, so the cap only matters when past is ON.

- **Stream path (`_onRebuildAssignmentSlotsFromData`)** — the windowed streams don't contain older events, so first **merge** `_extraPastEventsMap` into the events map and `_extraPastAssignments` into the assignments list, then build, sort, and apply the cap.
- **Full path (`_buildSlotsFromAssignments`, used after optimistic edits)** — already loads all events via `getAllEvents()`, so older events are present; just apply the same date‑boundary cap. Preserve `hasMorePast` / set `isLoadingMorePast = false` in the emitted state.

Both paths compute `hasMorePast = (unrevealed extra‑past rows exist) || !_pastPagingExhausted`.

### 5.5 Name resolution

- **Member name (filled + off‑quota rows):** hydrate the assigned member from a **full** member map `_allMembersById` (from `getAllTeamMembers()`, includes inactive), falling back to the active map. Availability computation and dropdowns keep using **active** members only. This also fixes the pre‑existing blank‑name case for recent events.
- **Role:** look up `_cachedRoles` by key first (archived included). If absent (permanently deleted role), synthesize `Role(key: roleType, hebrewName: <RoleTypeExtension.fromString(key).hebrewName inside try/catch, else the raw key>, sortOrder: large, isArchived: true)`. `fromString` throws on unknown keys, so the raw‑key fallback is required.

### 5.6 UI (screen)

- **"טען עוד" footer button** (`_buildSlotGrid`): rendered as the last item of the slots `ListView` when `FilterPersistence.showPastEvents == true && state.hasMorePast`. Style mirrors `/db` (`OutlinedButton.icon`, `Icons.expand_more`, label `טען עוד`, white background, centered). Show a small `CircularProgressIndicator` in place of the icon while `state.isLoadingMorePast`. On tap → `add(LoadMorePastAssignmentSlots())` and `Logger.action('tap:loadMorePast')`. Increase `itemCount` by 1 for the footer.
- **Off‑quota row rendering** (`_buildSlotRow`): when `slot.isOffQuota`, render a distinct **"מחוץ למכסה"** badge and a distinct row tint; show event / role / assigned person as usual; **no** dropdown and **no** notes‑edit swipe. Keep **swipe‑left to delete**, which deletes just the assignment document (no quota decrement — it's already outside the quota), relying on stream refresh. Use a **unique widget/Dismissible key** derived from `assignment.id` (not `event_role_slotIndex`, which can collide with the in‑quota row or another orphan).

### 5.7 Data layer (new methods)

Add to `DatabaseInterface`, `FirestoreDatabase`, and the relevant repositories (all env‑prefixed):

- `Future<List<Event>> getEventsBeforeDate(DateTime cursor, {required int limit})` — `collection(events).where('startDate', isLessThan: cursor).orderBy('startDate', descending: true).limit(limit)`.
- `Future<List<Assignment>> getAssignmentsByEventIds(List<String> eventIds)` — chunked `whereIn` (≤30 per chunk), extracted from the existing `getAssignmentsInTimeWindow` logic. Returns raw assignments (the rebuild populates relations).

## 6. Components Touched

- `lib/data/data_sources/database_interface.dart` — 2 method signatures.
- `lib/data/data_sources/firestore_database.dart` — 2 implementations (+ optional shared `whereIn` helper).
- `lib/data/repositories/event_repository.dart`, `assignment_repository.dart` — pass‑throughs.
- `lib/presentation/screens/assignment/models/assignment_slot.dart` — add `isOffQuota` (+ `props`).
- `lib/presentation/bloc/assignment/assignment_event.dart` — `LoadMorePastAssignmentSlots`.
- `lib/presentation/bloc/assignment/assignment_state.dart` — `hasMorePast`, `isLoadingMorePast` on `AssignmentSlotsLoaded` (+ `props`).
- `lib/presentation/bloc/assignment/assignment_bloc.dart` — sort flip, pagination fields + handler, off‑quota detection, name maps, reveal cap in both rebuild paths, mutation‑splice for extra‑past cache (§9).
- `lib/presentation/screens/assignment/assignment_list_screen.dart` — footer button, off‑quota row rendering + delete.

## 7. Data Flow (past ON)

1. Screen loads → 90‑day window streams paint the grid, now sorted newest→oldest; "טען עוד" shows at the bottom (`hasMorePast` initially true).
2. User taps "טען עוד" → `LoadMorePastAssignmentSlots` → BLoC fetches the next older events + their assignments until ≥25 new rows are available → reveals 25 → rebuild → 25 older rows appear below; overflow is buffered for the next tap.
3. Repeat until history runs out → `_pastPagingExhausted` and all revealed → `hasMorePast = false` → button hides.

## 8. Edge Cases

- **Duplicate `slotIndex`:** first assignment fills the quota slot; the rest become off‑quota rows (unique keys avoid Flutter duplicate‑key errors).
- **Deleted role:** off‑quota row with a synthesized role; name falls back to enum → raw key.
- **Inactive member on any filled row:** name resolves via `_allMembersById`.
- **Deactivated event:** still excluded everywhere (unchanged).
- **Screen filters active:** apply on top of loaded rows; "25 more" counts raw rows, so a heavy filter may reveal few visible rows per tap (acceptable).

## 9. Known Limitations

- **Extra‑past rows are a snapshot.** The stream path reads the `_extraPastAssignments` cache, not a live stream. To keep edits consistent: **on any successful create/update/delete whose event is older than `_slotsWindowStart`, splice the change into `_extraPastAssignments`** (re‑fetch that event's assignments via `getAssignmentsByEvent` and replace its slice). Without this, a stream re‑emit could visually revert an edit to an ancient row. This splice is part of the implementation.
- **Cursor tie‑boundary skip** (§5.2) — minor, dedupe‑mitigated.
- **No total counter** on the button (by decision).

## 10. Verification

No automated test suite exists yet (per `CLAUDE.md`); the developer runs the app manually. Gate on `flutter analyze` (must pass) plus manual checks in the **test** environment:

1. Past OFF → grid is oldest→newest (unchanged); no "טען עוד"; an off‑quota row on a future event shows marked + deletes correctly.
2. Past ON → grid flips to newest→oldest; "טען עוד" at the bottom.
3. Tap "טען עוד" → exactly ~25 older rows appear below; spinner shows during fetch; repeat; button disappears at the start of history.
4. Reduce a role quota below an existing assignment → an off‑quota "מחוץ למכסה" row appears; swipe‑delete removes only that assignment.
5. Assignment `0471a3ff‑b6e8‑4cc8‑adcc‑854a53e9f557` becomes reachable by tapping "טען עוד" enough times.
6. Old assignment to a now‑inactive member → name still shows.
7. Edit notes/label on a loaded ancient row → the edit sticks (does not revert on the next stream emit).
