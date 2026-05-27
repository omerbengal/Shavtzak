# Debug Logger & Share Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an always-on, in-memory debug logger that captures BLoC transitions, Firestore traffic, navigation, screen-level loading, and explicit UI actions; expose a long-press-on-FAB share button on the three admin tabs that copies a formatted plain-text trace to the clipboard. Buffer resets on every route change.

**Architecture:** A singleton `DebugLogger` owns a ring buffer of `LogEvent`s. Three automatic capture surfaces (`LoggingBlocObserver`, `LoggingDatabase` decorator over `DatabaseInterface`, `DebugRouteObserver`) and one explicit static facade (`Logger`) feed the buffer. A pure `formatBuffer()` function renders the buffer to share-friendly text. A `DebugLogShareFab` widget wraps the existing "+" FAB on the three admin screens; `GestureDetector.onLongPress` reveals a mini-FAB whose tap calls `Clipboard.setData(formatBuffer(...))`. Privacy: only IDs, field *names*, and content *lengths* enter the buffer — never raw content.

**Tech Stack:** Flutter Web, `flutter_bloc`, `go_router`, `cloud_firestore`, `equatable`. Tests use `flutter_test`, `bloc_test`, `mockito`, `fake_cloud_firestore` (already in `pubspec.yaml` per `CLAUDE.md`).

**Spec:** `docs/superpowers/specs/2026-05-18-debug-logger-design.md` — read first.

---

## File Structure

### New files (created by this plan)

| Path | Responsibility |
|------|----------------|
| `shavtzak/lib/core/debug/log_event.dart` | `LogEvent`, `LogEventType` — pure data types |
| `shavtzak/lib/core/debug/debug_logger.dart` | `DebugLogger` singleton + ring buffer + reset + snapshot |
| `shavtzak/lib/core/debug/log_formatter.dart` | Pure `formatBuffer(events, meta) -> String` |
| `shavtzak/lib/core/debug/logger.dart` | `Logger` static facade (action/loadingStart/loadingEnd/warning/redact) |
| `shavtzak/lib/core/debug/logging_bloc_observer.dart` | `BlocObserver` implementation |
| `shavtzak/lib/core/debug/debug_route_observer.dart` | `NavigatorObserver` implementation |
| `shavtzak/lib/data/data_sources/logging_database.dart` | Decorator around `DatabaseInterface` |
| `shavtzak/lib/presentation/widgets/debug_log_share_fab.dart` | Long-press FAB wrapper widget |

### Modified files

| Path | Change |
|------|--------|
| `shavtzak/lib/main.dart` | Set `Bloc.observer = LoggingBlocObserver()` |
| `shavtzak/lib/core/services/service_locator.dart` (and/or `environment_aware_factory.dart`) | Wrap `FirestoreDatabase` with `LoggingDatabase` |
| `shavtzak/lib/core/router/app_router.dart` | Attach `DebugRouteObserver` |
| `shavtzak/lib/presentation/widgets/swipeable_page_view.dart` | Call `DebugLogger.reset` on tab swipe |
| `shavtzak/lib/presentation/screens/team/team_list_screen.dart` | Wrap FAB + add `Logger.action` |
| `shavtzak/lib/presentation/screens/event/event_list_screen.dart` | Wrap FAB + add `Logger.action` |
| `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart` | Wrap FAB + add `Logger.action` + swipe-delete log |
| `shavtzak/lib/presentation/widgets/interactive_filter_bar.dart` | Add `Logger.action` on filter change |
| Team member modal widget (location TBD by engineer, see Task 10) | Add `Logger.loadingStart`/`loadingEnd` |
| `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart` | Opt-in no-emit warning when Equatable says equal |

### Test files

| Path | Covers |
|------|--------|
| `shavtzak/test/core/debug/log_event_test.dart` | `LogEvent` immutability + enum completeness |
| `shavtzak/test/core/debug/debug_logger_test.dart` | Ring buffer capacity, FIFO drop, reset behaviour |
| `shavtzak/test/core/debug/log_formatter_test.dart` | Header, event-line formatting, truncation, redaction-in-output |
| `shavtzak/test/core/debug/logger_test.dart` | `Logger.action`, `loadingStart`/`End` duration calc, `redact`, unmatched-end |
| `shavtzak/test/core/debug/logging_bloc_observer_test.dart` | `onEvent`/`onTransition`/`onError` produce expected `LogEvent`s + `propsChanged` indices |
| `shavtzak/test/core/debug/debug_route_observer_test.dart` | `didPush`/`didReplace`/`didPop` triggers `DebugLogger.reset` with the new route name |
| `shavtzak/test/data/data_sources/logging_database_test.dart` | Decorator delegates correctly + records start/end/error with non-zero duration |
| `shavtzak/test/presentation/widgets/debug_log_share_fab_test.dart` | Tap passes through to inner FAB; long-press shows mini-FAB; mini-FAB tap copies + snackbar; auto-dismiss after 4s |

---

## Notes for the implementer

1. The project uses package name `shavtzak` (folder name). All imports use `package:shavtzak/...`.
2. Run all tests from inside the Flutter app dir: `cd shavtzak && flutter test`.
3. `flutter analyze` must pass after every task. The user explicitly runs the app themselves — do not start a long-running `flutter run`.
4. Every task ends with a commit. Commit messages follow the existing repo style (see `git log` — `Backend:`, `Fix:`, `Docs:` prefixes are used). For this work, use `feat(debug):`, `test(debug):`, `chore(debug):` consistently.
5. The `DebugLogger` singleton needs a `@visibleForTesting` clear method so tests can isolate each other. This is the only test-affordance baked in.
6. All Hebrew strings appear only in UI (`DebugLogShareFab` snackbar, tooltip). Code, comments, log lines themselves are English.

---

## Task 1: `LogEvent` and `LogEventType` data types

**Files:**
- Create: `shavtzak/lib/core/debug/log_event.dart`
- Test: `shavtzak/test/core/debug/log_event_test.dart`

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/core/debug/log_event_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/log_event.dart';

void main() {
  group('LogEvent', () {
    test('constructs with required fields', () {
      final now = DateTime.utc(2026, 5, 18, 14, 30);
      final e = LogEvent(
        timestamp: now,
        type: LogEventType.action,
        name: 'openMemberModal',
        context: const {'memberId': 'm_abc'},
      );
      expect(e.timestamp, now);
      expect(e.type, LogEventType.action);
      expect(e.name, 'openMemberModal');
      expect(e.context['memberId'], 'm_abc');
      expect(e.duration, isNull);
    });

    test('optional duration is preserved', () {
      final e = LogEvent(
        timestamp: DateTime.utc(2026, 5, 18),
        type: LogEventType.loadEnd,
        name: 'memberAvailability',
        context: const {},
        duration: const Duration(milliseconds: 152),
      );
      expect(e.duration, const Duration(milliseconds: 152));
    });

    test('context map is unmodifiable from outside', () {
      final e = LogEvent(
        timestamp: DateTime.utc(2026, 5, 18),
        type: LogEventType.action,
        name: 'x',
        context: const {'a': 1},
      );
      expect(() => (e.context as Map)['b'] = 2, throwsUnsupportedError);
    });

    test('LogEventType enum has the documented 13 values', () {
      expect(LogEventType.values, hasLength(13));
      expect(LogEventType.values, containsAll(<LogEventType>[
        LogEventType.nav,
        LogEventType.action,
        LogEventType.blocDispatch,
        LogEventType.blocEmit,
        LogEventType.blocNoEmit,
        LogEventType.blocError,
        LogEventType.dbStart,
        LogEventType.dbEnd,
        LogEventType.dbStreamEmit,
        LogEventType.dbError,
        LogEventType.loadStart,
        LogEventType.loadEnd,
        LogEventType.warning,
      ]));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd shavtzak && flutter test test/core/debug/log_event_test.dart
```

Expected: FAIL with `Target of URI doesn't exist: 'package:shavtzak/core/debug/log_event.dart'`.

- [ ] **Step 3: Create the implementation**

Create `shavtzak/lib/core/debug/log_event.dart`:

```dart
/// Discrete categories of events captured by [DebugLogger].
enum LogEventType {
  nav,
  action,
  blocDispatch,
  blocEmit,
  blocNoEmit,
  blocError,
  dbStart,
  dbEnd,
  dbStreamEmit,
  dbError,
  loadStart,
  loadEnd,
  warning,
}

/// One captured debug event.
///
/// Held in the [DebugLogger] ring buffer and rendered by `formatBuffer`.
/// Fields are immutable; [context] is wrapped in an unmodifiable view so
/// accidental mutation outside this file is caught.
class LogEvent {
  LogEvent({
    required this.timestamp,
    required this.type,
    required this.name,
    required Map<String, Object?> context,
    this.duration,
  }) : context = Map.unmodifiable(context);

  final DateTime timestamp;
  final LogEventType type;
  final String name;
  final Map<String, Object?> context;
  final Duration? duration;
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd shavtzak && flutter test test/core/debug/log_event_test.dart
```

Expected: PASS — all 4 tests green.

- [ ] **Step 5: Run analyze**

```bash
cd shavtzak && flutter analyze lib/core/debug test/core/debug
```

Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/core/debug/log_event.dart shavtzak/test/core/debug/log_event_test.dart
git commit -m "feat(debug): add LogEvent and LogEventType data types"
```

---

## Task 2: `DebugLogger` singleton + ring buffer

**Files:**
- Create: `shavtzak/lib/core/debug/debug_logger.dart`
- Test: `shavtzak/test/core/debug/debug_logger_test.dart`

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/core/debug/debug_logger_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';

LogEvent _event(int i) => LogEvent(
      timestamp: DateTime.utc(2026, 5, 18).add(Duration(seconds: i)),
      type: LogEventType.action,
      name: 'evt_$i',
      context: {'i': i},
    );

void main() {
  setUp(() {
    DebugLogger.instance.debugClearForTests();
  });

  group('DebugLogger', () {
    test('records events in order', () {
      DebugLogger.instance.record(_event(0));
      DebugLogger.instance.record(_event(1));
      expect(DebugLogger.instance.events.map((e) => e.name),
          ['evt_0', 'evt_1']);
    });

    test('drops oldest event when at capacity', () {
      for (var i = 0; i < DebugLogger.capacity + 5; i++) {
        DebugLogger.instance.record(_event(i));
      }
      final names = DebugLogger.instance.events.map((e) => e.name).toList();
      expect(names, hasLength(DebugLogger.capacity));
      expect(names.first, 'evt_5');
      expect(names.last, 'evt_${DebugLogger.capacity + 4}');
    });

    test('reset clears buffer and records a NAV event', () {
      DebugLogger.instance.record(_event(0));
      DebugLogger.instance.record(_event(1));
      DebugLogger.instance.reset(newRoute: '/admin/events');
      final ev = DebugLogger.instance.events;
      expect(ev, hasLength(1));
      expect(ev.single.type, LogEventType.nav);
      expect(ev.single.name, '/admin/events');
      expect(ev.single.context['reset'], true);
    });

    test('events getter returns an unmodifiable view', () {
      DebugLogger.instance.record(_event(0));
      final ev = DebugLogger.instance.events;
      expect(() => ev.add(_event(1)), throwsUnsupportedError);
    });

    test('record never throws on weird context values', () {
      expect(() {
        DebugLogger.instance.record(LogEvent(
          timestamp: DateTime.now().toUtc(),
          type: LogEventType.action,
          name: 'odd',
          context: {'fn': () {}}, // not JSON-safe; toString fallback expected
        ));
      }, returnsNormally);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd shavtzak && flutter test test/core/debug/debug_logger_test.dart
```

Expected: FAIL with `Target of URI doesn't exist: 'package:shavtzak/core/debug/debug_logger.dart'`.

- [ ] **Step 3: Create the implementation**

Create `shavtzak/lib/core/debug/debug_logger.dart`:

```dart
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'log_event.dart';

/// In-memory ring buffer of recent [LogEvent]s. Singleton.
///
/// Always-on in both `test` and `prod` environments. Capacity is fixed at
/// [capacity]; new entries drop the oldest. Never throws (recording is
/// wrapped in `try/catch`).
class DebugLogger {
  DebugLogger._();
  static final DebugLogger instance = DebugLogger._();

  /// Maximum number of events held in memory at once.
  static const int capacity = 200;

  final Queue<LogEvent> _events = Queue<LogEvent>();

  /// Append an event to the buffer. If capacity is exceeded, the oldest
  /// event is dropped. This method must never throw.
  void record(LogEvent event) {
    try {
      if (_events.length >= capacity) {
        _events.removeFirst();
      }
      _events.add(event);
    } catch (_) {
      // Logging must never break the app.
    }
  }

  /// Clear the buffer and record a synthetic NAV event for [newRoute].
  /// Called by [DebugRouteObserver] on every route change.
  void reset({required String newRoute}) {
    try {
      _events.clear();
      _events.add(LogEvent(
        timestamp: DateTime.now().toUtc(),
        type: LogEventType.nav,
        name: newRoute,
        context: const {'reset': true},
      ));
    } catch (_) {}
  }

  /// Read-only view of the current buffer contents (oldest first).
  List<LogEvent> get events => List.unmodifiable(_events);

  @visibleForTesting
  void debugClearForTests() {
    _events.clear();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd shavtzak && flutter test test/core/debug/debug_logger_test.dart
```

Expected: PASS — all 5 tests green.

- [ ] **Step 5: Run analyze**

```bash
cd shavtzak && flutter analyze lib/core/debug test/core/debug
```

Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/core/debug/debug_logger.dart shavtzak/test/core/debug/debug_logger_test.dart
git commit -m "feat(debug): add DebugLogger singleton with ring buffer"
```

---

## Task 3: `Logger` static facade + `redact` helper

**Files:**
- Create: `shavtzak/lib/core/debug/logger.dart`
- Test: `shavtzak/test/core/debug/logger_test.dart`

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/core/debug/logger_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'package:shavtzak/core/debug/logger.dart';

void main() {
  setUp(() => DebugLogger.instance.debugClearForTests());

  group('Logger.redact', () {
    test('returns "<N chars>" for non-null strings', () {
      expect(Logger.redact('hello'), '<5 chars>');
      expect(Logger.redact(''), '<0 chars>');
    });

    test('returns "<null>" for null', () {
      expect(Logger.redact(null), '<null>');
    });

    test('never returns the original content', () {
      expect(Logger.redact('secret-token-XYZ'), isNot(contains('secret')));
    });
  });

  group('Logger.action', () {
    test('records a LogEvent with type action and the given name+context', () {
      Logger.action('openMemberModal', {'memberId': 'm_abc'});
      final ev = DebugLogger.instance.events.single;
      expect(ev.type, LogEventType.action);
      expect(ev.name, 'openMemberModal');
      expect(ev.context['memberId'], 'm_abc');
      expect(ev.duration, isNull);
    });

    test('works without explicit context', () {
      Logger.action('x');
      final ev = DebugLogger.instance.events.single;
      expect(ev.context, isEmpty);
    });
  });

  group('Logger.loadingStart / loadingEnd', () {
    test('end computes duration from matching start', () async {
      Logger.loadingStart('memberAvailability', {'memberId': 'm_abc'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      Logger.loadingEnd('memberAvailability');
      final events = DebugLogger.instance.events;
      expect(events, hasLength(2));
      expect(events[0].type, LogEventType.loadStart);
      expect(events[1].type, LogEventType.loadEnd);
      expect(events[1].duration, isNotNull);
      expect(events[1].duration!.inMilliseconds, greaterThanOrEqualTo(20));
      expect(events[1].context['ok'], true);
    });

    test('end without matching start is recorded with unmatched: true', () {
      Logger.loadingEnd('phantom');
      final ev = DebugLogger.instance.events.single;
      expect(ev.type, LogEventType.loadEnd);
      expect(ev.duration, isNull);
      expect(ev.context['unmatched'], true);
    });

    test('end with ok=false records error info', () {
      Logger.loadingStart('op');
      Logger.loadingEnd('op', ok: false, error: 'boom');
      final ev = DebugLogger.instance.events.last;
      expect(ev.context['ok'], false);
      expect(ev.context['error'], 'boom');
    });
  });

  group('Logger.warning', () {
    test('records a warning event', () {
      Logger.warning('AssignmentBloc no-emit', {'reason': 'equatable-equal'});
      final ev = DebugLogger.instance.events.single;
      expect(ev.type, LogEventType.warning);
      expect(ev.name, 'AssignmentBloc no-emit');
      expect(ev.context['reason'], 'equatable-equal');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd shavtzak && flutter test test/core/debug/logger_test.dart
```

Expected: FAIL with `Target of URI doesn't exist: 'package:shavtzak/core/debug/logger.dart'`.

- [ ] **Step 3: Create the implementation**

Create `shavtzak/lib/core/debug/logger.dart`:

```dart
import 'debug_logger.dart';
import 'log_event.dart';

/// Static facade for explicit instrumentation at UI sites that don't
/// naturally route through BLoC.
///
/// All recording goes through [DebugLogger.instance]. Methods never throw.
class Logger {
  Logger._();

  /// Record a semantic UI action.
  static void action(String name,
      [Map<String, Object?> context = const {}]) {
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now().toUtc(),
      type: LogEventType.action,
      name: name,
      context: context,
    ));
  }

  /// Record the start of a screen-level loading operation.
  ///
  /// Pair with [loadingEnd] using the same [operation] string.
  static void loadingStart(String operation,
      [Map<String, Object?> context = const {}]) {
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now().toUtc(),
      type: LogEventType.loadStart,
      name: operation,
      context: context,
    ));
  }

  /// Record the completion of a screen-level loading operation.
  ///
  /// If a prior [loadingStart] for the same [operation] exists in the
  /// buffer, the resulting event's `duration` is filled in. If not, the
  /// event is still recorded with `context: {unmatched: true}`.
  static void loadingEnd(
    String operation, {
    bool ok = true,
    Object? error,
    Map<String, Object?> context = const {},
  }) {
    final now = DateTime.now().toUtc();
    // Find the most recent matching loadStart for this operation.
    final events = DebugLogger.instance.events;
    LogEvent? start;
    for (final e in events.reversed) {
      if (e.type == LogEventType.loadStart && e.name == operation) {
        start = e;
        break;
      }
    }
    final merged = <String, Object?>{
      ...context,
      'ok': ok,
      if (error != null) 'error': error.toString(),
      if (start == null) 'unmatched': true,
    };
    DebugLogger.instance.record(LogEvent(
      timestamp: now,
      type: LogEventType.loadEnd,
      name: operation,
      context: merged,
      duration: start == null ? null : now.difference(start.timestamp),
    ));
  }

  /// Record a freeform diagnostic warning.
  static void warning(String name,
      [Map<String, Object?> context = const {}]) {
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now().toUtc(),
      type: LogEventType.warning,
      name: name,
      context: context,
    ));
  }

  /// Convert a possibly-sensitive string into a privacy-safe length stamp.
  ///
  /// Returns `<null>` for null, `<N chars>` otherwise. Never returns
  /// any portion of [raw].
  static String redact(String? raw) {
    if (raw == null) return '<null>';
    return '<${raw.length} chars>';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd shavtzak && flutter test test/core/debug/logger_test.dart
```

Expected: PASS — all 9 tests green.

- [ ] **Step 5: Run analyze**

```bash
cd shavtzak && flutter analyze lib/core/debug test/core/debug
```

Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/core/debug/logger.dart shavtzak/test/core/debug/logger_test.dart
git commit -m "feat(debug): add Logger facade with action/loading/warning/redact"
```

---

## Task 4: Plain-text formatter (`formatBuffer`)

**Files:**
- Create: `shavtzak/lib/core/debug/log_formatter.dart`
- Test: `shavtzak/test/core/debug/log_formatter_test.dart`

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/core/debug/log_formatter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'package:shavtzak/core/debug/log_formatter.dart';

LogEvent _e({
  required LogEventType type,
  required String name,
  Map<String, Object?> context = const {},
  Duration? duration,
  int second = 0,
}) =>
    LogEvent(
      timestamp: DateTime.utc(2026, 5, 18, 14, 30, second),
      type: type,
      name: name,
      context: context,
      duration: duration,
    );

void main() {
  group('formatBuffer', () {
    test('renders header with user, env, route, captured, events count', () {
      final out = formatBuffer(
        events: const [],
        userDisplay: 'Boss',
        isAdmin: true,
        env: 'prod',
        currentRoute: '/admin/assignments',
        capturedAt: DateTime.utc(2026, 5, 18, 14, 30, 0, 123),
      );
      expect(out, contains('=== Shavtzak Debug Log ==='));
      expect(out, contains('User: Boss (admin)'));
      expect(out, contains('Env: prod'));
      expect(out, contains('Route: /admin/assignments'));
      expect(out, contains('Captured: 2026-05-18T14:30:00.123Z'));
      expect(out, contains('Events: 0'));
    });

    test('non-admin user is rendered without (admin)', () {
      final out = formatBuffer(
        events: const [],
        userDisplay: 'Joe',
        isAdmin: false,
        env: 'test',
        currentRoute: '/test/admin/events',
        capturedAt: DateTime.utc(2026, 5, 18),
      );
      expect(out, contains('User: Joe |'));
      expect(out, isNot(contains('(admin)')));
    });

    test('renders one line per event with type, name, context', () {
      final out = formatBuffer(
        events: [
          _e(type: LogEventType.action, name: 'openMemberModal',
              context: const {'memberId': 'm_abc', 'isPermanent': false}),
        ],
        userDisplay: '-',
        isAdmin: true,
        env: 'prod',
        currentRoute: '/x',
        capturedAt: DateTime.utc(2026, 5, 18),
      );
      expect(out, contains('] ACTION openMemberModal'));
      expect(out, contains('memberId: m_abc'));
      expect(out, contains('isPermanent: false'));
    });

    test('renders duration in ms for events that carry one', () {
      final out = formatBuffer(
        events: [
          _e(
            type: LogEventType.dbEnd,
            name: 'getEvents',
            context: const {'count': 12, 'ok': true},
            duration: const Duration(milliseconds: 152),
          ),
        ],
        userDisplay: '-', isAdmin: true, env: 'prod',
        currentRoute: '/x', capturedAt: DateTime.utc(2026, 5, 18),
      );
      expect(out, contains('DB_END getEvents'));
      expect(out, contains('(152 ms)'));
    });

    test('truncates a single field longer than 200 chars', () {
      final long = 'x' * 500;
      final out = formatBuffer(
        events: [
          _e(type: LogEventType.warning, name: 'huge',
              context: {'blob': long}),
        ],
        userDisplay: '-', isAdmin: true, env: 'prod',
        currentRoute: '/x', capturedAt: DateTime.utc(2026, 5, 18),
      );
      expect(out, contains('…(truncated)'));
      expect(out.length, lessThan(2000));
    });

    test('never contains a raw note value when redact was used', () {
      // Simulating a properly-redacted event.
      final out = formatBuffer(
        events: [
          _e(type: LogEventType.blocDispatch, name: 'AssignmentBloc ← Update',
              context: const {'note': '<6 chars>'}),
        ],
        userDisplay: '-', isAdmin: true, env: 'prod',
        currentRoute: '/x', capturedAt: DateTime.utc(2026, 5, 18),
      );
      expect(out, contains('<6 chars>'));
      expect(out, isNot(contains('secret')));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd shavtzak && flutter test test/core/debug/log_formatter_test.dart
```

Expected: FAIL with `Target of URI doesn't exist: 'package:shavtzak/core/debug/log_formatter.dart'`.

- [ ] **Step 3: Create the implementation**

Create `shavtzak/lib/core/debug/log_formatter.dart`:

```dart
import 'log_event.dart';

const int _maxFieldChars = 200;

/// Render the [DebugLogger] buffer to share-friendly plain text.
///
/// Output format:
///
/// ```
/// === Shavtzak Debug Log ===
/// User: <display> [(admin)] | Env: <env> | Route: <route>
/// Captured: <ISO-Z> | Events: <n>
///
/// [HH:mm:ss.SSSZ] TYPE name {ctx} (duration ms)
/// ...
/// ```
String formatBuffer({
  required List<LogEvent> events,
  required String? userDisplay,
  required bool isAdmin,
  required String env,
  required String currentRoute,
  required DateTime capturedAt,
}) {
  final user = userDisplay ?? '-';
  final adminTag = isAdmin ? ' (admin)' : '';
  final headerIso = _iso(capturedAt);
  final lines = <String>[
    '=== Shavtzak Debug Log ===',
    'User: $user$adminTag | Env: $env | Route: $currentRoute',
    'Captured: $headerIso | Events: ${events.length}',
    '',
    for (final e in events) _formatEvent(e),
  ];
  return lines.join('\n');
}

String _formatEvent(LogEvent e) {
  final ts = '[${_timeOnly(e.timestamp)}]';
  final type = _typeLabel(e.type);
  final ctxStr = e.context.isEmpty ? '' : ' ${_renderContext(e.context)}';
  final durStr =
      e.duration == null ? '' : ' (${e.duration!.inMilliseconds} ms)';
  return '$ts $type ${e.name}$ctxStr$durStr';
}

String _typeLabel(LogEventType t) {
  switch (t) {
    case LogEventType.nav: return 'NAV';
    case LogEventType.action: return 'ACTION';
    case LogEventType.blocDispatch: return 'BLOC_DISPATCH';
    case LogEventType.blocEmit: return 'BLOC_EMIT';
    case LogEventType.blocNoEmit: return 'BLOC_NO_EMIT';
    case LogEventType.blocError: return 'BLOC_ERROR';
    case LogEventType.dbStart: return 'DB_START';
    case LogEventType.dbEnd: return 'DB_END';
    case LogEventType.dbStreamEmit: return 'DB_STREAM_EMIT';
    case LogEventType.dbError: return 'DB_ERROR';
    case LogEventType.loadStart: return 'LOAD_START';
    case LogEventType.loadEnd: return 'LOAD_END';
    case LogEventType.warning: return 'WARN';
  }
}

String _renderContext(Map<String, Object?> ctx) {
  final parts = <String>[];
  for (final entry in ctx.entries) {
    parts.add('${entry.key}: ${_renderValue(entry.value)}');
  }
  return '{${parts.join(', ')}}';
}

String _renderValue(Object? v) {
  String s;
  if (v == null) {
    s = 'null';
  } else if (v is String || v is num || v is bool) {
    s = v.toString();
  } else if (v is List) {
    s = v.map(_renderValue).join(',');
    s = '[$s]';
  } else if (v is Map) {
    s = _renderContext(v.cast<String, Object?>());
  } else {
    s = v.toString();
  }
  if (s.length > _maxFieldChars) {
    s = '${s.substring(0, _maxFieldChars)}…(truncated)';
  }
  return s;
}

String _iso(DateTime utc) {
  final d = utc.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}T'
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}.'
      '${three(d.millisecond)}Z';
}

String _timeOnly(DateTime utc) {
  final d = utc.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return '${two(d.hour)}:${two(d.minute)}:${two(d.second)}.'
      '${three(d.millisecond)}Z';
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd shavtzak && flutter test test/core/debug/log_formatter_test.dart
```

Expected: PASS — all 6 tests green.

- [ ] **Step 5: Run analyze**

```bash
cd shavtzak && flutter analyze lib/core/debug test/core/debug
```

Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/core/debug/log_formatter.dart shavtzak/test/core/debug/log_formatter_test.dart
git commit -m "feat(debug): add plain-text formatBuffer formatter"
```

---

## Task 5: `LoggingBlocObserver`

**Files:**
- Create: `shavtzak/lib/core/debug/logging_bloc_observer.dart`
- Test: `shavtzak/test/core/debug/logging_bloc_observer_test.dart`

This task introduces a `BlocObserver` that records dispatches, transitions, and errors. `propsChanged` is computed by comparing `current.props` and `next.props` index-wise for `Equatable` states; if lengths differ, propsChanged is `['structural']`.

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/core/debug/logging_bloc_observer_test.dart`:

```dart
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'package:shavtzak/core/debug/logging_bloc_observer.dart';

class _FxState extends Equatable {
  const _FxState(this.x, this.y);
  final int x;
  final int y;
  @override
  List<Object?> get props => [x, y];
}

class _FxEvent {
  const _FxEvent();
}

class _FxBloc extends Bloc<_FxEvent, _FxState> {
  _FxBloc() : super(const _FxState(0, 0));
}

void main() {
  late LoggingBlocObserver observer;
  late _FxBloc bloc;

  setUp(() {
    DebugLogger.instance.debugClearForTests();
    observer = LoggingBlocObserver();
    bloc = _FxBloc();
  });

  tearDown(() async {
    await bloc.close();
  });

  test('onEvent records a blocDispatch event', () {
    observer.onEvent(bloc, const _FxEvent());
    final ev = DebugLogger.instance.events.single;
    expect(ev.type, LogEventType.blocDispatch);
    expect(ev.name, contains('_FxBloc'));
    expect(ev.name, contains('_FxEvent'));
  });

  test('onTransition records propsChanged by index', () {
    observer.onTransition(
      bloc,
      const Transition<_FxEvent, _FxState>(
        currentState: _FxState(0, 0),
        event: _FxEvent(),
        nextState: _FxState(0, 1),
      ),
    );
    final ev = DebugLogger.instance.events.single;
    expect(ev.type, LogEventType.blocEmit);
    expect(ev.name, contains('_FxBloc'));
    expect(ev.context['propsChanged'], [1]);
  });

  test('onTransition records "structural" when props lengths differ', () {
    // Construct a state with a different shape (subclass-like behavior).
    final next = _FxStateExt(0, 1, 99);
    observer.onTransition(
      bloc,
      Transition<_FxEvent, _FxState>(
        currentState: const _FxState(0, 0),
        event: const _FxEvent(),
        nextState: next,
      ),
    );
    final ev = DebugLogger.instance.events.single;
    expect(ev.context['propsChanged'], ['structural']);
  });

  test('onError records a blocError with error class name', () {
    observer.onError(bloc, ArgumentError('boom'), StackTrace.current);
    final ev = DebugLogger.instance.events.single;
    expect(ev.type, LogEventType.blocError);
    expect(ev.context['error'], contains('ArgumentError'));
  });
}

class _FxStateExt extends _FxState {
  const _FxStateExt(super.x, super.y, this.z);
  final int z;
  @override
  List<Object?> get props => [x, y, z];
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd shavtzak && flutter test test/core/debug/logging_bloc_observer_test.dart
```

Expected: FAIL with `Target of URI doesn't exist: 'package:shavtzak/core/debug/logging_bloc_observer.dart'`.

- [ ] **Step 3: Create the implementation**

Create `shavtzak/lib/core/debug/logging_bloc_observer.dart`:

```dart
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'debug_logger.dart';
import 'log_event.dart';

/// Records every BLoC dispatch, state transition, and error into the
/// global [DebugLogger] buffer.
///
/// Wired in `main.dart` via `Bloc.observer = LoggingBlocObserver();`.
///
/// Privacy: dispatched events are recorded as `{eventType: <runtimeType>}`
/// only. We do not introspect event fields, since they may carry raw user
/// content. Callers wanting field-level visibility should add an explicit
/// [Logger.action] call alongside the BLoC dispatch.
class LoggingBlocObserver extends BlocObserver {
  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now().toUtc(),
      type: LogEventType.blocDispatch,
      name: '${bloc.runtimeType} ← ${event.runtimeType}',
      context: {'eventType': '${event.runtimeType}'},
    ));
  }

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    super.onTransition(bloc, transition);
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now().toUtc(),
      type: LogEventType.blocEmit,
      name: '${bloc.runtimeType} → ${transition.nextState.runtimeType}',
      context: {
        'propsChanged':
            _propsChanged(transition.currentState, transition.nextState),
      },
    ));
  }

  @override
  void onError(
    BlocBase<dynamic> bloc,
    Object error,
    StackTrace stackTrace,
  ) {
    super.onError(bloc, error, stackTrace);
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now().toUtc(),
      type: LogEventType.blocError,
      name: '${bloc.runtimeType} error',
      context: {
        'error': error.runtimeType.toString(),
        'message': error.toString(),
        'stackHead': stackTrace.toString().split('\n').first,
      },
    ));
  }

  /// Returns the indices at which `current.props` and `next.props` differ.
  /// If lengths differ or either is not [Equatable], returns `['structural']`.
  List<Object> _propsChanged(Object? current, Object? next) {
    if (current is! Equatable || next is! Equatable) {
      return const ['structural'];
    }
    final cp = current.props;
    final np = next.props;
    if (cp.length != np.length) return const ['structural'];
    final out = <int>[];
    for (var i = 0; i < cp.length; i++) {
      if (cp[i] != np[i]) out.add(i);
    }
    return out;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd shavtzak && flutter test test/core/debug/logging_bloc_observer_test.dart
```

Expected: PASS — all 4 tests green.

- [ ] **Step 5: Wire `Bloc.observer` in `main.dart`**

Open `shavtzak/lib/main.dart`. Find the first line inside `main()` after `WidgetsFlutterBinding.ensureInitialized();` and add:

```dart
import 'package:bloc/bloc.dart';
import 'core/debug/logging_bloc_observer.dart';
// ... inside main(), right after WidgetsFlutterBinding.ensureInitialized():
Bloc.observer = LoggingBlocObserver();
```

- [ ] **Step 6: Run analyze + full test suite**

```bash
cd shavtzak && flutter analyze
cd shavtzak && flutter test
```

Expected: `No issues found!` and all tests green.

- [ ] **Step 7: Commit**

```bash
git add shavtzak/lib/core/debug/logging_bloc_observer.dart \
        shavtzak/test/core/debug/logging_bloc_observer_test.dart \
        shavtzak/lib/main.dart
git commit -m "feat(debug): add LoggingBlocObserver and wire as Bloc.observer"
```

---

## Task 6: `LoggingDatabase` decorator + service-locator wiring

**Files:**
- Create: `shavtzak/lib/data/data_sources/logging_database.dart`
- Test: `shavtzak/test/data/data_sources/logging_database_test.dart`
- Modify: `shavtzak/lib/core/services/service_locator.dart` (and/or `environment_aware_factory.dart`)

The decorator must implement *every* method on `DatabaseInterface`. The pattern is identical for each. Write tests for one `get*`, one `watch*`, one `insert*`/`update*` method to lock in the pattern, then apply mechanically to all interface members.

- [ ] **Step 1: Read `database_interface.dart` to enumerate methods**

```bash
cat shavtzak/lib/data/data_sources/database_interface.dart
```

Make a list of every method signature. (The plan code below uses placeholder names `getEvents`, `watchTeamMembers`, `insertAssignment` — the implementer must mirror the actual signatures one-for-one. No method may be skipped.)

- [ ] **Step 2: Write the failing test**

Create `shavtzak/test/data/data_sources/logging_database_test.dart`. Replace the placeholder method names with real ones from the interface; the structure is the same.

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'package:shavtzak/data/data_sources/database_interface.dart';
import 'package:shavtzak/data/data_sources/logging_database.dart';
import 'package:shavtzak/data/models/event_model.dart';

import 'logging_database_test.mocks.dart';

@GenerateMocks([DatabaseInterface])
void main() {
  late MockDatabaseInterface inner;
  late LoggingDatabase decorator;

  setUp(() {
    DebugLogger.instance.debugClearForTests();
    inner = MockDatabaseInterface();
    decorator = LoggingDatabase(inner);
  });

  test('one-shot read records DB_START then DB_END with count + ok', () async {
    when(inner.getEvents()).thenAnswer((_) async => <EventModel>[]);
    final result = await decorator.getEvents();
    verify(inner.getEvents()).called(1);
    final events = DebugLogger.instance.events;
    expect(events.map((e) => e.type),
        containsAllInOrder([LogEventType.dbStart, LogEventType.dbEnd]));
    expect(events.last.context['ok'], true);
    expect(events.last.context['count'], result.length);
    expect(events.last.duration, isNotNull);
  });

  test('one-shot read that throws records DB_START then DB_ERROR', () async {
    when(inner.getEvents()).thenThrow(StateError('boom'));
    await expectLater(decorator.getEvents(), throwsStateError);
    final events = DebugLogger.instance.events;
    expect(events.map((e) => e.type),
        containsAllInOrder([LogEventType.dbStart, LogEventType.dbError]));
    expect(events.last.context['error'], contains('StateError'));
  });

  test('stream read records DB_START then DB_STREAM_EMIT per emission',
      () async {
    final ctl = StreamController<List<EventModel>>();
    when(inner.watchEvents()).thenAnswer((_) => ctl.stream);
    final subscription = decorator.watchEvents().listen((_) {});
    ctl.add(<EventModel>[]);
    await Future<void>.delayed(Duration.zero);
    final types = DebugLogger.instance.events.map((e) => e.type).toList();
    expect(types, contains(LogEventType.dbStart));
    expect(types, contains(LogEventType.dbStreamEmit));
    await subscription.cancel();
    await ctl.close();
  });
}
```

Generate the mockito helper:

```bash
cd shavtzak && flutter pub run build_runner build --delete-conflicting-outputs
```

(If the project already uses `build.yaml` defaults, this generates `logging_database_test.mocks.dart`.)

- [ ] **Step 3: Run test to verify it fails**

```bash
cd shavtzak && flutter test test/data/data_sources/logging_database_test.dart
```

Expected: FAIL (file `logging_database.dart` does not exist).

- [ ] **Step 4: Create the implementation**

Create `shavtzak/lib/data/data_sources/logging_database.dart`. The pattern below shows three representative methods (`getEvents`, `watchEvents`, `insertEvent`). **Repeat the pattern for every method on `DatabaseInterface` — no method may be left undecorated.**

```dart
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'database_interface.dart';
import '../models/event_model.dart';
// import other models as needed for the full interface signature set...

/// Decorator that wraps any [DatabaseInterface] implementation and records
/// every call/emission/error into [DebugLogger]. Pure decorator — does not
/// change behavior or ordering.
class LoggingDatabase implements DatabaseInterface {
  LoggingDatabase(this._inner);
  final DatabaseInterface _inner;

  // --- one-shot read pattern ---------------------------------------------

  @override
  Future<List<EventModel>> getEvents() async {
    return _runFuture<List<EventModel>>(
      op: 'getEvents',
      ctx: const {'collection': 'events'},
      countOf: (r) => r.length,
      action: _inner.getEvents,
    );
  }

  // --- stream watch pattern ----------------------------------------------

  @override
  Stream<List<EventModel>> watchEvents() {
    final startedAt = DateTime.now().toUtc();
    DebugLogger.instance.record(LogEvent(
      timestamp: startedAt,
      type: LogEventType.dbStart,
      name: 'watchEvents',
      context: const {'collection': 'events', 'kind': 'stream'},
    ));
    return _inner.watchEvents().map((snapshot) {
      DebugLogger.instance.record(LogEvent(
        timestamp: DateTime.now().toUtc(),
        type: LogEventType.dbStreamEmit,
        name: 'watchEvents',
        context: {'collection': 'events', 'count': snapshot.length},
      ));
      return snapshot;
    });
  }

  // --- write pattern -----------------------------------------------------

  @override
  Future<void> insertEvent(EventModel m) async {
    return _runFuture<void>(
      op: 'insertEvent',
      ctx: {'collection': 'events', 'id': m.id},
      countOf: (_) => null,
      action: () => _inner.insertEvent(m),
    );
  }

  // --- shared helper -----------------------------------------------------

  Future<T> _runFuture<T>({
    required String op,
    required Map<String, Object?> ctx,
    required int? Function(T) countOf,
    required Future<T> Function() action,
  }) async {
    final start = DateTime.now().toUtc();
    DebugLogger.instance.record(LogEvent(
      timestamp: start,
      type: LogEventType.dbStart,
      name: op,
      context: ctx,
    ));
    try {
      final result = await action();
      final now = DateTime.now().toUtc();
      DebugLogger.instance.record(LogEvent(
        timestamp: now,
        type: LogEventType.dbEnd,
        name: op,
        context: {
          ...ctx,
          'ok': true,
          if (countOf(result) != null) 'count': countOf(result),
        },
        duration: now.difference(start),
      ));
      return result;
    } catch (e, s) {
      final now = DateTime.now().toUtc();
      DebugLogger.instance.record(LogEvent(
        timestamp: now,
        type: LogEventType.dbError,
        name: op,
        context: {
          ...ctx,
          'error': e.runtimeType.toString(),
          'message': e.toString(),
          'stackHead': s.toString().split('\n').first,
        },
        duration: now.difference(start),
      ));
      rethrow;
    }
  }

  // !!! Repeat the same pattern for every remaining method on
  // !!! DatabaseInterface — getX, watchX, insertX, updateX, deleteX,
  // !!! insertXBatch, etc. Do not omit any method.
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd shavtzak && flutter test test/data/data_sources/logging_database_test.dart
```

Expected: PASS — 3 tests green.

- [ ] **Step 6: Wire the decorator in service locator / factory**

Open `shavtzak/lib/core/services/service_locator.dart` (and `environment_aware_factory.dart` if applicable). Find every site that constructs `FirestoreDatabase(...)` to be used as a `DatabaseInterface`. Wrap with `LoggingDatabase(...)`. For example:

```dart
// Before:
final DatabaseInterface _db = FirestoreDatabase();
// After:
final DatabaseInterface _db = LoggingDatabase(FirestoreDatabase());
```

(Repositories take `DatabaseInterface`, so no repository code changes.)

- [ ] **Step 7: Run analyze + full suite**

```bash
cd shavtzak && flutter analyze
cd shavtzak && flutter test
```

Expected: `No issues found!` and all tests green.

- [ ] **Step 8: Commit**

```bash
git add shavtzak/lib/data/data_sources/logging_database.dart \
        shavtzak/test/data/data_sources/logging_database_test.dart \
        shavtzak/test/data/data_sources/logging_database_test.mocks.dart \
        shavtzak/lib/core/services/service_locator.dart
# add environment_aware_factory.dart too if you touched it
git commit -m "feat(debug): add LoggingDatabase decorator and wire via service locator"
```

---

## Task 7: `DebugRouteObserver` + router and SwipeablePageView wiring

**Files:**
- Create: `shavtzak/lib/core/debug/debug_route_observer.dart`
- Test: `shavtzak/test/core/debug/debug_route_observer_test.dart`
- Modify: `shavtzak/lib/core/router/app_router.dart`
- Modify: `shavtzak/lib/presentation/widgets/swipeable_page_view.dart`

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/core/debug/debug_route_observer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/debug_route_observer.dart';
import 'package:shavtzak/core/debug/log_event.dart';

void main() {
  setUp(() => DebugLogger.instance.debugClearForTests());

  PageRoute<dynamic> _route(String name) =>
      MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
        settings: RouteSettings(name: name),
      );

  test('didPush resets the buffer with the new route name', () {
    final obs = DebugRouteObserver();
    obs.didPush(_route('/admin/events'), _route('/admin/team-members'));
    final ev = DebugLogger.instance.events;
    expect(ev, hasLength(1));
    expect(ev.single.type, LogEventType.nav);
    expect(ev.single.name, '/admin/events');
  });

  test('didReplace resets with the replacement route name', () {
    final obs = DebugRouteObserver();
    obs.didReplace(
      newRoute: _route('/admin/assignments'),
      oldRoute: _route('/admin/events'),
    );
    expect(DebugLogger.instance.events.single.name, '/admin/assignments');
  });

  test('didPop resets with the destination route name', () {
    final obs = DebugRouteObserver();
    obs.didPop(_route('/admin/events'), _route('/admin/team-members'));
    expect(DebugLogger.instance.events.single.name, '/admin/team-members');
  });

  test('null route name falls back to "<unknown>"', () {
    final obs = DebugRouteObserver();
    obs.didPush(
      MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
      null,
    );
    expect(DebugLogger.instance.events.single.name, '<unknown>');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd shavtzak && flutter test test/core/debug/debug_route_observer_test.dart
```

Expected: FAIL (`debug_route_observer.dart` does not exist).

- [ ] **Step 3: Create the implementation**

Create `shavtzak/lib/core/debug/debug_route_observer.dart`:

```dart
import 'package:flutter/widgets.dart';

import 'debug_logger.dart';

/// `NavigatorObserver` that resets the [DebugLogger] buffer on every
/// route push/replace/pop. The new route's name is recorded as the
/// first event of the new buffer.
class DebugRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _reset(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _reset(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _reset(previousRoute);
  }

  void _reset(Route<dynamic> r) {
    final name = r.settings.name ?? '<unknown>';
    DebugLogger.instance.reset(newRoute: name);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd shavtzak && flutter test test/core/debug/debug_route_observer_test.dart
```

Expected: PASS — 4 tests green.

- [ ] **Step 5: Wire the observer into `app_router.dart`**

Open `shavtzak/lib/core/router/app_router.dart`. Locate the `GoRouter(...)` constructor. Add:

```dart
import '../debug/debug_route_observer.dart';

// ... inside GoRouter(...):
observers: [DebugRouteObserver()],
```

If the project uses `StatefulShellRoute` and each branch has its own `Navigator`, also pass `observers: [DebugRouteObserver()]` to each `StatefulShellBranch` so swipes between branches reset.

- [ ] **Step 6: Wire `SwipeablePageView` to also reset**

Open `shavtzak/lib/presentation/widgets/swipeable_page_view.dart`. Find the `PageView`'s `onPageChanged: (index) { ... }` callback (or equivalent). Add:

```dart
import '../../core/debug/debug_logger.dart';

// inside onPageChanged:
DebugLogger.instance.reset(
  newRoute: _routeForIndex(index), // e.g. '/admin/team-members'
);
```

If the swipe also pushes a GoRouter route, the observer already resets — calling `reset` again is harmless (we lose at most microseconds of trace).

- [ ] **Step 7: Run analyze + full suite**

```bash
cd shavtzak && flutter analyze
cd shavtzak && flutter test
```

Expected: `No issues found!` and all tests green.

- [ ] **Step 8: Commit**

```bash
git add shavtzak/lib/core/debug/debug_route_observer.dart \
        shavtzak/test/core/debug/debug_route_observer_test.dart \
        shavtzak/lib/core/router/app_router.dart \
        shavtzak/lib/presentation/widgets/swipeable_page_view.dart
git commit -m "feat(debug): add route observer and reset buffer on navigation"
```

---

## Task 8: `DebugLogShareFab` widget

**Files:**
- Create: `shavtzak/lib/presentation/widgets/debug_log_share_fab.dart`
- Test: `shavtzak/test/presentation/widgets/debug_log_share_fab_test.dart`

The widget wraps the existing "+" FAB. A normal tap on the wrapped child still triggers the inner FAB's `onPressed`. Long-press toggles a mini-FAB above the main FAB (`Icons.bug_report`, tooltip "העתק לוג תקלה"). Tapping the mini-FAB:

1. Snapshots `DebugLogger.instance.events` and formats with `formatBuffer(...)`.
2. Writes to clipboard via `Clipboard.setData`.
3. Records a `Logger.action('debugShareLogsCopied', {bytes, eventCount})`.
4. Shows a snackbar "הלוג הועתק ללוח (N אירועים)".
5. Dismisses itself.

If untouched for 4 seconds the mini-FAB auto-dismisses.

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/presentation/widgets/debug_log_share_fab_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'package:shavtzak/core/debug/logger.dart';
import 'package:shavtzak/presentation/widgets/debug_log_share_fab.dart';

Future<void> _pumpHost(WidgetTester tester, {required VoidCallback onTap})
    async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: const SizedBox.expand(),
      floatingActionButton: DebugLogShareFab(
        currentRouteForShare: '/admin/events',
        userDisplay: 'Boss',
        isAdmin: true,
        env: 'prod',
        child: FloatingActionButton(
          heroTag: 'host-fab',
          onPressed: onTap,
          child: const Icon(Icons.add),
        ),
      ),
    ),
  ));
}

void main() {
  setUp(() {
    DebugLogger.instance.debugClearForTests();
  });

  testWidgets('a tap still triggers the inner FAB.onPressed', (tester) async {
    var taps = 0;
    await _pumpHost(tester, onTap: () => taps++);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(taps, 1);
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });

  testWidgets('long-press reveals the mini-FAB', (tester) async {
    await _pumpHost(tester, onTap: () {});
    await tester.longPress(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
  });

  testWidgets('mini-FAB tap copies logs to clipboard + records action',
      (tester) async {
    Logger.action('precondition'); // 1 event seeded
    final List<MethodCall> calls = [];
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    await _pumpHost(tester, onTap: () {});
    await tester.longPress(find.byIcon(Icons.add));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.bug_report));
    await tester.pump();

    final setData = calls.singleWhere((c) => c.method == 'Clipboard.setData');
    final payload = (setData.arguments as Map)['text'] as String;
    expect(payload, contains('=== Shavtzak Debug Log ==='));
    expect(payload, contains('precondition'));

    // 'debugShareLogsCopied' action was recorded
    expect(
      DebugLogger.instance.events
          .map((e) => e.name)
          .where((n) => n == 'debugShareLogsCopied'),
      hasLength(1),
    );
  });

  testWidgets('mini-FAB auto-dismisses after 4 seconds', (tester) async {
    await _pumpHost(tester, onTap: () {});
    await tester.longPress(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.byIcon(Icons.bug_report), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byIcon(Icons.bug_report), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd shavtzak && flutter test test/presentation/widgets/debug_log_share_fab_test.dart
```

Expected: FAIL (`debug_log_share_fab.dart` does not exist).

- [ ] **Step 3: Create the implementation**

Create `shavtzak/lib/presentation/widgets/debug_log_share_fab.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/debug/debug_logger.dart';
import '../../core/debug/log_formatter.dart';
import '../../core/debug/logger.dart';

/// Wraps the host screen's "+" FAB. Long-press reveals a mini-FAB; tapping
/// the mini-FAB copies the formatted [DebugLogger] buffer to the system
/// clipboard.
class DebugLogShareFab extends StatefulWidget {
  const DebugLogShareFab({
    super.key,
    required this.child,
    required this.currentRouteForShare,
    required this.userDisplay,
    required this.isAdmin,
    required this.env,
  });

  final Widget child;
  final String currentRouteForShare;
  final String? userDisplay;
  final bool isAdmin;
  final String env;

  @override
  State<DebugLogShareFab> createState() => _DebugLogShareFabState();
}

class _DebugLogShareFabState extends State<DebugLogShareFab> {
  bool _menuVisible = false;
  Timer? _autoDismiss;

  void _toggleMenu() {
    setState(() => _menuVisible = !_menuVisible);
    _autoDismiss?.cancel();
    if (_menuVisible) {
      Logger.action('debugShareMenuOpen');
      _autoDismiss = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _menuVisible = false);
      });
    }
  }

  Future<void> _copyLogs() async {
    final text = formatBuffer(
      events: DebugLogger.instance.events,
      userDisplay: widget.userDisplay,
      isAdmin: widget.isAdmin,
      env: widget.env,
      currentRoute: widget.currentRouteForShare,
      capturedAt: DateTime.now().toUtc(),
    );
    await Clipboard.setData(ClipboardData(text: text));
    Logger.action('debugShareLogsCopied', {
      'bytes': text.length,
      'eventCount': DebugLogger.instance.events.length,
    });
    if (!mounted) return;
    final count = DebugLogger.instance.events.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('הלוג הועתק ללוח ($count אירועים)')),
    );
    setState(() => _menuVisible = false);
    _autoDismiss?.cancel();
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomRight,
      children: [
        if (_menuVisible)
          Positioned(
            bottom: 72,
            right: 0,
            child: FloatingActionButton(
              mini: true,
              heroTag: 'debug-share-mini-fab',
              tooltip: 'העתק לוג תקלה',
              onPressed: _copyLogs,
              child: const Icon(Icons.bug_report),
            ),
          ),
        GestureDetector(
          onLongPress: _toggleMenu,
          child: widget.child,
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd shavtzak && flutter test test/presentation/widgets/debug_log_share_fab_test.dart
```

Expected: PASS — 4 tests green.

- [ ] **Step 5: Run analyze**

```bash
cd shavtzak && flutter analyze lib/presentation/widgets/debug_log_share_fab.dart \
                              test/presentation/widgets/debug_log_share_fab_test.dart
```

Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation/widgets/debug_log_share_fab.dart \
        shavtzak/test/presentation/widgets/debug_log_share_fab_test.dart
git commit -m "feat(debug): add DebugLogShareFab long-press share widget"
```

---

## Task 9: Wrap FABs on the three admin screens

**Files:**
- Modify: `shavtzak/lib/presentation/screens/team/team_list_screen.dart`
- Modify: `shavtzak/lib/presentation/screens/event/event_list_screen.dart`
- Modify: `shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart`

For each of the three admin screens, locate the existing `Scaffold(... floatingActionButton: FloatingActionButton(...))` and wrap it with `DebugLogShareFab`. The current logged-in user and environment are read from `UserSelectionBloc` and `EnvironmentService` respectively.

- [ ] **Step 1: Modify `team_list_screen.dart`**

Add imports:

```dart
import '../../widgets/debug_log_share_fab.dart';
import '../../bloc/user_selection/user_selection_bloc.dart';
import '../../../core/services/environment_service.dart';
```

Replace:

```dart
floatingActionButton: FloatingActionButton(
  onPressed: ...,
  child: const Icon(Icons.add),
),
```

With:

```dart
floatingActionButton: _buildFab(context),
```

…and add inside the State (or as a local helper):

```dart
Widget _buildFab(BuildContext context) {
  final state = context.read<UserSelectionBloc>().state;
  final display = state is UserAuthenticated
      ? state.user.displayName ?? state.user.uniqueKey
      : null;
  final isAdmin = state is UserAuthenticated ? state.user.isAdmin : false;
  return DebugLogShareFab(
    currentRouteForShare:
        '${EnvironmentService.instance.routePrefix}/admin/team-members',
    userDisplay: display,
    isAdmin: isAdmin,
    env: EnvironmentService.instance.isTestMode ? 'test' : 'prod',
    child: FloatingActionButton(
      heroTag: 'team-list-fab',
      onPressed: () { /* existing add-member flow */ },
      child: const Icon(Icons.add),
    ),
  );
}
```

(Use the actual `UserAuthenticated` state class name from the project — replace if different. Use the actual `displayName`/identity property of `TeamMember` — replace if different.)

- [ ] **Step 2: Modify `event_list_screen.dart`**

Same pattern. `heroTag: 'event-list-fab'`, `currentRouteForShare: '${EnvironmentService.instance.routePrefix}/admin/events'`.

- [ ] **Step 3: Modify `assignment_list_screen.dart`**

Same pattern. `heroTag: 'assignment-list-fab'`, `currentRouteForShare: '${EnvironmentService.instance.routePrefix}/admin/assignments'`.

- [ ] **Step 4: Run analyze + full suite**

```bash
cd shavtzak && flutter analyze
cd shavtzak && flutter test
```

Expected: `No issues found!` and all existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add shavtzak/lib/presentation/screens/team/team_list_screen.dart \
        shavtzak/lib/presentation/screens/event/event_list_screen.dart \
        shavtzak/lib/presentation/screens/assignment/assignment_list_screen.dart
git commit -m "feat(debug): wrap admin-tab FABs with DebugLogShareFab"
```

---

## Task 10: Explicit `Logger.action` / `loadingStart` / `loadingEnd` at v1 sites

**Files (modify):**
- Wherever the team member modal is opened from `team_list_screen.dart`
- Wherever the event form modal is opened from `event_list_screen.dart`
- Wherever the manual assignment flow is opened from `assignment_list_screen.dart`
- `shavtzak/lib/presentation/widgets/interactive_filter_bar.dart`
- The team member modal widget itself (loading availability/constraints)
- Event detail widget (loading assignments), if it exists

This task adds **only** the explicit `Logger.*` calls from §6.5 of the spec. No behavior changes.

- [ ] **Step 1: Open-member-modal logging (team list screen)**

At the start of the handler that opens the team-member edit modal:

```dart
import '../../../core/debug/logger.dart';

Logger.action('openMemberModal', {
  'memberId': member.id,
  'isPermanent': member.isPermanent,
});
```

- [ ] **Step 2: Open-event-form-modal logging (event list screen)**

At the start of the handler that opens the event form modal (both create and edit paths):

```dart
import '../../../core/debug/logger.dart';

Logger.action('openEventFormModal', {
  'eventId': event?.id,
  'mode': event == null ? 'create' : 'edit',
});
```

- [ ] **Step 3: Open-manual-assignment-flow logging**

At the start of the manual-assignment-flow handler:

```dart
import '../../../core/debug/logger.dart';

Logger.action('openManualAssignmentFlow');
```

- [ ] **Step 4: Swipe-to-delete assignment logging**

In the dismiss/swipe handler of the assignment row:

```dart
Logger.action('swipeDeleteAssignment', {'assignmentId': a.id});
```

- [ ] **Step 5: Interactive filter bar change logging**

In the change handler of `InteractiveFilterBar` (every filter field):

```dart
import '../../core/debug/logger.dart';

Logger.action('filterChange', {
  'field': fieldName,
  'valueLen': Logger.redact(newValue?.toString()),
});
```

- [ ] **Step 6: Member modal availability loading**

In the modal widget that loads the member's constraints/availability:

```dart
import '../../core/debug/logger.dart';

// On loading start (e.g. initState or first build before the future fires):
Logger.loadingStart('memberAvailability', {'memberId': member.id});

// On success:
Logger.loadingEnd('memberAvailability');

// On error:
Logger.loadingEnd('memberAvailability', ok: false, error: err);
```

- [ ] **Step 7: Run analyze + full suite**

```bash
cd shavtzak && flutter analyze
cd shavtzak && flutter test
```

Expected: `No issues found!` and all tests pass.

- [ ] **Step 8: Commit**

```bash
git add shavtzak/lib/presentation/screens \
        shavtzak/lib/presentation/widgets/interactive_filter_bar.dart
# add modal files actually touched
git commit -m "feat(debug): instrument key UI sites with Logger.action and loading markers"
```

---

## Task 11: `AssignmentBloc` no-emit opt-in

**Files:**
- Modify: `shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart`
- Test: `shavtzak/test/presentation/bloc/assignment_bloc_no_emit_test.dart` (new — co-located with any existing assignment bloc tests if present)

The spec calls out the Equatable-props pitfall as the most likely root cause of example #1 (stale UI). `BlocObserver.onTransition` only fires when a state is emitted, so we can't *automatically* detect "no-emit because Equatable said equal" from the observer alone. We add a small opt-in inside `AssignmentBloc`'s update handler: when a candidate state equals the current state, record `Logger.warning('AssignmentBloc no-emit', {reason: 'equatable-equal'})` before returning.

- [ ] **Step 1: Write the failing test**

Create `shavtzak/test/presentation/bloc/assignment_bloc_no_emit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/debug/debug_logger.dart';
import 'package:shavtzak/core/debug/log_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
// import the state and event classes; replace names with real ones

void main() {
  setUp(() => DebugLogger.instance.debugClearForTests());

  test('logs warning when handler computes a state equal to current', () async {
    // 1. Construct an AssignmentBloc seeded with a known state.
    // 2. Dispatch an event whose handler computes a candidate state
    //    that is Equatable-equal to the current state.
    // 3. Assert the bloc did NOT emit (state count unchanged).
    // 4. Assert DebugLogger contains a warning with name "AssignmentBloc no-emit"
    //    and context['reason'] == 'equatable-equal'.
    // The exact event to dispatch depends on the bloc's actual API; the
    // implementer fills in the matching event/state fixtures here.
    expect(
      DebugLogger.instance.events.where((e) =>
        e.type == LogEventType.warning &&
        e.name == 'AssignmentBloc no-emit'),
      hasLength(1),
    );
  }, skip: 'fill in fixture once the bloc handler in step 2 lands');
}
```

(The test is marked `skip` until step 2 lands a recognizable handler hook; un-skip it in step 3.)

- [ ] **Step 2: Modify the update-state handler in `assignment_bloc.dart`**

Wherever the bloc handler computes a candidate next state and compares to the current state (or wherever `emit` would be called conditionally), insert before returning without emitting:

```dart
import '../../../core/debug/logger.dart';

// inside the handler, when about to skip an emission:
if (candidate == state) {
  Logger.warning('AssignmentBloc no-emit', const {
    'reason': 'equatable-equal',
  });
  return; // or simply do not call emit(...)
}
emit(candidate);
```

If the existing handler does not currently compute `candidate` ahead of `emit`, refactor the smallest possible region to do so (no behavior change — same emit-or-not decisions, just observable).

- [ ] **Step 3: Un-skip the test from step 1 and fill in the fixture**

Replace the `skip` with real event/state construction matching the actual bloc API; the assertion stays the same.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd shavtzak && flutter test test/presentation/bloc/assignment_bloc_no_emit_test.dart
```

Expected: PASS — 1 test green.

- [ ] **Step 5: Run analyze + full suite**

```bash
cd shavtzak && flutter analyze
cd shavtzak && flutter test
```

Expected: `No issues found!` and all tests pass.

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation/bloc/assignment/assignment_bloc.dart \
        shavtzak/test/presentation/bloc/assignment_bloc_no_emit_test.dart
git commit -m "feat(debug): opt-in no-emit warning in AssignmentBloc"
```

---

## Task 12: Manual end-to-end smoke verification

This is a verification step, not a code task. No commit.

- [ ] **Step 1: Run `flutter analyze` from scratch**

```bash
cd shavtzak && flutter analyze
```

Expected: `No issues found!`.

- [ ] **Step 2: Run the full test suite**

```bash
cd shavtzak && flutter test
```

Expected: all green.

- [ ] **Step 3: Hand off to the user for live smoke test**

Tell the user:

> The implementation is complete. To verify end-to-end:
>
> 1. Run the app in **test** environment (`/test/admin/events`).
> 2. Open the events tab and tap the "+" FAB normally — the new-event modal should open as before.
> 3. Long-press the "+" FAB — a small 🐞 mini-FAB should appear above it.
> 4. Tap the mini-FAB — you should see a snackbar "הלוג הועתק ללוח (N אירועים)".
> 5. Paste the clipboard into a text editor — you should see the `=== Shavtzak Debug Log ===` header followed by event lines including `NAV → /test/admin/events`, `ACTION openEventFormModal`, `DB_START watchEvents`, etc.
> 6. Repeat once on `/admin/team-members` and once on `/admin/assignments`.
> 7. Try to reproduce one of the original bugs (or simulate one) and share the resulting clipboard with the developer.
>
> If anything is off (no mini-FAB, empty buffer, snackbar text wrong), file an issue and link to the spec/plan.

---

## Self-Review (run after writing the plan)

1. **Spec coverage.** Walk §§1–13 of the spec and confirm every requirement maps to a task:
   - §6.1 `DebugLogger` → Task 2 ✓
   - §6.2 `LogEvent` + `LogEventType` → Task 1 ✓
   - §6.3 `LoggingBlocObserver` → Task 5 ✓
   - §6.4 `DebugRouteObserver` + page rules → Task 7 ✓
   - §6.5 `Logger` facade + v1 call-site list → Tasks 3, 10 ✓
   - §6.6 `LoggingDatabase` → Task 6 ✓
   - §6.7 `DebugLogShareFab` → Tasks 8, 9 ✓
   - §7 Output format → Task 4 (formatter) + Task 8 (consumer) ✓
   - §8 Privacy (redact) → Task 3 ✓
   - §9 Integration touchpoints → Tasks 5–11 across the table ✓
   - §10 Edge cases → covered in unit tests in Tasks 2, 3, 4, 6 ✓
   - §12 Testing strategy → unit + widget tests in each task ✓
   - §13 Implementation order → matches Tasks 1→11, plus the §13 step-9 smoke test = Task 12 ✓
   - §11 Future work → explicitly out of scope, no task needed ✓
   - Equatable-equal opt-in in `AssignmentBloc` (spec §6.3 / §9 / §13 step 8) → Task 11 ✓

2. **Placeholder scan.** No "TBD", "TODO", "implement later", or generic "add error handling" phrases. The two places that ask the implementer to substitute names ("real method signatures from `database_interface.dart`" in Task 6, "real state/event classes" in Task 11) are inherent to working in this codebase without prior file reads; they include concrete patterns and an explicit "no method may be skipped" instruction. Not placeholders — *site-specific substitutions* with full patterns supplied.

3. **Type consistency.**
   - `LogEvent` and `LogEventType` defined in Task 1, used identically in every later task ✓
   - `DebugLogger.instance.record(...)`, `events`, `reset(newRoute:)`, `debugClearForTests()` used consistently from Task 2 onward ✓
   - `Logger.action`, `Logger.loadingStart`, `Logger.loadingEnd(operation, {ok, error, context})`, `Logger.warning`, `Logger.redact` signatures match in Tasks 3, 8, 10, 11 ✓
   - `formatBuffer(events:, userDisplay:, isAdmin:, env:, currentRoute:, capturedAt:)` signature in Task 4 used identically in Task 8 ✓
   - `DebugLogShareFab(child:, currentRouteForShare:, userDisplay:, isAdmin:, env:)` signature in Task 8 used in Task 9 ✓
