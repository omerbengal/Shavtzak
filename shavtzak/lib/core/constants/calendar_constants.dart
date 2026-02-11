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
  // Unavailability constraints - Graphite tone
  static const String unavailability = '8'; // Graphite

  // Availability constraints - Green tone
  static const String availability = '10'; // Green (Basil)

  // App events - Peacock tone
  static const String appEvent = '7'; // Peacock (טווס)

  // Test mode - Yellow tone (used for all test events)
  static const String testMode = '5'; // Yellow (Banana)
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
  /// Prefix for test mode events
  static const String testModePrefix = 'שבצק טסטינג: ';

  /// Title for unavailability constraint events
  /// Format: "[Name] - מגבלה" (or "שבצק טסטינג: [Name] - מגבלה" in test mode)
  static String unavailability(String memberName, {bool isTestMode = false}) {
    final title = '$memberName - מגבלה';
    return isTestMode ? '$testModePrefix$title' : title;
  }

  /// Title for availability constraint events
  /// Format: "[Name] - זמינות" (or "שבצק טסטינג: [Name] - זמינות" in test mode)
  static String availability(String memberName, {bool isTestMode = false}) {
    final title = '$memberName - זמינות';
    return isTestMode ? '$testModePrefix$title' : title;
  }

  /// Title for event assembly calendar event
  /// Format: "[Event Name] - התייצבות והכנות" (or "שבצק טסטינג: [Event Name] - התייצבות והכנות" in test mode)
  static String eventAssembly(String eventName, {bool isTestMode = false}) {
    final title = '$eventName - התייצבות והכנות';
    return isTestMode ? '$testModePrefix$title' : title;
  }

  /// Title for event main calendar event
  /// Format: "[Event Name]" (or "שבצק טסטינג: [Event Name]" in test mode)
  static String eventMain(String eventName, {bool isTestMode = false}) {
    return isTestMode ? '$testModePrefix$eventName' : eventName;
  }
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

    // Remove the rejection message and any preceding newlines
    final cleaned = note
        .replaceAll('\n\n${CalendarAutoRejection.message}', '')
        .replaceAll(CalendarAutoRejection.message, '')
        .trim();

    return cleaned.isEmpty ? null : cleaned;
  }
}

/// Helper class for auto-rejected constraints messaging
/// A constraint is considered auto-rejected when an admin deletes it from Google Calendar
class CalendarAutoRejection {
  /// The message to display when a constraint was auto-rejected from Google Calendar
  static const String message = '(מגבלה זו נדחתה באופן אוטומטי בגלל שאחד מהמנהלים מחק את המגבלה מגוגל קלנדר)';
}
