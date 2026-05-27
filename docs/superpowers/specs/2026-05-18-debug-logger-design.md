# Debug Logger & Share — Design

- **Date:** 2026-05-18
- **Status:** Draft (awaiting review)
- **Owner:** Omer
- **Audience:** Anyone implementing or reviewing the in-app debug logger

## 1. Background

Admins (notably a power-user / "boss" persona) periodically observe behaviour we cannot reproduce:

1. **Stale UI after a write.** A field is saved (e.g. an assignment note) but the UI does not reflect it; another user, or a refresh, shows the new value. The most common root cause class is the documented Equatable-props pitfall in `CLAUDE.md` ("Use FULL objects in props, NEVER just IDs"), but a stream that did not emit, or a write that silently failed, would look identical.
2. **Infinite loading.** A loading indicator never resolves for one user but resolves immediately for another, suggesting an in-flight Firestore stream that never delivered, a BLoC subscription set up incorrectly, or a race between two state emissions.

We currently have no way to inspect what happened in the user's session after the fact. Errors do not surface, state transitions are invisible, and reload destroys the trail. We need a low-overhead, privacy-safe, always-on trace mechanism plus a one-tap way for the user to share what was captured.

## 2. Goals

- Capture enough information to diagnose state/sync bugs (BLoC transitions, Firestore traffic, navigation, key UI actions, screen-level loading start/end) **without leaking content**.
- Provide a one-tap share path from inside the admin management surface, requiring no copy/paste of console output.
- Zero configuration: always-on in both `test` and `prod` environments.
- Negligible perf cost (in-memory only, capped buffer, no I/O until the user explicitly shares).
- Slot into the existing Clean Architecture / BLoC / `DatabaseInterface` patterns without reshaping them.

## 3. Non-Goals

- **Not a telemetry/analytics pipeline.** No server-side aggregation, no usage metrics, no opt-out UI.
- **Not pointer-level UI capture.** No global gesture listener, no widget tree dumping.
- **Not for user-facing screens (v1).** The share button lives only on the three admin management tabs. Logging itself runs everywhere (so future expansion is cheap), but the trigger is admin-only.
- **No persistence across page changes.** Buffer resets on route change by explicit design — see §6.4. Cross-page issues are out of scope for v1.
- **No file download / email / Firestore upload (v1).** Clipboard only. Upload-to-Firestore is sketched in §11 (Future Work) but not built now.
- **No PII content.** Only IDs, field names, lengths. See §8 (Privacy).

## 4. The Two Worked Examples

For grounding, the spec is calibrated against the two reported bugs.

### 4.1 Stale UI after note save (example #1)

Expected trace shape with this design:

```
[ts] ACTION openAssignmentEditModal {assignmentId: a_xxx}
[ts] ACTION saveAssignment {assignmentId: a_xxx, fieldsChanged: [note]}
[ts] BLOC AssignmentBloc dispatched UpdateAssignmentRequested {assignmentId: a_xxx, note: <14 chars>}
[ts] DB write <env>_assignments/a_xxx fields=[note] → start
[ts] DB write <env>_assignments/a_xxx → ok (152 ms)
[ts] DB stream <env>_assignments emit (count=37)        ← did the stream emit?
[ts] BLOC AssignmentBloc emit AssignmentsLoaded propsChanged=[assignments]   ← did Equatable see a change?
[ts] BLOC AssignmentBloc no-emit (Equatable: equal)     ← or did it consider state unchanged?
```

The diagnostic gold is the BLoC `emit` vs `no-emit` line. If the write happened, the stream emitted, but the BLoC produced `no-emit (Equatable: equal)`, the bug is almost certainly the Equatable-props pitfall.

### 4.2 Stuck loading on team member modal (example #2)

Expected trace shape:

```
[ts] ACTION openMemberModal {memberId: m_xxx, isPermanent: false}
[ts] LOAD_START memberAvailability {memberId: m_xxx}
[ts] DB watch <env>_teamMembers/m_xxx → start
[ts] DB stream <env>_teamMembers emit (count=12)
[ts] (no further events)
```

The diagnostic gold is the absence of a matching `LOAD_END memberAvailability`. The buffer contains the last few hundred events, so we see exactly what was emitted, what was not, and the timing.

## 5. High-Level Architecture

```
                +-------------------------+
                |   DebugLogger (singleton) |
                |   - ring buffer (~200)    |
                |   - sessionMeta           |
                |   - reset(route)          |
                |   - record(LogEvent)      |
                |   - snapshotAsText()      |
                +------------▲--------------+
                             |
   +--------------+----------+-----------+----------------+
   | Bloc layer   | DB layer            | Router         | UI sites
   |              |                     |                |
   | LoggingBloc  | LoggingDatabase     | DebugRoute     | Logger.action()
   | Observer     | (decorator around   | Observer       | Logger.loadingStart()
   |              |  DatabaseInterface) |                | Logger.loadingEnd()
   +--------------+---------------------+----------------+
                             |
                             v
                +----------------------------+
                |   DebugLogShareFab widget   |
                |   wraps the existing "+"    |
                |   FAB on admin tabs:        |
                |   long-press → mini FAB →   |
                |   Clipboard.setData(text)   |
                +----------------------------+
```

Three automatic capture surfaces (BLoC, DB, Router) and one explicit API (`Logger.*`) all feed the singleton ring buffer. One UI widget consumes the buffer and copies it to the clipboard.

## 6. Components

### 6.1 `DebugLogger` (singleton)

**Purpose.** Owns the ring buffer and the session metadata; provides the public recording and snapshot API.

**Location.** `lib/core/debug/debug_logger.dart` (new directory `lib/core/debug/`).

**Public API.**

```dart
class DebugLogger {
  static final DebugLogger instance = DebugLogger._();
  DebugLogger._();

  /// Capacity of the ring buffer in events. Constant for v1.
  static const int capacity = 200;

  /// Record a single event. Cheap; safe to call from any thread/zone.
  void record(LogEvent event);

  /// Reset the buffer. Called by the router observer on every route change.
  /// Records a synthetic NAV event as the first entry of the new buffer.
  void reset({required String newRoute});

  /// Convenience recorders used by the explicit API. Defined on the static
  /// helper `Logger` (see 6.5) which delegates here.

  /// Snapshot the buffer as a share-friendly plain text blob, including
  /// the header (user, env, route, captured timestamp, event count) and
  /// one line per event. Does NOT clear the buffer.
  String snapshotAsText({
    required String? userDisplay,
    required bool isAdmin,
    required String env,
    required String currentRoute,
  });

  /// For tests / debug overlays. Returns an unmodifiable view.
  List<LogEvent> get events;
}
```

**Internals.**

- Uses `dart:collection` `Queue<LogEvent>` with manual size enforcement: on `record()`, if `events.length == capacity`, `removeFirst()` before `add()`.
- Records timestamps as `DateTime.now().toUtc()` so all entries are comparable regardless of locale.
- Never throws. All recording paths are wrapped in `try { ... } catch (_) {}`; logging must never break the app.

**Thread/zone safety.** Flutter runs on a single isolate. No locking required. If we ever record from a different zone, the singleton is still safe because `Queue` mutations are synchronous.

### 6.2 `LogEvent`

**Purpose.** Strongly-typed record of one captured event.

**Location.** Same file as `DebugLogger`.

```dart
enum LogEventType {
  nav,           // route change
  action,        // explicit Logger.action() — semantic UI event
  blocDispatch,  // a BLoC received an event
  blocEmit,      // a BLoC emitted a state (with propsChanged when known)
  blocNoEmit,    // a BLoC chose not to emit (Equatable considered equal)
  blocError,     // a BLoC produced an error
  dbStart,       // DB read/write/watch began
  dbEnd,         // DB read/write completed
  dbStreamEmit,  // a watched stream emitted
  dbError,       // DB call threw
  loadStart,     // explicit Logger.loadingStart()
  loadEnd,       // explicit Logger.loadingEnd()
  warning,       // freeform diagnostic
}

class LogEvent {
  final DateTime timestamp;     // UTC
  final LogEventType type;
  final String name;            // human-readable label
  final Map<String, Object?> context;   // structured, JSON-safe
  final Duration? duration;     // only for *End-ish events
}
```

`context` values are restricted to JSON-safe primitives (`String`, `num`, `bool`, `null`, `List`, `Map`). Anything richer is converted via `toString()` at record time so the buffer never holds references that prevent GC.

### 6.3 `LoggingBlocObserver`

**Purpose.** Captures every BLoC event dispatched and every state transition across all BLoCs in the app, plus errors.

**Location.** `lib/core/debug/logging_bloc_observer.dart`.

**Wiring point.** `lib/main.dart`, immediately after `WidgetsFlutterBinding.ensureInitialized()`:

```dart
Bloc.observer = LoggingBlocObserver();
```

**Coverage.** Implement the four hooks of `BlocObserver`:

| Hook            | Recorded type                                    | Notes |
|-----------------|--------------------------------------------------|-------|
| `onEvent`       | `blocDispatch`                                   | `name: "${bloc.runtimeType} ← ${event.runtimeType}"`, `context: { fields: redact(event) }` |
| `onTransition`  | `blocEmit` (or `blocNoEmit` — see below)         | `name: "${bloc.runtimeType} → ${nextState.runtimeType}"`, `context: { propsChanged: <List<String>> }` |
| `onError`       | `blocError`                                      | `context: { error: e.toString(), stackHead: stack.first }` |
| `onChange`      | reserved (not currently logged — redundant with `onTransition` for `Bloc`, only fires for `Cubit`) | |

**Detecting "no-emit because Equatable saw equal".** `BlocObserver.onTransition` only fires when a state change is actually emitted. To detect *suppressed* emissions, we cannot intercept Equatable comparisons from the observer alone. Instead, the suppression diagnostic is opt-in per BLoC: a BLoC that wants to surface it can call `Logger.warning('AssignmentBloc no-emit', {reason: 'equatable-equal'})` from its handler when it computed a candidate state, compared, and chose not to emit. For v1, we wire this into `AssignmentBloc` (highest-signal site, given example #1) and document the pattern; other BLoCs can opt in later. This is intentionally lightweight — full automatic detection would require a custom base class for all BLoCs, which is a larger refactor we are *not* doing here.

**Computing `propsChanged`.** Each entity / state class extends `Equatable` with `props` defined. We compute `propsChanged` by iterating `current.props` and `next.props` pairwise and recording the indices that differ. Because `Equatable` does not name its props, the observer reports them by index plus the state's `runtimeType` — sufficient to spot "nothing changed" vs "field at index 2 changed". (A later improvement could thread named props through a mixin, but is out of scope.)

### 6.4 `DebugRouteObserver`

**Purpose.** Listens to GoRouter route changes and triggers `DebugLogger.reset()` on every navigation. Records the new route as the buffer's first event.

**Location.** `lib/core/debug/debug_route_observer.dart`.

**Wiring point.** `lib/core/router/app_router.dart` — added to the `GoRouter` configuration's `observers` (or wrapping `NavigatorObserver`s on each `StatefulShellRoute` branch as the existing pattern allows).

**"Page" definition (per design discussion).** A *page* is a route push/replace at the GoRouter level. Concretely:

| User action                                                  | Page change? | Buffer reset? |
|--------------------------------------------------------------|--------------|---------------|
| Swipe between `/admin/team-members` ↔ `/admin/events`         | Yes          | Yes |
| Tap a row to open an `EventFormModal` over the events screen | No (modal is in-page) | No |
| Open the team member edit modal                              | No           | No |
| Navigate from `/admin/events` to `/admin/assignments`         | Yes          | Yes |
| Pull-to-refresh / soft reload                                | No           | No |

This matches both worked examples: example #2's stuck loading happens after opening a modal, so the buffer still contains the originating `openMemberModal` action. Example #1's save flow opens a modal, saves, and closes — all within one page — so the entire save → stream → BLoC chain is in the buffer.

If `SwipeablePageView` swipes between admin tabs without going through GoRouter (i.e. the URL does not change), it must publish the equivalent reset by calling `DebugLogger.instance.reset(newRoute: ...)` from its `onPageChanged`. This is a known integration touch-point (§9).

### 6.5 Explicit API: `Logger`

**Purpose.** Lightweight static facade for explicit instrumentation at UI sites that do not naturally route through BLoC.

**Location.** `lib/core/debug/logger.dart`.

```dart
class Logger {
  static void action(String name, [Map<String, Object?> context = const {}]);
  static void loadingStart(String operation, [Map<String, Object?> context = const {}]);
  static void loadingEnd(String operation, {bool ok = true, Object? error, Map<String, Object?> context = const {}});
  static void warning(String name, [Map<String, Object?> context = const {}]);
  static String redact(String? raw); // returns "<N chars>" or "<null>"
}
```

`loadingEnd` looks up the most recent matching `loadingStart` by `operation` name in the buffer and writes the elapsed `Duration` into the `LogEvent.duration` field. If no matching start is found, it still records an `loadEnd` event with `duration: null` and `context: { unmatched: true }`.

**Call-site list (v1).** The explicit-instrumentation points we add as part of this work:

| Call site                                              | Event |
|--------------------------------------------------------|-------|
| Open team member modal                                 | `action("openMemberModal", {memberId, isPermanent})` |
| Open event form modal (create or edit)                 | `action("openEventFormModal", {eventId?, mode})` |
| Open manual assignment flow dialog                     | `action("openManualAssignmentFlow")` |
| Filter bar change (interactive filter bar)             | `action("filterChange", {field, valueLen})` |
| Swipe-to-delete on an assignment row                   | `action("swipeDeleteAssignment", {assignmentId})` |
| Member modal: start loading availability/constraints   | `loadingStart("memberAvailability", {memberId})` |
| Member modal: availability/constraints loaded or error | `loadingEnd("memberAvailability", ok: ...)` |
| Event detail: start loading assignments                | `loadingStart("eventAssignments", {eventId})` |
| Event detail: assignments loaded                       | `loadingEnd("eventAssignments", ok: ...)` |
| Long-press FAB → mini-FAB revealed                     | `action("debugShareMenuOpen")` |
| Mini-FAB tapped (logs copied)                          | `action("debugShareLogsCopied", {bytes, eventCount})` |

(This is the v1 set. New screens can add more as needed. The pattern is grep-able and additive.)

### 6.6 `LoggingDatabase` decorator

**Purpose.** Wraps the existing `DatabaseInterface` implementation (currently `FirestoreDatabase`) and records `dbStart` / `dbEnd` / `dbStreamEmit` / `dbError` for every call. Pure decorator — does not change behaviour or ordering.

**Location.** `lib/data/data_sources/logging_database.dart`.

**Wiring point.** In whatever site currently constructs `FirestoreDatabase` (per `CLAUDE.md`, dependency wiring goes through `service_locator.dart` / `environment_aware_factory.dart` for env-aware features, and direct construction elsewhere). The repository constructors that today receive a `DatabaseInterface` will receive `LoggingDatabase(FirestoreDatabase(...))` instead. No repository code changes.

**Pattern.** For each method on `DatabaseInterface`:

```dart
@override
Future<List<EventModel>> getEvents() async {
  final start = DateTime.now();
  DebugLogger.instance.record(LogEvent(
    timestamp: start,
    type: LogEventType.dbStart,
    name: 'getEvents',
    context: const {'collection': 'events'},
  ));
  try {
    final result = await _inner.getEvents();
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now(),
      duration: DateTime.now().difference(start),
      type: LogEventType.dbEnd,
      name: 'getEvents',
      context: {'count': result.length, 'ok': true},
    ));
    return result;
  } catch (e, s) {
    DebugLogger.instance.record(LogEvent(
      timestamp: DateTime.now(),
      duration: DateTime.now().difference(start),
      type: LogEventType.dbError,
      name: 'getEvents',
      context: {'error': e.toString(), 'stackHead': s.toString().split('\n').first},
    ));
    rethrow;
  }
}
```

For `watchX()` stream methods, the pattern wraps the returned `Stream` with `.map((snapshot) { record(dbStreamEmit, count: snapshot.length); return snapshot; })`. The initial subscription is logged as `dbStart` and disposal as a synthetic `dbEnd` with `{disposed: true}`.

**Collection name redaction.** The environment prefix (`test_` / empty) is preserved in logs — it is diagnostic, not sensitive.

### 6.7 `DebugLogShareFab` widget

**Purpose.** Wraps the existing "+" FAB on the three admin management screens. Long-press reveals a mini-FAB; tap on the mini-FAB copies the buffer to the clipboard.

**Location.** `lib/presentation/widgets/debug_log_share_fab.dart`.

**API.**

```dart
class DebugLogShareFab extends StatefulWidget {
  final Widget child; // the existing "+" FloatingActionButton
  const DebugLogShareFab({super.key, required this.child});
}
```

**Behaviour.**

- Renders `child` inside a `GestureDetector` (or `Listener`) so that taps still propagate to the FAB's `onPressed`, but long-press is captured for the debug menu.
- On long-press: toggles internal `_menuVisible = true` and starts a 4-second auto-dismiss timer. The mini-FAB is rendered slightly above/start-side of the primary FAB inside the same `Stack`.
- Mini-FAB icon: `Icons.bug_report` (or 🐞 in a `Text` if we want to stay icon-pack-free). Tooltip text: "העתק לוג תקלה".
- On mini-FAB tap:
  1. Take a `DebugLogger.instance.snapshotAsText(...)`.
  2. `Clipboard.setData(ClipboardData(text: snapshot))`.
  3. Show a snackbar: `"הלוג הועתק ללוח (N אירועים)"`.
  4. Record `Logger.action("debugShareLogsCopied", {bytes, eventCount})`.
  5. Dismiss the menu.
- Tap-outside or timer expiry: dismiss the menu silently.

**Native long-press caveat.** Flutter's `FloatingActionButton` exposes `onPressed` but not `onLongPress`. The wrapping `GestureDetector` is configured with `behavior: HitTestBehavior.translucent` and we set `onLongPress`, while letting the FAB's own gesture detector handle taps. Tests cover the "tap still saves" + "long-press still opens menu" cases.

**Wiring point.** In each of the three admin screens — `team_list_screen.dart`, `event_list_screen.dart`, `assignment_list_screen.dart` — the `Scaffold.floatingActionButton: FloatingActionButton(...)` is wrapped: `floatingActionButton: DebugLogShareFab(child: FloatingActionButton(...))`. No other change to those screens.

## 7. Output Format (clipboard payload)

Plain text. UTF-8. Designed to be share-friendly via WhatsApp/email and trivially parseable by eye.

```
=== Shavtzak Debug Log ===
User: <displayName> (admin) | Env: prod | Route: /admin/assignments
Captured: 2026-05-18T14:30:00.123Z | Events: 47

[14:29:51.123Z] NAV → /admin/assignments (reset)
[14:29:53.456Z] ACTION openMemberModal {memberId: m_abc, isPermanent: false}
[14:29:53.460Z] LOAD_START memberAvailability {memberId: m_abc}
[14:29:53.502Z] DB_START watch test_teamMembers/m_abc
[14:29:54.654Z] DB_STREAM_EMIT test_teamMembers count=12
[14:29:54.660Z] BLOC_EMIT TeamBloc → TeamLoaded propsChanged=[0]
[14:29:54.700Z] BLOC_NO_EMIT AssignmentBloc (equatable-equal)
...
```

**Rules.**

- Header is exactly four lines: `=== Shavtzak Debug Log ===`, identity line, capture line, blank.
- Each event: `[HH:mm:ss.SSSZ] TYPE name [propsChanged=[..]] [{context}] [(duration ms)]`.
- Timestamps are UTC, suffixed `Z`, to second + millis. Date appears only in the header.
- `context` is rendered as a compact, single-line `{k: v, k2: v2}` with strings unquoted. No content fields ever appear here (see §8).

**Size.** Empirically, 200 events at ~120 bytes each ≈ 24 KB. Well under any practical clipboard or messaging limit.

## 8. Privacy

The buffer **must not** capture raw user content. The user we are most likely to ask for logs is the boss, who has access to operational data (team members, events with locations, assignments with notes). We log structure, not substance.

**Allowed.**

- Entity IDs (`assignmentId`, `eventId`, `memberId`).
- Collection names including env prefix (`test_teamMembers`).
- Field names that were changed (`fieldsChanged: [note, location]`).
- Lengths and counts (`note: <14 chars>`, `members: 12`).
- Booleans / enums (`isPermanent: false`, `mode: edit`).
- BLoC / state class `runtimeType` names.
- Error class names and the first line of the stack.

**Not allowed.**

- Raw note text, member names, emails, phone numbers, locations.
- Anything that would let a third party identify an individual from the log alone.

**Enforcement.**

- All explicit call sites use `Logger.redact(...)` for any field that could contain content.
- `LoggingBlocObserver.onEvent` walks the dispatched event's `props` (or `toString()`) and records only field *names* it can syntactically identify. As a defensive default, it never dumps the entire `event.toString()` — only `{eventType: ..., fields: [...]}` derived from a small allow-list of types (`int`, `bool`, ID-shaped strings).
- The `LoggingDatabase` decorator records collection name + IDs + counts only. It does not record the document payload.
- A unit test asserts that for a representative `Assignment` write with `note: "secret"`, the buffer contains `<6 chars>` and **does not** contain the literal `secret`.

## 9. Integration Touch-points

Concrete change-list, organised by file/area. Implementation will follow this list.

| File / area                                                                | Change |
|-----------------------------------------------------------------------------|--------|
| `lib/core/debug/debug_logger.dart` (new)                                    | Implement `DebugLogger`, `LogEvent`, `LogEventType`. |
| `lib/core/debug/logger.dart` (new)                                          | Implement static `Logger` facade. |
| `lib/core/debug/logging_bloc_observer.dart` (new)                           | Implement `LoggingBlocObserver`. |
| `lib/core/debug/debug_route_observer.dart` (new)                            | Implement `DebugRouteObserver` extending `NavigatorObserver`. |
| `lib/data/data_sources/logging_database.dart` (new)                         | Implement `LoggingDatabase` decorator over `DatabaseInterface`. |
| `lib/presentation/widgets/debug_log_share_fab.dart` (new)                   | Implement the share-FAB wrapper widget. |
| `lib/main.dart`                                                             | Set `Bloc.observer = LoggingBlocObserver()` after `WidgetsFlutterBinding.ensureInitialized()`. |
| `lib/core/services/service_locator.dart` (and/or `environment_aware_factory.dart`) | When constructing the database for repositories, wrap with `LoggingDatabase(FirestoreDatabase(...))`. |
| `lib/core/router/app_router.dart`                                           | Attach `DebugRouteObserver` to the `GoRouter` (and to inner shells if `StatefulShellRoute` requires per-branch attachment). |
| `lib/presentation/widgets/swipeable_page_view.dart`                         | In `onPageChanged`, call `DebugLogger.instance.reset(newRoute: <tab name or route>)` because the swipe may not push a new GoRouter route. |
| `lib/presentation/screens/team/team_list_screen.dart`                       | Wrap FAB with `DebugLogShareFab(child: ...)`. Add `Logger.action` at member-modal open. |
| `lib/presentation/screens/event/event_list_screen.dart`                     | Wrap FAB with `DebugLogShareFab(child: ...)`. Add `Logger.action` at event-form-modal open. |
| `lib/presentation/screens/assignment/assignment_list_screen.dart`           | Wrap FAB with `DebugLogShareFab(child: ...)`. Add `Logger.action` at manual-assignment-flow open + swipe-delete. |
| (Team member modal widget — wherever it lives)                              | Add `Logger.loadingStart/End` around availability/constraints fetch. |
| `lib/presentation/bloc/assignment/assignment_bloc.dart`                     | Inside the update-state handler, if `current == candidate`, call `Logger.warning('AssignmentBloc no-emit', {reason: 'equatable-equal'})` before returning without emitting. |
| `lib/presentation/widgets/interactive_filter_bar.dart`                      | Add `Logger.action` on filter change. |

**No environment gating.** Logging runs in both `test` and `prod`. The share button placement is the only gate. (We considered making logging `kDebugMode`-only and rejected: the whole point is that the bug repros on the boss's `prod` build, not on a developer's debug build.)

## 10. Edge Cases & Error Handling

- **Buffer full.** `record()` drops the oldest entry. The header's `Events:` count reflects what is currently held, not historical total.
- **`record()` throws.** Wrapped in `try { ... } catch (_) {}`. The app does not crash because of logging. A test asserts this for a deliberately broken `LogEvent` (e.g. unencodable context).
- **Clipboard write fails.** Catch the platform exception. Show a snackbar `"שגיאה בהעתקה ללוח"`. Log a `warning` event before the failure (which the user can then... not share — degraded but acceptable).
- **`Logger.loadingEnd` with no matching start.** Recorded with `unmatched: true` and `duration: null`. Does not throw. (Useful: an "end without start" itself signals a control-flow bug.)
- **`SwipeablePageView` page change races a GoRouter push.** Both routes get reset events; the later one wins. Acceptable — we lose at most a few microseconds of trace.
- **Hot reload during development.** The singleton survives hot reload (it's a top-level `static final`). The buffer therefore carries across reloads. Documented; not a v1 problem.
- **Web (PWA) clipboard permissions.** `Clipboard.setData` requires a user gesture on web — we are inside a tap handler, so permission is granted by the gesture. Tested manually.
- **Very long event names / contexts.** The text formatter truncates any single field's stringified value to 200 chars and appends `…(truncated)`. Prevents one malformed entry from dominating the share payload.

## 11. Future Work (explicitly out of scope for v1)

- **Firestore upload share path.** Add a second mini-FAB that writes the buffer to `debugLogs` (env-prefixed) so the admin can read it from Firebase Console without the user pasting anything. Requires a Firestore security rule allowing the user's own writes.
- **User-facing screens.** Add `DebugLogShareFab` to `/user/*` if non-admin users start reporting reproducible issues.
- **Automated equatable-equal detection.** Introduce a `LoggingBlocBase` that always computes the candidate state, compares to current, and records `blocNoEmit` if equal — removing the need for opt-in per BLoC.
- **Filtering / search.** A small overlay listing the in-memory events with type filters and copy-by-range.
- **Persistence across reloads.** Optional `localStorage` mirror of the last buffer for "the page crashed before I could long-press."
- **Severity levels & sampling.** Currently every event is recorded. If volume becomes a problem in some hot path, add a sampling rate.

## 12. Testing Strategy

Test coverage at three levels.

**Unit (most of the value).**

- `DebugLogger` ring buffer: fills to `capacity`, then drops oldest in FIFO order.
- `DebugLogger.reset` records a synthetic NAV event and discards everything else.
- `LoggingBlocObserver.onEvent` / `onTransition` produce well-formed `LogEvent`s for a fixture BLoC.
- `LoggingDatabase` delegates correctly to the inner `DatabaseInterface` for at least one `get*`, one `watch*`, and one `insert*` method, and records start/end events with non-zero `duration`.
- Text formatter: golden test against a fixed buffer → expected string.
- Redaction: an event whose context contains `{note: "secret"}` formatted via `Logger.redact` produces `<6 chars>` and does **not** contain `secret`.

**Widget.**

- `DebugLogShareFab`: a normal tap still invokes the inner FAB's `onPressed`.
- A long-press reveals the mini-FAB; tapping it triggers `Clipboard.setData` (mocked) with a non-empty payload and shows the success snackbar.
- The mini-FAB auto-dismisses after 4 seconds.

**Integration (one happy path).**

- Drive a fake BLoC + fake `DatabaseInterface` through the example-#1 sequence (action → BLoC dispatch → DB write → stream emit → BLoC emit). Assert the buffer's event-type sequence matches the expected shape.

The project uses `bloc_test`, `mockito`, `fake_cloud_firestore` per `CLAUDE.md`, so all of the above can run without additional dependencies.

## 13. Implementation Order (suggested)

Each item is independently mergeable.

1. `LogEvent`, `LogEventType`, `DebugLogger` + unit tests for the ring buffer & reset.
2. `Logger` static facade + text formatter + redaction helper + unit tests.
3. `LoggingBlocObserver` + unit tests; wire `Bloc.observer` in `main.dart`.
4. `LoggingDatabase` decorator + unit tests; wire in service locator.
5. `DebugRouteObserver` + unit tests; wire in `app_router.dart`; teach `SwipeablePageView` to reset on tab change.
6. `DebugLogShareFab` widget + widget tests; wrap FABs on the three admin screens.
7. Explicit instrumentation at the v1 call-site list in §6.5.
8. One opt-in `Logger.warning('… no-emit …')` in `AssignmentBloc` (matches example #1).
9. Manual end-to-end test in `/test/*` env, then `/prod`.

## 14. Open Questions

None tracked. (Anything that comes up during planning lands in the implementation plan, not this design.)
