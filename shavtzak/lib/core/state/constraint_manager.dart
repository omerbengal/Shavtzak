import '../../domain/entities/team_member.dart';
import '../../core/constants/constraint_status.dart';

/// Represents a constraint with local modification tracking
class TrackedConstraint {
  final DateConstraint constraint;
  final DateConstraint? originalDatabaseConstraint; // Original DB state before local modifications
  final String? localId; // null for constraints from database
  final DateTime lastModified;
  final bool isLocallyAdded;
  final bool isLocallyModified;
  final bool isLocallyDeleted;

  const TrackedConstraint({
    required this.constraint,
    this.originalDatabaseConstraint,
    this.localId,
    required this.lastModified,
    this.isLocallyAdded = false,
    this.isLocallyModified = false,
    this.isLocallyDeleted = false,
  });

  /// Create a tracked constraint from database constraint
  factory TrackedConstraint.fromDatabase(DateConstraint constraint) {
    return TrackedConstraint(
      constraint: constraint,
      originalDatabaseConstraint: constraint, // Store original DB state
      lastModified: DateTime.now(),
    );
  }

  /// Create a newly added tracked constraint
  factory TrackedConstraint.addedLocally(DateConstraint constraint, String localId) {
    return TrackedConstraint(
      constraint: constraint,
      localId: localId,
      lastModified: DateTime.now(),
      isLocallyAdded: true,
      isLocallyModified: true,
    );
  }

  /// Check if this constraint conflicts with an incoming remote constraint
  bool conflictsWith(TrackedConstraint other) {
    // Same constraint ID (both from database)
    if (localId == null && other.localId == null) {
      return false; // These are the same constraint
    }

    // Same local ID (both are local versions of same constraint)
    if (localId != null && other.localId != null && localId == other.localId) {
      return false; // Same local constraint
    }

    // Check if constraints have overlapping dates
    return constraint.startDate.isAtSameMomentAs(other.constraint.startDate) ||
           (constraint.endDate != null && other.constraint.endDate != null &&
            constraint.endDate!.isAtSameMomentAs(other.constraint.endDate!)) ||
           _hasOverlappingTime(constraint, other.constraint);
  }

  bool _hasOverlappingTime(DateConstraint a, DateConstraint b) {
    if (a.endDate == null && b.endDate == null) {
      return a.startDate.isAtSameMomentAs(b.startDate);
    }
    if (a.endDate == null) {
      return b.startDate.isBefore(a.startDate.add(const Duration(days: 1))) &&
             (b.endDate == null || b.endDate!.isAfter(a.startDate.subtract(const Duration(days: 1))));
    }
    if (b.endDate == null) {
      return a.startDate.isBefore(b.startDate.add(const Duration(days: 1))) &&
             (a.endDate == null || a.endDate!.isAfter(b.startDate.subtract(const Duration(days: 1))));
    }
    // Both have end dates - check for overlap
    return a.startDate.isBefore(b.endDate!.add(const Duration(days: 1))) &&
           b.startDate.isBefore(a.endDate!.add(const Duration(days: 1)));
  }

  TrackedConstraint copyWith({
    DateConstraint? constraint,
    DateConstraint? originalDatabaseConstraint,
    String? localId,
    DateTime? lastModified,
    bool? isLocallyAdded,
    bool? isLocallyModified,
    bool? isLocallyDeleted,
  }) {
    return TrackedConstraint(
      constraint: constraint ?? this.constraint,
      originalDatabaseConstraint: originalDatabaseConstraint ?? this.originalDatabaseConstraint,
      localId: localId ?? this.localId,
      lastModified: lastModified ?? this.lastModified,
      isLocallyAdded: isLocallyAdded ?? this.isLocallyAdded,
      isLocallyModified: isLocallyModified ?? this.isLocallyModified,
      isLocallyDeleted: isLocallyDeleted ?? this.isLocallyDeleted,
    );
  }
}

/// Conflict between local and remote constraint changes
class ConstraintConflict {
  final TrackedConstraint localConstraint;
  final TrackedConstraint remoteConstraint;
  final ConflictType type;

  ConstraintConflict({
    required this.localConstraint,
    required this.remoteConstraint,
    required this.type,
  });
}

enum ConflictType {
  statusModified, // Same constraint, different status
  datesModified,  // Same constraint, different dates
  addedRemotely,  // Remote constraint added during local session
  deletedRemotely, // Remote constraint deleted during local session
  complexConflict, // Multiple changes to same constraint
}

/// Hybrid constraint state manager that handles local and remote state synchronization
class LocalConstraintManager {
  final Map<String, TrackedConstraint> _databaseConstraints = {}; // constraint.id -> TrackedConstraint
  final Map<String, TrackedConstraint> _localConstraints = {}; // localId -> TrackedConstraint
  final Set<String> _deletedDatabaseIds = {}; // Database constraints marked for deletion
  final Set<String> _deletedLocalIds = {}; // Local constraints marked for deletion

  /// Get all effective constraints (database + local additions - deletions)
  List<DateConstraint> getEffectiveConstraints() {
    final effectiveConstraints = <DateConstraint>[];

    // Add database constraints that aren't deleted
    for (final tracked in _databaseConstraints.values) {
      if (!_deletedDatabaseIds.contains(tracked.constraint.id) && !tracked.isLocallyDeleted) {
        effectiveConstraints.add(tracked.constraint);
      }
    }

    // Add locally added constraints that aren't deleted
    for (final tracked in _localConstraints.values) {
      if (!_deletedLocalIds.contains(tracked.localId!) && !tracked.isLocallyDeleted) {
        effectiveConstraints.add(tracked.constraint);
      }
    }

    return effectiveConstraints;
  }

  /// Initialize with database constraints
  void initializeFromDatabase(List<DateConstraint> databaseConstraints) {
    _databaseConstraints.clear();
    for (final constraint in databaseConstraints) {
      _databaseConstraints[constraint.id] = TrackedConstraint.fromDatabase(constraint);
    }
  }

  /// Update with incoming database changes and detect conflicts
  List<ConstraintConflict> syncWithDatabaseChanges(List<DateConstraint> remoteConstraints) {
    final conflicts = <ConstraintConflict>[];
    final newDatabaseConstraints = <String, DateConstraint>{};

    // Build map of remote constraints
    for (final constraint in remoteConstraints) {
      newDatabaseConstraints[constraint.id] = constraint;
    }

    // Check for conflicts and update database constraints
    for (final entry in _databaseConstraints.entries.toList()) {
      final constraintId = entry.key;
      final localTracked = entry.value;
      final remoteConstraint = newDatabaseConstraints[constraintId];

      if (remoteConstraint == null) {
        // Constraint deleted remotely
        if (localTracked.isLocallyModified) {
          conflicts.add(ConstraintConflict(
            localConstraint: localTracked,
            remoteConstraint: TrackedConstraint(
              constraint: localTracked.constraint,
              lastModified: DateTime.now(),
              isLocallyDeleted: true,
            ),
            type: ConflictType.deletedRemotely,
          ));
        }
        _databaseConstraints.remove(constraintId);
      } else {
        // Constraint exists remotely - check if it was updated in DB
        final originalDbConstraint = localTracked.originalDatabaseConstraint ?? localTracked.constraint;
        final wasUpdatedInDb = remoteConstraint != originalDbConstraint;

        if (wasUpdatedInDb) {
          // Constraint was updated in database - override local changes
          if (localTracked.isLocallyModified) {
            // Log conflicts for debugging (but still override with DB state)
            if (localTracked.constraint.status != remoteConstraint.status) {
              conflicts.add(ConstraintConflict(
                localConstraint: localTracked,
                remoteConstraint: TrackedConstraint.fromDatabase(remoteConstraint),
                type: ConflictType.statusModified,
              ));
            }
            if (localTracked.constraint.startDate != remoteConstraint.startDate ||
                localTracked.constraint.endDate != remoteConstraint.endDate) {
              conflicts.add(ConstraintConflict(
                localConstraint: localTracked,
                remoteConstraint: TrackedConstraint.fromDatabase(remoteConstraint),
                type: ConflictType.datesModified,
              ));
            }
          }
          // Update with new database state (clears local modifications)
          _databaseConstraints[constraintId] = TrackedConstraint.fromDatabase(remoteConstraint);
        } else {
          // Constraint was NOT updated in database - keep local changes
          // Don't update _databaseConstraints[constraintId]
        }
      }
      newDatabaseConstraints.remove(constraintId);
    }

    // Check for newly added remote constraints
    for (final entry in newDatabaseConstraints.entries) {
      final constraintId = entry.key;
      final remoteConstraint = entry.value;

      // Check if this conflicts with any local constraint
      final remoteTracked = TrackedConstraint.fromDatabase(remoteConstraint);
      for (final localTracked in _localConstraints.values) {
        if (localTracked.conflictsWith(remoteTracked)) {
          conflicts.add(ConstraintConflict(
            localConstraint: localTracked,
            remoteConstraint: remoteTracked,
            type: ConflictType.addedRemotely,
          ));
          break;
        }
      }

      // Add to database constraints
      _databaseConstraints[constraintId] = remoteTracked;
    }

    return conflicts;
  }

  /// Update constraint status locally
  void updateConstraintStatus(String constraintId, ConstraintStatus newStatus) {
    if (_databaseConstraints.containsKey(constraintId)) {
      final tracked = _databaseConstraints[constraintId]!;
      _databaseConstraints[constraintId] = tracked.copyWith(
        constraint: tracked.constraint.copyWith(status: newStatus),
        lastModified: DateTime.now(),
        isLocallyModified: true,
      );
    }
  }

  /// Add new constraint locally
  String addConstraintLocally(DateConstraint constraint) {
    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}_${constraint.hashCode}';
    final tracked = TrackedConstraint.addedLocally(constraint, localId);
    _localConstraints[localId] = tracked;
    return localId;
  }

  /// Delete constraint locally (can be database or local constraint)
  void deleteConstraint(String id, {bool isLocalId = false}) {
    if (isLocalId) {
      if (_localConstraints.containsKey(id)) {
        final tracked = _localConstraints[id]!;
        _localConstraints[id] = tracked.copyWith(
          isLocallyDeleted: true,
          lastModified: DateTime.now(),
        );
      }
    } else {
      if (_databaseConstraints.containsKey(id)) {
        final tracked = _databaseConstraints[id]!;
        _databaseConstraints[id] = tracked.copyWith(
          isLocallyDeleted: true,
          lastModified: DateTime.now(),
        );
      }
    }
  }

  /// Get constraints that need to be synchronized with database
  List<DateConstraint> getPendingChanges() {
    final pending = <DateConstraint>[];

    // Modified database constraints
    for (final tracked in _databaseConstraints.values) {
      if (tracked.isLocallyModified && !tracked.isLocallyDeleted) {
        pending.add(tracked.constraint);
      }
    }

    // New local constraints
    for (final tracked in _localConstraints.values) {
      if (!tracked.isLocallyDeleted) {
        pending.add(tracked.constraint);
      }
    }

    return pending;
  }

  /// Get constraint IDs that need to be deleted from database
  List<String> getPendingDeletions() {
    final deletions = <String>[];

    for (final tracked in _databaseConstraints.values) {
      if (tracked.isLocallyDeleted) {
        deletions.add(tracked.constraint.id);
      }
    }

    return deletions;
  }

  /// Get tracked constraints for debugging
  Map<String, TrackedConstraint> getDatabaseConstraints() => Map.unmodifiable(_databaseConstraints);
  Map<String, TrackedConstraint> getLocalConstraints() => Map.unmodifiable(_localConstraints);
  Set<String> getDeletedDatabaseIds() => Set.unmodifiable(_deletedDatabaseIds);
  Set<String> getDeletedLocalIds() => Set.unmodifiable(_deletedLocalIds);

  /// Clear all local state (used when closing modal/discarding changes)
  void clearLocalState() {
    // Reset all database constraints to non-modified state
    for (final key in _databaseConstraints.keys.toList()) {
      final tracked = _databaseConstraints[key]!;
      _databaseConstraints[key] = tracked.copyWith(
        isLocallyModified: false,
        isLocallyDeleted: false,
      );
    }

    // Clear all local constraints
    _localConstraints.clear();
    _deletedDatabaseIds.clear();
    _deletedLocalIds.clear();
  }

  /// Check if there are any pending changes
  bool hasPendingChanges() {
    return getPendingChanges().isNotEmpty || getPendingDeletions().isNotEmpty;
  }
}