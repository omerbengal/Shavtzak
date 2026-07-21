# Availability date-range + search/category filter bars — Design

**Date:** 2026-07-21
**Branch:** `feat/availability-dates-and-filter-bar-availability-and-export`

Three UI features. Two are the same pattern in two places (search + category filter
+ "select all"); one is different (date-range bulk availability).

## Confirmed decisions (from the user)

1. **"סינון וחיפוש" = search box + category filter** — mirror the `/admin/events`
   bar exactly (search `TextField` by name/location + a `filter_list` badge-button
   that opens the existing `CategoryFilterModal`). "בחר הכל" selects everything
   passing **both** the search and the category filter.
2. **Date-range availability = union** — events in the chosen range get marked
   available; anything already marked stays marked; nothing gets un-selected.

## Reusable foundations already in the codebase

- `DualCalendarDatePicker(isSingleDate: false, …)` (`widgets/date_picker_dialog.dart`)
  returns `{ 'startDate': DateTime, 'endDate': DateTime? }` and supports
  `highlightedDates` (red frame on dates that have events).
- `Event.occursOn(date)` / date-only overlap for range membership.
- `normalizeForSearch(text)` (`core/utils/search_utils.dart`) — the app's search
  normalizer (name/location).
- `CategoryFilterModal(selectedCategoryIds, onFilterChanged)` — existing bottom-sheet.
- `CategoryBloc` is provided globally in `main.dart`, so it is reachable from both
  the availability screen and the export dialog.

## Approach: extract two shared pieces (vs. copy the bar a 3rd/4th time)

- **`EventSearchFilterBar`** — new widget in `lib/presentation/widgets/`. Renders the
  search field + clear button + `filter_list` badge-button opening `CategoryFilterModal`.
  Reads `CategoryBloc`; the category button is shown **only when categories are
  loaded and non-empty** (graceful degradation for non-permanent members / test-env
  reference-collection permission gaps). Props: `hintText`, `searchQuery`,
  `onSearchChanged`, `selectedCategoryIds`, `onCategoryFilterChanged`.
- **`filterEventsBySearchAndCategory(events, {query, categoryIds})`** — pure helper
  (new, `lib/core/utils/event_filter_utils.dart`). Category match first
  (`categoryIds` empty ⇒ all pass; else `event.categoryId ∈ categoryIds`), then
  normalized name/location contains-search. Used by Features 2 and 3 identically.

`/admin/events` is intentionally **left as-is** (no refactor — out of scope, avoids risk).

## Feature 1 — Date-range availability (`presentation/screens/user/availability_screen.dart`)

- Header button **"בחירה לפי טווח תאריכים"** (calendar icon) opens
  `DualCalendarDatePicker(isSingleDate: false, minDate: today,
  highlightedDates: <every day covered by the eligible future events>)`.
- On confirm `{startDate, endDate}` (endDate null ⇒ single-day range): select every
  **eligible future event** (the screen's `_futureEvents` set) whose date span overlaps
  `[startDate, endDate]` (`event.startDate ≤ rangeEnd && event.endDate ≥ rangeStart`,
  date-only), and **union** their IDs into `availableEventIds`.
- **One batched `UpdateTeamMember`** via the existing `_runBlockingMutation` overlay;
  snackbar "נוספה זמינות ל-N אירועים", or an info snackbar when nothing new fell in range.
- Operates on all eligible future events, **independent of** the search/category filter
  (the date range is its own filter).

## Feature 1b — Date-range availability in the admin modal (`presentation/screens/team/team_list_screen.dart`)

Same date-range picker, second home: the admin's `/admin/team-members` → member modal
→ **"ערוך זמינות"** dialog (`_AdminAvailabilityDialog`), so an admin can set a
non-permanent member's availability by range on their behalf.

- A **"בחירה לפי טווח תאריכים"** button in the dialog header opens the same
  `DualCalendarDatePicker` (range, `highlightedDates` from the dialog's events).
- On confirm, **union** the in-range event IDs into the dialog's local `_selectedEventIds`
  (`setState`). Persistence is unchanged — it flows through the modal's existing staged
  `_availableEventIds` + `_isDirty` save path (no direct DB write from the dialog).
- Only the date-range button is added here (search/category/"select all" stay scoped to
  Features 2 and 3, per the request).

## Feature 2 — Search + filter + "בחר הכל" (`availability_screen.dart`)

- `EventSearchFilterBar` above the month-grouped list; the list renders
  `filterEventsBySearchAndCategory(_futureEvents, …)`.
- A row under the bar: **"בחר הכל"** button + **"נבחרו X מתוך Y"** count (Y = filtered
  count, X = how many of the filtered are already available). "בחר הכל" marks all
  currently-filtered events available in **one batched write**; when every filtered
  event is already available it flips to **"בטל בחירה"** (removes them) — reversible,
  no confirm modal.
- Filter state is **ephemeral** (local `setState`, resets on leaving the screen).

## Feature 3 — Search + filter + "בחר הכל" (`presentation/widgets/assignment_export_dialog.dart`)

- `EventSearchFilterBar` + the same helper inside `_buildPerEventContent`; the checkbox
  list renders the filtered subset. Local filter state on the dialog.
- The count line gains a **"בחר הכל" / "בטל בחירה"** toggle that adds/removes the
  **filtered** event IDs to/from `_selectedEventIds`. Export mode picker and `canExport`
  logic are unchanged (per-event still requires ≥1 selected).

## Cross-cutting

- **Batched writes** for every bulk op (single `UpdateTeamMember`), then real-time
  stream refreshes the checkboxes.
- **Select-all is a toggle** (select-all ⇄ clear) in Features 2 and 3.
- **Verification:** `flutter analyze` clean (zero *new* issues; ~108 pre-existing infos
  are the baseline). The user runs the app to test `/user/constraints` (non-permanent
  member) and the admin export dialog. A focused unit test for the pure helper may be added.
- **Out of scope:** refactoring `/admin/events`, cross-session filter persistence,
  any backend / Cloud Functions change (none needed).
