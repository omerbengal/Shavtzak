// iPhone/iPad: open the keyboard on the FIRST tap of a text field.
//
// Flutter focuses its hidden <input> from code while it handles the tap
// (~35 ms in, after `pointerup`). iOS did not open the keyboard for that, so
// the field looked focused with no keyboard, and only a second tap (landing
// on the now-placed input) opened it. Happens with a bare Flutter app too, on
// regular and beta iOS, Flutter 3.41 and 3.47 (measured 2026-11-08).
//
// So: when Flutter's input took focus during this tap, focus a throwaway
// input inside the same flutter-view and give the focus straight back,
// inside `touchend` and again inside `click`. On the iPhone the keyboard
// came up only after the `click` one; a `touchend` re-focus alone was not
// enough. Keeping the throwaway inside the view means Flutter does not see
// the view losing focus, so it keeps its text connection. A tap in a field
// that was already focused (moving the cursor) is left alone.
//
// Add `?kbdlog` to the address to see the tap's events on screen, with every
// move of the input's caret and every touch the browser takes over.
(function () {
  var isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  // The app rewrites the address while it starts, so the flag is kept for
  // the tab once seen.
  var LOG = false;
  try {
    if (location.href.indexOf('kbdlog') >= 0) sessionStorage.setItem('kbdlog', '1');
    LOG = sessionStorage.getItem('kbdlog') === '1';
  } catch (_) {
    LOG = location.href.indexOf('kbdlog') >= 0;
  }
  if (!isIOS && !LOG) return;

  // index.html gives Flutter's hidden input the app's font, so that the
  // iPhone's own selection highlight lands on the text. Start loading it
  // once the page's styles are in, so the first selection already has it.
  if (isIOS) {
    document.addEventListener('DOMContentLoaded', function () {
      try {
        if (document.fonts && document.fonts.load) document.fonts.load('16px Rubik');
      } catch (_) {
        // Only a head start; the input loads the font itself when it needs it.
      }
    });
  }

  var DUMMY_ID = 'ios-keyboard-fix-dummy';
  var tap = null;

  // ---- optional on-screen log ----
  var box = null;
  var lines = [];
  var t0 = performance.now();
  function log(text) {
    if (!LOG) return;
    if (!box && document.body) {
      box = document.createElement('div');
      box.style.cssText =
        'position:fixed;left:0;right:0;bottom:0;max-height:45%;overflow:hidden;' +
        'background:rgba(0,0,0,.8);color:#0f0;font:11px/1.35 monospace;' +
        'padding:6px;z-index:2147483647;pointer-events:none;direction:ltr;' +
        'white-space:pre';
      document.body.appendChild(box);
    }
    lines.push(Math.round(performance.now() - t0) + 'ms ' + text);
    while (lines.length > 22) lines.shift();
    if (box) box.textContent = 'kbd fix v6 ios=' + isIOS + '\n' + lines.join('\n');
  }
  function describe(el) {
    if (!el) return 'none';
    return el.tagName + (el.closest && el.closest('flutter-view') ? '(view)' : '');
  }

  function flutterInput(el) {
    if (!el || el.id === DUMMY_ID) return null;
    if (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA') return null;
    return el.closest && el.closest('flutter-view') ? el : null;
  }

  function dummyIn(view) {
    var dummy = document.getElementById(DUMMY_ID);
    if (!dummy) {
      dummy = document.createElement('input');
      dummy.id = DUMMY_ID;
      dummy.tabIndex = -1;
      dummy.setAttribute('aria-hidden', 'true');
      dummy.style.cssText =
        'position:absolute;top:0;left:0;width:1px;height:1px;opacity:0;' +
        'font-size:16px;border:0;padding:0;margin:0;pointer-events:none';
    }
    if (dummy.parentNode !== view) view.appendChild(dummy);
    return dummy;
  }

  function nudge(where) {
    log(where + ' active=' + describe(document.activeElement) +
      (tap && tap.focused ? ' tapFocus=' + describe(tap.focused) : ''));
    if (!isIOS || !tap || tap.done || !tap.focused) return;
    var input = tap.focused;
    if (document.activeElement !== input) return;
    var view = input.closest('flutter-view');
    if (!view) return;
    // Both: on the iPhone the keyboard came up only after the `click`
    // re-focus (2026-11-08 log); `touchend` alone was not enough.
    if (where === 'click') tap.done = true;
    try {
      dummyIn(view).focus({preventScroll: true});
      input.focus({preventScroll: true});
      log('  fix: refocused ' + describe(document.activeElement));
    } catch (_) {
      // Never let the fix break a tap.
    }
  }

  if (LOG) {
    if (document.body) log('loaded');
    else document.addEventListener('DOMContentLoaded', function () { log('loaded'); });
    // For caret problems: every move of the hidden input's caret, and
    // whether the browser takes a touch away from Flutter mid-drag.
    document.addEventListener('selectionchange', function () {
      var input = flutterInput(document.activeElement);
      log('selectionchange' + (input ? ' ' + input.selectionStart + '..' + input.selectionEnd : ''));
    }, true);
    ['pointercancel', 'touchcancel'].forEach(function (type) {
      document.addEventListener(type, function (event) {
        log(type + ' on ' + describe(event.target));
      }, true);
    });
  }

  document.addEventListener('touchstart', function () {
    t0 = performance.now();
    lines.length = 0;
    tap = {
      before: flutterInput(document.activeElement),
      focused: null,
      done: false,
    };
    log('touchstart active=' + describe(document.activeElement));
  }, true);

  document.addEventListener('pointerup', function () {
    log('pointerup active=' + describe(document.activeElement));
  }, true);

  document.addEventListener('focusin', function (event) {
    if (event.target && event.target.id === DUMMY_ID) return;
    log('focusin ' + describe(event.target));
    var input = flutterInput(event.target);
    // A field that already had focus before the tap is left alone.
    if (input && tap && !tap.done && input !== tap.before) tap.focused = input;
  }, true);

  document.addEventListener('touchend', function () { nudge('touchend'); }, true);
  document.addEventListener('click', function () { nudge('click'); }, true);

  if (LOG && window.visualViewport) {
    var last = visualViewport.height;
    visualViewport.addEventListener('resize', function () {
      var now = visualViewport.height;
      if (now < last - 100) log('KEYBOARD UP');
      else if (now > last + 100) log('keyboard down');
      last = now;
    });
  }
})();
