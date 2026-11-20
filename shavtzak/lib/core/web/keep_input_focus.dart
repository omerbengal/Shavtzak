import 'dart:ui' show Rect;

import 'keep_input_focus_stub.dart' if (dart.library.js_interop) 'keep_input_focus_web.dart'
    as impl;

/// Keeps the browser's text input (and with it the phone's keyboard) focused
/// while the finger or mouse goes down inside [area] (in the page's CSS
/// pixels, which are Flutter's logical pixels), e.g. a suggestions list over
/// a field (Omer, 20/11/2026: picking a member from the "@" list closed the
/// keyboard mid-sentence). On a phone's browser the touch moved the focus off
/// Flutter's hidden input, and the keyboard went down with it. Null = stop.
/// Does nothing off the web.
void keepInputFocusIn(Object owner, Rect? area) => impl.keepInputFocusIn(owner, area);
