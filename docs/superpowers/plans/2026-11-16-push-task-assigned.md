# Push notification "שובצת למשימה" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A team member added as an owner of a team task gets a Web Push notification "📋 שובצת למשימה" + the task title on every device they enabled, and a tap opens that task.

**Architecture:** Plain Web Push + VAPID. The existing `web/sw.js` shows the push and handles the tap; a new `web/push.js` wraps the browser APIs; Dart reaches it through a conditional-import bridge. Subscriptions live in a new API-only collection `pushSubscriptions`; the `api` function sends from `teamTask.insert|update` with npm `web-push`. Each subscription is tagged with the function that stored it (`site: main|preview`), so `api` and `apiPreview` only send to their own site's devices.

**Tech Stack:** Flutter Web 3.50, `package:web` + `dart:js_interop`, Firebase Functions v2 (TypeScript, node:test), `web-push` npm, Firebase secret.

**Spec:** design page https://claude.ai/artifact/LGLLB6mWz5Q1kMvzkVfWc7 (approved 16/11/2026, msg 4302, minus the urgency) + memory `project_pwa_push_research.md`.

## Global Constraints

- Text: title `📋 שובצת למשימה`, body = the task title only. No urgency, no other line.
- Recipients: owners ADDED by the write (`after.ownerIds - before.ownerIds`; insert: all owners), minus the actor, and only members who can open the team-tasks screen: today `isAdmin === true` (one rule per side: `canReceiveTaskPush` in `functions/src/push.ts`, `canGetTeamTaskNotifications` in `team_tasks_place.dart`). Active, unarchived members only.
- Delivery: every subscription of each recipient for the calling function's site and environment. A failed send never fails the task write; 404/410 deletes the subscription.
- The VAPID private key is a Firebase secret `WEB_PUSH_VAPID_PRIVATE_KEY`; never in the repo. The public key is a constant (client + server).
- `pushSubscriptions` / `test_pushSubscriptions`: no client access in `firestore.rules`.
- Popup: shown when this device was not asked (permission `default`, no subscription) and "לא עכשיו" was not pressed for the version the device runs (`AppVersionService.cachedVersion`); never after `denied`. iPhone Safari not installed = install explainer instead of the button.
- Silent re-subscribe on every sign-in / app open when permission is `granted` and the device flag "turned off by hand" is not set (the in-app refresh unregisters the worker and with it the subscription).
- Settings "off": unsubscribe + delete on the server + set the device flag. Logout: delete the device's subscription on the server.
- Tap: an open app window goes to `#<routePrefix>/team-tasks?task=<id>`; else a new window opens there. A deleted task: snackbar "המשימה לא נמצאה".

## Review Focus

- A task edit that does not change owners (title, status, a log update) must send nothing.
- The actor adding themselves gets nothing; a non-admin owner gets nothing.
- A subscription stored through `apiPreview` must never get a push from `api` (and the reverse).
- The same device signed in as another member: the subscription moves to the new member (doc id = hash of the endpoint), so a shared PC does not get the previous member's pushes.
- A web-push failure (timeout, 500) must not change the HTTP result of the task write.

---

### Task 1: Backend push rules + sender (`functions/src/push.ts`)

**Files:** Create `functions/src/push.ts`, `functions/src/push.test.ts`. Modify `functions/package.json` (dep `web-push`, devDep `@types/web-push`).

**Interfaces (Produces):**
- `VAPID_PUBLIC_KEY: string`, `PUSH_SUBJECT = 'https://omerbengal.github.io/Shavtzak/'`
- `type PushSite = 'main' | 'preview'`
- `addedOwnerIds(before: {ownerIds: string[]} | null, after: {ownerIds: string[]} | null, actorId: string): string[]`
- `canReceiveTaskPush(member: Record<string, unknown>): boolean`
- `taskAssignedMessage(task: {id: string; title: string}, routePrefix: '' | '/test'): {title: string; body: string; tag: string; path: string}`
- `subscriptionDocId(endpoint: string): string` (sha256 hex)
- `parseSubscription(raw: unknown): {endpoint: string; keys: {p256dh: string; auth: string}}` (TaskError 400)
- `interface PushStore { members(ids): Promise<Map<string, Record<string, unknown>>>; subscriptionsOf(memberIds, site): Promise<StoredSub[]>; deleteSubscription(id): Promise<void> }`
- `type PushSend = (sub, payloadJson) => Promise<void>` (throws `{statusCode}` like web-push)
- `sendTaskAssignedPush(store, send, {before, after, actorId, site, routePrefix}): Promise<{sent: number; dropped: number; failed: number}>` never throws.

- [ ] Tests: no owner change ⇒ 0 sends; insert with owners [a(admin), b(non-admin), actor] ⇒ only a; message title `📋 שובצת למשימה`, body = title, path `/team-tasks?task=<id>` / `/test/team-tasks?task=<id>`; 410 and 404 ⇒ subscription deleted, 500 ⇒ kept and counted failed; a store error ⇒ resolves, no throw; parseSubscription rejects non-https endpoint and missing keys.
- [ ] Run `npm test` ⇒ new tests fail, implement, pass. Commit.

### Task 2: Wire into the API (`functions/src/index.ts`) + rules

**Files:** Modify `functions/src/index.ts`, `firestore.rules`.

- `Collections.pushSubscriptions` (`${prefix}pushSubscriptions`).
- `defineSecret('WEB_PUSH_VAPID_PRIVATE_KEY')`; `api` and a re-added `apiPreview` (wrapper that sets `response.locals.pushSite = 'preview'`) both declare `secrets`.
- `POST /push/subscribe` (auth; body `subscription`, `device`): writes `{memberId, endpoint, keys, site, environment, device, origin, createdAt?, lastSeenAt}` at `subscriptionDocId(endpoint)`. `POST /push/unsubscribe` (auth; body `endpoint`): deletes that doc.
- `executeMutation(..., site: PushSite = 'main')`; in the teamTask case after the transaction + audit, for `teamTask.insert|update`: `await sendTaskAssignedPush(...)` with a Firestore `PushStore` and a `web-push` sender (`timeout: 5000`, TTL 1 day).
- rules: `match /pushSubscriptions/{d=**}` and `test_` ⇒ `allow read, write: if false;` (the catch-all already denies; explicit for clarity).
- [ ] `npm run build && npm test` pass. Commit.

### Task 3: Service worker + `web/push.js`

**Files:** Modify `shavtzak/web/sw.js`, `shavtzak/web/index.html`; create `shavtzak/web/push.js`.

- sw.js `push`: always `showNotification(data.title, {body, tag, icon: 'icons/Icon-192.png', badge, data: {path}, dir: 'rtl', lang: 'he'})`; `notificationclick`: focus a window client under `BASE` and `postMessage({type: 'shavtzak-open', path})`, else `clients.openWindow(BASE + '#' + path)`.
- push.js: `window.shavtzakPush = {permission(), isIosNotInstalled(), subscribe(publicKey) → JSON string|null, current() → JSON|null, unsubscribe() → endpoint|null}`; page listens for `shavtzak-open` and sets `location.hash`. `subscribe` calls `Notification.requestPermission()` first (iPhone gesture rule).
- [ ] CI's service-worker check still passes (`node tool/generate_service_worker.mjs` untouched). Commit.

### Task 4: Dart push service

**Files:** Create `lib/core/web/web_push.dart` (+ `_stub`, `_web`), `lib/core/services/push_notification_service.dart`, test `test/core/services/push_notification_service_test.dart`. Modify `backend_api_service.dart` (`pushSubscribe`, `pushUnsubscribe`), `user_selection_repository.dart` (forget device before sign-out), `main.dart` (silent sync on first auth / identity change), `team_tasks_place.dart` (`canGetTeamTaskNotifications`).

- `enum PushStatus {unsupported, iosInstallNeeded, notAsked, enabled, off, blocked}`
- `PushNotificationService(WebPushBridge, PushBackend, PushDeviceFlags)`: `status()`, `shouldPrompt(status, version)`, `enable()`, `disable()`, `snooze(version)`, `syncSilently(member)`, `forgetDevice()`.
- [ ] Tests with fakes: notAsked+snoozed same version ⇒ no prompt; new version ⇒ prompt; blocked ⇒ never; off flag ⇒ sync does nothing; granted + no flag ⇒ sync subscribes and posts; disable ⇒ flag set + server delete; non-admin ⇒ sync does nothing. Commit.

### Task 5: UI — popup, settings row, deep link

**Files:** Create `lib/presentation/widgets/push_prompt_dialog.dart`, `lib/presentation/widgets/push_settings_section.dart`. Modify `admin_choice_screen.dart` (post-frame prompt), `settings_dialog.dart` (section, admins only), `app_router.dart` + `team_tasks_screen.dart` (`taskId` query param ⇒ open the task once loaded; missing ⇒ "המשימה לא נמצאה").
- Popup copy (design page): "🔔 התראות על משימות" / "נעדכן אותך כשמשבצים אותך למשימה, גם כשהאפליקציה סגורה." / "לא עכשיו" · "הפעל התראות". iPhone: "🔔 התראות באייפון" + 3 steps + "הבנתי".
- Settings row: enabled ⇒ switch on; off/notAsked ⇒ "הפעל התראות"; blocked ⇒ the unblock steps.
- [ ] Widget tests: the popup's two buttons call enable/snooze; the deep link opens the task sheet / shows the snackbar. Commit.

### Task 6: Keys, checks, preview, review

- [ ] `npx web-push generate-vapid-keys`; public key into code; `firebase functions:secrets:set WEB_PUSH_VAPID_PRIVATE_KEY` (stop and ask Omer if blocked).
- [ ] `flutter analyze` (compare the info count with main), `flutter test`, `flutter build web --release --base-href /Shavtzak/`, `npm run build && npm test`.
- [ ] `firebase deploy --only functions:apiPreview`; `scripts/preview.sh`; push the branch; review message with relok/relno buttons.
- [ ] Before merge: remove `apiPreview` export (main keeps only `api`), deploy rules + functions after Omer's ✅.
