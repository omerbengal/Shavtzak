# Invite-all-permanent-when-unassigned Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in per-event toggle that invites every eligible permanent team member to an event's Google Calendar event(s) while the event has zero assignments, reverting to per-assignee invites once the first assignment exists (sticky + self-resuming).

**Architecture:** A new persisted `bool` on `Event` (`inviteAllPermanentWhenUnassigned`) controls a new toggle in the event modal, coupled to the existing "permanent team only" switch. The substitution rule ("if flag on AND permanent-only AND zero assignments → attendees = all eligible permanent members") is mirrored in the two independent attendee-computation paths: the Flutter client (`CalendarSyncService.syncAttendeesForAppEvent`) and the Cloud Functions backend reconcile path (`readEventAttendeeEmails`). The rule is evaluated live on every sync, so "sticky + self-resuming" requires no state machine.

**Tech Stack:** Flutter/Dart (web app under `shavtzak/`), Firebase Cloud Functions TypeScript 5.8 / Node 20 (under `functions/`), Firestore.

**Spec:** `docs/superpowers/specs/2026-05-18-calendar-invite-all-permanent-when-unassigned-design.md`

**Testing approach (read before starting):**
- **Backend (TypeScript):** the project has an existing automated-test convention — `npm test` runs `tsc` then `node --test "lib/**/*.test.js"`, with existing tests like `functions/src/availability.test.ts` (`import test from 'node:test'`, `import assert from 'node:assert/strict'`). Backend logic is built TDD-style with a real test file.
- **Flutter (Dart):** per the authoritative project `CLAUDE.md` ("Testing infrastructure exists but no tests implemented yet"; "Run `flutter analyze`… Do not run the app - I will run the app myself"), the Dart side has **no unit-test convention**. Dart tasks are verified by `flutter analyze` (the project's gate) plus the written manual protocol in Task 8, executed by the project owner. This is a deliberate, project-faithful deviation from default TDD; do not scaffold a Dart test framework.

**No `firestore.rules` change is required.** Firestore rules are not schemas; the new event field is written as part of the existing admin event-write, and the backend reads `teamMembers` via the Admin SDK (rules bypassed). The plan includes no rules edit by design.

---

### Task 1: Add `inviteAllPermanentWhenUnassigned` to the `Event` entity

**Files:**
- Modify: `shavtzak/lib/domain/entities/event.dart`

- [ ] **Step 1: Add the field declaration after `isDeactivated`**

Edit `shavtzak/lib/domain/entities/event.dart` — old:

```dart
  // Lifecycle / status
  final bool isDeactivated; // Admin-controlled "on hold": hides from /admin/assignments, /user/assignments, summary; deletes calendar events; assignments preserved for reactivation
```

new:

```dart
  // Lifecycle / status
  final bool isDeactivated; // Admin-controlled "on hold": hides from /admin/assignments, /user/assignments, summary; deletes calendar events; assignments preserved for reactivation

  // Calendar: when true AND the event is permanent-only AND the event has zero
  // assignments, invite all eligible permanent members to the calendar event(s)
  final bool inviteAllPermanentWhenUnassigned;
```

- [ ] **Step 2: Add the constructor parameter**

Edit — old:

```dart
    this.relevantForExtendedTeam = false,
    this.isDeactivated = false,
  });
```

new:

```dart
    this.relevantForExtendedTeam = false,
    this.isDeactivated = false,
    this.inviteAllPermanentWhenUnassigned = false,
  });
```

- [ ] **Step 3: Add the `copyWith` parameter**

Edit — old:

```dart
    bool? relevantForExtendedTeam,
    bool? isDeactivated,
    bool clearParkingLocation = false, // Flag to explicitly clear nullable fields
```

new:

```dart
    bool? relevantForExtendedTeam,
    bool? isDeactivated,
    bool? inviteAllPermanentWhenUnassigned,
    bool clearParkingLocation = false, // Flag to explicitly clear nullable fields
```

- [ ] **Step 4: Add the `copyWith` body assignment**

Edit — old:

```dart
      relevantForExtendedTeam: relevantForExtendedTeam ?? this.relevantForExtendedTeam,
      isDeactivated: isDeactivated ?? this.isDeactivated,
    );
  }
```

new:

```dart
      relevantForExtendedTeam: relevantForExtendedTeam ?? this.relevantForExtendedTeam,
      isDeactivated: isDeactivated ?? this.isDeactivated,
      inviteAllPermanentWhenUnassigned:
          inviteAllPermanentWhenUnassigned ?? this.inviteAllPermanentWhenUnassigned,
    );
  }
```

- [ ] **Step 5: Add the field to `props` (required for real-time UI updates)**

Edit — old:

```dart
        driveFolderLink,
        relevantForExtendedTeam,
        isDeactivated,
      ];
```

new:

```dart
        driveFolderLink,
        relevantForExtendedTeam,
        isDeactivated,
        inviteAllPermanentWhenUnassigned,
      ];
```

- [ ] **Step 6: Analyze**

Run: `cd shavtzak && flutter analyze`
Expected: `No issues found!` (exit code 0). If the analyzer reports errors, fix them before continuing; there must be no errors and no new warnings introduced by this task.

- [ ] **Step 7: Commit**

```bash
git add shavtzak/lib/domain/entities/event.dart
git commit -m "Add inviteAllPermanentWhenUnassigned to Event entity"
```

---

### Task 2: Thread the field through `EventModel`

**Files:**
- Modify: `shavtzak/lib/data/models/event_model.dart`

- [ ] **Step 1: Add the field declaration**

Edit `shavtzak/lib/data/models/event_model.dart` — old:

```dart
  // Lifecycle / status
  final bool isDeactivated;
```

new:

```dart
  // Lifecycle / status
  final bool isDeactivated;

  // Calendar: invite all eligible permanent members while event has 0 assignments
  final bool inviteAllPermanentWhenUnassigned;
```

- [ ] **Step 2: Add the constructor parameter**

Edit — old:

```dart
    this.relevantForExtendedTeam = false,
    this.isDeactivated = false,
  });
```

new:

```dart
    this.relevantForExtendedTeam = false,
    this.isDeactivated = false,
    this.inviteAllPermanentWhenUnassigned = false,
  });
```

- [ ] **Step 3: `fromEntity`**

Edit — old:

```dart
      relevantForExtendedTeam: entity.relevantForExtendedTeam,
      isDeactivated: entity.isDeactivated,
    );
  }
```

new:

```dart
      relevantForExtendedTeam: entity.relevantForExtendedTeam,
      isDeactivated: entity.isDeactivated,
      inviteAllPermanentWhenUnassigned: entity.inviteAllPermanentWhenUnassigned,
    );
  }
```

- [ ] **Step 4: `toEntity`**

Edit — old:

```dart
      relevantForExtendedTeam: relevantForExtendedTeam,
      isDeactivated: isDeactivated,
    );
  }
```

new:

```dart
      relevantForExtendedTeam: relevantForExtendedTeam,
      isDeactivated: isDeactivated,
      inviteAllPermanentWhenUnassigned: inviteAllPermanentWhenUnassigned,
    );
  }
```

- [ ] **Step 5: `fromFirestore`**

Edit — old:

```dart
      relevantForExtendedTeam:
          data['relevantForExtendedTeam'] as bool? ?? false,
      isDeactivated: data['isDeactivated'] as bool? ?? false,
    );
  }
```

new:

```dart
      relevantForExtendedTeam:
          data['relevantForExtendedTeam'] as bool? ?? false,
      isDeactivated: data['isDeactivated'] as bool? ?? false,
      inviteAllPermanentWhenUnassigned:
          data['inviteAllPermanentWhenUnassigned'] as bool? ?? false,
    );
  }
```

- [ ] **Step 6: `toFirestore`**

Edit — old:

```dart
      'relevantForExtendedTeam': relevantForExtendedTeam,
      'isDeactivated': isDeactivated,
    };
  }
```

new:

```dart
      'relevantForExtendedTeam': relevantForExtendedTeam,
      'isDeactivated': isDeactivated,
      'inviteAllPermanentWhenUnassigned': inviteAllPermanentWhenUnassigned,
    };
  }
```

- [ ] **Step 7: `fromJson`**

Edit — old:

```dart
      relevantForExtendedTeam:
          json['relevantForExtendedTeam'] as bool? ?? false,
      isDeactivated: json['isDeactivated'] as bool? ?? false,
    );
  }
```

new:

```dart
      relevantForExtendedTeam:
          json['relevantForExtendedTeam'] as bool? ?? false,
      isDeactivated: json['isDeactivated'] as bool? ?? false,
      inviteAllPermanentWhenUnassigned:
          json['inviteAllPermanentWhenUnassigned'] as bool? ?? false,
    );
  }
```

- [ ] **Step 8: `toJson`**

Edit — old:

```dart
      'relevantForExtendedTeam': relevantForExtendedTeam,
      'isDeactivated': isDeactivated,
    };
  }
}
```

new:

```dart
      'relevantForExtendedTeam': relevantForExtendedTeam,
      'isDeactivated': isDeactivated,
      'inviteAllPermanentWhenUnassigned': inviteAllPermanentWhenUnassigned,
    };
  }
}
```

- [ ] **Step 9: Analyze**

Run: `cd shavtzak && flutter analyze`
Expected: `No issues found!` (exit code 0).

- [ ] **Step 10: Commit**

```bash
git add shavtzak/lib/data/models/event_model.dart
git commit -m "Thread inviteAllPermanentWhenUnassigned through EventModel"
```

---

### Task 3: Add the toggle to the event form modal

**Files:**
- Modify: `shavtzak/lib/presentation/screens/event/widgets/event_form_modal.dart`

- [ ] **Step 1: Add the state variable**

Edit `shavtzak/lib/presentation/screens/event/widgets/event_form_modal.dart` — old:

```dart
  bool _relevantForExtendedTeam =
      true; // Event is relevant for extended team (UI is inverted)
```

new:

```dart
  bool _relevantForExtendedTeam =
      true; // Event is relevant for extended team (UI is inverted)
  // Calendar: invite all permanent staff while the event has no assignments.
  // Only meaningful when the "permanent team only" switch is ON.
  bool _inviteAllPermanentWhenUnassigned = false;
```

- [ ] **Step 2: Initialize it from the event in edit mode**

Edit — old:

```dart
      // Load relevant for extended team (inverted for UI)
      _relevantForExtendedTeam = !widget.event!.relevantForExtendedTeam;
    }
```

new:

```dart
      // Load relevant for extended team (inverted for UI)
      _relevantForExtendedTeam = !widget.event!.relevantForExtendedTeam;
      _inviteAllPermanentWhenUnassigned =
          widget.event!.inviteAllPermanentWhenUnassigned;
    }
```

- [ ] **Step 3: Couple the existing "permanent team only" switch and add the new toggle**

Note on polarity: the existing switch's `value` is `_relevantForExtendedTeam`. Because of the inverted UI naming, `_relevantForExtendedTeam == true` means the switch is **ON = "permanent team only"**. So when the user turns it OFF (`v == false`), the new toggle must be reset and disabled.

Edit — old:

```dart
                                        // Permanent Team Only (inverted logic for UI)
                                        SwitchListTile(
                                          title: const Text('צוות קבוע בלבד?'),
                                          subtitle: const Text(
                                              'האם האירוע מיועד לצוות הקבוע בלבד (לא לצוות המורחב)?'),
                                          value: _relevantForExtendedTeam,
                                          onChanged: (v) => setState(() {
                                            _relevantForExtendedTeam = v;
                                            _isDirty = true;
                                          }),
                                        ),

                                        // Duplicate Assignments (only show in duplication mode)
```

new:

```dart
                                        // Permanent Team Only (inverted logic for UI)
                                        SwitchListTile(
                                          title: const Text('צוות קבוע בלבד?'),
                                          subtitle: const Text(
                                              'האם האירוע מיועד לצוות הקבוע בלבד (לא לצוות המורחב)?'),
                                          value: _relevantForExtendedTeam,
                                          onChanged: (v) => setState(() {
                                            _relevantForExtendedTeam = v;
                                            if (!v) {
                                              // Not permanent-only: this feature
                                              // is not applicable.
                                              _inviteAllPermanentWhenUnassigned =
                                                  false;
                                            }
                                            _isDirty = true;
                                          }),
                                        ),

                                        // Invite all permanent staff to the
                                        // calendar while the event has no
                                        // assignments. Enabled only while
                                        // "permanent team only" is ON.
                                        SwitchListTile(
                                          title: const Text(
                                              'הזמן את כל הצוות הקבוע כשאין שיבוצים?'),
                                          subtitle: const Text(
                                              'כשאין אף שיבוץ באירוע, כל הצוות הקבוע עם אימייל יוזמן ליומן. עם השיבוץ הראשון – רק המשובצים יוזמנו.'),
                                          value: _relevantForExtendedTeam &&
                                              _inviteAllPermanentWhenUnassigned,
                                          onChanged: _relevantForExtendedTeam
                                              ? (v) => setState(() {
                                                    _inviteAllPermanentWhenUnassigned =
                                                        v;
                                                    _isDirty = true;
                                                  })
                                              : null,
                                        ),

                                        // Duplicate Assignments (only show in duplication mode)
```

- [ ] **Step 4: Persist the field on save (defensively false when not permanent-only)**

Edit — old:

```dart
      relevantForExtendedTeam:
          !_relevantForExtendedTeam, // Invert back for database
    );
```

new:

```dart
      relevantForExtendedTeam:
          !_relevantForExtendedTeam, // Invert back for database
      inviteAllPermanentWhenUnassigned:
          _relevantForExtendedTeam && _inviteAllPermanentWhenUnassigned,
    );
```

- [ ] **Step 5: Analyze**

Run: `cd shavtzak && flutter analyze`
Expected: `No issues found!` (exit code 0).

- [ ] **Step 6: Commit**

```bash
git add shavtzak/lib/presentation/screens/event/widgets/event_form_modal.dart
git commit -m "Add invite-all-permanent toggle to event modal, coupled to permanent-only switch"
```

---

### Task 4: Apply the rule in the Flutter client sync path

**Files:**
- Modify: `shavtzak/lib/core/services/calendar_sync_service.dart`

`TeamMember` is already imported at the top of this file (`import '../../domain/entities/team_member.dart';`). `DatabaseInterface` already exposes `getEventById`, `getTeamMembers`, `getTeamMemberById`, and `getAssignmentsByEvent`.

- [ ] **Step 1: Add the eligibility helper method**

Edit `shavtzak/lib/core/services/calendar_sync_service.dart` — old:

```dart
  /// Sync all attendees for app event
  /// Fetches all assignments for event and adds all team member emails as attendees
  Future<void> syncAttendeesForAppEvent(String eventId) async {
```

new:

```dart
  /// A member is eligible for the "invite all permanent staff" calendar
  /// behavior when they are a permanent, active, non-archived member with a
  /// non-empty email address.
  bool _isEligiblePermanentMember(TeamMember member) {
    final email = member.email?.trim() ?? '';
    return member.isPermanent &&
        member.isActive &&
        !member.isArchived &&
        email.isNotEmpty;
  }

  /// Sync all attendees for app event
  /// Fetches all assignments for event and adds all team member emails as attendees.
  /// Special case: when the event opted into "invite all permanent staff" and it
  /// is permanent-only and currently has zero assignments, all eligible permanent
  /// members are invited instead.
  Future<void> syncAttendeesForAppEvent(String eventId) async {
```

- [ ] **Step 2: Replace the email-collection block with the rule branch**

Edit — old:

```dart
      // Get all assignments for this event
      final assignments = await _database.getAssignmentsByEvent(eventId);

      // Collect all unique emails from assignments
      final emails = <String>{};
      for (final assignment in assignments) {
        final teamMember =
            await _database.getTeamMemberById(assignment.teamMemberId);
        if (teamMember != null &&
            teamMember.email != null &&
            teamMember.email!.isNotEmpty) {
          emails.add(teamMember.email!);
        }
      }
```

new:

```dart
      // Get all assignments for this event
      final assignments = await _database.getAssignmentsByEvent(eventId);

      // Collect all unique attendee emails.
      final emails = <String>{};

      final event = await _database.getEventById(eventId);
      final useAllPermanent = assignments.isEmpty &&
          event != null &&
          event.inviteAllPermanentWhenUnassigned &&
          !event.relevantForExtendedTeam;

      if (useAllPermanent) {
        // No assignments yet and the event opted in: invite all eligible
        // permanent members.
        final members = await _database.getTeamMembers();
        for (final member in members) {
          if (_isEligiblePermanentMember(member)) {
            emails.add(member.email!.trim());
          }
        }
      } else {
        // Default behavior: attendees are exactly the assignees.
        for (final assignment in assignments) {
          final teamMember =
              await _database.getTeamMemberById(assignment.teamMemberId);
          if (teamMember != null &&
              teamMember.email != null &&
              teamMember.email!.isNotEmpty) {
            emails.add(teamMember.email!);
          }
        }
      }
```

- [ ] **Step 3: Analyze**

Run: `cd shavtzak && flutter analyze`
Expected: `No issues found!` (exit code 0).

- [ ] **Step 4: Commit**

```bash
git add shavtzak/lib/core/services/calendar_sync_service.dart
git commit -m "Client: invite all eligible permanent members when opted-in event has no assignments"
```

---

### Task 5: Backend pure rule helpers (TDD)

**Files:**
- Modify: `functions/src/calendar_sync_backend.ts`
- Create: `functions/src/calendar_sync_backend.test.ts`

- [ ] **Step 1: Write the failing test**

Create `functions/src/calendar_sync_backend.test.ts`:

```typescript
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  isEligiblePermanentMember,
  shouldInviteAllPermanentForEvent,
} from './calendar_sync_backend';

type Mutable = Record<string, unknown>;

function buildMember(overrides: Mutable = {}): Mutable {
  return {
    isActive: true,
    isArchived: false,
    isPermanent: true,
    email: 'a@example.com',
    ...overrides,
  };
}

test('eligible: permanent active non-archived with email', () => {
  assert.equal(isEligiblePermanentMember(buildMember()), true);
});

test('ineligible: non-permanent', () => {
  assert.equal(
    isEligiblePermanentMember(buildMember({isPermanent: false})),
    false,
  );
});

test('ineligible: missing isPermanent', () => {
  const m = buildMember();
  delete m.isPermanent;
  assert.equal(isEligiblePermanentMember(m), false);
});

test('ineligible: archived', () => {
  assert.equal(
    isEligiblePermanentMember(buildMember({isArchived: true})),
    false,
  );
});

test('ineligible: inactive', () => {
  assert.equal(
    isEligiblePermanentMember(buildMember({isActive: false})),
    false,
  );
});

test('missing isArchived derives from !isActive (inactive => archived => ineligible)', () => {
  const m = buildMember({isActive: false});
  delete m.isArchived;
  assert.equal(isEligiblePermanentMember(m), false);
});

test('missing isActive defaults to active => eligible', () => {
  const m = buildMember();
  delete m.isActive;
  delete m.isArchived;
  assert.equal(isEligiblePermanentMember(m), true);
});

test('ineligible: blank or missing email', () => {
  assert.equal(isEligiblePermanentMember(buildMember({email: '   '})), false);
  const m = buildMember();
  delete m.email;
  assert.equal(isEligiblePermanentMember(m), false);
});

test('ineligible: null/undefined data', () => {
  assert.equal(isEligiblePermanentMember(null), false);
  assert.equal(isEligiblePermanentMember(undefined), false);
});

test('shouldInvite: flag on, permanent-only, zero assignments => true', () => {
  assert.equal(
    shouldInviteAllPermanentForEvent(
      {inviteAllPermanentWhenUnassigned: true, relevantForExtendedTeam: false},
      0,
    ),
    true,
  );
});

test('shouldInvite: missing relevantForExtendedTeam treated as permanent-only', () => {
  assert.equal(
    shouldInviteAllPermanentForEvent(
      {inviteAllPermanentWhenUnassigned: true},
      0,
    ),
    true,
  );
});

test('shouldInvite: any assignment => false', () => {
  assert.equal(
    shouldInviteAllPermanentForEvent(
      {inviteAllPermanentWhenUnassigned: true, relevantForExtendedTeam: false},
      1,
    ),
    false,
  );
});

test('shouldInvite: flag off => false', () => {
  assert.equal(
    shouldInviteAllPermanentForEvent(
      {inviteAllPermanentWhenUnassigned: false, relevantForExtendedTeam: false},
      0,
    ),
    false,
  );
});

test('shouldInvite: extended-team event => false even if flag on', () => {
  assert.equal(
    shouldInviteAllPermanentForEvent(
      {inviteAllPermanentWhenUnassigned: true, relevantForExtendedTeam: true},
      0,
    ),
    false,
  );
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd functions && npm test`
Expected: FAIL — `tsc` errors that `'isEligiblePermanentMember'` / `'shouldInviteAllPermanentForEvent'` are not exported by `./calendar_sync_backend` (the build step fails before tests run).

- [ ] **Step 3: Implement the two exported helpers**

Edit `functions/src/calendar_sync_backend.ts` — old:

```typescript
function uniqueSortedStrings(values: Iterable<string>): string[] {
  return Array.from(new Set(
    Array.from(values)
      .map((value) => value.trim())
      .filter((value) => value.length > 0),
  )).sort((left, right) => left.localeCompare(right));
}
```

new:

```typescript
function uniqueSortedStrings(values: Iterable<string>): string[] {
  return Array.from(new Set(
    Array.from(values)
      .map((value) => value.trim())
      .filter((value) => value.length > 0),
  )).sort((left, right) => left.localeCompare(right));
}

/**
 * A member is eligible for the "invite all permanent staff" calendar behavior
 * when they are a permanent, active, non-archived member with a non-empty
 * email. Mirrors the Flutter TeamMember model migration defaults: a missing
 * `isActive` is treated as active; a missing `isArchived` is derived from
 * `!isActive`.
 */
export function isEligiblePermanentMember(
  data: Record<string, unknown> | null | undefined,
): boolean {
  if (data == null) {
    return false;
  }
  if (data['isPermanent'] !== true) {
    return false;
  }
  const isActive = data['isActive'] === false ? false : true;
  const isArchived =
    typeof data['isArchived'] === 'boolean'
      ? (data['isArchived'] as boolean)
      : !isActive;
  if (!isActive || isArchived) {
    return false;
  }
  return normalizeOptionalText(data['email']) != null;
}

/**
 * The "invite all permanent staff" substitution applies when the event opted
 * in, is permanent-only (a missing `relevantForExtendedTeam` is treated as
 * permanent-only, matching the model default of `false`), and currently has
 * zero assignment records.
 */
export function shouldInviteAllPermanentForEvent(
  eventData: Record<string, unknown>,
  assignmentCount: number,
): boolean {
  return (
    assignmentCount === 0 &&
    eventData['inviteAllPermanentWhenUnassigned'] === true &&
    eventData['relevantForExtendedTeam'] !== true
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd functions && npm test`
Expected: PASS — `tsc` succeeds and `node --test` reports all tests passing (including the new `calendar_sync_backend.test.js`), `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add functions/src/calendar_sync_backend.ts functions/src/calendar_sync_backend.test.ts
git commit -m "Backend: add tested isEligiblePermanentMember + shouldInviteAllPermanentForEvent helpers"
```

---

### Task 6: Wire the rule into the backend reconcile path

**Files:**
- Modify: `functions/src/calendar_sync_backend.ts`

- [ ] **Step 1: Add the eligible-permanent-members reader (in-memory filter, no index)**

Edit `functions/src/calendar_sync_backend.ts` — old:

```typescript
async function readEventAttendeeEmails(
  dependencies: SyncDependencies,
  eventId: string,
  teamMemberCache: Map<string, Record<string, unknown> | null>,
): Promise<string[]> {
  const assignmentsSnapshot = await dependencies.firestore
    .collection(dependencies.collections.assignments)
    .where('eventId', '==', eventId)
    .get();
```

new:

```typescript
async function readEligiblePermanentMemberEmails(
  dependencies: SyncDependencies,
): Promise<string[]> {
  const snapshot = await dependencies.firestore
    .collection(dependencies.collections.teamMembers)
    .get();

  const emails = new Set<string>();
  for (const doc of snapshot.docs) {
    const data = doc.data() ?? {};
    if (!isEligiblePermanentMember(data)) {
      continue;
    }
    const email = normalizeOptionalText(data['email']);
    if (email != null) {
      emails.add(normalizeEmail(email));
    }
  }
  return uniqueSortedStrings(emails);
}

async function readEventAttendeeEmails(
  dependencies: SyncDependencies,
  eventId: string,
  eventData: Record<string, unknown>,
  teamMemberCache: Map<string, Record<string, unknown> | null>,
): Promise<string[]> {
  const assignmentsSnapshot = await dependencies.firestore
    .collection(dependencies.collections.assignments)
    .where('eventId', '==', eventId)
    .get();

  if (shouldInviteAllPermanentForEvent(eventData, assignmentsSnapshot.size)) {
    return readEligiblePermanentMemberEmails(dependencies);
  }
```

(Only the function header and the first statement block change; the rest of `readEventAttendeeEmails` — the `teamMemberIds` mapping, the cache loop, and `return uniqueSortedStrings(emails);` — is unchanged.)

- [ ] **Step 2: Pass `eventData` from the sole caller**

`reconcileSingleAppEvent` already receives `eventData: Record<string, unknown>` as a parameter. Edit — old:

```typescript
  const desired = buildDesiredAppEventState(eventId, eventData, dependencies.environment);
  const desiredEmails = await readEventAttendeeEmails(dependencies, eventId, teamMemberCache);
```

new:

```typescript
  const desired = buildDesiredAppEventState(eventId, eventData, dependencies.environment);
  const desiredEmails = await readEventAttendeeEmails(dependencies, eventId, eventData, teamMemberCache);
```

- [ ] **Step 3: Build and test**

Run: `cd functions && npm test`
Expected: PASS — `tsc` compiles with no errors (the new `eventData` parameter is the only signature change and its single call site is updated), and `node --test` reports `# fail 0`.

- [ ] **Step 4: Commit**

```bash
git add functions/src/calendar_sync_backend.ts
git commit -m "Backend: apply invite-all-permanent rule in readEventAttendeeEmails reconcile path"
```

---

### Task 7: Final static verification (whole change)

**Files:** none (verification only)

- [ ] **Step 1: Flutter analyzer is clean**

Run: `cd shavtzak && flutter analyze`
Expected: `No issues found!` (exit code 0).

- [ ] **Step 2: Cloud Functions build + tests are clean**

Run: `cd functions && npm run build && npm test`
Expected: `tsc` exits 0; `node --test` reports `# fail 0` with the `calendar_sync_backend.test.js` suite present.

- [ ] **Step 3: Confirm the spec is fully covered**

Re-read `docs/superpowers/specs/2026-05-18-calendar-invite-all-permanent-when-unassigned-design.md` §10 acceptance criteria and confirm each maps to implemented code:
- AC1/AC2 → Task 4 (client) + Task 6 (backend) eligibility filter (`_isEligiblePermanentMember` / `isEligiblePermanentMember`).
- AC3 → existing per-assignee branch (untouched else-branch) once `assignments` non-empty.
- AC4 → rule re-evaluated live every sync (no clearing logic) — Tasks 4 & 6.
- AC5 → Task 3 coupling + Step 4 defensive save.
- AC6 → Task 6 (backend reconcile honors the rule).
- AC7 → per-event scoping: client `getAssignmentsByEvent(eventId)`, backend `.where('eventId','==',eventId)` (unchanged scoping).
- AC8 → env-aware collections used unchanged on both sides.

No commit (verification only).

---

### Task 8: Manual end-to-end protocol, docs, and deploy note

**Files:**
- Modify: `docs/superpowers/specs/2026-05-18-calendar-invite-all-permanent-when-unassigned-design.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Record the manual test protocol for the project owner**

The project owner runs the app and Google Calendar manually (per `CLAUDE.md`). Provide them this protocol to execute in the **test** environment (`/test/*` routes, `test_` collections, test calendar) after deploying functions (Step 3):

1. Create a new event, "permanent team only" ON, the new toggle ON, valid times, no assignments → save. In Google Calendar (test calendar), the event's calendar event(s) have exactly the active, non-archived permanent members who have an email as attendees.
2. Add a permanent member with a blank email and an archived permanent member → re-save the event → neither appears as an attendee.
3. Create one assignment on that event → calendar attendees become exactly that assignee.
4. Delete that assignment (event back to zero assignments) → calendar attendees return to all eligible permanent members (self-resuming).
5. Open the event, turn "permanent team only" OFF → the new toggle grays out and turns off; save → re-open: it is still off; calendar (zero assignments) has no attendees.
6. With the toggle ON and zero assignments, edit only the event location and save (forces a full event re-sync) → attendees still all eligible permanent members (proves the backend reconcile honors the rule).
7. Create a second event with no assignments and the toggle OFF → it has no attendees, and assignments on event 1 never affect event 2 (per-event scoping).

- [ ] **Step 2: Flip the spec status and note the feature**

Edit `docs/superpowers/specs/2026-05-18-calendar-invite-all-permanent-when-unassigned-design.md` — old:

```markdown
**Status:** Approved (pending spec review)
```

new:

```markdown
**Status:** Implemented
```

Edit `CLAUDE.md` — old:

```markdown
### Constraints & Availability ✅
```

new:

```markdown
### Calendar ✅
- Opt-in per-event toggle: invite all eligible permanent members (active, non-archived, with email) to an event's Google Calendar event(s) while the event has zero assignments; reverts to per-assignee invites once the first assignment exists (sticky + self-resuming). Coupled to the "permanent team only" switch.

### Constraints & Availability ✅
```

- [ ] **Step 3: Deployment reminder (owner action — do not run automatically)**

The backend rule only takes effect once Cloud Functions are deployed. Inform the owner: deploy with `cd functions && npm run deploy` (this runs `firebase deploy --only functions,firestore:rules`). The Flutter changes ship with the normal `flutter build web` deployment.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-05-18-calendar-invite-all-permanent-when-unassigned-design.md CLAUDE.md
git commit -m "Docs: mark invite-all-permanent feature implemented + manual protocol"
```

---

## Self-Review

**Spec coverage:** Every spec section maps to a task — §4 data model → Tasks 1–2; §6 UI/coupling → Task 3; §5 client rule → Task 4; §3/§5 backend mirror → Tasks 5–6; §10 acceptance criteria → Task 7 Step 3; §8 (no confirmation dialog) respected (no such task); manual verification (§10) → Task 8. No gaps.

**Placeholder scan:** No "TBD/TODO"; every code step contains complete, copy-ready code; every command has an expected result. None of the forbidden patterns are present.

**Type/name consistency:** Dart `inviteAllPermanentWhenUnassigned` (entity ↔ model ↔ modal ↔ `getEventById`-loaded event) is spelled identically everywhere. Backend exports `isEligiblePermanentMember` / `shouldInviteAllPermanentForEvent` are defined in Task 5 and consumed by name in Task 5's test and Task 6's `readEventAttendeeEmails`. `readEventAttendeeEmails`'s new `eventData: Record<string, unknown>` parameter (Task 6 Step 1) matches the single call-site update (Task 6 Step 2). Firestore keys used by the backend (`isPermanent`, `isActive`, `isArchived`, `email`, `inviteAllPermanentWhenUnassigned`, `relevantForExtendedTeam`) match `team_member_model.dart` / `event_model.dart` serialization. No mismatches found.

## Post-implementation correction (found during manual testing)

The plan and spec assumed the new `Event` field would persist automatically because the
Dart `CreateEvent`/`UpdateEvent` events carry the full `Event` object. That was wrong:
`firestore.rules` forbids client writes to `events`; persistence happens server-side via the
backend `event.insert`/`event.update`/`event.insertBatch` mutations, which rebuild the
document through a strict field **whitelist** `eventDocFromJson` (`functions/src/index.ts`
≈ line 1316). Because that whitelist did not list `inviteAllPermanentWhenUnassigned`, the
field was silently dropped on every save and the rule never fired (no invitees).

**Fix:** add `inviteAllPermanentWhenUnassigned: event['inviteAllPermanentWhenUnassigned'] ?? false`
to `eventDocFromJson` (mirrors the adjacent `relevantForExtendedTeam` / `isDeactivated`
lines). This makes the feature require a Cloud Functions deploy to work end-to-end (which it
already did for the backend attendee mirror).
