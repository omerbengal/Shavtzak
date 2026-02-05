/// Static class to persist filter states across page navigation
///
/// This allows filter selections to be preserved when users navigate
/// away from a screen and return to it later.
class FilterPersistence {
  /// Selected filter index for Team Members screen
  /// 0 = All (סה״כ), 1 = Active (פעילים), 2 = Inactive (לא פעילים)
  static int teamFilterIndex = 0; // Default to all

  /// Selected filter index for Events screen
  /// 0 = All (סה״כ), 1 = Future (עתידיים), 2 = Past (עברו)
  static int eventFilterIndex = 1; // Default to future (עתידיים)

  /// Selected filter index for Assignments screen
  /// 0 = All (סה״כ), 1 = Filled (משובצים), 2 = Unfilled (לא משובצים)
  static int assignmentFilterIndex = 0; // Default to all

  /// Whether to show past events in Assignments screen
  static bool showPastEvents = false; // Default to false (hide past events)

  /// Selected category IDs for Events screen
  static Set<String> selectedEventCategoryIds = {};

  /// Selected category IDs for Assignments screen
  static Set<String> selectedAssignmentCategoryIds = {};
}
