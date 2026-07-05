# Summary Events Calendar Share Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From the `/summary` screen, let a user pick a date range, render all events in it as a weekly or monthly Hebrew RTL calendar card, and share/copy it as a PNG via the existing image pipeline.

**Architecture:** A pure data builder (`CalendarShareDataBuilder`) converts domain `Event`s into a dumb `CalendarShareData` snapshot; a fixed-width 1080px `CalendarShareCard` renders it; a pattern-copy of `EventAssignmentsSharePreviewDialog` captures it via `RepaintBoundary` → PNG → `AssignmentShareImageService`. A small flow function chains the existing `DualCalendarDatePicker` (range mode) → a new mode-choice dialog → the preview. Entry point is a new AppBar button on `SummaryScreen`.

**Tech Stack:** Flutter Web, existing packages only (no new dependencies). Tests with plain `flutter_test` (no mocks needed — the builder is pure).

**Spec:** `docs/superpowers/specs/2026-07-05-summary-events-calendar-share-design.md`

## Global Constraints

- All `flutter` commands run from the `shavtzak/` directory.
- UI text in Hebrew; code comments in English; every dialog/screen wrapped in `Directionality(textDirection: TextDirection.rtl)`.
- Card capture width is exactly **1080** logical px; capture at `pixelRatio: 1.0`.
- **No new pub dependencies.**
- Range cap: `rangeEnd` must be **strictly before** `DateTime(rangeStart.year, rangeStart.month + 6, rangeStart.day)`.
- Time semantics must mirror `lib/core/services/calendar_sync_service.dart:355-368` exactly: `separator = actualShowStartTime.isNotEmpty ? actualShowStartTime : startTime`; all-day iff `assemblyTime.isEmpty || endTime.isEmpty`.
- Day bucketing/`today` must use Israel calendar days (`IsraelCalendar.calendarDay`), never raw browser-local days.
- `flutter analyze` must report "No issues found!" at the end of every task.
- Exact user-facing strings are specified per task — copy them verbatim (Hebrew strings are load-bearing).
- Commit at the end of every task. End each commit message body with:
  ```
  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01CMBquhogf66jRNjeDE4ruS
  ```

---

### Task 1: Hebrew month names — shared list + typo fix in DateUtils

`lib/core/utils/date_utils.dart` has two duplicated hard-coded Hebrew month arrays; the one inside `formatDayMonth` contains a typo (`'סptמבר'` at line 32). The calendar feature needs month names for titles, so extract one correct shared list.

**Files:**
- Modify: `shavtzak/lib/core/utils/date_utils.dart`
- Test: `shavtzak/test/core/utils/date_utils_test.dart` (create)

**Interfaces:**
- Consumes: nothing new.
- Produces: `DateUtils.hebrewMonths` (`List<String>`, index 0 = ינואר) and `static String DateUtils.hebrewMonthName(int month)` (1-indexed). Later tasks import this as `app_date_utils.DateUtils.hebrewMonthName(...)`.

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/core/utils/date_utils_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/date_utils.dart';

void main() {
  group('DateUtils.hebrewMonthName', () {
    test('returns correct name for boundary and middle months', () {
      expect(DateUtils.hebrewMonthName(1), 'ינואר');
      expect(DateUtils.hebrewMonthName(9), 'ספטמבר');
      expect(DateUtils.hebrewMonthName(12), 'דצמבר');
    });
  });

  group('DateUtils.formatDayMonth', () {
    test('formats September without the legacy typo', () {
      expect(DateUtils.formatDayMonth(DateTime(2026, 9, 3)), '3 בספטמבר');
    });

    test('formats other months unchanged', () {
      expect(DateUtils.formatDayMonth(DateTime(2026, 7, 15)), '15 ביולי');
    });
  });

  group('DateUtils.formatDateRange', () {
    test('same-month format is unchanged', () {
      expect(
        DateUtils.formatDateRange(DateTime(2026, 9, 3), DateTime(2026, 9, 5)),
        '3-5 בספטמבר',
      );
    });

    test('cross-month format is unchanged', () {
      expect(
        DateUtils.formatDateRange(DateTime(2026, 9, 3), DateTime(2026, 10, 2)),
        '3 בספטמבר - 2 באוקטובר',
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd shavtzak && flutter test test/core/utils/date_utils_test.dart`
Expected: FAIL — `hebrewMonthName` isn't defined (compile error). That's the failing state.

- [ ] **Step 3: Implement**

In `shavtzak/lib/core/utils/date_utils.dart`:

Add inside `class DateUtils`, right above `formatDayMonth`:

```dart
  /// Hebrew month names. Index 0 = ינואר. Prefer [hebrewMonthName].
  static const List<String> hebrewMonths = [
    'ינואר',
    'פברואר',
    'מרץ',
    'אפריל',
    'מאי',
    'יוני',
    'יולי',
    'אוגוסט',
    'ספטמבר',
    'אוקטובר',
    'נובמבר',
    'דצמבר',
  ];

  /// Hebrew name for a 1-indexed month (1 = ינואר).
  static String hebrewMonthName(int month) => hebrewMonths[month - 1];
```

Replace the entire body of `formatDayMonth` (which contains the typo'd local array) with:

```dart
  /// Format date as day and month (e.g., "3 בספטמבר")
  static String formatDayMonth(DateTime date) {
    return '${date.day} ב${hebrewMonthName(date.month)}';
  }
```

In `formatDateRange`, delete the local `hebrewMonths` array (the correctly-spelled one) and change its usage line from:

```dart
      return '${start.day}-${end.day} ב${hebrewMonths[start.month - 1]}';
```

to:

```dart
      return '${start.day}-${end.day} ב${hebrewMonthName(start.month)}';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd shavtzak && flutter test test/core/utils/date_utils_test.dart`
Expected: PASS (all tests green).

- [ ] **Step 5: Analyze and commit**

Run: `cd shavtzak && flutter analyze`
Expected: `No issues found!`

```bash
git add shavtzak/lib/core/utils/date_utils.dart shavtzak/test/core/utils/date_utils_test.dart
git commit -m "fix(utils): extract shared Hebrew month names, fix ספטמבר typo"
```

---

### Task 2: Calendar share models + per-event time-line semantics

Create the pure model classes and the event-level share formatting (gcal-mirroring time lines, location stripping, past flag, continuation).

**Files:**
- Create: `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_models.dart`
- Create: `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_data_builder.dart`
- Test: `shavtzak/test/presentation/screens/summary/calendar_share_data_builder_test.dart` (create)

**Interfaces:**
- Consumes: `Event` entity (`lib/domain/entities/event.dart`), `MapLocationResult.stripCoordinates` (`lib/presentation/widgets/map_location_picker.dart`).
- Produces (used by Tasks 3–7):
  - `enum CalendarShareMode { weeks, months }`
  - `CalendarShareEvent({required String name, List<String> timeLines = const [], String locationLine = '', required bool isPast, bool isContinuation = false})`
  - `CalendarShareDay({required DateTime date, required bool inRange, required bool isPast, List<CalendarShareEvent> events = const []})`
  - `CalendarShareWeek({required List<CalendarShareDay?> days})` — exactly 7 entries, index 0 = Sunday; `null` = blank cell.
  - `CalendarShareMonth({required String title, required List<CalendarShareWeek> weeks})`
  - `CalendarShareData({required String rangeTitle, required CalendarShareMode mode, List<CalendarShareWeek> weeks = const [], List<CalendarShareMonth> months = const []})`
  - `static CalendarShareEvent CalendarShareDataBuilder.buildShareEvent(Event event, {required DateTime today, required bool isContinuation})`

- [ ] **Step 1: Create the models file**

Create `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_models.dart`:

```dart
/// Pure data snapshot for the events-calendar share card.
///
/// Plain immutable classes with no entity/widget/bloc imports — the card
/// renders these with zero knowledge of Firestore or domain entities (same
/// discipline as EventAssignmentsShareData). They never enter bloc states,
/// so Equatable is intentionally not used.

enum CalendarShareMode { weeks, months }

class CalendarShareEvent {
  final String name;

  /// 0–2 lines, e.g. 'התייצבות 15:00–17:00' / 'מופע 17:00–22:30', or a single
  /// 'כל היום'. Empty on continuation days.
  final List<String> timeLines;

  /// Display location with hidden coordinates stripped. Empty when absent or
  /// on continuation days.
  final String locationLine;

  final bool isPast;

  /// True on the 2nd+ visible day of a multi-day event ("(המשך)" rendering).
  final bool isContinuation;

  const CalendarShareEvent({
    required this.name,
    this.timeLines = const [],
    this.locationLine = '',
    required this.isPast,
    this.isContinuation = false,
  });
}

class CalendarShareDay {
  final DateTime date;

  /// False for days padding a week/month grid outside the picked range —
  /// rendered dimmed with no events.
  final bool inRange;

  final bool isPast;
  final List<CalendarShareEvent> events;

  const CalendarShareDay({
    required this.date,
    required this.inRange,
    required this.isPast,
    this.events = const [],
  });
}

class CalendarShareWeek {
  /// Exactly 7 entries, index 0 = Sunday. Null = blank cell (months mode,
  /// out-of-month).
  final List<CalendarShareDay?> days;

  const CalendarShareWeek({required this.days});
}

class CalendarShareMonth {
  /// e.g. 'יולי 2026'
  final String title;
  final List<CalendarShareWeek> weeks;

  const CalendarShareMonth({required this.title, required this.weeks});
}

class CalendarShareData {
  /// e.g. '5–31 ביולי 2026'
  final String rangeTitle;
  final CalendarShareMode mode;

  /// Populated in weeks mode; empty in months mode.
  final List<CalendarShareWeek> weeks;

  /// Populated in months mode; empty in weeks mode.
  final List<CalendarShareMonth> months;

  const CalendarShareData({
    required this.rangeTitle,
    required this.mode,
    this.weeks = const [],
    this.months = const [],
  });
}
```

- [ ] **Step 2: Write the failing tests**

Create `shavtzak/test/presentation/screens/summary/calendar_share_data_builder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/presentation/screens/summary/widgets/calendar_share/calendar_share_data_builder.dart';

Event makeEvent({
  String id = 'e1',
  String name = 'אירוע בדיקה',
  DateTime? startDate,
  DateTime? endDate,
  String startTime = '17:00',
  String endTime = '22:30',
  String assemblyTime = '15:00',
  String actualShowStartTime = '',
  String location = 'גן הפסלים||32.794000,34.989600',
  bool isDeactivated = false,
}) {
  final start = startDate ?? DateTime(2026, 7, 15);
  return Event(
    id: id,
    name: name,
    startDate: start,
    endDate: endDate ?? start,
    startTime: startTime,
    endTime: endTime,
    assemblyTime: assemblyTime,
    actualShowStartTime: actualShowStartTime,
    location: location,
    requiresArmed: false,
    roleRequirements: const {},
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    isDeactivated: isDeactivated,
  );
}

// 2026-07-05 is a Sunday.
final today = DateTime(2026, 7, 5);

void main() {
  group('buildShareEvent — time semantics (mirror of calendar sync)', () {
    test('assembly + main lines when all times present', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(),
        today: today,
        isContinuation: false,
      );
      expect(share.timeLines, ['התייצבות 15:00–17:00', 'מופע 17:00–22:30']);
    });

    test('actualShowStartTime overrides startTime as separator', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(actualShowStartTime: '18:00'),
        today: today,
        isContinuation: false,
      );
      expect(share.timeLines, ['התייצבות 15:00–18:00', 'מופע 18:00–22:30']);
    });

    test('all-day when assemblyTime is empty', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(assemblyTime: ''),
        today: today,
        isContinuation: false,
      );
      expect(share.timeLines, ['כל היום']);
    });

    test('all-day when endTime is empty', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(endTime: ''),
        today: today,
        isContinuation: false,
      );
      expect(share.timeLines, ['כל היום']);
    });

    test('degraded main line when separator is empty (legacy data)', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(startTime: '', actualShowStartTime: ''),
        today: today,
        isContinuation: false,
      );
      expect(share.timeLines, ['מופע עד 22:30']);
    });
  });

  group('buildShareEvent — location, past, continuation', () {
    test('strips hidden coordinates from location', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(),
        today: today,
        isContinuation: false,
      );
      expect(share.locationLine, 'גן הפסלים');
    });

    test('empty location yields empty locationLine', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(location: ''),
        today: today,
        isContinuation: false,
      );
      expect(share.locationLine, '');
    });

    test('isPast is true only when endDate is strictly before today', () {
      final past = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(startDate: DateTime(2026, 7, 4)),
        today: today,
        isContinuation: false,
      );
      final todayEvent = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(startDate: DateTime(2026, 7, 5)),
        today: today,
        isContinuation: false,
      );
      expect(past.isPast, isTrue);
      expect(todayEvent.isPast, isFalse);
    });

    test('continuation carries name only', () {
      final share = CalendarShareDataBuilder.buildShareEvent(
        makeEvent(
          startDate: DateTime(2026, 7, 8),
          endDate: DateTime(2026, 7, 10),
        ),
        today: today,
        isContinuation: true,
      );
      expect(share.isContinuation, isTrue);
      expect(share.timeLines, isEmpty);
      expect(share.locationLine, '');
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd shavtzak && flutter test test/presentation/screens/summary/calendar_share_data_builder_test.dart`
Expected: FAIL — `calendar_share_data_builder.dart` doesn't exist yet (compile error).

- [ ] **Step 4: Implement the builder (event-level only)**

Create `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_data_builder.dart`:

```dart
import '../../../../../domain/entities/event.dart';
import '../../../../widgets/map_location_picker.dart';
import 'calendar_share_models.dart';

/// Builds the pure CalendarShareData snapshot from domain events.
///
/// Time semantics mirror calendar_sync_service.syncAppEventToCalendar:
///   separator = actualShowStartTime if non-empty, else startTime
///   allDay    = assemblyTime.isEmpty || endTime.isEmpty
class CalendarShareDataBuilder {
  static CalendarShareEvent buildShareEvent(
    Event event, {
    required DateTime today,
    required bool isContinuation,
  }) {
    final isPast = _dateOnly(event.endDate).isBefore(today);
    if (isContinuation) {
      return CalendarShareEvent(
        name: event.name,
        isPast: isPast,
        isContinuation: true,
      );
    }
    final location = event.location.trim().isEmpty
        ? ''
        : MapLocationResult.stripCoordinates(event.location).trim();
    return CalendarShareEvent(
      name: event.name,
      timeLines: _buildTimeLines(event),
      locationLine: location,
      isPast: isPast,
    );
  }

  static List<String> _buildTimeLines(Event event) {
    final assemblyTime = event.assemblyTime.trim();
    final endTime = event.endTime.trim();
    final actualShowStartTime = event.actualShowStartTime.trim();
    final startTime = event.startTime.trim();

    final separator =
        actualShowStartTime.isNotEmpty ? actualShowStartTime : startTime;
    final allDay = assemblyTime.isEmpty || endTime.isEmpty;
    if (allDay) {
      return const ['כל היום'];
    }

    final lines = <String>[];
    if (assemblyTime.isNotEmpty && separator.isNotEmpty) {
      lines.add('התייצבות $assemblyTime–$separator');
    }
    if (endTime.isNotEmpty &&
        (separator.isNotEmpty || assemblyTime.isNotEmpty)) {
      lines.add(
        separator.isNotEmpty ? 'מופע $separator–$endTime' : 'מופע עד $endTime',
      );
    }
    return lines;
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd shavtzak && flutter test test/presentation/screens/summary/calendar_share_data_builder_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze and commit**

Run: `cd shavtzak && flutter analyze`
Expected: `No issues found!`

```bash
git add shavtzak/lib/presentation/screens/summary/widgets/calendar_share/ shavtzak/test/presentation/screens/summary/
git commit -m "feat(summary): calendar share models + gcal-mirroring event time lines"
```

---

### Task 3: build() weeks mode — Sunday partition, day bucketing, range title

**Files:**
- Modify: `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_data_builder.dart`
- Test: `shavtzak/test/presentation/screens/summary/calendar_share_data_builder_test.dart`

**Interfaces:**
- Consumes: Task 1's `DateUtils.hebrewMonthName`, Task 2's models and `buildShareEvent`, `compareEventsChronologically` (`lib/core/utils/event_sorting.dart`), `Event.occursOn`.
- Produces: `static CalendarShareData CalendarShareDataBuilder.build({required List<Event> events, required DateTime rangeStart, required DateTime rangeEnd, required CalendarShareMode mode, required DateTime today})`. Weeks mode fully works; months mode throws `UnimplementedError` until Task 4.

- [ ] **Step 1: Add the failing tests**

Append inside `main()` of the test file (calendar facts used: 2026-07-05=Sunday, 2026-07-06=Monday, 2026-07-08=Wednesday, 2026-07-15=Wednesday, 2026-07-18=Saturday):

```dart
  group('build — weeks mode', () {
    test('pads to full Sunday-start weeks and flags out-of-range days', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 6), // Monday
        rangeEnd: DateTime(2026, 7, 15), // Wednesday
        mode: CalendarShareMode.weeks,
        today: today,
      );
      expect(data.mode, CalendarShareMode.weeks);
      expect(data.months, isEmpty);
      expect(data.weeks, hasLength(2));

      final firstDay = data.weeks.first.days.first!;
      expect(firstDay.date, DateTime(2026, 7, 5)); // padded Sunday
      expect(firstDay.inRange, isFalse);

      final lastDay = data.weeks.last.days.last!;
      expect(lastDay.date, DateTime(2026, 7, 18)); // padded Saturday
      expect(lastDay.inRange, isFalse);

      expect(data.weeks.first.days[1]!.inRange, isTrue); // Monday 6.7

      for (final week in data.weeks) {
        expect(week.days, hasLength(7));
        expect(week.days.whereType<CalendarShareDay>(), hasLength(7));
      }
    });

    test('single-day range yields a single week', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 8),
        rangeEnd: DateTime(2026, 7, 8),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      expect(data.weeks, hasLength(1));
      final inRangeDays = data.weeks.first.days
          .whereType<CalendarShareDay>()
          .where((d) => d.inRange)
          .toList();
      expect(inRangeDays, hasLength(1));
      expect(inRangeDays.single.date, DateTime(2026, 7, 8));
    });

    test('day.isPast is true strictly before today', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 4),
        rangeEnd: DateTime(2026, 7, 6),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      final days = <DateTime, CalendarShareDay>{
        for (final w in data.weeks)
          for (final d in w.days)
            if (d != null) d.date: d,
      };
      expect(days[DateTime(2026, 7, 4)]!.isPast, isTrue);
      expect(days[DateTime(2026, 7, 5)]!.isPast, isFalse);
    });

    test('event appears on its day with details', () {
      final data = CalendarShareDataBuilder.build(
        events: [makeEvent(startDate: DateTime(2026, 7, 8))],
        rangeStart: DateTime(2026, 7, 6),
        rangeEnd: DateTime(2026, 7, 15),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      final wednesday = data.weeks.first.days[3]!; // index 3 = Wednesday
      expect(wednesday.date, DateTime(2026, 7, 8));
      expect(wednesday.events, hasLength(1));
      expect(wednesday.events.single.name, 'אירוע בדיקה');
      expect(wednesday.events.single.isContinuation, isFalse);
      expect(wednesday.events.single.timeLines, isNotEmpty);
    });

    test('multi-day event: details on first day, continuation after', () {
      final data = CalendarShareDataBuilder.build(
        events: [
          makeEvent(
            startDate: DateTime(2026, 7, 8),
            endDate: DateTime(2026, 7, 10),
          ),
        ],
        rangeStart: DateTime(2026, 7, 6),
        rangeEnd: DateTime(2026, 7, 15),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      final week = data.weeks.first;
      expect(week.days[3]!.events.single.isContinuation, isFalse); // 8.7
      expect(week.days[4]!.events.single.isContinuation, isTrue); // 9.7
      expect(week.days[5]!.events.single.isContinuation, isTrue); // 10.7
      expect(week.days[6]!.events, isEmpty); // 11.7
    });

    test('multi-day event starting before range: details on first in-range day',
        () {
      final data = CalendarShareDataBuilder.build(
        events: [
          makeEvent(
            startDate: DateTime(2026, 7, 4),
            endDate: DateTime(2026, 7, 8),
          ),
        ],
        rangeStart: DateTime(2026, 7, 6),
        rangeEnd: DateTime(2026, 7, 15),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      final week = data.weeks.first;
      expect(week.days[0]!.events, isEmpty); // 5.7 out of range
      expect(week.days[1]!.events.single.isContinuation, isFalse); // 6.7
      expect(week.days[2]!.events.single.isContinuation, isTrue); // 7.7
      expect(week.days[3]!.events.single.isContinuation, isTrue); // 8.7
    });

    test('deactivated events are excluded', () {
      final data = CalendarShareDataBuilder.build(
        events: [makeEvent(startDate: DateTime(2026, 7, 8), isDeactivated: true)],
        rangeStart: DateTime(2026, 7, 6),
        rangeEnd: DateTime(2026, 7, 15),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      for (final week in data.weeks) {
        for (final day in week.days) {
          expect(day!.events, isEmpty);
        }
      }
    });

    test('events within a day are chronologically ordered', () {
      final late = makeEvent(
        id: 'late',
        name: 'מאוחר',
        startDate: DateTime(2026, 7, 8),
        assemblyTime: '18:00',
        startTime: '19:00',
        endTime: '23:00',
      );
      final early = makeEvent(
        id: 'early',
        name: 'מוקדם',
        startDate: DateTime(2026, 7, 8),
        assemblyTime: '08:00',
        startTime: '09:00',
        endTime: '12:00',
      );
      final data = CalendarShareDataBuilder.build(
        events: [late, early], // intentionally unsorted
        rangeStart: DateTime(2026, 7, 8),
        rangeEnd: DateTime(2026, 7, 8),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      final day = data.weeks.first.days
          .whereType<CalendarShareDay>()
          .firstWhere((d) => d.inRange);
      expect(day.events.map((e) => e.name).toList(), ['מוקדם', 'מאוחר']);
    });
  });

  group('build — range title', () {
    test('same month', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 5),
        rangeEnd: DateTime(2026, 7, 31),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      expect(data.rangeTitle, '5–31 ביולי 2026');
    });

    test('cross month, same year', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 20),
        rangeEnd: DateTime(2026, 8, 3),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      expect(data.rangeTitle, '20 ביולי – 3 באוגוסט 2026');
    });

    test('cross year', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 12, 15),
        rangeEnd: DateTime(2027, 1, 10),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      expect(data.rangeTitle, '15 בדצמבר 2026 – 10 בינואר 2027');
    });

    test('single day', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 8),
        rangeEnd: DateTime(2026, 7, 8),
        mode: CalendarShareMode.weeks,
        today: today,
      );
      expect(data.rangeTitle, '8 ביולי 2026');
    });
  });
```

- [ ] **Step 2: Run tests to verify the new group fails**

Run: `cd shavtzak && flutter test test/presentation/screens/summary/calendar_share_data_builder_test.dart`
Expected: FAIL — `build` is not defined.

- [ ] **Step 3: Implement build() for weeks mode**

In `calendar_share_data_builder.dart`, add imports at the top:

```dart
import '../../../../../core/utils/date_utils.dart' as app_date_utils;
import '../../../../../core/utils/event_sorting.dart';
```

Add inside `CalendarShareDataBuilder`, above `buildShareEvent`:

```dart
  static CalendarShareData build({
    required List<Event> events,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required CalendarShareMode mode,
    required DateTime today,
  }) {
    final start = _dateOnly(rangeStart);
    final end = _dateOnly(rangeEnd);
    final active = events.where((e) => !e.isDeactivated).toList()
      ..sort(compareEventsChronologically);
    final rangeTitle = _formatRangeTitle(start, end);

    if (mode == CalendarShareMode.weeks) {
      return CalendarShareData(
        rangeTitle: rangeTitle,
        mode: mode,
        weeks: _buildWeeks(
          gridStart: _sundayOnOrBefore(start),
          gridEnd: _saturdayOnOrAfter(end),
          rangeStart: start,
          rangeEnd: end,
          monthBounds: null,
          events: active,
          today: today,
        ),
      );
    }
    // Months mode is implemented in the next task.
    throw UnimplementedError('months mode not implemented yet');
  }

  /// One week per row from [gridStart] (a Sunday) to [gridEnd] (a Saturday).
  /// When [monthBounds] is set (months mode), days outside it become null
  /// (blank cells); days outside [rangeStart..rangeEnd] carry inRange=false.
  static List<CalendarShareWeek> _buildWeeks({
    required DateTime gridStart,
    required DateTime gridEnd,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required ({DateTime first, DateTime last})? monthBounds,
    required List<Event> events,
    required DateTime today,
  }) {
    final weeks = <CalendarShareWeek>[];
    var cursor = gridStart;
    while (!cursor.isAfter(gridEnd)) {
      final days = <CalendarShareDay?>[];
      for (var i = 0; i < 7; i++) {
        final date = _addDays(cursor, i);
        final inMonth = monthBounds == null ||
            (!date.isBefore(monthBounds.first) &&
                !date.isAfter(monthBounds.last));
        if (!inMonth) {
          days.add(null);
          continue;
        }
        final inRange =
            !date.isBefore(rangeStart) && !date.isAfter(rangeEnd);
        days.add(CalendarShareDay(
          date: date,
          inRange: inRange,
          isPast: date.isBefore(today),
          events: inRange
              ? _eventsForDay(events, date, rangeStart, today)
              : const [],
        ));
      }
      weeks.add(CalendarShareWeek(days: days));
      cursor = _addDays(cursor, 7);
    }
    return weeks;
  }

  static List<CalendarShareEvent> _eventsForDay(
    List<Event> events,
    DateTime date,
    DateTime rangeStart,
    DateTime today,
  ) {
    final result = <CalendarShareEvent>[];
    for (final event in events) {
      if (!event.occursOn(date)) {
        continue;
      }
      final eventStart = _dateOnly(event.startDate);
      final firstVisibleDay =
          eventStart.isBefore(rangeStart) ? rangeStart : eventStart;
      result.add(buildShareEvent(
        event,
        today: today,
        isContinuation: date.isAfter(firstVisibleDay),
      ));
    }
    return result;
  }

  static String _formatRangeTitle(DateTime start, DateTime end) {
    final startMonth = app_date_utils.DateUtils.hebrewMonthName(start.month);
    final endMonth = app_date_utils.DateUtils.hebrewMonthName(end.month);
    if (start.year == end.year && start.month == end.month) {
      if (start.day == end.day) {
        return '${start.day} ב$startMonth ${start.year}';
      }
      return '${start.day}–${end.day} ב$startMonth ${start.year}';
    }
    if (start.year == end.year) {
      return '${start.day} ב$startMonth – ${end.day} ב$endMonth ${start.year}';
    }
    return '${start.day} ב$startMonth ${start.year} – '
        '${end.day} ב$endMonth ${end.year}';
  }

  /// Dart weekday: Mon=1..Sun=7, so weekday % 7 is days-since-Sunday.
  static DateTime _sundayOnOrBefore(DateTime date) =>
      _addDays(date, -(date.weekday % 7));

  static DateTime _saturdayOnOrAfter(DateTime date) =>
      _addDays(date, 6 - (date.weekday % 7));

  /// Constructor arithmetic (not Duration) so DST shifts can't move midnight.
  static DateTime _addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd shavtzak && flutter test test/presentation/screens/summary/calendar_share_data_builder_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Analyze and commit**

Run: `cd shavtzak && flutter analyze`
Expected: `No issues found!`

```bash
git add shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_data_builder.dart shavtzak/test/presentation/screens/summary/calendar_share_data_builder_test.dart
git commit -m "feat(summary): calendar share builder — weeks partition, day bucketing, range title"
```

---

### Task 4: build() months mode

**Files:**
- Modify: `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_data_builder.dart`
- Test: `shavtzak/test/presentation/screens/summary/calendar_share_data_builder_test.dart`

**Interfaces:**
- Consumes: Task 3's `_buildWeeks` (with `monthBounds`), Task 1's `hebrewMonthName`.
- Produces: `build(..., mode: CalendarShareMode.months)` returns `CalendarShareData.months` populated; `weeks` empty.

- [ ] **Step 1: Add the failing tests**

Append inside `main()` (calendar facts: 2026-07-01=Wednesday, 2026-08-01=Saturday):

```dart
  group('build — months mode', () {
    test('one grid per calendar month intersecting the range', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 20),
        rangeEnd: DateTime(2026, 8, 3),
        mode: CalendarShareMode.months,
        today: today,
      );
      expect(data.mode, CalendarShareMode.months);
      expect(data.weeks, isEmpty);
      expect(data.months, hasLength(2));
      expect(data.months[0].title, 'יולי 2026');
      expect(data.months[1].title, 'אוגוסט 2026');
    });

    test('out-of-month cells are null, out-of-range days are dimmed', () {
      final data = CalendarShareDataBuilder.build(
        events: const [],
        rangeStart: DateTime(2026, 7, 20),
        rangeEnd: DateTime(2026, 8, 3),
        mode: CalendarShareMode.months,
        today: today,
      );
      final july = data.months[0];
      // 2026-07-01 is a Wednesday: Sun/Mon/Tue of the first week are blank.
      expect(july.weeks.first.days[0], isNull);
      expect(july.weeks.first.days[1], isNull);
      expect(july.weeks.first.days[2], isNull);
      expect(july.weeks.first.days[3]!.date, DateTime(2026, 7, 1));
      expect(july.weeks.first.days[3]!.inRange, isFalse); // before 20.7
      // A day inside the picked range:
      final allJulyDays = july.weeks
          .expand((w) => w.days)
          .whereType<CalendarShareDay>()
          .toList();
      expect(
        allJulyDays.firstWhere((d) => d.date == DateTime(2026, 7, 20)).inRange,
        isTrue,
      );
      // Every in-month day belongs to July.
      for (final d in allJulyDays) {
        expect(d.date.month, 7);
      }
    });

    test('events land in the right month grid', () {
      final data = CalendarShareDataBuilder.build(
        events: [
          makeEvent(id: 'jul', name: 'ביולי', startDate: DateTime(2026, 7, 25)),
          makeEvent(id: 'aug', name: 'באוגוסט', startDate: DateTime(2026, 8, 1)),
        ],
        rangeStart: DateTime(2026, 7, 20),
        rangeEnd: DateTime(2026, 8, 3),
        mode: CalendarShareMode.months,
        today: today,
      );
      final julyEvents = data.months[0].weeks
          .expand((w) => w.days)
          .whereType<CalendarShareDay>()
          .expand((d) => d.events)
          .map((e) => e.name)
          .toList();
      final augustEvents = data.months[1].weeks
          .expand((w) => w.days)
          .whereType<CalendarShareDay>()
          .expand((d) => d.events)
          .map((e) => e.name)
          .toList();
      expect(julyEvents, ['ביולי']);
      expect(augustEvents, ['באוגוסט']);
    });

    test('event spanning a month boundary continues into the next grid', () {
      final data = CalendarShareDataBuilder.build(
        events: [
          makeEvent(
            startDate: DateTime(2026, 7, 31),
            endDate: DateTime(2026, 8, 2),
          ),
        ],
        rangeStart: DateTime(2026, 7, 20),
        rangeEnd: DateTime(2026, 8, 3),
        mode: CalendarShareMode.months,
        today: today,
      );
      final jul31 = data.months[0].weeks
          .expand((w) => w.days)
          .whereType<CalendarShareDay>()
          .firstWhere((d) => d.date == DateTime(2026, 7, 31));
      final aug1 = data.months[1].weeks
          .expand((w) => w.days)
          .whereType<CalendarShareDay>()
          .firstWhere((d) => d.date == DateTime(2026, 8, 1));
      expect(jul31.events.single.isContinuation, isFalse);
      expect(aug1.events.single.isContinuation, isTrue);
    });
  });
```

- [ ] **Step 2: Run tests to verify the new group fails**

Run: `cd shavtzak && flutter test test/presentation/screens/summary/calendar_share_data_builder_test.dart`
Expected: FAIL — `UnimplementedError: months mode not implemented yet`.

- [ ] **Step 3: Implement months mode**

In `build()`, replace:

```dart
    // Months mode is implemented in the next task.
    throw UnimplementedError('months mode not implemented yet');
```

with:

```dart
    return CalendarShareData(
      rangeTitle: rangeTitle,
      mode: mode,
      months: _buildMonths(
        rangeStart: start,
        rangeEnd: end,
        events: active,
        today: today,
      ),
    );
```

Add the private helper below `_buildWeeks`:

```dart
  static List<CalendarShareMonth> _buildMonths({
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required List<Event> events,
    required DateTime today,
  }) {
    final months = <CalendarShareMonth>[];
    var year = rangeStart.year;
    var month = rangeStart.month;
    while (year < rangeEnd.year ||
        (year == rangeEnd.year && month <= rangeEnd.month)) {
      final firstOfMonth = DateTime(year, month, 1);
      final lastOfMonth = DateTime(year, month + 1, 0);
      months.add(CalendarShareMonth(
        title: '${app_date_utils.DateUtils.hebrewMonthName(month)} $year',
        weeks: _buildWeeks(
          gridStart: _sundayOnOrBefore(firstOfMonth),
          gridEnd: _saturdayOnOrAfter(lastOfMonth),
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
          monthBounds: (first: firstOfMonth, last: lastOfMonth),
          events: events,
          today: today,
        ),
      ));
      month++;
      if (month == 13) {
        month = 1;
        year++;
      }
    }
    return months;
  }
```

- [ ] **Step 4: Run all builder tests to verify they pass**

Run: `cd shavtzak && flutter test test/presentation/screens/summary/calendar_share_data_builder_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze and commit**

Run: `cd shavtzak && flutter analyze`
Expected: `No issues found!`

```bash
git add shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_data_builder.dart shavtzak/test/presentation/screens/summary/calendar_share_data_builder_test.dart
git commit -m "feat(summary): calendar share builder — months mode grids"
```

---

### Task 5: CalendarShareCard — the 1080px render widget

Pure rendering of `CalendarShareData`; visual verification only (no unit test per spec — the builder tests pin all logic).

**Files:**
- Create: `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_card.dart`

**Interfaces:**
- Consumes: Task 2's models.
- Produces: `CalendarShareCard({required CalendarShareData data})` with `static const double captureWidth = 1080` — used by Task 6's preview dialog.

- [ ] **Step 1: Create the card widget**

Create `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_card.dart`:

```dart
import 'package:flutter/material.dart';

import 'calendar_share_models.dart';

class CalendarShareCard extends StatelessWidget {
  static const double captureWidth = 1080;

  final CalendarShareData data;

  const CalendarShareCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.white,
        child: Container(
          width: captureWidth,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'לוח אירועים',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                data.rangeTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              if (data.mode == CalendarShareMode.weeks) ...[
                const _WeekdayHeaderRow(),
                const SizedBox(height: 6),
                for (final week in data.weeks) ...[
                  _CalendarGrid(weeks: [week], dense: false),
                  const SizedBox(height: 10),
                ],
              ] else ...[
                for (final month in data.months) ...[
                  Text(
                    month.title,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _WeekdayHeaderRow(),
                  const SizedBox(height: 6),
                  _CalendarGrid(weeks: month.weeks, dense: true),
                  const SizedBox(height: 24),
                ],
              ],
              const SizedBox(height: 8),
              const Text(
                'נוצר משבצק',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekdayHeaderRow extends StatelessWidget {
  static const List<String> _weekdayNames = [
    'ראשון',
    'שני',
    'שלישי',
    'רביעי',
    'חמישי',
    'שישי',
    'שבת',
  ];

  const _WeekdayHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final name in _weekdayNames)
          Expanded(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  final List<CalendarShareWeek> weeks;
  final bool dense;

  const _CalendarGrid({required this.weeks, required this.dense});

  @override
  Widget build(BuildContext context) {
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      border: TableBorder.all(color: const Color(0xFFE2E8F0)),
      children: [
        for (final week in weeks)
          TableRow(
            children: [
              for (final day in week.days) _DayCell(day: day, dense: dense),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  static const List<String> _shortDayNames = [
    'א׳',
    'ב׳',
    'ג׳',
    'ד׳',
    'ה׳',
    'ו׳',
    'ש׳',
  ];

  final CalendarShareDay? day;
  final bool dense;

  const _DayCell({required this.day, required this.dense});

  @override
  Widget build(BuildContext context) {
    final minHeight = dense ? 88.0 : 120.0;
    final d = day;
    if (d == null) {
      return Container(
        constraints: BoxConstraints(minHeight: minHeight),
        color: const Color(0xFFF8FAFC),
      );
    }

    final headerColor = !d.inRange
        ? const Color(0xFFCBD5E1)
        : d.isPast
            ? const Color(0xFF94A3B8)
            : const Color(0xFF0F172A);

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.all(6),
      color: d.inRange ? Colors.white : const Color(0xFFF8FAFC),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${d.date.day}',
                style: TextStyle(
                  fontSize: dense ? 15 : 17,
                  fontWeight: FontWeight.w800,
                  color: headerColor,
                ),
              ),
              Text(
                // Dart weekday: Mon=1..Sun=7 → % 7 maps Sunday to index 0.
                _shortDayNames[d.date.weekday % 7],
                style: TextStyle(
                  fontSize: dense ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: headerColor,
                ),
              ),
            ],
          ),
          for (final event in d.events) _EventBlock(event: event, dense: dense),
        ],
      ),
    );
  }
}

class _EventBlock extends StatelessWidget {
  final CalendarShareEvent event;
  final bool dense;

  const _EventBlock({required this.event, required this.dense});

  @override
  Widget build(BuildContext context) {
    final detailStyle = TextStyle(
      fontSize: dense ? 12 : 13.5,
      fontWeight: FontWeight.w500,
      height: 1.3,
      color: const Color(0xFF334155),
    );

    return Opacity(
      // Past events are shown but visually muted (spec: ~45%).
      opacity: event.isPast ? 0.45 : 1.0,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 4),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 4 : 6,
          vertical: dense ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              event.isContinuation ? '${event.name} (המשך)' : event.name,
              style: TextStyle(
                fontSize: dense ? 13 : 15,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: const Color(0xFF0F172A),
              ),
            ),
            for (final line in event.timeLines)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(line, style: detailStyle),
              ),
            if (event.locationLine.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('📍 ${event.locationLine}', style: detailStyle),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze and commit**

Run: `cd shavtzak && flutter analyze`
Expected: `No issues found!`

```bash
git add shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_card.dart
git commit -m "feat(summary): CalendarShareCard 1080px render widget"
```

---

### Task 6: Shared SharePreviewDialog + thin wrappers (assignments + calendar)

Extract the generic capture/share preview machinery out of
`EventAssignmentsSharePreviewDialog` into a reusable `SharePreviewDialog`,
keep the assignments dialog's public API as a thin wrapper (**zero call-site
changes** — the only call site is `event_assignments_dialog.dart:343-346`),
and add the calendar preview as a second thin wrapper. This supersedes the
spec's original "pattern-copy" wording (extraction approved by Omer,
2026-07-05). The private `_ShareImageAction` enum and
`_ButtonProgressIndicator` move into the generic file.

**Files:**
- Create: `shavtzak/lib/presentation/widgets/share_preview_dialog.dart`
- Modify (full rewrite): `shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_preview_dialog.dart`
- Create: `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_preview_dialog.dart`

**Interfaces:**
- Consumes: Task 2's `CalendarShareData`, Task 5's `CalendarShareCard`, existing `EventAssignmentsShareCard`/`EventAssignmentsShareData`, `AssignmentShareImageService` (`lib/core/services/assignment_share_image_service.dart`), `Logger` (`lib/core/debug/logger.dart`).
- Produces:
  - `SharePreviewDialog({required Widget card, required String appBarTitle, required String filename, required String shareTitle, required String shareText, required String closeLogAction, required String shareLogAction, required String copyLogAction, bool autoStartShare = true})`
  - `EventAssignmentsSharePreviewDialog({required EventAssignmentsShareData data, bool autoStartShare = true})` — public API **unchanged**.
  - `CalendarSharePreviewDialog({required CalendarShareData data, required DateTime rangeStart, required DateTime rangeEnd, bool autoStartShare = true})` — opened by Task 7's flow.

- [ ] **Step 1: Create the generic dialog**

Create `shavtzak/lib/presentation/widgets/share_preview_dialog.dart`. The body
is a lift of the current `event_assignments_share_preview_dialog.dart` with
the feature-specific values turned into constructor parameters:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/debug/logger.dart';
import '../../core/services/assignment_share_image_service.dart';

/// Generic full-screen share-preview dialog: renders a fixed-width card
/// inside a RepaintBoundary, captures it as a PNG, and offers share / copy
/// actions via AssignmentShareImageService.
///
/// Feature wrappers (assignments image, events calendar) supply the card
/// widget, titles, filename, and Logger action names.
class SharePreviewDialog extends StatefulWidget {
  final Widget card;
  final String appBarTitle;
  final String filename;
  final String shareTitle;
  final String shareText;
  final String closeLogAction;
  final String shareLogAction;
  final String copyLogAction;
  final bool autoStartShare;

  const SharePreviewDialog({
    super.key,
    required this.card,
    required this.appBarTitle,
    required this.filename,
    required this.shareTitle,
    required this.shareText,
    required this.closeLogAction,
    required this.shareLogAction,
    required this.copyLogAction,
    this.autoStartShare = true,
  });

  @override
  State<SharePreviewDialog> createState() => _SharePreviewDialogState();
}

class _SharePreviewDialogState extends State<SharePreviewDialog> {
  final GlobalKey _captureKey = GlobalKey();
  _ShareImageAction? _activeAction;
  String _message = 'אפשר לצלם את המסך הזה כתמונה אחת';

  bool get _isBusy => _activeAction != null;

  @override
  void initState() {
    super.initState();
    if (widget.autoStartShare) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _shareImage(showFailureMessage: false);
      });
    }
  }

  Future<void> _shareImage({bool showFailureMessage = true}) async {
    await _runImageAction(
      action: _ShareImageAction.share,
      showFailureMessage: showFailureMessage,
    );
  }

  Future<void> _copyImage() async {
    await _runImageAction(
      action: _ShareImageAction.copy,
      showFailureMessage: true,
    );
  }

  Future<void> _runImageAction({
    required _ShareImageAction action,
    required bool showFailureMessage,
  }) async {
    if (!mounted || _isBusy) {
      return;
    }

    setState(() {
      _activeAction = action;
      _message = action == _ShareImageAction.share
          ? 'מכין תמונה לשיתוף...'
          : 'מכין תמונה להעתקה...';
    });

    try {
      final pngBytes = await _capturePngBytes();
      final result = action == _ShareImageAction.share
          ? await const AssignmentShareImageService().sharePng(
              pngBytes: pngBytes,
              filename: widget.filename,
              title: widget.shareTitle,
              text: widget.shareText,
            )
          : await const AssignmentShareImageService().copyPng(
              pngBytes: pngBytes,
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _message = switch (result) {
          AssignmentShareImageResult.shared => 'התמונה נשלחה לשיתוף',
          AssignmentShareImageResult.copiedImage =>
            'התמונה הועתקה. אפשר להדביק אותה בצ׳אט',
          AssignmentShareImageResult.needsManualScreenshot =>
            'אפשר לצלם את המסך הזה כתמונה אחת',
        };
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = 'אפשר לצלם את המסך הזה כתמונה אחת';
      });
    } finally {
      if (mounted) {
        setState(() {
          _activeAction = null;
        });
      }
    }
  }

  Future<Uint8List> _capturePngBytes() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      throw StateError('Share preview is no longer mounted');
    }

    final renderObject = _captureKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('Share card is not ready for capture');
    }

    final image = await renderObject.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (byteData == null) {
      throw StateError('Failed to encode share card as PNG');
    }

    return Uint8List.view(byteData.buffer);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.appBarTitle),
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'סגירה',
              onPressed: () {
                Logger.action(widget.closeLogAction);
                Navigator.of(context).pop();
              },
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    color: const Color(0xFFE2E8F0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: FittedBox(
                              fit: BoxFit.fitWidth,
                              alignment: Alignment.topCenter,
                              child: RepaintBoundary(
                                key: _captureKey,
                                child: widget.card,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isBusy
                                  ? null
                                  : () {
                                      Logger.action(widget.shareLogAction);
                                      _shareImage();
                                    },
                              icon: _activeAction == _ShareImageAction.share
                                  ? const _ButtonProgressIndicator()
                                  : const Icon(Icons.ios_share),
                              label: Text(
                                _activeAction == _ShareImageAction.share
                                    ? 'משתף...'
                                    : 'שתף',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isBusy
                                  ? null
                                  : () {
                                      Logger.action(widget.copyLogAction);
                                      _copyImage();
                                    },
                              icon: _activeAction == _ShareImageAction.copy
                                  ? const _ButtonProgressIndicator()
                                  : const Icon(Icons.copy),
                              label: Text(
                                _activeAction == _ShareImageAction.copy
                                    ? 'מעתיק...'
                                    : 'העתק תמונה',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ShareImageAction {
  share,
  copy,
}

class _ButtonProgressIndicator extends StatelessWidget {
  const _ButtonProgressIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
```

Behavior notes (must hold): identical strings, identical
`autoStartShare` post-frame silent share, identical capture
(`pixelRatio: 1.0`, PNG), identical busy/disabled handling.

- [ ] **Step 2: Rewrite the assignments dialog as a thin wrapper**

Replace the ENTIRE contents of
`shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_preview_dialog.dart` with:

```dart
import 'package:flutter/material.dart';

import '../../../widgets/share_preview_dialog.dart';
import 'event_assignments_share_card.dart';
import 'event_assignments_share_models.dart';

/// Thin wrapper over [SharePreviewDialog] for the assignments-image share.
/// Public API is unchanged — the call site in event_assignments_dialog.dart
/// must not need any modification.
class EventAssignmentsSharePreviewDialog extends StatelessWidget {
  final EventAssignmentsShareData data;
  final bool autoStartShare;

  const EventAssignmentsSharePreviewDialog({
    super.key,
    required this.data,
    this.autoStartShare = true,
  });

  @override
  Widget build(BuildContext context) {
    return SharePreviewDialog(
      card: EventAssignmentsShareCard(data: data),
      appBarTitle: 'תמונת שיבוצים',
      filename: _buildFilename(data.eventName),
      shareTitle: 'תמונת שיבוצים',
      shareText: 'שיבוצים ל${data.eventName}',
      closeLogAction: 'tap:close:sharePreview',
      shareLogAction: 'tap:shareImage',
      copyLogAction: 'tap:copyImage',
      autoStartShare: autoStartShare,
    );
  }

  String _buildFilename(String eventName) {
    final safeName = eventName
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final suffix = safeName.isEmpty ? 'event' : safeName;
    return 'shavtzak_assignments_$suffix.png';
  }
}
```

The Logger action names are copied verbatim from the original file
(`tap:close:sharePreview`, `tap:shareImage`, `tap:copyImage`) so existing
debug-log traces keep their meaning.

- [ ] **Step 3: Create the calendar preview wrapper**

Create `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_preview_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../widgets/share_preview_dialog.dart';
import 'calendar_share_card.dart';
import 'calendar_share_models.dart';

/// Thin wrapper over [SharePreviewDialog] for the events-calendar share.
class CalendarSharePreviewDialog extends StatelessWidget {
  final CalendarShareData data;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final bool autoStartShare;

  const CalendarSharePreviewDialog({
    super.key,
    required this.data,
    required this.rangeStart,
    required this.rangeEnd,
    this.autoStartShare = true,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('yyyy-MM-dd');
    return SharePreviewDialog(
      card: CalendarShareCard(data: data),
      appBarTitle: 'לוח אירועים',
      filename: 'shavtzak_events_calendar_'
          '${formatter.format(rangeStart)}_'
          '${formatter.format(rangeEnd)}.png',
      shareTitle: 'לוח אירועים',
      shareText: 'לוח אירועים ${data.rangeTitle}',
      closeLogAction: 'tap:close:calendarSharePreview',
      shareLogAction: 'tap:shareCalendarImage',
      copyLogAction: 'tap:copyCalendarImage',
      autoStartShare: autoStartShare,
    );
  }
}
```

- [ ] **Step 4: Verify the call site is untouched and everything compiles**

Run: `grep -rn "EventAssignmentsSharePreviewDialog" shavtzak/lib`
Expected: exactly two files — the wrapper itself and the existing call site
`shavtzak/lib/presentation/screens/event/widgets/event_assignments_dialog.dart`
(unchanged; `git status` must show no modification to it).

Run: `cd shavtzak && flutter test && flutter analyze`
Expected: all tests PASS; `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/widgets/share_preview_dialog.dart shavtzak/lib/presentation/screens/event/widgets/event_assignments_share_preview_dialog.dart shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_preview_dialog.dart
git commit -m "refactor(share): extract generic SharePreviewDialog; add calendar preview wrapper"
```

---

### Task 7: Flow (picker → mode → preview) + SummaryScreen entry button

Also includes a small backward-compatible tweak to `DualCalendarDatePicker`: today it forces `firstDate` to `DateTime.now()` when `minDate` is null (`date_picker_dialog.dart:283-285`), which would make past ranges unpickable. All existing callers pass a non-null `minDate`, so relaxing the null fallback affects only the new flow.

**Files:**
- Modify: `shavtzak/lib/presentation/widgets/date_picker_dialog.dart:283-285`
- Create: `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_flow_dialog.dart`
- Modify: `shavtzak/lib/presentation/screens/summary/summary_screen.dart` (imports, one state field, one AppBar action, one method)

**Interfaces:**
- Consumes: `DualCalendarDatePicker` (range mode, returns `Map<String, DateTime?>` with `startDate`/`endDate`, endDate may be null = single day), Task 3/4's `CalendarShareDataBuilder.build`, Task 6's `CalendarSharePreviewDialog`, `IsraelCalendar.calendarDay`, `EventBloc`/`EventsLoaded`, `EventRepository.getAllEvents()` (provided app-wide via `RepositoryProvider`, `main.dart:325`).
- Produces: `Future<void> startCalendarShareFlow(BuildContext context, List<Event> events)` and `bool calendarShareRangeExceedsMax(DateTime start, DateTime end)`.

- [ ] **Step 1: Relax the date picker's null-minDate clamp**

In `shavtzak/lib/presentation/widgets/date_picker_dialog.dart`, change:

```dart
                        // Set the minimum date that can be viewed/selected
                        firstDate: widget.minDate ?? DateTime.now(),
                        // Set the current date to initially display
                        currentDate: widget.minDate ?? DateTime.now(),
```

to:

```dart
                        // Set the minimum date that can be viewed/selected.
                        // Null minDate = unrestricted (allows past ranges).
                        firstDate: widget.minDate ??
                            DateTime(DateTime.now().year - 3, 1, 1),
                        // Set the current date to initially display
                        currentDate: widget.initialStartDate ?? DateTime.now(),
```

(All existing callers pass `minDate`, so `firstDate` behavior is unchanged for them; `currentDate` now prefers the existing selection's month, falling back to today exactly as before when there is no initial date.)

- [ ] **Step 2: Create the flow file**

Create `shavtzak/lib/presentation/screens/summary/widgets/calendar_share/calendar_share_flow_dialog.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../../core/debug/logger.dart';
import '../../../../../core/utils/israel_calendar.dart';
import '../../../../../domain/entities/event.dart';
import '../../../../widgets/date_picker_dialog.dart';
import 'calendar_share_data_builder.dart';
import 'calendar_share_models.dart';
import 'calendar_share_preview_dialog.dart';

/// Range cap: rangeEnd must be strictly before rangeStart + 6 months.
bool calendarShareRangeExceedsMax(DateTime start, DateTime end) {
  final cap = DateTime(start.year, start.month + 6, start.day);
  return !end.isBefore(cap);
}

/// Runs the calendar-share flow: date range picker → weeks/months choice →
/// share preview. Re-opens the range picker when the range exceeds the cap.
Future<void> startCalendarShareFlow(
  BuildContext context,
  List<Event> events,
) async {
  DateTime? initialStart;
  DateTime? initialEnd;

  while (true) {
    final rangeResult = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (_) => DualCalendarDatePicker(
        isSingleDate: false,
        initialStartDate: initialStart,
        initialEndDate: initialEnd,
        title: 'בחר טווח תאריכים ללוח',
        highlightedDates: _collectEventDates(events),
      ),
    );
    if (!context.mounted ||
        rangeResult == null ||
        rangeResult['startDate'] == null) {
      return;
    }

    final start = _dateOnly(rangeResult['startDate']!);
    // Start-only selection means a single-day range (same as constraints flow).
    final end = _dateOnly(rangeResult['endDate'] ?? rangeResult['startDate']!);

    if (calendarShareRangeExceedsMax(start, end)) {
      Logger.action('calendarShare:rangeTooLong');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('טווח התאריכים המקסימלי הוא 6 חודשים')),
      );
      initialStart = start;
      initialEnd = end;
      continue;
    }

    final mode = await showDialog<CalendarShareMode>(
      context: context,
      builder: (_) => const CalendarShareModeDialog(),
    );
    if (!context.mounted || mode == null) {
      return;
    }

    Logger.action('open:calendarSharePreview', {
      'mode': mode.name,
      'days': end.difference(start).inDays + 1,
    });
    final data = CalendarShareDataBuilder.build(
      events: events,
      rangeStart: start,
      rangeEnd: end,
      mode: mode,
      today: IsraelCalendar.calendarDay(DateTime.now()),
    );
    await showDialog(
      context: context,
      builder: (_) => CalendarSharePreviewDialog(
        data: data,
        rangeStart: start,
        rangeEnd: end,
      ),
    );
    return;
  }
}

Set<DateTime> _collectEventDates(List<Event> events) {
  final dates = <DateTime>{};
  for (final event in events) {
    if (event.isDeactivated) {
      continue;
    }
    var day = _dateOnly(event.startDate);
    final last = _dateOnly(event.endDate);
    while (!day.isAfter(last)) {
      dates.add(day);
      day = DateTime(day.year, day.month, day.day + 1);
    }
  }
  return dates;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

class CalendarShareModeDialog extends StatelessWidget {
  const CalendarShareModeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('איך להציג את הלוח?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            _ModeTile(
              icon: Icons.view_week,
              title: 'שבועי',
              subtitle: 'רצועה לכל שבוע — תאים מרווחים',
              mode: CalendarShareMode.weeks,
            ),
            SizedBox(height: 8),
            _ModeTile(
              icon: Icons.calendar_month,
              title: 'חודשי',
              subtitle: 'לוח חודשי מלא — תצוגה צפופה',
              mode: CalendarShareMode.months,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Logger.action('tap:cancel:calendarShareMode');
              Navigator.of(context).pop();
            },
            child: const Text('ביטול'),
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final CalendarShareMode mode;

  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        onTap: () {
          Logger.action('tap:calendarShareMode', {'mode': mode.name});
          Navigator.of(context).pop(mode);
        },
      ),
    );
  }
}
```

- [ ] **Step 3: Wire the SummaryScreen entry button**

In `shavtzak/lib/presentation/screens/summary/summary_screen.dart`:

Add two imports (after the existing `import '../../../data/repositories/assignment_label_repository.dart';` line):

```dart
import '../../../data/repositories/event_repository.dart';
import 'widgets/calendar_share/calendar_share_flow_dialog.dart';
```

Add a state field to `_SummaryScreenState` (next to the existing `_lastKnownAssignments` field):

```dart
  bool _isPreparingCalendarShare = false;
```

In the AppBar `actions: [` list, insert as the FIRST action (before the Home button's `BlocBuilder` — first action renders closest to the title in RTL):

```dart
            // Events calendar image export (spec: summary calendar share)
            IconButton(
              icon: _isPreparingCalendarShare
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.calendar_month),
              tooltip: 'לוח אירועים',
              onPressed: _isPreparingCalendarShare
                  ? null
                  : () {
                      Logger.action('open:calendarShareFlow');
                      _openCalendarShareFlow();
                    },
              iconSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(minWidth: 56, minHeight: 44),
            ),
```

Add this method to `_SummaryScreenState` (next to `_showLogoutDialog`):

```dart
  Future<void> _openCalendarShareFlow() async {
    setState(() => _isPreparingCalendarShare = true);
    try {
      List<Event> events;
      final eventState = context.read<EventBloc>().state;
      if (eventState is EventsLoaded) {
        events = eventState.events;
      } else {
        events = await context.read<EventRepository>().getAllEvents();
      }
      if (!mounted) {
        return;
      }
      await startCalendarShareFlow(context, events);
    } catch (e) {
      Logger.action('error:calendarShareFlow', {'error': e.toString()});
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא ניתן להכין לוח אירועים')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPreparingCalendarShare = false);
      }
    }
  }
```

- [ ] **Step 4: Run the full test suite and analyzer**

Run: `cd shavtzak && flutter test && flutter analyze`
Expected: all tests PASS; `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/widgets/date_picker_dialog.dart shavtzak/lib/presentation/screens/summary/
git commit -m "feat(summary): calendar share flow — range picker, mode choice, AppBar entry"
```

---

### Task 8: Final verification against the spec

**Files:** none (verification only).

- [ ] **Step 1: Full clean check**

Run: `cd shavtzak && flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 2: Spec conformance checklist**

Re-read `docs/superpowers/specs/2026-07-05-summary-events-calendar-share-design.md` and verify each of these in the code (fix and commit if any fail):

- Entry only on `/summary`; no router or permission changes anywhere in the diff (`git diff main --stat` must not touch `app_router.dart` or entity/model files).
- No pubspec changes (`git diff main -- shavtzak/pubspec.yaml` is empty).
- Time strings mirror sync semantics; all-day = 'כל היום'; degraded form 'מופע עד'.
- Past = `endDate` strictly before Israel-day today; muting at 0.45 opacity.
- Multi-day: details on first in-range day; '(המשך)' after; excluded `isDeactivated`.
- Range cap: strictly before start+6 months; snackbar 'טווח התאריכים המקסימלי הוא 6 חודשים'.
- Filename `shavtzak_events_calendar_<yyyy-MM-dd>_<yyyy-MM-dd>.png`.
- Error snackbar 'לא ניתן להכין לוח אירועים'.
- Card: 1080px, RTL, 'לוח אירועים' header, 'נוצר משבצק' footer.
- Shared extraction: `EventAssignmentsSharePreviewDialog`'s constructor is unchanged and `event_assignments_dialog.dart` shows no diff vs main; the generic `SharePreviewDialog` carries the exact original Hebrew strings and capture behavior.

- [ ] **Step 3: Report for manual testing**

Summarize for Omer what to manually verify in the running app (he runs it himself, test env first):
1. `/test/summary` → calendar button → pick a range spanning past+future days → both שבועי and חודשי renders look right (past muted, hours+location legible).
2. Share and copy buttons work in a browser that supports them; fallback message shows otherwise.
3. A >6-month range is rejected with the snackbar and the picker re-opens.
4. Multi-day event shows details on day 1 and '(המשך)' after.
5. Regression smoke: the existing שתף תמונת שיבוצים flow (summary tile → צפה בשיבוצים → share icon) still previews, shares, and copies correctly — its dialog now delegates to the shared SharePreviewDialog.
