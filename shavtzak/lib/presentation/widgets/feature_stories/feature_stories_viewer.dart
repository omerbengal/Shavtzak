import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/debug/logger.dart';
import '../../../core/utils/feature_stories.dart';
import 'story_media.dart';

/// The stories screen (Omer, 20/11/2026), exactly like Instagram / WhatsApp
/// stories: a bar per story at the top (the first on the right, the current
/// one fills while it plays), each story moves on by itself, a tap on the
/// left half = next and on the right half = previous (Hebrew Instagram), a
/// long press holds it, ✕ closes. After the last one: "צפייה מחדש" (from
/// the first) and "סגירה". A story that cannot load is skipped.
class FeatureStoriesViewer extends StatefulWidget {
  final List<FeatureStory> stories;
  final VoidCallback onClose;

  /// Tests swap the real image / video for a stand-in.
  final StoryMediaBuilder mediaBuilder;

  const FeatureStoriesViewer({
    super.key,
    required this.stories,
    required this.onClose,
    this.mediaBuilder = defaultStoryMedia,
  });

  @override
  State<FeatureStoriesViewer> createState() => _FeatureStoriesViewerState();
}

class _FeatureStoriesViewerState extends State<FeatureStoriesViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  final ValueNotifier<bool> _paused = ValueNotifier(false);
  Timer? _loadTimeout;
  int _index = 0;
  bool _ended = false;

  /// Bumped on every move, so a late answer from a story already left
  /// (its media, its timeout) is ignored, and replaying remounts the media.
  int _generation = 0;

  /// The key of the media on screen: a new one only when a story is
  /// entered, so the end screen keeps the last story's frame.
  int _mediaEpoch = 0;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    Logger.action('open:featureStories', {'count': widget.stories.length});
    _enter(0);
  }

  void _enter(int index) {
    _loadTimeout?.cancel();
    _progress.stop();
    _progress.value = 0;
    _generation++;
    if (index >= widget.stories.length) {
      setState(() => _ended = true);
      _paused.value = true;
      return;
    }
    setState(() {
      _index = index;
      _ended = false;
      _mediaEpoch++;
    });
    _paused.value = false;
    final generation = _generation;
    _loadTimeout = Timer(featureStoryLoadTimeout, () {
      if (generation == _generation) _skip(generation);
    });
  }

  void _onReady(int generation, Duration length) {
    if (generation != _generation || !mounted) return;
    _loadTimeout?.cancel();
    _progress.duration = length > Duration.zero ? length : featureStoryImageDuration;
    if (!_paused.value) _progress.forward(from: 0);
  }

  void _skip(int generation) {
    if (generation != _generation || !mounted) return;
    Logger.warning('stories:skipped', {'file': widget.stories[_index].file});
    _next();
  }

  void _next() => _enter(_index + 1);

  void _previous() => _enter(_index > 0 ? _index - 1 : 0);

  void _hold(bool hold) {
    if (_ended) return;
    _paused.value = hold;
    if (hold) {
      _progress.stop();
    } else if (_progress.duration != null && _progress.value > 0) {
      _progress.forward();
    }
  }

  void _close() {
    Logger.action('tap:featureStoriesClose', {'ended': _ended});
    widget.onClose();
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    _progress.dispose();
    _paused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    final story = widget.stories[_index];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.black,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // A portrait story: on a wide screen it stays phone-shaped.
              final width = constraints.maxWidth
                  .clamp(0.0, constraints.maxHeight * 9 / 16 + 1)
                  .toDouble();
              return Center(
                child: SizedBox(
                  width: width,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: KeyedSubtree(
                          key: ValueKey('story-media-$_mediaEpoch'),
                          child: widget.mediaBuilder(
                            context,
                            story,
                            StoryMediaCallbacks(
                              onReady: (length) => _onReady(generation, length),
                              onError: () => _skip(generation),
                              paused: _paused,
                            ),
                          ),
                        ),
                      ),
                      if (!_ended) _tapZones(width),
                      // A shade under the bars and ✕, as on Instagram: a
                      // light story would hide them.
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 96,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x73000000), Color(0x00000000)],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _bars(),
                      PositionedDirectional(
                        top: 18,
                        end: 4,
                        child: IconButton(
                          key: const Key('stories-close'),
                          color: Colors.white,
                          icon: const Icon(Icons.close_rounded, size: 28),
                          onPressed: _close,
                        ),
                      ),
                      if (_ended) _endScreen(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _tapZones(double width) {
    return GestureDetector(
      key: const Key('stories-tap-zone'),
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        if (details.localPosition.dx < width / 2) {
          Logger.action('tap:storyNext');
          _next();
        } else {
          Logger.action('tap:storyPrevious');
          _previous();
        }
      },
      onLongPressStart: (_) => _hold(true),
      onLongPressEnd: (_) => _hold(false),
    );
  }

  Widget _bars() {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, _) => Row(
          children: [
            for (var i = 0; i < widget.stories.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    key: Key('story-bar-$i'),
                    minHeight: 3,
                    value: _ended || i < _index
                        ? 1
                        : i == _index
                            ? _progress.value
                            : 0,
                    backgroundColor: Colors.white.withValues(alpha: 0.35),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _endScreen() {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                key: const Key('stories-replay'),
                onPressed: () {
                  Logger.action('tap:featureStoriesReplay');
                  _enter(0);
                },
                icon: const Icon(Icons.replay_rounded),
                label: const Text('צפייה מחדש'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('stories-end-close'),
                onPressed: _close,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('סגירה'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
