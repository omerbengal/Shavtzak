# Plan: Move All DB Write Logic to Firebase Cloud Functions

## Goal

Move every write operation (create / update / delete) from the Flutter client into
Firebase Cloud Functions (TypeScript, HTTPS Callable). Reads stay as direct Firestore
access so real-time streams keep working. After the migration, Firestore Security Rules
will deny all direct client writes, forcing every mutation through a Cloud Function.

---

## Architecture Overview

### Before
```
Flutter UI → BLoC → Repository → FirestoreDatabase → Firestore (direct write)
```

### After
```
Flutter UI → BLoC → Repository → HybridDatabase ──reads──► Firestore (direct)
                                                 └──writes──► Cloud Function → Admin SDK → Firestore
```

**Key decisions:**

| Concern | Decision |
|---|---|
| Read strategy | Unchanged — direct Firestore via `cloud_firestore` (real-time streams unaffected) |
| Write strategy | HTTPS Callable Functions via `cloud_functions` Flutter package |
| Auth (no Firebase Auth) | Pass caller's `uniqueKey` in every function payload; function validates it against Firestore |
| Environment (test/prod) | Pass `isTestMode: boolean` in every payload; function uses `test_` prefix on collections |
| Language | TypeScript |
| Function granularity | One exported function per logical operation (easier to audit, deploy, and monitor) |

---

## Scope — Write Operations to Migrate

### Team Members (8)
- `insertTeamMember`
- `updateTeamMember`
- `updateTeamMemberPasscode`
- `clearTeamMemberPasscode`
- `deleteTeamMember`
- `insertTeamMembersBatch`

### Constraints (4)
- `addConstraint`
- `editConstraintById`
- `removeConstraintById`
- `updateConstraintStatus`

### Events (6)
- `insertEvent`
- `updateEvent`
- `deleteEvent`
- `insertEventsBatch`
- `updateEventArchiveStatus`

### Assignments (7)
- `insertAssignment`
- `updateAssignment`
- `deleteAssignment`
- `deleteAssignmentsByEvent`
- `deleteAssignmentsByPerson`
- `deleteAssignmentsBatch`
- `insertAssignmentsBatch`

### Checklist Items (6)
- `insertChecklistItem`
- `updateChecklistItem`
- `deleteChecklistItem`
- `deleteChecklistItemsByEvent`
- `addNoteToChecklistItem`
- _(loadPresetIntoEvent creates checklist items — covered here)_

### Presets (4)
- `insertPreset`
- `updatePreset`
- `deletePreset`
- `loadPresetIntoEvent`

### Roles (7)
- `insertRole`
- `updateRole`
- `archiveRole`
- `restoreRole`
- `deleteRole`
- `seedRolesFromEnum`
- `updateRolesSortOrder`

### Categories (6)
- `insertCategory`
- `updateCategory`
- `deleteCategory`
- `permanentlyDeleteCategory`
- `restoreCategory`

### Calendar Sync State (6)
- `saveCalendarSyncState`
- `updateCalendarSyncStatus`
- `removeCalendarSyncState`
- `atomicCheckAndSetSyncState`
- `saveEventCalendarSyncState`
- `removeEventCalendarSyncState`

**Total: ~54 callable functions**

---

## File Structure

```
/home/user/Shavtzak/
├── firebase.json                       # Firebase project config (functions + firestore)
├── .firebaserc                         # Project alias (production project ID)
├── firestore.rules                     # Updated rules (deny client writes)
│
├── functions/                          # Cloud Functions root
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       ├── index.ts                    # Exports all functions
│       ├── shared/
│       │   ├── auth.ts                 # validateCaller(uniqueKey, isTestMode)
│       │   ├── collections.ts          # getCollectionName(base, isTestMode)
│       │   └── audit.ts                # addAuditLog(batch, ...)
│       ├── team/
│       │   └── index.ts                # 6 team member functions
│       ├── constraints/
│       │   └── index.ts                # 4 constraint functions
│       ├── events/
│       │   └── index.ts                # 6 event functions
│       ├── assignments/
│       │   └── index.ts                # 7 assignment functions
│       ├── checklist/
│       │   └── index.ts                # 6 checklist functions
│       ├── presets/
│       │   └── index.ts                # 4 preset functions
│       ├── roles/
│       │   └── index.ts                # 7 role functions
│       ├── categories/
│       │   └── index.ts                # 5 category functions
│       └── calendar/
│           └── index.ts                # 6 calendar sync functions
│
└── shavtzak/
    ├── pubspec.yaml                    # + cloud_functions dependency
    └── lib/
        ├── core/services/
        │   └── cloud_functions_client.dart   # Thin wrapper over FirebaseFunctions
        └── data/
            ├── data_sources/
            │   └── hybrid_database.dart      # Extends FirestoreDatabase, overrides writes
            └── repositories/               # Unchanged — still call DatabaseInterface
```

---

## Implementation Phases

### Phase 1 — Firebase Project Setup

1. **Create `firebase.json`** at repo root:
   - Configure `functions` (source: `./functions`, runtime: nodejs20)
   - Configure `firestore` (rules: `firestore.rules`)

2. **Create `.firebaserc`** with the existing Firebase project ID
   (found in `lib/firebase_options.dart` → `projectId`)

3. **Initialize `functions/`**:
   - `package.json` with `firebase-functions`, `firebase-admin`, TypeScript dev deps
   - `tsconfig.json` targeting ES2020 / Node 20
   - `src/index.ts` as the entry point

### Phase 2 — Shared Utilities (TypeScript)

**`src/shared/collections.ts`**
```typescript
export function col(base: string, isTestMode: boolean): string {
  return isTestMode ? `test_${base}` : base;
}
```

**`src/shared/auth.ts`**
```typescript
// Validates that the caller's uniqueKey matches a real team member.
// Optionally enforces isAdmin for admin-only operations.
export async function validateCaller(
  db: Firestore,
  uniqueKey: string,
  isTestMode: boolean,
  requireAdmin = false,
): Promise<TeamMemberDoc>
```

**`src/shared/audit.ts`**
```typescript
// Mirrors existing client-side _addAuditLogToBatch logic
export function addAuditLog(
  batch: WriteBatch,
  db: Firestore,
  isTestMode: boolean,
  params: { actionType, entityType, entityId, actorId, before?, after? }
): void
```

### Phase 3 — Cloud Functions (one module per entity)

Each callable function follows this template:

```typescript
export const insertTeamMember = onCall(async (request) => {
  const { uniqueKey, isTestMode, member } = request.data;
  await validateCaller(db, uniqueKey, isTestMode, /* requireAdmin */ true);
  const batch = db.batch();
  const ref = db.collection(col('teamMembers', isTestMode)).doc(member.id);
  batch.set(ref, member);
  addAuditLog(batch, db, isTestMode, { actionType: 'create', ... });
  await batch.commit();
  return { success: true };
});
```

Business logic currently in repositories (FK validation, conflict checks) moves into the
relevant function. This ensures validation cannot be bypassed from any client.

### Phase 4 — Flutter: `CloudFunctionsClient`

New file: `lib/core/services/cloud_functions_client.dart`

```dart
class CloudFunctionsClient {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<Map<String, dynamic>> call(String functionName, Map<String, dynamic> data) async {
    final callable = _functions.httpsCallable(functionName);
    final result = await callable.call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }
}
```

Adds `cloud_functions: ^4.0.0` to `pubspec.yaml`.

### Phase 5 — Flutter: `HybridDatabase`

New file: `lib/data/data_sources/hybrid_database.dart`

```dart
/// Reads: direct Firestore (inherited from FirestoreDatabase)
/// Writes: via Cloud Functions callable
class HybridDatabase extends FirestoreDatabase {
  final CloudFunctionsClient _cf;
  HybridDatabase(super.environmentService, this._cf, {required String callerUniqueKey})
      : _callerUniqueKey = callerUniqueKey;

  @override
  Future<void> insertTeamMember(TeamMember member) async {
    await _cf.call('insertTeamMember', {
      'uniqueKey': _callerUniqueKey,
      'isTestMode': environmentService.isTestMode,
      'member': TeamMemberModel.fromEntity(member).toFirestore(),
    });
  }
  // ... override all ~54 write methods
}
```

**Injection point**: `main.dart` (or `ServiceLocator`) constructs `HybridDatabase` instead
of `FirestoreDatabase` once the user is authenticated (so `callerUniqueKey` is known).
Before auth, a pre-auth `FirestoreDatabase` is used for the initial `getTeamMemberByUniqueKey`
lookup (that read is not affected).

### Phase 6 — Firestore Security Rules

`firestore.rules`:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Allow reads for authenticated session (uniqueKey-based)
    // Deny all writes from client — all writes go through Cloud Functions

    match /{document=**} {
      allow read: if true;   // Tighten later per-collection if needed
      allow write: if false; // Cloud Functions use Admin SDK — bypass rules
    }
  }
}
```

> **Note**: `allow read: if true` is intentionally permissive for now; the app has no
> sensitive PII and already shows all team members on the /whoami screen. This can be
> tightened per-collection in a follow-up (e.g., restrict reads to known uniqueKey holders).

### Phase 7 — Wiring & Deployment

1. **Deploy Cloud Functions**: `firebase deploy --only functions`
2. **Deploy Firestore rules**: `firebase deploy --only firestore:rules`
3. **Build Flutter web**: `cd shavtzak && flutter build web`
4. **Test** with Firebase Emulator Suite locally first:
   `firebase emulators:start --only functions,firestore`

---

## Open Questions / Decisions Deferred

| Question | Recommendation |
|---|---|
| Should `isTestMode` be trusted from the client, or derived server-side from Auth context? | Since there's no Firebase Auth, trust it from the payload for now. A future improvement: tie test mode to a Firebase App Check token or custom claim. |
| Should reads also eventually move server-side? | Not recommended — direct Firestore reads enable real-time streams (`watchX`). Moving reads would require Server-Sent Events or WebSockets, adding complexity with no security benefit (data is not secret). |
| Error handling in Flutter? | Map `FirebaseFunctionsException` codes to user-friendly Hebrew messages in `HybridDatabase` catch blocks. |
| Region for Cloud Functions? | Default (`us-central1`) unless you want lower latency for Israel → consider `europe-west1`. |

---

## Estimated Effort Breakdown

| Phase | Effort |
|---|---|
| Phase 1: Firebase project setup | Small |
| Phase 2: Shared TS utilities | Small |
| Phase 3: ~54 Cloud Functions | Large (mechanical but repetitive) |
| Phase 4: CloudFunctionsClient | Trivial |
| Phase 5: HybridDatabase (~54 overrides) | Large (mechanical) |
| Phase 6: Firestore rules | Trivial |
| Phase 7: Wiring + deploy | Small |

The bulk of the work is mechanical translation of existing Dart write logic into
TypeScript functions. The architecture and shared utilities are the intellectually complex
parts; the individual functions follow a clear, repeatable template.
