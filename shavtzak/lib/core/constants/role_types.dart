/// Role types for team assignments
/// Hebrew names are stored for display purposes
enum RoleType {
  eventCommander,
  safetyOfficer,
  safetyManager,
  internalProduction,
  entryCommander,
  entryScreening,
  investigation,
  social,
  guidesToInvestigation,
  orderOrganization,
  giftDistribution,
  medic,
  paramedic,
  rabbi,
  commandCenter,
  operationsCrew,
}

/// Extension to add Hebrew display names and helper methods
extension RoleTypeExtension on RoleType {
  /// Get the Hebrew display name for this role
  String get hebrewName {
    switch (this) {
      case RoleType.eventCommander:
        return 'מפקד אירוע';
      case RoleType.safetyOfficer:
        return 'קצין בטיחות';
      case RoleType.safetyManager:
        return 'ממונה בטיחות';
      case RoleType.internalProduction:
        return 'הפקה פנימית';
      case RoleType.entryCommander:
        return 'מפקד כניסה';
      case RoleType.entryScreening:
        return 'כניסה / סריקה';
      case RoleType.investigation:
        return 'בירור / מחשב';
      case RoleType.social:
        return 'סושיאל';
      case RoleType.guidesToInvestigation:
        return 'מלווים לעמדת בירור';
      case RoleType.orderOrganization:
        return 'סדר וארגון';
      case RoleType.giftDistribution:
        return 'חלוקת מתנות';
      case RoleType.medic:
        return 'חובש/ת';
      case RoleType.paramedic:
        return 'פרמדיק/ית';
      case RoleType.rabbi:
        return 'רב';
      case RoleType.commandCenter:
        return 'מוקד';
      case RoleType.operationsCrew:
        return 'צוות תפעול';
    }
  }

  /// Get the English key for database storage
  String get key {
    return toString().split('.').last;
  }

  /// Parse a role type from a string key
  static RoleType fromString(String key) {
    return RoleType.values.firstWhere(
      (type) => type.key == key,
      orElse: () => throw ArgumentError('Invalid role type: $key'),
    );
  }

  /// Parse a role type from Hebrew name (for V1 import)
  static RoleType? fromHebrewName(String hebrewName) {
    for (final role in RoleType.values) {
      if (role.hebrewName == hebrewName) {
        return role;
      }
    }
    return null;
  }
}

/// Assignment status
enum AssignmentStatus {
  pending,
  confirmed,
  declined,
}

extension AssignmentStatusExtension on AssignmentStatus {
  String get hebrewName {
    switch (this) {
      case AssignmentStatus.pending:
        return 'ממתין';
      case AssignmentStatus.confirmed:
        return 'מאושר';
      case AssignmentStatus.declined:
        return 'נדחה';
    }
  }

  String get key {
    return toString().split('.').last;
  }

  static AssignmentStatus fromString(String key) {
    return AssignmentStatus.values.firstWhere(
      (status) => status.key == key,
      orElse: () => AssignmentStatus.pending,
    );
  }
}
