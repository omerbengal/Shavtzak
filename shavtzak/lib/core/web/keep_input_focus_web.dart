import 'dart:js_interop';
import 'dart:ui' show Offset, Rect;

import 'package:web/web.dart' as web;

/// The areas that must not take the focus, by owner.
final Map<Object, Rect> _areas = {};
bool _listening = false;

void keepInputFocusIn(Object owner, Rect? area) {
  if (area == null) {
    _areas.remove(owner);
    return;
  }
  _areas[owner] = area;
  if (_listening) return;
  _listening = true;
  try {
    final options = web.AddEventListenerOptions(capture: true, passive: false);
    // `touchstart` and `mousedown` are what move the focus (the second also
    // after a touch, as its compatibility event). Flutter reads the pointer
    // events, which come before them, so taps and scrolling still work.
    web.document.addEventListener('touchstart', _onDown.toJS, options);
    web.document.addEventListener('mousedown', _onDown.toJS, options);
  } catch (_) {
    // Only a comfort; never break the page.
  }
}

void _onDown(web.Event event) {
  if (_areas.isEmpty) return;
  try {
    final Offset at;
    if (event.type == 'touchstart') {
      final touches = (event as web.TouchEvent).touches;
      if (touches.length == 0) return;
      final touch = touches.item(0)!;
      at = Offset(touch.clientX.toDouble(), touch.clientY.toDouble());
    } else {
      final mouse = event as web.MouseEvent;
      at = Offset(mouse.clientX.toDouble(), mouse.clientY.toDouble());
    }
    if (!_areas.values.any((area) => area.contains(at))) return;
    // Only while one of Flutter's inputs holds the focus.
    final active = web.document.activeElement;
    if (active == null) return;
    final tag = active.tagName.toUpperCase();
    if (tag != 'INPUT' && tag != 'TEXTAREA') return;
    event.preventDefault();
  } catch (_) {
    // Never break a tap.
  }
}
