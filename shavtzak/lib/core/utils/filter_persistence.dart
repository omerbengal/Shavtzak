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
}
