# Summary Events Calendar Share — Design

**Date**: 2026-07-05
**Branch**: `feat/summary-events-calendar-share`
**Status**: Approved by Omer (sections 1–3 approved in brainstorming session)

## Overview

A new export feature on the `/summary` screen (מסך מנהלים): the user picks a date
range, chooses a weekly or monthly presentation, and gets a calendar image of all
events in that range — each event showing its name, its Google-Calendar-style time
ranges, and its location. The image is shared/copied as PNG through the exact same
pipeline as the existing "שתף תמונת שיבוצים" feature.

**Primary consumer**: the user's boss, who receives the image (e.g. via WhatsApp).
The exported PNG is the product; the on-screen preview is a review surface, not an
interactive calendar.

## Requirements (as clarified)

1. Entry point lives on the `/summary` screen. No new permission flag — the
   feature sits behind the existing `/summary` gating (`isAdmin` or
   `canAccessSummaryScreen`).
2. Flow: pick **date range** first → then choose **שבועי (weeks)** or
   **חודשי (months)** presentation → preview → share/copy as PNG.
3. Every non-deactivated event occurring in the range appears. (Revised
   2026-07-05, supersedes the original no-colors decision:) events whose
   category has a color (`Category.colorValue`, added the same day) are
   tinted with a pale version of that color, and the card shows a compact
   legend (color dot + category name) under the header for the colored
   categories present in range; colorless/uncategorized events keep the
   neutral gray style.
4. Per event: name, time range(s) **matching the Google Calendar sync semantics**
   (see Time semantics), and location (coordinates stripped).
5. Past events (relative to today) appear with full details but **visually muted**
   (grayed / reduced opacity).
6. Export is **PNG only** — share sheet + copy-to-clipboard + manual-screenshot
   fallback, identical to the assignments-image feature. No PDF.
7. Range length capped at **6 calendar months**: `rangeEnd` must be strictly
   before `DateTime(rangeStart.year, rangeStart.month + 6, rangeStart.day)`.

## Non-goals

- No interactive on-screen calendar (no tapping events, no live browsing). The
  architecture leaves room for one later (see Future extensions).
- No PDF export.
- No new Firestore queries, collections, indexes, or `DatabaseInterface` changes.
- No recurring-event logic (the app has none; repeats are explicit duplicates).

## Architecture

All new UI code under `lib/presentation/screens/summary/widgets/calendar_share/`,
mirroring the assignments-share layout (models / builder / card / preview kept
separate):

| File | Responsibility |
|---|---|
| `calendar_share_models.dart` | Pure data classes: `CalendarShareMode {weeks, months}`, `CalendarShareData`, `CalendarShareMonth`, `CalendarShareWeek`, `CalendarShareDay`, `CalendarShareEvent`. No entity/widget/bloc imports. Plain immutable classes (they never enter bloc states, so the Equatable-props rule does not apply — same as `EventAssignmentsShareData`). |
| `calendar_share_data_builder.dart` | Pure function: `build(List<Event> events, List<Category> categories, DateTime rangeStart, DateTime rangeEnd, CalendarShareMode mode, DateTime today) → CalendarShareData`. All business logic (filtering, bucketing, time formatting, week/month partitioning, category colors + legend) lives here. `today` is a parameter for testability. |
| `calendar_share_card.dart` | Fixed-width (1080 logical px) RTL widget rendering `CalendarShareData`. This is the capture target. Zero knowledge of entities/blocs/Firestore. |
| `calendar_share_flow_dialog.dart` | Two-step wizard: step 1 date range, step 2 mode choice. |
| `calendar_share_preview_dialog.dart` | Thin wrapper over the shared `SharePreviewDialog` (see below), supplying the calendar card, titles, filename, and Logger action names. |

**Shared preview extraction** (decision revised 2026-07-05, supersedes the
original "pattern-copy" approach): the capture/share machinery currently
private to `EventAssignmentsSharePreviewDialog` (`RepaintBoundary` → PNG →
share/copy → status messages → button row) is lifted into a new generic
`lib/presentation/widgets/share_preview_dialog.dart` (`SharePreviewDialog`),
parameterized by card widget, titles, filename, and Logger action names.
`EventAssignmentsSharePreviewDialog` keeps its exact public API and becomes a
thin wrapper delegating to it — zero call-site changes to the assignments
feature. The calendar preview is a second thin wrapper. Rationale: the two
dialogs differ only in data; the ~200-line behavior core is identical, and a
third share surface is plausible.

**Entry point**: new `Icons.calendar_month` action button in the SummaryScreen
AppBar (tooltip "לוח אירועים"), alongside the existing home/logout actions. Shows
a spinner while preparing (parity with `_isPreparingShare` in
`event_assignments_dialog.dart`).

### Data flow

1. Button tap reads events from `EventBloc` state (already loaded and streaming
   live on `/summary`). If the state is not `EventsLoaded`, fall back to a
   one-shot `EventRepository.getAllEvents()`.
2. Wizard collects `(rangeStart, rangeEnd, mode)`.
3. `CalendarShareDataBuilder` produces the snapshot.
4. Preview dialog renders `CalendarShareCard` inside a `RepaintBoundary`, captures
   via `renderObject.toImage(pixelRatio: 1.0)` → PNG bytes → existing
   `AssignmentShareImageService.sharePng/copyPng`.

The preview is a **static snapshot** by design — no real-time subscription,
exactly like the assignments share preview.

### Builder rules

- **Inclusion**: `!event.isDeactivated` and `event.occursOn(day)` for at least one
  day in `[rangeStart, rangeEnd]`. Day bucketing uses `occursOn()` per day —
  deliberately NOT `getEventsByDateRange`, which filters on `startDate` only and
  drops multi-day events that start before the range
  (`firestore_database.dart:614-615`).
- **Day identity**: Israel calendar days via `IsraelCalendar.calendarDay` — event
  `startDate`/`endDate` are already Israel-day normalized; `today` must be
  projected the same way so users abroad don't get off-by-one muting.
- **Past**: an event is past iff its `endDate` (Israel day) is strictly before
  `today`. Whole event blocks are muted on every day they appear.
- **Multi-day events**: appear on every day they occur. Full details (times +
  location) render on the event's **first in-range day**; on subsequent days,
  name + "(המשך)" only.
- **Within-day ordering**: existing `compareEventsChronologically` (empty times
  sort last).
- **Weeks partition**: from the Sunday on/before `rangeStart` through the Saturday
  on/after `rangeEnd` (week starts Sunday, per app convention). Days inside a
  strip but outside the picked range are marked out-of-range.
- **Months partition**: one grid per calendar month intersecting the range. Cells
  outside the month render completely blank (no day number); in-month days outside
  the picked range are marked out-of-range.

### Time semantics (mirror of `calendar_sync_service.dart:340-368`)

```
separator = actualShowStartTime.isNotEmpty ? actualShowStartTime : startTime
allDay    = assemblyTime.isEmpty || endTime.isEmpty
```

- If `allDay` → single line: **"כל היום"**.
- Else:
  - Assembly line, if `assemblyTime.isNotEmpty && separator.isNotEmpty`:
    **"התייצבות {assemblyTime}"** — the assembly END time is deliberately
    omitted (revised 2026-07-05): it always equals the מופע start shown on the
    next line, and the full range made the line wrap in day cells.
  - Main line, if `endTime.isNotEmpty && (separator.isNotEmpty || assemblyTime.isNotEmpty)`:
    **"מופע {effectiveStart}–{endTime}"** where
    `effectiveStart = separator.isNotEmpty ? separator : assemblyTime` — this
    mirrors the backend's main-event fallback (`calendar_integration.ts`,
    main event start), so the card matches the exact block Google Calendar
    shows even for events with only התייצבות + סיום.

Note (corrected 2026-07-05): ALL time fields are optional in the event form
(labeled "אופציונלי"), so the empty-separator case is reachable through the
UI — the original claim that `startTime` is form-required was wrong.
As a rendering safety net, the card wraps every time line in
`FittedBox(scaleDown)` so no time line can ever wrap to two lines.

## Rendering spec (`CalendarShareCard`)

- **Card**: width 1080, intrinsic height, white background, RTL `Directionality`,
  Rubik font — same visual language as `EventAssignmentsShareCard`. Header:
  "לוח אירועים" + Hebrew range string (via the existing `formatDateRange`-style
  month names). Footer: "נוצר משבצק".
- **Grid**: Flutter `Table` — each row's height grows to the tallest cell (busy
  days never truncate). Column order RTL: ראשון rightmost, שבת leftmost. Weekday
  header row (א׳–ש׳).
  - Weeks mode: one 7-column strip per week, stacked.
  - Months mode: month title ("יולי 2026") + full month grid, months stacked;
    identical day-cell widget with slightly smaller typography.
- **Day cell**: day number + short Hebrew day name at top; event blocks stacked
  beneath:

  ```
  שם האירוע               (w600)
  התייצבות 15:00
  מופע 17:00–22:30
  📍 גן הפסלים, חיפה
  ```

  Location via existing `MapLocationResult.stripCoordinates`.
- **Muting**: past event blocks at reduced opacity (~45%, tune visually); past
  day numbers slightly grayed. Out-of-range days: dimmed day number, no events. Out-of-month cells
  (months mode): blank.
- **Empty days** render as empty cells — an empty week is itself information.

## UX flow

1. AppBar button → `Logger.action` breadcrumbs at each step (parity with existing
   dialogs).
2. **Step 1 — range**: `DualCalendarDatePicker` in range mode, `highlightedDates`
   fed from loaded events (existing red-ring "has events" marker). No minimum
   date (past ranges allowed). Inline validation: range ≤ 6 calendar months.
3. **Step 2 — mode**: two choice tiles, שבועי / חודשי.
4. **Preview**: full-screen dialog, card scaled with `FittedBox`,
   `autoStartShare: true` (silent share attempt on open, parity with existing).
   Buttons **שתף** / **העתק תמונה**. Status messages identical to existing:
   "התמונה נשלחה לשיתוף" / "התמונה הועתקה. אפשר להדביק אותה בצ׳אט" /
   "אפשר לצלם את המסך הזה כתמונה אחת".
5. **Filename**: `shavtzak_events_calendar_<yyyy-MM-dd>_<yyyy-MM-dd>.png`.

## Error handling

- Events unavailable (bloc not `EventsLoaded` AND fallback fetch throws) →
  snackbar **"לא ניתן להכין לוח אירועים"**, flow closes (mirrors
  "לא ניתן להכין תמונת שיבוצים").
- Capture failure (`StateError` on non-`RepaintBoundary` render object, encode
  failure) → same `needsManualScreenshot` handling as today; the visible preview
  is the fallback.
- Empty range → calendar renders with empty cells; not an error.
- Range > 6 months → inline validation message in the picker step; cannot proceed.

## Drive-by fix

`DateUtils.formatDayMonth` has a Hebrew month typo `'סptמבר'`
(`lib/core/utils/date_utils.dart:32`; the array in `formatDateRange` at line 96
is spelled correctly). The feature reuses these month names for titles, so the
typo gets fixed as part of this work.

## Testing

- `flutter analyze` must pass (per CLAUDE.md; Omer runs the app himself for
  manual verification in test + production environments).
- Manual regression smoke: the existing "שתף תמונת שיבוצים" flow still
  previews/shares/copies correctly, since its dialog now delegates to the
  shared `SharePreviewDialog`.
- **Unit tests for `CalendarShareDataBuilder`** — the first tests in the repo.
  Pure Dart, no mocks/fakes needed. Coverage targets:
  - Time semantics: separator fallback (`actualShowStartTime` → `startTime`),
    all-day condition (`assemblyTime` or `endTime` empty), assembly/main line
    conditions, degraded "מופע עד" form.
  - Sunday-week partitioning (range edges mid-week; single-day range).
  - Month partitioning (range spanning month boundaries; out-of-month blanks vs
    out-of-range dimming).
  - Multi-day events: appears on each day; details on first in-range day;
    "(המשך)" on subsequent days; event starting before `rangeStart`.
  - Past-muting boundary: event ending yesterday vs today (Israel-day
    comparison).
  - `isDeactivated` exclusion; within-day chronological ordering.

## Future extensions (explicitly out of scope now)

- **Interactive calendar tab** on `/summary`: the data builder and day-cell
  widget are reusable for a responsive interactive view later.
- **PDF export**: would require `pdf`/`printing` packages + Rubik font embedding
  + RTL layout; the preview/card separation keeps a `CalendarShareData → PDF`
  exporter addable without touching the widget layer.
