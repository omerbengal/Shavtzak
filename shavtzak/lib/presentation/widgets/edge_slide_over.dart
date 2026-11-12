import 'package:flutter/material.dart';

/// A full-screen panel that slides in over [child] from the screen's right
/// edge (physical right, also under RTL).
///
/// Phone ([wide] false): a finger dragged leftwards from a thin strip at the
/// right edge pulls the panel along; let go past [openThreshold] of the width
/// and it slides in the rest of the way, else back out. Once open, a
/// horizontal drag anywhere on it to the right of at least [closeThreshold]
/// of the width slides it back out; less snaps it back.
///
/// Wide: no edge swipe. A small "<" box on the right edge, vertically
/// centred, opens it with a tap.
///
/// Either way [panelBuilder] gets a `close` callback (the panel's ✕). The
/// panel is only built while it is at least partly on screen.
class EdgeSlideOver extends StatefulWidget {
  const EdgeSlideOver({
    super.key,
    required this.child,
    required this.panelBuilder,
    required this.wide,
    this.handleTooltip,
  });

  final Widget child;
  final Widget Function(BuildContext context, VoidCallback close) panelBuilder;
  final bool wide;
  final String? handleTooltip;

  static const double openThreshold = 0.15;
  static const double closeThreshold = 0.15;
  static const double edgeStripWidth = 24;
  static const Duration slideDuration = Duration(milliseconds: 220);

  @override
  State<EdgeSlideOver> createState() => _EdgeSlideOverState();
}

class _EdgeSlideOverState extends State<EdgeSlideOver>
    with SingleTickerProviderStateMixin {
  /// 0 = closed (off the right edge), 1 = covering the screen.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: EdgeSlideOver.slideDuration,
  );

  /// Where the panel was when the current drag on the open panel started.
  double _closeDragStart = 1;

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _show() => _open.animateTo(1, curve: Curves.easeOutCubic);
  void _hide() => _open.animateTo(0, curve: Curves.easeOutCubic);

  void _dragBy(double dx, double width) {
    if (width <= 0) return;
    // Leftwards (negative dx) opens.
    _open.value = (_open.value - dx / width).clamp(0.0, 1.0);
  }

  void _endOpenDrag() {
    if (_open.value >= EdgeSlideOver.openThreshold) {
      _show();
    } else {
      _hide();
    }
  }

  void _endCloseDrag() {
    if (_closeDragStart - _open.value >= EdgeSlideOver.closeThreshold) {
      _hide();
    } else {
      _show();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: [
            Positioned.fill(child: widget.child),
            if (!widget.wide)
              Positioned(
                key: const Key('slide-over-edge'),
                top: 0,
                bottom: 0,
                right: 0,
                width: EdgeSlideOver.edgeStripWidth,
                child: GestureDetector(
                  // Lets taps through to what lies under the strip.
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (d) => _dragBy(d.delta.dx, width),
                  onHorizontalDragEnd: (_) => _endOpenDrag(),
                  onHorizontalDragCancel: _endOpenDrag,
                ),
              )
            else
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(child: _handle()),
              ),
            AnimatedBuilder(
              animation: _open,
              builder: (context, _) {
                if (_open.value == 0) return const SizedBox.shrink();
                return Positioned.fill(
                  child: Transform.translate(
                    offset: Offset((1 - _open.value) * width, 0),
                    child: GestureDetector(
                      key: const Key('slide-over-panel'),
                      onHorizontalDragStart: widget.wide
                          ? null
                          : (_) => _closeDragStart = _open.value,
                      onHorizontalDragUpdate: widget.wide
                          ? null
                          : (d) => _dragBy(d.delta.dx, width),
                      onHorizontalDragEnd: widget.wide
                          ? null
                          : (_) => _endCloseDrag(),
                      onHorizontalDragCancel: widget.wide
                          ? null
                          : _endCloseDrag,
                      child: Material(
                        elevation: 12,
                        child: widget.panelBuilder(context, _hide),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _handle() {
    final box = Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
      child: InkWell(
        key: const Key('slide-over-handle'),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
        onTap: _show,
        // chevron_left mirrors under RTL; the box must point left on screen.
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 28,
            height: 56,
            child: Icon(Icons.chevron_left, size: 24),
          ),
        ),
      ),
    );
    final tooltip = widget.handleTooltip;
    return tooltip == null ? box : Tooltip(message: tooltip, child: box);
  }
}
