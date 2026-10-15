import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';
import {
  StageDoc,
  applyStageEdit,
  buildNewStage,
  eventLocalDays,
  stageAuditDetails,
  stageFromStored,
} from './stages';
import {TaskActor, TaskError} from './tasks';

const now = Timestamp.fromMillis(1_800_000_000_000);
const later = Timestamp.fromMillis(1_800_000_600_000);

const manager: TaskActor = {
  memberId: 'm-admin',
  name: 'מנהל',
  isAdmin: true,
  canManageTasks: false,
};

// A two-day event on 21–22/10/2026, stored the way the app stores events:
// each day as the UTC instant of Israel midnight (UTC+3 in October).
const twoDays = ['2026-10-21', '2026-10-22'];

function baseInput(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 's1',
    eventId: 'e1',
    title: 'קליטה ורישום',
    date: '2026-10-21',
    startTime: '08:00',
    endTime: '10:45',
    requirements: 'שני שולחנות בלובי',
    hotelLocation: 'לובי',
    notes: 'להגיע מוקדם',
    contacts: [
      {id: 'c1', name: 'אבי', phone: '050-1234567', role: 'מנהל אירועים'},
    ],
    ...overrides,
  };
}

function expectStageError(fn: () => unknown, status: number, message?: string): void {
  assert.throws(fn, (error: unknown) => {
    assert.ok(error instanceof TaskError, `expected TaskError, got ${error}`);
    assert.equal(error.status, status);
    if (message != null) assert.equal(error.message, message);
    return true;
  });
}

const ctx = {now, actor: manager};

test('eventLocalDays lists one day for a one-day event', () => {
  const start = Date.parse('2026-10-13T21:00:00Z'); // 14/10 in Israel
  assert.deepEqual(eventLocalDays(start, start), ['2026-10-14']);
});

test('eventLocalDays lists every Israel day of a multi-day event', () => {
  const start = Date.parse('2026-10-20T21:00:00Z'); // 21/10
  const end = Date.parse('2026-10-22T21:00:00Z'); // 23/10
  assert.deepEqual(eventLocalDays(start, end), [
    '2026-10-21',
    '2026-10-22',
    '2026-10-23',
  ]);
});

test('eventLocalDays reads days in Israel time across the winter clock change', () => {
  // Winter time (UTC+2): Israel midnight is 22:00Z the day before.
  const start = Date.parse('2026-12-15T22:00:00Z'); // 16/12
  const end = Date.parse('2026-12-16T22:00:00Z'); // 17/12
  assert.deepEqual(eventLocalDays(start, end), ['2026-12-16', '2026-12-17']);
});

test('eventLocalDays treats a missing or earlier end as a one-day event', () => {
  const start = Date.parse('2026-10-20T21:00:00Z');
  assert.deepEqual(eventLocalDays(start, null), ['2026-10-21']);
  assert.deepEqual(
    eventLocalDays(start, Date.parse('2026-10-10T21:00:00Z')),
    ['2026-10-21'],
  );
});

test('buildNewStage keeps the fields and stamps the creation', () => {
  const stage = buildNewStage(baseInput(), ctx, twoDays);
  assert.equal(stage.id, 's1');
  assert.equal(stage.eventId, 'e1');
  assert.equal(stage.title, 'קליטה ורישום');
  assert.equal(stage.date, '2026-10-21');
  assert.equal(stage.startTime, '08:00');
  assert.equal(stage.endTime, '10:45');
  assert.equal(stage.requirements, 'שני שולחנות בלובי');
  assert.equal(stage.hotelLocation, 'לובי');
  assert.equal(stage.notes, 'להגיע מוקדם');
  assert.deepEqual(stage.contacts, [
    {id: 'c1', name: 'אבי', phone: '050-1234567', role: 'מנהל אירועים'},
  ]);
  assert.equal(stage.createdById, 'm-admin');
  assert.equal(stage.createdAt, now);
  assert.equal(stage.updatedAt, now);
});

test('buildNewStage trims text and fills absent optional fields', () => {
  const stage = buildNewStage(
    {
      id: 's1',
      eventId: 'e1',
      title: '  ארוחת ערב  ',
      date: '2026-10-22',
    },
    ctx,
    twoDays,
  );
  assert.equal(stage.title, 'ארוחת ערב');
  assert.equal(stage.startTime, null);
  assert.equal(stage.endTime, null);
  assert.equal(stage.requirements, '');
  assert.equal(stage.hotelLocation, '');
  assert.equal(stage.notes, '');
  assert.deepEqual(stage.contacts, []);
});

test('a stage needs an id, an event and a title', () => {
  expectStageError(() => buildNewStage(baseInput({id: 'a/b'}), ctx, twoDays), 400);
  expectStageError(() => buildNewStage(baseInput({eventId: ''}), ctx, twoDays), 400);
  expectStageError(
    () => buildNewStage(baseInput({title: '   '}), ctx, twoDays),
    400,
    'חובה להזין כותרת',
  );
  expectStageError(
    () => buildNewStage(baseInput({title: 'א'.repeat(201)}), ctx, twoDays),
    400,
  );
});

test('the date must be one of the event days', () => {
  expectStageError(
    () => buildNewStage(baseInput({date: null}), ctx, twoDays),
    400,
    'חובה לבחור תאריך',
  );
  expectStageError(
    () => buildNewStage(baseInput({date: '2026-10-23'}), ctx, twoDays),
    400,
    'התאריך אינו מתאריכי האירוע',
  );
  expectStageError(
    () => buildNewStage(baseInput({date: '21/10/2026'}), ctx, twoDays),
    400,
  );
});

test('times are HH:mm on the 24-hour clock', () => {
  for (const bad of ['8:00', '24:00', '08:60', '0800', 8]) {
    expectStageError(
      () => buildNewStage(baseInput({startTime: bad, endTime: null}), ctx, twoDays),
      400,
    );
  }
  const single = buildNewStage(
    baseInput({startTime: '23:30', endTime: null}),
    ctx,
    twoDays,
  );
  assert.equal(single.startTime, '23:30');
  assert.equal(single.endTime, null);
});

test('an end time needs a start time and must come after it', () => {
  expectStageError(
    () => buildNewStage(baseInput({startTime: null, endTime: '10:00'}), ctx, twoDays),
    400,
    'שעת סיום דורשת שעת התחלה',
  );
  expectStageError(
    () => buildNewStage(baseInput({startTime: '10:00', endTime: '10:00'}), ctx, twoDays),
    400,
    'שעת הסיום חייבת להיות אחרי שעת ההתחלה',
  );
  expectStageError(
    () => buildNewStage(baseInput({startTime: '10:00', endTime: '09:59'}), ctx, twoDays),
    400,
  );
});

test('long text fields are refused', () => {
  expectStageError(
    () => buildNewStage(baseInput({requirements: 'א'.repeat(5001)}), ctx, twoDays),
    400,
  );
  expectStageError(
    () => buildNewStage(baseInput({notes: 'א'.repeat(5001)}), ctx, twoDays),
    400,
  );
  expectStageError(
    () => buildNewStage(baseInput({hotelLocation: 'א'.repeat(201)}), ctx, twoDays),
    400,
  );
});

test('blank contact rows are dropped and the rest trimmed', () => {
  const stage = buildNewStage(
    baseInput({
      contacts: [
        {id: 'c1', name: ' אבי ', phone: ' 050-1234567 ', role: ''},
        {id: 'c2', name: '', phone: '', role: ''},
        {id: 'c3', name: 'דנה', phone: '', role: 'קבלה'},
      ],
    }),
    ctx,
    twoDays,
  );
  assert.deepEqual(stage.contacts, [
    {id: 'c1', name: 'אבי', phone: '050-1234567', role: ''},
    {id: 'c3', name: 'דנה', phone: '', role: 'קבלה'},
  ]);
});

test('a contact with a phone or role needs a name', () => {
  expectStageError(
    () => buildNewStage(
      baseInput({contacts: [{id: 'c1', name: '', phone: '050', role: ''}]}),
      ctx,
      twoDays,
    ),
    400,
    'לכל איש קשר נדרש שם',
  );
});

test('a contact phone may hold only digits and phone punctuation', () => {
  expectStageError(
    () => buildNewStage(
      baseInput({contacts: [{id: 'c1', name: 'אבי', phone: 'abc', role: ''}]}),
      ctx,
      twoDays,
    ),
    400,
    'מספר טלפון לא תקין',
  );
  const stage = buildNewStage(
    baseInput({
      contacts: [{id: 'c1', name: 'אבי', phone: '+972 (50) 123-4567', role: ''}],
    }),
    ctx,
    twoDays,
  );
  assert.equal(stage.contacts[0].phone, '+972 (50) 123-4567');
});

test('contacts are limited and need distinct ids', () => {
  const many = Array.from({length: 31}, (_, index) => ({
    id: `c${index}`,
    name: 'אבי',
    phone: '',
    role: '',
  }));
  expectStageError(() => buildNewStage(baseInput({contacts: many}), ctx, twoDays), 400);
  expectStageError(
    () => buildNewStage(
      baseInput({
        contacts: [
          {id: 'c1', name: 'אבי', phone: '', role: ''},
          {id: 'c1', name: 'דנה', phone: '', role: ''},
        ],
      }),
      ctx,
      twoDays,
    ),
    400,
  );
  expectStageError(
    () => buildNewStage(baseInput({contacts: 'אבי'}), ctx, twoDays),
    400,
  );
});

test('applyStageEdit replaces the edited fields and keeps the creation', () => {
  const existing = buildNewStage(baseInput(), ctx, twoDays);
  const edited = applyStageEdit(
    existing,
    baseInput({title: 'קליטה', date: '2026-10-22', startTime: null, endTime: null}),
    {now: later, actor: manager},
    twoDays,
  );
  assert.equal(edited.title, 'קליטה');
  assert.equal(edited.date, '2026-10-22');
  assert.equal(edited.startTime, null);
  assert.equal(edited.createdAt, now);
  assert.equal(edited.createdById, 'm-admin');
  assert.equal(edited.updatedAt, later);
});

test('applyStageEdit cannot move a stage to another event or id', () => {
  const existing = buildNewStage(baseInput(), ctx, twoDays);
  expectStageError(
    () => applyStageEdit(existing, baseInput({eventId: 'e2'}), ctx, twoDays),
    400,
  );
  expectStageError(
    () => applyStageEdit(existing, baseInput({id: 's2'}), ctx, twoDays),
    400,
  );
});

test('stageFromStored tolerates a document with missing or odd fields', () => {
  const stage: StageDoc = stageFromStored('s1', {
    title: 42,
    contacts: [{id: 'c1', name: 'אבי'}, 'junk', {name: 'no id'}],
  });
  assert.equal(stage.id, 's1');
  assert.equal(stage.eventId, '');
  assert.equal(stage.title, '');
  assert.equal(stage.date, '');
  assert.equal(stage.startTime, null);
  assert.deepEqual(stage.contacts, [{id: 'c1', name: 'אבי', phone: '', role: ''}]);
});

test('stageAuditDetails names the stage by its title', () => {
  const stage = buildNewStage(baseInput(), ctx, twoDays);
  assert.deepEqual(stageAuditDetails(stage, {taskCount: 3}), {
    name: 'קליטה ורישום',
    eventId: 'e1',
    date: '2026-10-21',
    taskCount: 3,
  });
});
