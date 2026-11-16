import 'browser_insets_stub.dart' if (dart.library.js_interop) 'browser_insets_web.dart'
    as impl;

/// How much of the page's bottom a browser's own toolbar covers, in logical
/// pixels. Add it to the bottom padding of anything pinned to the bottom of
/// the screen (buttons, a bottom bar).
///
/// Safari on an iPhone (iOS 26 on) floats its bottom toolbar OVER the page
/// instead of above it: the page runs down to the screen's edge, so Flutter
/// lays out buttons that end up behind the glass (WebKit bug 297779). Older
/// Safari keeps its bars outside the page, and the installed app (PWA),
/// Android and desktop have no such bar: zero there, and on every non-web
/// platform.
double browserBottomOverlap() => impl.browserBottomOverlap();
