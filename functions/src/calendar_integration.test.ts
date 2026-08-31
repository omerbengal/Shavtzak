import test from 'node:test';
import assert from 'node:assert/strict';
import type {Firestore} from 'firebase-admin/firestore';
import {executeCalendarAction} from './calendar_integration';

const adminActor = {memberId: 'admin', isAdmin: true};

function fakeFirestore(): Firestore {
  return {
    collection: (collectionName: string) => ({
      doc: (_documentId: string) => ({
        get: async () => ({
          exists: true,
          data: () => collectionName.endsWith('keys')
            ? {calendarId: 'calendar@example.com'}
            : {
              accessToken: 'access-token',
              expiresAtMs: Date.now() + 60 * 60 * 1000,
            },
        }),
      }),
    }),
  } as unknown as Firestore;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {'Content-Type': 'application/json'},
  });
}

function appEventResponse(
  attendees: Array<Record<string, unknown>> = [],
): Record<string, unknown> {
  return {
    id: 'google-event',
    status: 'confirmed',
    attendees,
    extendedProperties: {
      private: {
        eventId: 'app-event',
        eventType: 'main',
        isTestMode: 'false',
      },
    },
  };
}

function appEventPayload(): Record<string, unknown> {
  return {
    eventId: 'app-event',
    eventName: 'Event',
    startDate: '2026-07-20',
    endDate: '2026-07-20',
    assemblyTime: '18:00',
    separatorTime: '19:00',
    endTime: '22:00',
    location: 'Location',
    isTestMode: false,
  };
}

test('Omer guest cleanup preserves every remaining attendee field and is silent', async () => {
  const originalFetch = globalThis.fetch;
  const requests: Array<{url: URL; init: RequestInit}> = [];
  globalThis.fetch = async (input, init = {}) => {
    const url = new URL(String(input));
    requests.push({url, init});
    if (init.method === 'GET') {
      return jsonResponse(appEventResponse([
        {email: 'OMERBENGAL7@GMAIL.COM', responseStatus: 'accepted'},
        {email: 'other@example.com', responseStatus: 'tentative', comment: 'Keep me'},
      ]));
    }
    return jsonResponse({});
  };

  try {
    const result = await executeCalendarAction(
      fakeFirestore(),
      adminActor,
      'production',
      'cleanupAppEventGuests',
      {
        calendarEventId: 'google-event',
        mode: 'omer',
        eventId: 'app-event',
        isTestMode: false,
      },
    );

    assert.deepEqual(result, {changed: true});
    assert.equal(requests.length, 2);
    assert.equal(requests[1].init.method, 'PATCH');
    assert.equal(requests[1].url.searchParams.get('sendUpdates'), 'none');
    assert.deepEqual(JSON.parse(String(requests[1].init.body)), {
      attendees: [
        {email: 'other@example.com', responseStatus: 'tentative', comment: 'Keep me'},
      ],
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('all-guest cleanup sends an explicit empty attendee array without notifications', async () => {
  const originalFetch = globalThis.fetch;
  const requests: Array<{url: URL; init: RequestInit}> = [];
  globalThis.fetch = async (input, init = {}) => {
    requests.push({url: new URL(String(input)), init});
    if (init.method === 'GET') {
      return jsonResponse(appEventResponse([
        {email: 'one@example.com'},
        {email: 'two@example.com', responseStatus: 'accepted'},
      ]));
    }
    return jsonResponse({});
  };

  try {
    const result = await executeCalendarAction(
      fakeFirestore(),
      adminActor,
      'production',
      'cleanupAppEventGuests',
      {
        calendarEventId: 'google-event',
        mode: 'all',
        eventId: 'app-event',
        isTestMode: false,
      },
    );

    assert.deepEqual(result, {changed: true});
    assert.equal(requests[1].url.searchParams.get('sendUpdates'), 'none');
    assert.deepEqual(JSON.parse(String(requests[1].init.body)), {attendees: []});
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('guest cleanup refuses an event from the other environment', async () => {
  const originalFetch = globalThis.fetch;
  const requests: RequestInit[] = [];
  globalThis.fetch = async (_input, init = {}) => {
    requests.push(init);
    return jsonResponse(appEventResponse([{email: 'one@example.com'}]));
  };

  try {
    await assert.rejects(
      executeCalendarAction(
        fakeFirestore(),
        adminActor,
        'test',
        'cleanupAppEventGuests',
        {
          calendarEventId: 'google-event',
          mode: 'all',
          eventId: 'app-event',
          isTestMode: true,
        },
      ),
      /identity does not match/,
    );
    assert.deepEqual(requests.map((request) => request.method ?? 'GET'), ['GET']);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('all legacy attendee actions are no-ops for managed app events', async () => {
  const originalFetch = globalThis.fetch;
  const requests: RequestInit[] = [];
  globalThis.fetch = async (_input, init = {}) => {
    requests.push(init);
    return jsonResponse(appEventResponse([{email: 'existing@example.com'}]));
  };

  try {
    await executeCalendarAction(
      fakeFirestore(),
      adminActor,
      'production',
      'addAttendeeToEvent',
      {calendarEventId: 'google-event', email: 'new@example.com'},
    );
    await executeCalendarAction(
      fakeFirestore(),
      adminActor,
      'production',
      'updateEventAttendees',
      {calendarEventId: 'google-event', emails: ['new@example.com']},
    );
    await executeCalendarAction(
      fakeFirestore(),
      adminActor,
      'production',
      'removeAttendeeFromEvent',
      {
        calendarEventId: 'google-event',
        email: 'existing@example.com',
        sendUpdates: 'none',
      },
    );

    assert.deepEqual(
      requests.map((request) => request.method ?? 'GET'),
      ['GET', 'GET', 'GET'],
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('app-event detail updates PATCH without attendees or notifications', async () => {
  const originalFetch = globalThis.fetch;
  const requests: Array<{url: URL; init: RequestInit}> = [];
  globalThis.fetch = async (input, init = {}) => {
    requests.push({url: new URL(String(input)), init});
    return jsonResponse({});
  };

  try {
    await executeCalendarAction(
      fakeFirestore(),
      adminActor,
      'production',
      'updateAppEventCalendarEvents',
      {
        assemblyCalendarEventId: 'assembly-id',
        mainCalendarEventId: 'main-id',
        event: appEventPayload(),
      },
    );

    assert.equal(requests.length, 2);
    for (const request of requests) {
      assert.equal(request.init.method, 'PATCH');
      assert.equal(request.url.searchParams.get('sendUpdates'), 'none');
      const body = JSON.parse(String(request.init.body)) as Record<string, unknown>;
      assert.equal(Object.hasOwn(body, 'attendees'), false);
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('timed-to-all-day update silently deletes assembly and PATCHes main', async () => {
  const originalFetch = globalThis.fetch;
  const requests: Array<{url: URL; init: RequestInit}> = [];
  globalThis.fetch = async (input, init = {}) => {
    requests.push({url: new URL(String(input)), init});
    return jsonResponse({});
  };

  try {
    await executeCalendarAction(
      fakeFirestore(),
      adminActor,
      'production',
      'updateAppEventCalendarEvents',
      {
        assemblyCalendarEventId: 'assembly-id',
        mainCalendarEventId: 'main-id',
        event: {
          ...appEventPayload(),
          assemblyTime: '',
          separatorTime: '',
          endTime: '',
        },
      },
    );

    assert.deepEqual(requests.map((request) => request.init.method), ['DELETE', 'PATCH']);
    assert.equal(requests[0].url.searchParams.get('sendUpdates'), 'none');
    assert.equal(requests[1].url.searchParams.get('sendUpdates'), 'none');
    const body = JSON.parse(String(requests[1].init.body)) as Record<string, unknown>;
    assert.equal(Object.hasOwn(body, 'attendees'), false);
    // PATCH merges nested objects field by field, so the timed event's
    // dateTime/timeZone survive unless they are explicitly cleared, and Google
    // rejects a start carrying both date and dateTime with 400 Invalid start time.
    assert.deepEqual(body['start'], {date: '2026-07-20', dateTime: null, timeZone: null});
    assert.deepEqual(body['end'], {date: '2026-07-21', dateTime: null, timeZone: null});
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('all-day-to-timed update clears the leftover all-day date on both parts', async () => {
  const originalFetch = globalThis.fetch;
  const requests: Array<{url: URL; init: RequestInit}> = [];
  globalThis.fetch = async (input, init = {}) => {
    requests.push({url: new URL(String(input)), init});
    return jsonResponse({});
  };

  try {
    await executeCalendarAction(
      fakeFirestore(),
      adminActor,
      'production',
      'updateAppEventCalendarEvents',
      {
        assemblyCalendarEventId: 'assembly-id',
        mainCalendarEventId: 'main-id',
        event: appEventPayload(),
      },
    );

    assert.deepEqual(requests.map((request) => request.init.method), ['PATCH', 'PATCH']);
    // The main part is the calendar event that used to be the all-day block, so
    // its stored start.date/end.date must be nulled out in the same patch that
    // introduces dateTime — otherwise Google merges both and returns
    // 400 Invalid start time.
    for (const request of requests) {
      const body = JSON.parse(String(request.init.body)) as Record<string, unknown>;
      const start = body['start'] as Record<string, unknown>;
      const end = body['end'] as Record<string, unknown>;
      assert.equal(start['date'], null);
      assert.equal(end['date'], null);
      assert.equal(typeof start['dateTime'], 'string');
      assert.equal(typeof end['dateTime'], 'string');
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('deterministic app-event create is silent and treats a matching 409 as success', async () => {
  const originalFetch = globalThis.fetch;
  const requests: Array<{url: URL; init: RequestInit}> = [];
  globalThis.fetch = async (input, init = {}) => {
    requests.push({url: new URL(String(input)), init});
    if (init.method === 'POST') {
      return jsonResponse({error: {message: 'Already exists'}}, 409);
    }
    return jsonResponse(appEventResponse());
  };

  try {
    const result = await executeCalendarAction(
      fakeFirestore(),
      adminActor,
      'production',
      'createAppEventCalendarEventPart',
      {
        event: appEventPayload(),
        eventType: 'main',
        calendarEventId: 'deterministic-id',
      },
    );

    assert.deepEqual(result, {calendarEventId: 'deterministic-id'});
    assert.equal(requests[0].init.method, 'POST');
    assert.equal(requests[0].url.searchParams.get('sendUpdates'), 'none');
    const body = JSON.parse(String(requests[0].init.body)) as Record<string, unknown>;
    assert.equal(body['id'], 'deterministic-id');
    assert.equal(Object.hasOwn(body, 'attendees'), false);
    assert.equal(requests[1].init.method, 'GET');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('a cancelled deterministic ID is recreated silently with a fresh ID', async () => {
  const originalFetch = globalThis.fetch;
  const requests: Array<{url: URL; init: RequestInit}> = [];
  var postCount = 0;
  globalThis.fetch = async (input, init = {}) => {
    requests.push({url: new URL(String(input)), init});
    if (init.method === 'POST') {
      postCount += 1;
      return postCount === 1
        ? jsonResponse({error: {message: 'Already exists'}}, 409)
        : jsonResponse({id: 'replacement-id'});
    }
    return jsonResponse({...appEventResponse(), status: 'cancelled'});
  };

  try {
    const result = await executeCalendarAction(
      fakeFirestore(),
      adminActor,
      'production',
      'createAppEventCalendarEventPart',
      {
        event: appEventPayload(),
        eventType: 'main',
        calendarEventId: 'deterministic-id',
      },
    );

    assert.deepEqual(result, {calendarEventId: 'replacement-id'});
    assert.deepEqual(
      requests.map((request) => request.init.method),
      ['POST', 'GET', 'POST'],
    );
    assert.equal(requests[2].url.searchParams.get('sendUpdates'), 'none');
    const replacementBody = JSON.parse(String(requests[2].init.body)) as Record<string, unknown>;
    assert.equal(Object.hasOwn(replacementBody, 'id'), false);
    assert.equal(Object.hasOwn(replacementBody, 'attendees'), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
