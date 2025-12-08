/// Constraint type for date constraints
enum ConstraintType {
  unavailability,  // For permanent members - requires approval
  availability,    // For non-permanent members - immediate effect
}

/// Constraint status for user-submitted date constraint requests
/// Hebrew names are stored for display purposes
enum ConstraintStatus {
  pending,
  approved,
  rejected,
}

/// Extension to add Hebrew display names for constraint types
extension ConstraintTypeExtension on ConstraintType {
  /// Get the Hebrew display name for this type
  String get hebrewName {
    switch (this) {
      case ConstraintType.unavailability:
        return 'אי-זמינות';
      case ConstraintType.availability:
        return 'זמינות';
    }
  }
}

/// Extension to add Hebrew display names and helper methods
extension ConstraintStatusExtension on ConstraintStatus {
  /// Get the Hebrew display name for this status
  String get hebrewName {
    switch (this) {
      case ConstraintStatus.pending:
        return 'ממתין לאישור';
      case ConstraintStatus.approved:
        return 'אושר';
      case ConstraintStatus.rejected:
        return 'נדחה';
    }
  }

  /// Get the short Hebrew display name for this status
  String get hebrewShortName {
    switch (this) {
      case ConstraintStatus.pending:
        return 'ממתין';
      case ConstraintStatus.approved:
        return 'אושר';
      case ConstraintStatus.rejected:
        return 'נדחה';
    }
  }

  /// Get the color associated with this status
  String get colorHex {
    switch (this) {
      case ConstraintStatus.pending:
        return '#FF9800'; // Orange
      case ConstraintStatus.approved:
        return '#4CAF50'; // Green
      case ConstraintStatus.rejected:
        return '#F44336'; // Red
    }
  }
}