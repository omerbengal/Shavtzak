/// Builds the URLs used to share and subscribe to a member's personal
/// calendar feed. Pure string construction so the shapes stay testable.
class CalendarFeedLinks {
  const CalendarFeedLinks._();

  static const String _functionsBase =
      'https://us-central1-tsevet-shir-shavtzak.cloudfunctions.net/api';

  static String httpsUrl(String token, {required bool isTestMode}) {
    final segment = isTestMode ? 'test' : 'prod';
    return '$_functionsBase/calendar/feed/$segment/$token.ics';
  }

  /// The webcal scheme makes iOS and macOS open the Calendar subscribe sheet
  /// directly instead of downloading the file.
  static String webcalUrl(String token, {required bool isTestMode}) {
    final https = httpsUrl(token, isTestMode: isTestMode);
    return 'webcal://${https.substring('https://'.length)}';
  }

  static String whatsappShareUrl({
    required String token,
    required String? phoneNumber,
    required bool isTestMode,
  }) {
    final link = httpsUrl(token, isTestMode: isTestMode);
    final message = 'הנה קישור אישי ליומן המשמרות שלך בשבצק:\n$link';
    final recipient = _toInternational(phoneNumber);
    return 'https://wa.me/$recipient?text=${Uri.encodeComponent(message)}';
  }

  /// '050-123-4567' -> '972501234567'. Returns an empty string when there is
  /// no usable number, which makes wa.me open without a preselected chat.
  static String _toInternational(String? phoneNumber) {
    if (phoneNumber == null) return '';
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('972')) return digits;
    if (digits.startsWith('0')) return '972${digits.substring(1)}';
    return digits;
  }
}
