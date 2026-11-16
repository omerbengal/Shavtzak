import 'package:flutter/widgets.dart';

/// The app's binding: [WidgetsFlutterBinding] that keeps its animations when
/// the system asks to reduce motion.
///
/// On the web Flutter reads the browser's `prefers-reduced-motion` (the Mac's
/// "Reduce motion", Windows' "Animation effects" off) into
/// `disableAnimations`, and every AnimationController, the implicit ones
/// (AnimatedPositioned, AnimatedSwitcher, TweenAnimationBuilder...) too, then
/// runs 20 times faster: a 1 s Blitz throw took 50 ms, so on Omer's computer
/// Blitz and the tasks list's slide looked as if they had no animation at all
/// while his phone played them (16/11/2026). The app's motions are short and
/// part of how it reads, so they stay.
class AppBinding extends WidgetsFlutterBinding {
  /// Creates the binding once, before anything else asks for one.
  static WidgetsBinding ensureInitialized() {
    if (!_created) {
      _created = true;
      AppBinding();
    }
    return WidgetsBinding.instance;
  }

  static bool _created = false;

  @override
  bool get disableAnimations => false;
}
