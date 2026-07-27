# Personal ICS Calendar Feed — Design

**Date:** 2026-07-27
**Status:** Approved design, not yet implemented
**Branch:** `worktree-feat-personal-ics-calendar-feed`

## Problem

Team members want their shifts to appear in their own phone calendar, and to see
changes reflected there. The app currently gives them nothing: since the
2026-07-15 guest purge, Shavtzak's Google Calendar events carry no attendees at
all, so a member's personal calendar shows nothing about their shifts.

The obvious fix — go back to inviting members as Google Calendar guests — is the
mechanism that blocked the organiser account (`atkamiluaim@gmail.com`) in July
2026. That block was not a bug we can fix. It is a per-account anti-abuse limit
on guest invitations, community-measured at roughly 36–60/day for a consumer
Gmail account, refilling on a slow trickle rather than resetting nightly.

### Why batching invites does not solve it

Production numbers as of 2026-07-27:

| Measure | Value |
|---|---|
| Team members | 51 |
| …with an email address on file | 14 |
| Active future events | 48 (~2/day, out to late September) |
| Google Calendar entries per event | 2 (התייצבות + מופע) |
| Members-with-email assigned per event | ~5–10 (sampled: 5/9 and 10/14) |
| Attendees currently on those events | 0 |

Re-enabling invites means a cold start of roughly `48 × 2 × 7 ≈ 670`
attendee-adds — 11–19 days of continuous max-rate spending, competing with the
admin's own browser for the same bucket. Steady state is worse than the average
suggests because planning is bursty: `createTime` data shows ~25 events created
in a single sitting on 2026-07-01, which is ~350 adds, or roughly a week of
quota, spent in one afternoon.

Batching to once a day fixes the *storm* (redundant re-adds of the same person
to the same event — the actual 2026-07-12 bug). It does not fix the *ceiling*,
because the ceiling is set by the count of distinct (member × event-part) pairs,
and that number structurally exceeds what a consumer Gmail account will pass.

### Why the fast alternatives were rejected

Both alternatives that deliver instant updates require a Google account per
member, and the owner confirmed that **14 emails is roughly the ceiling** — many
members are non-permanent, will not hand over an email, or do not use Google.

- **Per-member secondary Google Calendars** (app owns the calendar, shares it
  once, writes shifts directly). Instant, and touches no invitation quota. But
  it reaches ~12 of 51 people, and it multiplies the state to converge from ~96
  Google Calendar objects to ~670 — 7× more surface for the orphan/duplicate/
  drift failures this project has repeatedly hit.
- **Silent invites** (`sendUpdates: 'none'`, so members are added as attendees
  but no email is sent). Zero setup for the member and no email spam, but still
  quota-bound and still limited to the same 14.

An ICS feed reaches all 51, because the URL is delivered in-app and needs no
account at all.

## Approach

Each member gets one secret URL serving an RFC 5545 calendar feed of their own
shifts. They subscribe once in whatever calendar app they use.

The decisive property is that **there is no state to converge.** The feed is a
pure function of Firestore, recomputed per request. Nothing is pushed to Google,
so:

- Unassigning someone removes the `VEVENT` from the next poll. No API call, no
  quota, no orphan, no cleanup job.
- Duplicate calendar events, quota exhaustion, invite storms, the paused-queue
  gotcha — none of these failure modes can exist on this path.
- No emails are sent to anyone, ever. The team's original complaint becomes
  structurally impossible.

The trade-off is refresh latency, and it is the member's client that decides it,
not us:

| Client | Refresh | Notes |
|---|---|---|
| Apple Calendar (iOS/macOS) | User-settable, min 5 minutes | Near-real-time |
| Google Calendar (`From URL`) | Google's own schedule, ~8–48h | `REFRESH-INTERVAL` and `X-PUBLISHED-TTL` are ignored; no way to force a refresh |
| Android + ICSx⁵ | User-settable | Requires an app install |

This is acceptable because the people most likely to suffer Google's slow poll
are precisely the 14 who gave a Gmail address; the other 37 are mostly on
whatever ships with their phone. Genuinely urgent changes are not a calendar
problem anyway — that is a notification problem, deferred (see Non-Goals).

## Design

### Data model

One new field, `calendarFeedToken` — 256-bit random, base64url encoded — stored
on the member's **`private_member_credentials/{memberId}`** document, alongside
the passcode hash.

**Not on `teamMembers`.** An earlier draft of this spec put it there. That is
insecure: `firestore.rules` grants `allow read: if isAuthorizedProdUser()` over
the whole `teamMembers` collection, and `isAuthorizedProdUser()` only checks
that the *caller* is an active member — not that they are reading their own
document. Every one of the 51 active members can therefore read every other
member's `teamMembers` document straight from the client SDK, so a bearer token
stored there would be readable by the whole team, and the mutation-level
`requireSelfOrAdmin` check would be bypassed entirely at the read layer.
`private_member_credentials` is already `allow read, write: if false`
(Admin-SDK-only), which is exactly the precedent the passcode hash follows. This
choice needs **no rules change and no rules deploy**.

A consequence worth stating: the token never reaches the Flutter client except
as the return value of the minting mutation. It is therefore **not** a field on
the `TeamMember` entity or model.

The token is explicitly **not** `uniqueKey`. That is an authentication
credential and must never appear in a URL that gets pasted into calendar apps
and WhatsApp.

Tokens are minted on demand by an authenticated backend mutation
`ensureCalendarFeedToken(memberId)`, which returns the existing token or creates
one. Both the member self-serve dialog and the admin screen call it, so there is
no migration and no unused secrets. A separate `rotateCalendarFeedToken`
invalidates a leaked link.

Access control on both mutations: a member may act on **themselves only**; an
admin may act on any member. Without that check, any authenticated member could
mint and read any colleague's feed token.

Tokens are naturally per-environment: `teamMembers` and `test_teamMembers` are
separate collections holding separate documents. Lookup needs only a
single-field index, which Firestore creates automatically — no composite index
to deploy, avoiding the trap that silently disabled duplicate-event detection.

### Endpoint

```
GET /api/calendar/feed/{prod|test}/{token}.ics
```

A public, unauthenticated route on the existing `api` function, which is already
declared `invoker: 'public'` (index.ts). Auth in this codebase is per-route —
handlers call `authenticateRequest` themselves rather than via middleware — so a
public route requires no infrastructure change.

Request flow:

1. Parse the environment segment; anything other than `prod`/`test` → 404.
2. Query the environment's members collection for `calendarFeedToken == token`,
   limit 1. Not found → 404, indistinguishable from a malformed token.
3. Query `assignments` where `teamMemberId == member.id`. This returns all-time
   assignments; there is no date filter because the date lives on the event.
4. Batch-get the distinct referenced events. Drop deactivated events.
5. Render the VCALENDAR.
6. Respond `text/calendar; charset=utf-8` with `Cache-Control` and an `ETag`.

### Feed content

Two `VEVENT`s per **(member, event)** pair — התייצבות and מופע — mirroring what
the shared Shavtzak calendar already produces, so the two views stay consistent.

Note the grouping key: it is per event, **not per assignment**. A member can hold
more than one assignment in the same event — production data confirms it (member
`a606f320` holds two `entryScreening` slots in event `2511d06b`), and members
flagged `allowMultipleAssignments` do it by design. Emitting one pair per
assignment would produce duplicate `UID`s and two identical blocks on the same
calendar. Instead, collapse to one pair per event and list all of the member's
roles for that event in the `DESCRIPTION`.

- **`UID`**: `{eventId}-{part}-{memberId}@shavtzak`, stable across refreshes so
  updates replace rather than duplicate. Unique given the grouping above.
- **Titles and times**: reuse the existing `createAssemblyTitle` /
  `createEventTitle` and the assembly/main prefix logic in
  `buildDesiredAppEventState` (calendar_sync_backend.ts). Factor the shared
  computation into a pure helper so the feed and the Google Calendar sync cannot
  drift apart.
- **All-day fallback**: when `assemblyTime` or `endTime` is missing,
  `buildDesiredAppEventState` already falls back to an all-day event. Mirror
  that rule exactly — emit a single all-day `VEVENT` with `DTSTART;VALUE=DATE`.
- **`LOCATION`**: the event's location.
- **`DESCRIPTION`**: the member's role(s) in Hebrew, plus their **assignment**
  notes — production data has entries like `"מסייע לאורנה בכניסות"`, which is
  exactly the per-member detail worth surfacing. There is no event-level notes
  field; notes live on the assignment. Times are not repeated in the
  description, since the two-block shape already shows them.

A member with no assignments still gets a valid, empty `VCALENDAR` — never an
empty body, which some clients treat as a fetch failure and others as a reason to
drop the subscription.

### Scope

- The member's own assignments, **all of them, with no time limit** — past
  shifts remain in the feed permanently. The owner chose this deliberately: the
  calendar becomes a lasting record of every shift worked.
- **Deactivated events are excluded**, past and future. A cancelled event is not
  history — nobody worked it. This matches the existing `isEventInDefaultScope`
  rule.

Note that subscribed calendars are **read-only**: members cannot delete entries
themselves, and anything dropped from the feed disappears from their calendar.
Keeping everything forever means their calendar accumulates ~50 entries per year
that they cannot clear. This is the accepted trade for a permanent record.

### Cost

Reads per request are roughly `1 + 2 × (the member's all-time assignment count)`
— about 50 today for the heaviest-loaded member (25 assignments), growing ~100
per year for that member.

At realistic usage (~30 subscribers, mostly hourly refresh or slower):

- ~720 requests/day × ~50 reads ≈ **37,000 Firestore reads/day**, inside the
  50,000/day free allowance.
- ~22k function invocations/month against a 2M free tier.
- ~260 MB/month egress against a 5 GB free tier.

Effectively **zero**. If every subscriber chose the 5-minute minimum refresh it
would be ~440k reads/day, or roughly $3–7/month — still trivial.

Two caveats: these reads add to whatever the app already consumes (an admin page
load streams ~630 documents), and the per-request cost grows with career length
rather than with any calendar window.

**Therefore: build no caching at all in v1.** An earlier draft of this spec
called for a shared per-instance cache of the events documents, on the reasoning
that events are common to every member's feed. Working the arithmetic through
reverses that: a whole-collection cache costs ~80 reads per refresh window
regardless of traffic, whereas fetching only the events a member is actually
assigned to costs ~25 reads per request. At ~720 requests/day the cache is the
*more* expensive of the two, and both are inside the free tier. The simpler
option therefore wins on both counts. If poll rates turn out high,
the natural later optimisation is that past shifts are immutable, so the
historical portion of a feed can be rendered once and cached — but that
reintroduces state and is not justified now.

### UI

**Member self-serve** on `/user/assignments`: a "הוסף ליומן שלי" button opens a
dialog containing

- a one-tap `webcal://` button, which opens the Calendar subscribe sheet
  directly on iOS/macOS,
- a "העתק קישור" fallback,
- collapsible per-platform Hebrew instructions, including an honest note that
  Google Calendar takes about a day to pick up changes, and the ICSx⁵ tip for
  Android users who want it faster,
- a warning that the link is personal and should not be forwarded.

**Admin**, in the team-member modal: copy-link and share actions so links can go
out over WhatsApp — the only channel that reaches the 37 members without an
email — plus a rotate action.

### Security

- 256-bit random token; brute force is not realistic.
- Unknown and malformed tokens both return a bare 404.
- Rotatable per member if a link leaks.
- The feed exposes only that member's own schedule — the same data they already
  see in the app.
- The URL is a bearer token, which is exactly how Google's own "secret address
  in iCal format" works. The UI states this plainly.

## Testing

The renderer is a pure function (assignments + events → ICS string) and carries
most of the test weight:

- two-block shape (התייצבות + מופע) for a normal event,
- all-day fallback when `assemblyTime` or `endTime` is missing,
- an event spanning a DST boundary — Israel is UTC+2/+3, and this repo already
  stores `events.startDate` as Israel local midnight in UTC (`T21:00Z` is the
  *next* day locally), which is the likeliest source of an off-by-one,
- stable `UID`s across renders,
- **a member holding two assignments in the same event yields exactly one pair
  of `VEVENT`s, with both roles in the description** — the duplicate-`UID` trap,
- an unassigned member's event absent from the output,
- a member with zero assignments yields a valid empty `VCALENDAR`,
- deactivated events excluded,
- **RFC 5545 escaping** — commas, semicolons, backslashes and newlines in
  `SUMMARY`/`DESCRIPTION`,
- **RFC 5545 line folding at 75 octets, not 75 characters** — folding on
  character boundaries silently corrupts UTF-8 Hebrew.

Endpoint tests: unknown token → 404, wrong environment segment → 404, correct
`Content-Type`, and that a test-environment token cannot read production data.

No existing calendar sync code changes, so existing tests are unaffected.

## Non-Goals

Deliberately out of scope. These are recorded because several were considered
and rejected on evidence, not overlooked:

- **Do not re-enable Google Calendar guest invitations** for app events, on any
  path — event create, event edit, manual re-sync, assignment change, team
  member email update, or the legacy attendee endpoint.
- **Do not build per-member Google Calendars.**
- **Do not touch the existing shared-calendar sync.** It keeps working as the
  team-wide view; this feed is a personal layer on top. Keeping them independent
  is what makes this feature zero-regression-risk.
- **No push notifications.** They are the right answer for urgent changes and
  carry no quota, but the app has no FCM today and this is a separate decision
  to make once the feed's real-world behaviour is known.
- **No QR codes** in the first version. Considered for onboarding; deferred.

## Deployment

- **Cloud Functions do not auto-deploy.** `firebase deploy --only functions`
  from the repo root is required for the endpoint to go live.
- The Flutter web app **does** auto-deploy on merge to `main` (`.github/workflows/web.yml`).

## Open Risks

- **Adoption.** A feed nobody subscribes to is worthless, and 51 people of mixed
  technical comfort must each complete a one-time setup. The self-serve dialog
  and the admin WhatsApp path are the mitigation; if adoption is poor, QR codes
  are the next lever.
- **Google Calendar's refresh latency is outside our control**, and there is no
  workaround. Members who need speed must subscribe in Apple Calendar or ICSx⁵.
- **Timezone correctness** is the most likely implementation bug, given the
  existing local-midnight-as-UTC storage convention.
