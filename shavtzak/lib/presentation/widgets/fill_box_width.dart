import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays [child] out at the width that lets it fill a box of [available]
/// size once scaled down to fit (by an ancestor `FittedBox`), and reports
/// the child's size at that width.
///
/// Starts at [minWidth] (the widest drawing wanted: smaller layout width =
/// bigger once scaled). When the child is then too tall for [available], a
/// wider layout makes it shorter (lines wrap less, columns widen), so the
/// width is raised until its shape matches [available]'s: the scaled result
/// then touches both the sides and the bottom instead of leaving empty
/// strips at the sides.
class FillBoxWidth extends SingleChildRenderObjectWidget {
  const FillBoxWidth({
    super.key,
    required this.available,
    required this.minWidth,
    super.child,
  });

  final Size available;
  final double minWidth;

  @override
  RenderFillBoxWidth createRenderObject(BuildContext context) =>
      RenderFillBoxWidth(available: available, minWidth: minWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFillBoxWidth renderObject,
  ) {
    renderObject
      ..available = available
      ..minWidth = minWidth;
  }
}

class RenderFillBoxWidth extends RenderProxyBox {
  RenderFillBoxWidth({required Size available, required double minWidth})
      : _available = available,
        _minWidth = minWidth;

  Size _available;
  set available(Size value) {
    if (value == _available) return;
    _available = value;
    markNeedsLayout();
  }

  double _minWidth;
  set minWidth(double value) {
    if (value == _minWidth) return;
    _minWidth = value;
    markNeedsLayout();
  }

  /// The layout width last chosen (for tests).
  double chosenWidth = 0;

  /// How much wider than [_minWidth] the search may go.
  static const double maxStretch = 4;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final width = _solveWidth(child);
    chosenWidth = width;
    child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    size = child.size;
  }

  double _solveWidth(RenderBox child) {
    final availW = _available.width;
    final availH = _available.height;
    if (availW <= 0 || availH <= 0 || _minWidth <= 0) return _minWidth;
    // Too tall at width w: height/width above the box's shape.
    bool tooTall(double w) =>
        child.getMaxIntrinsicHeight(w) / w > availH / availW;
    var low = _minWidth;
    if (!tooTall(low)) return low;
    var high = _minWidth * maxStretch;
    if (tooTall(high)) return high;
    for (var i = 0; i < 14; i++) {
      final mid = (low + high) / 2;
      if (tooTall(mid)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return math.max(high, _minWidth);
  }
}
