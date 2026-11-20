import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// web/index.html sends an address with no "#" route to "#/whoami" before
/// Flutter starts. It must keep the query: "?stories=" (feature stories) and
/// "?refreshdemo" ride on it (Omer, msg 5395: the preview link
/// ".../?stories=stories/tagging.mp4" lost its query here and showed nothing).
void main() {
  test('the hash-route redirect keeps the address query', () {
    final html = File('web/index.html').readAsStringSync();
    final redirect = RegExp(r'window\.location\.replace\(([^;]*)\);').firstMatch(html);
    expect(redirect, isNotNull);
    expect(redirect!.group(1), contains('window.location.search'));
    final search = redirect.group(1)!.indexOf('window.location.search');
    expect(search, lessThan(redirect.group(1)!.indexOf("'#/whoami'")),
        reason: 'the query goes before the "#"');
  });
}
