// Constants for Google Calendar integration

/// Calendar sync status
enum CalendarSyncStatus {
  synced,
  pending,
  failed,
  removed,
}

/// Extension for CalendarSyncStatus
extension CalendarSyncStatusExtension on CalendarSyncStatus {
  String get name {
    switch (this) {
      case CalendarSyncStatus.synced:
        return 'synced';
      case CalendarSyncStatus.pending:
        return 'pending';
      case CalendarSyncStatus.failed:
        return 'failed';
      case CalendarSyncStatus.removed:
        return 'removed';
    }
  }

  static CalendarSyncStatus fromString(String value) {
    switch (value) {
      case 'synced':
        return CalendarSyncStatus.synced;
      case 'pending':
        return CalendarSyncStatus.pending;
      case 'failed':
        return CalendarSyncStatus.failed;
      case 'removed':
        return CalendarSyncStatus.removed;
      default:
        return CalendarSyncStatus.pending;
    }
  }
}

/// Calendar event colors (Google Calendar color IDs)
/// See: https://developers.google.com/calendar/api/v3/reference/colors
class CalendarEventColors {
  // Unavailability constraints - Red tone
  static const String unavailability = '11'; // Red (Tomato)

  // Availability constraints - Green tone
  static const String availability = '10'; // Green (Basil)
}

/// Calendar sync configuration
class CalendarSyncConfig {
  /// Maximum number of retry attempts for failed syncs
  static const int maxRetryAttempts = 3;

  /// Initial retry delay in milliseconds
  static const int initialRetryDelayMs = 1000;

  /// Exponential backoff multiplier
  static const double backoffMultiplier = 2.0;

  /// Maximum retry delay in milliseconds (5 minutes)
  static const int maxRetryDelayMs = 300000;

  /// Debounce delay for rapid sync operations in milliseconds
  static const int debounceDelayMs = 500;

  /// Batch size for bulk calendar operations
  static const int batchSize = 50;

  /// Google Calendar API rate limit (requests per day)
  static const int dailyRateLimit = 10000;
}

/// Calendar event title templates (Hebrew)
class CalendarEventTitles {
  /// Title for unavailability constraint events
  /// Format: "[Name] - מגבלה"
  static String unavailability(String memberName) => '$memberName - מגבלה';

  /// Title for availability constraint events
  /// Format: "[Name] - זמינות"
  static String availability(String memberName) => '$memberName - זמינות';
}

/// Calendar event description templates (Hebrew)
class CalendarEventDescriptions {
  /// Description for constraint events
  static String constraint({
    required String memberName,
    required List<String> roles,
    String? note,
    required bool isUnavailability,
  }) {
    final buffer = StringBuffer();

    // Clean the note by removing the automatic rejection message if present
    final cleanedNote = _cleanNote(note);
    if (cleanedNote != null && cleanedNote.isNotEmpty) {
      buffer.writeln(cleanedNote);
      buffer.writeln('');
    }

    buffer.writeln('--- נוצר אוטומטית על ידי שבצק ---');
    return buffer.toString();
  }

  /// Clean the note by removing the automatic rejection message
  static String? _cleanNote(String? note) {
    if (note == null || note.isEmpty) return null;

    const rejectionMessage = '(מגבלה זו נדחתה באופן אוטומטי בגלל שאחד מהמנהלים מחק את המגבלה מגוגל קלנדר)';

    // Remove the rejection message and any preceding newlines
    final cleaned = note
        .replaceAll('\n\n$rejectionMessage', '')
        .replaceAll(rejectionMessage, '')
        .trim();

    return cleaned.isEmpty ? null : cleaned;
  }
}
