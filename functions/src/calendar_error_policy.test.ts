import test from 'node:test';
import assert from 'node:assert/strict';
import {
  CalendarAuthError,
  GoogleApiError,
} from './calendar_integration';
import {classifyCalendarFailure} from './calendar_error_policy';

test('classifies Google usage limits and every HTTP 429 as quota', () => {
  assert.equal(
    classifyCalendarFailure(
      new GoogleApiError(403, '{"domain":"usageLimits","reason":"quotaExceeded"}'),
    ).kind,
    'quota',
  );
  assert.equal(
    classifyCalendarFailure(new GoogleApiError(429, 'Too many requests')).kind,
    'quota',
  );
});

test('classifies missing, revoked, and unauthorized OAuth as auth-blocked', () => {
  assert.equal(
    classifyCalendarFailure(new CalendarAuthError()).kind,
    'auth-blocked',
  );
  assert.equal(
    classifyCalendarFailure(new GoogleApiError(401, 'Unauthorized')).kind,
    'auth-blocked',
  );
  assert.equal(
    classifyCalendarFailure(new GoogleApiError(403, 'Forbidden')).kind,
    'auth-blocked',
  );
  assert.equal(
    classifyCalendarFailure(new GoogleApiError(400, '{"error":"invalid_client"}')).kind,
    'auth-blocked',
  );
});

test('classifies Google 5xx and nested network failures as transient', () => {
  assert.equal(
    classifyCalendarFailure(new GoogleApiError(503, 'Service unavailable')).kind,
    'retryable-transient',
  );

  const networkError = new TypeError('fetch failed', {
    cause: Object.assign(new Error('socket closed'), {code: 'ECONNRESET'}),
  });
  assert.equal(
    classifyCalendarFailure(networkError).kind,
    'retryable-transient',
  );
});

test('classifies validation and ordinary not-found errors as terminal', () => {
  assert.equal(
    classifyCalendarFailure(new GoogleApiError(400, 'Invalid event time')).kind,
    'terminal',
  );
  assert.equal(
    classifyCalendarFailure(new GoogleApiError(404, 'Not found')).kind,
    'terminal',
  );
  assert.equal(classifyCalendarFailure(new Error('Invalid payload')).kind, 'terminal');
});
