// iPhone/iPad: no zoom-in when a text field takes focus.
//
// Safari zooms the page in when an <input>, <textarea> or contenteditable
// whose font is under 16 px takes focus, unless the viewport forbids zooming
// past 1 (`maximum-scale=1`). index.html says so, but Flutter's engine
// replaces that tag while it starts with its own (`maximum-scale=5.0`, see
// full_page_embedding_strategy.dart), so the app's fields (real browser
// fields since the native-fields change) zoomed the page in, and Flutter's
// `touch-action: none` meant no pinch could bring it back.
//
// So: whenever a viewport tag appears or changes, cap it at maximum-scale=1,
// keeping everything else it says (`viewport-fit` included). On iOS 10+ the
// cap stops only the automatic zoom; Safari still lets the user pinch-zoom
// where the page allows it. iOS only: Android and desktop keep Flutter's tag.
//
// If the page is ever zoomed in anyway, it is brought back to 1 when the
// field loses focus.
(function () {
  var isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (!isIOS) return;

  function capped(content) {
    var parts = (content || '').split(',')
      .map(function (p) { return p.trim(); })
      .filter(function (p) {
        return p && !/^maximum-scale\s*=/i.test(p);
      });
    parts.push('maximum-scale=1.0');
    return parts.join(', ');
  }

  function capAll() {
    var metas = document.querySelectorAll('meta[name="viewport"]');
    for (var i = 0; i < metas.length; i++) {
      var current = metas[i].getAttribute('content') || '';
      var wanted = capped(current);
      if (current !== wanted) metas[i].setAttribute('content', wanted);
    }
  }

  capAll();
  new MutationObserver(capAll).observe(document.head || document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['content'],
  });

  // Safety net: zoomed in after all (an older iOS, an edge case) = zoom back
  // out once the field is left. Changing the tag makes Safari re-apply it.
  document.addEventListener('focusout', function () {
    var vv = window.visualViewport;
    if (!vv || vv.scale <= 1.01) return;
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) return;
    var content = meta.getAttribute('content') || '';
    meta.setAttribute('content', content.replace(/maximum-scale=1\.0/, 'maximum-scale=1'));
    // The observer turns it back into maximum-scale=1.0 right after.
  }, true);
})();
