import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/calendar_feed_links.dart';

void main() {
  group('CalendarFeedLinks', () {
    test('builds an https feed URL ending in .ics', () {
      final url = CalendarFeedLinks.httpsUrl('abc123', isTestMode: false);
      expect(url, endsWith('/calendar/feed/prod/abc123.ics'));
      expect(url, startsWith('https://'));
    });

    test('uses the test segment in test mode', () {
      final url = CalendarFeedLinks.httpsUrl('abc123', isTestMode: true);
      expect(url, contains('/calendar/feed/test/'));
    });

    test('webcal URL mirrors the https URL with the webcal scheme', () {
      final https = CalendarFeedLinks.httpsUrl('abc123', isTestMode: false);
      final webcal = CalendarFeedLinks.webcalUrl('abc123', isTestMode: false);
      expect(webcal, 'webcal://${https.substring('https://'.length)}');
    });

    test('WhatsApp URL targets the member and encodes the link', () {
      final url = CalendarFeedLinks.whatsappShareUrl(
        token: 'abc123',
        phoneNumber: '050-123-4567',
        isTestMode: false,
      );
      // Israeli local numbers must be normalised to international form and
      // stripped of separators, or wa.me rejects them.
      expect(url, startsWith('https://wa.me/972501234567?text='));
      expect(url, contains(Uri.encodeComponent('.ics')));
    });

    test('WhatsApp URL omits the recipient when there is no phone number', () {
      final url = CalendarFeedLinks.whatsappShareUrl(
        token: 'abc123',
        phoneNumber: null,
        isTestMode: false,
      );
      expect(url, startsWith('https://wa.me/?text='));
    });
  });
}
