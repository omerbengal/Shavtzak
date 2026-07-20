/// Staged-vs-DB conflict types detected at Save time, by comparing each
/// staged change's baseline (the DB state captured when the slot was first
/// touched) against the CURRENT DB state.
enum AssignmentConflictType {
  slotTaken, // A: fill/swap; DB now a different member
  targetRemoved, // B: swap/notes; DB assignment gone (now empty)
  clearCollision, // C: clear; DB now a different member
  slotVanished, // D: quota shrank; slot no longer exists
  memberGone, // E: assigned member deactivated/deleted — DEFERRED, not produced yet
  notesChanged, // F: notes edit collides with a DB notes change
  quotaChanged, // G: role quota changed in DB under a staged quota change
}

/// How the admin chose to resolve a two-button [AssignmentConflict].
enum ConflictResolution { overrideDb, takeDb }

/// A single staged-vs-DB conflict to resolve at Save.
class AssignmentConflict {
  final String slotKey;
  final AssignmentConflictType type;
  final String description; // Hebrew, human-readable
  final String? title; // Hebrew "<event name> · <role>" context header (which slot)
  final bool discardOnly; // true => single-button (E fully-deleted only). D is two-button.

  const AssignmentConflict({
    required this.slotKey,
    required this.type,
    required this.description,
    this.title,
    this.discardOnly = false,
  });
}
