import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

/// Safari's own flag for a page opened from the home screen.
@JS('navigator.standalone')
external JSBoolean? get _standalone;

/// Safari on iOS 26 floats its expanded bottom toolbar (address field plus
/// the back / share / tabs row, never collapsed here, since a Flutter page
/// does not scroll the document) about 125 px above the screen's edge.
const double _floatingToolbar = 116;

/// Below this many px between the page's bottom and the screen height, the
/// page reaches down to the screen's edge (only the status bar is above it),
/// i.e. the toolbar floats over it. Older Safari takes its bars out of the
/// page: 150 px and more.
const double _pageReachesEdge = 120;

double browserBottomOverlap() {
  try {
    final window = web.window;
    if (!window.navigator.userAgent.contains('iPhone')) return 0;
    if ((_standalone?.toDart ?? false) ||
        window.matchMedia('(display-mode: standalone)').matches) {
      return 0;
    }
    final width = window.innerWidth.toDouble();
    final height = window.innerHeight.toDouble();
    if (width > height) return 0; // Landscape: no bottom toolbar there.
    final screen = window.screen;
    final screenHeight = math.max(screen.width, screen.height).toDouble();
    if (screenHeight - height >= _pageReachesEdge) return 0;
    return _floatingToolbar;
  } catch (_) {
    return 0;
  }
}
