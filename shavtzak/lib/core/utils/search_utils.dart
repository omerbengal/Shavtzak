// Utilities for search functionality across the app

/// Normalize text to only Hebrew letters, English letters, numbers, and spaces for search.
/// This handles special characters like apostrophes, quotes, geresh, etc.
///
/// Examples:
/// - "מג'יק קאס" → "מגיק קאס"
/// - "event #123" → "event 123"
/// - "test@example.com" → "testexamplecom"
String normalizeForSearch(String text) {
  return text.runes
      .where((rune) {
        // Keep Hebrew letters (א-ת), English letters (a-z, A-Z), numbers (0-9), and spaces
        return (rune >= 0x05D0 && rune <= 0x05EA) || // Hebrew letters
               (rune >= 0x0041 && rune <= 0x005A) || // A-Z
               (rune >= 0x0061 && rune <= 0x007A) || // a-z
               (rune >= 0x0030 && rune <= 0x0039) || // 0-9
               rune == 0x0020; // space
      })
      .map((rune) => String.fromCharCode(rune))
      .join();
}
