export type ParticipantGroup = {
  label: string | null;
  count: number;
};

const MAX_PARTICIPANT_GROUPS = 10;

/**
 * Coerce an event payload's participant groups into the shape stored in Firestore.
 *
 * Falls back to the retired `participantCount` scalar so an old web client — one
 * that has never heard of participantGroups — does not lose its audience size
 * during the rollout window.
 *
 * Coerces rather than throws: a malformed entry is dropped, never a failed save.
 */
export function normalizeParticipantGroups(
  groupsRaw: unknown,
  legacyCount: unknown,
): ParticipantGroup[] {
  if (Array.isArray(groupsRaw)) {
    const groups: ParticipantGroup[] = [];
    for (const entry of groupsRaw) {
      if (groups.length === MAX_PARTICIPANT_GROUPS) break;
      const group = toParticipantGroup(entry);
      if (group != null) {
        groups.push(group);
      }
    }
    return groups;
  }

  const legacy = toCount(legacyCount);
  return legacy == null ? [] : [{label: null, count: legacy}];
}

function toParticipantGroup(entry: unknown): ParticipantGroup | null {
  if (entry == null || typeof entry !== 'object') return null;
  const record = entry as Record<string, unknown>;
  const count = toCount(record['count']);
  if (count == null) return null;
  return {label: toLabel(record['label']), count};
}

function toCount(value: unknown): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    return null;
  }
  return Math.floor(value);
}

function toLabel(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}
