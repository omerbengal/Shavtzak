import {
  CalendarAuthError,
  GoogleApiError,
  isCalendarQuotaError,
} from './calendar_integration';

export type CalendarFailureKind =
  | 'quota'
  | 'auth-blocked'
  | 'retryable-transient'
  | 'terminal';

export type CalendarFailurePolicy = {
  kind: CalendarFailureKind;
  retryAfterSeconds: number | null;
};

const QUOTA_RETRY_SECONDS = 30 * 60;
const TRANSIENT_RETRY_SECONDS = 60;

const TRANSIENT_ERROR_CODES = new Set<unknown>([
  'ABORT_ERR',
  'ECONNREFUSED',
  'ECONNRESET',
  'EAI_AGAIN',
  'ENETDOWN',
  'ENETUNREACH',
  'EPIPE',
  'ETIMEDOUT',
  'UND_ERR_CONNECT_TIMEOUT',
  'UND_ERR_HEADERS_TIMEOUT',
  'UND_ERR_SOCKET',
  // Retryable gRPC codes used by Firestore/google-gax.
  4, // DEADLINE_EXCEEDED
  8, // RESOURCE_EXHAUSTED
  10, // ABORTED
  13, // INTERNAL
  14, // UNAVAILABLE
]);

function asRecord(value: unknown): Record<string, unknown> | null {
  return value != null && typeof value === 'object'
    ? value as Record<string, unknown>
    : null;
}

function hasTransientCode(error: unknown): boolean {
  let current: unknown = error;
  const seen = new Set<unknown>();
  while (current != null && !seen.has(current)) {
    seen.add(current);
    const record = asRecord(current);
    if (record == null) return false;
    if (TRANSIENT_ERROR_CODES.has(record['code'])) return true;
    current = record['cause'];
  }
  return false;
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message.toLowerCase();
  return String(error).toLowerCase();
}

function isOAuthConfigurationError(error: unknown): boolean {
  const message = errorMessage(error);
  return (
    message.includes('oauth credentials are not configured') ||
    message.includes('google calendar is not configured') ||
    message.includes('google did not return a refresh token') ||
    message.includes('invalid_client') ||
    message.includes('invalid_grant') ||
    message.includes('unauthorized_client')
  );
}

/**
 * Maps failures raised anywhere in a durable Calendar job to a state-machine
 * decision. Auth/config failures deliberately have no retry delay: they must
 * remain blocked until an admin reconnects or repairs the configuration.
 */
export function classifyCalendarFailure(error: unknown): CalendarFailurePolicy {
  if (
    isCalendarQuotaError(error) ||
    (error instanceof GoogleApiError && error.status === 429)
  ) {
    return {kind: 'quota', retryAfterSeconds: QUOTA_RETRY_SECONDS};
  }

  if (
    error instanceof CalendarAuthError ||
    isOAuthConfigurationError(error) ||
    (error instanceof GoogleApiError &&
      (error.status === 401 || error.status === 403))
  ) {
    return {kind: 'auth-blocked', retryAfterSeconds: null};
  }

  if (
    (error instanceof GoogleApiError &&
      (error.status === 408 ||
        error.status === 425 ||
        error.status >= 500)) ||
    hasTransientCode(error) ||
    errorMessage(error).includes('fetch failed')
  ) {
    return {
      kind: 'retryable-transient',
      retryAfterSeconds: TRANSIENT_RETRY_SECONDS,
    };
  }

  return {kind: 'terminal', retryAfterSeconds: null};
}
