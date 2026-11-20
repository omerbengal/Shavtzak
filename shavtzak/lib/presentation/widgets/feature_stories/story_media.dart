import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/debug/logger.dart';
import '../../../core/utils/feature_stories.dart';

/// What a story's media tells the viewer: it is showing and how long it
/// lasts ([onReady], an image: [featureStoryImageDuration], a video: its
/// length), or it cannot be shown ([onError] with why; the viewer skips it).
class StoryMediaCallbacks {
  final void Function(Duration length) onReady;
  final void Function(String reason) onError;

  /// True while the viewer holds the story (a long press, the end screen).
  final ValueListenable<bool> paused;

  const StoryMediaCallbacks({required this.onReady, required this.onError, required this.paused});
}

typedef StoryMediaBuilder = Widget Function(
  BuildContext context,
  FeatureStory story,
  StoryMediaCallbacks callbacks,
);

/// The real media: [Image.network] or a muted, inline [VideoPlayer].
Widget defaultStoryMedia(BuildContext context, FeatureStory story, StoryMediaCallbacks callbacks) {
  final uri = featureStoryUri(story.file, Uri.base);
  return switch (story.type) {
    FeatureStoryType.image => _ImageStory(uri: uri, callbacks: callbacks),
    FeatureStoryType.video => _VideoStory(uri: uri, callbacks: callbacks),
  };
}

class _ImageStory extends StatefulWidget {
  final Uri uri;
  final StoryMediaCallbacks callbacks;

  const _ImageStory({required this.uri, required this.callbacks});

  @override
  State<_ImageStory> createState() => _ImageStoryState();
}

class _ImageStoryState extends State<_ImageStory> {
  bool _reported = false;

  void _report(bool ok) {
    if (_reported) return;
    _reported = true;
    // Never during build: the viewer rebuilds on it.
    scheduleMicrotask(() => ok
        ? widget.callbacks.onReady(featureStoryImageDuration)
        : widget.callbacks.onError('image did not load'));
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.uri.toString(),
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null) _report(true);
        return child;
      },
      errorBuilder: (context, error, stackTrace) {
        Logger.warning('stories:imageFailed', {'file': widget.uri.path});
        _report(false);
        return const SizedBox.shrink();
      },
    );
  }
}

class _VideoStory extends StatefulWidget {
  final Uri uri;
  final StoryMediaCallbacks callbacks;

  const _VideoStory({required this.uri, required this.callbacks});

  @override
  State<_VideoStory> createState() => _VideoStoryState();
}

class _VideoStoryState extends State<_VideoStory> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _started = false;
  bool _failed = false;

  /// The browser refused to start it by itself (an iPhone in low-power
  /// mode refuses even a muted video): a tap on the play button starts it.
  bool _needsTap = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      widget.uri,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller.addListener(_onValue);
    widget.callbacks.paused.addListener(_onPaused);
    _start();
  }

  Future<void> _start() async {
    try {
      await _controller.initialize();
      await _controller.setVolume(0);
      if (!mounted) return;
      setState(() => _ready = true);
      if (!widget.callbacks.paused.value) await _controller.play();
    } catch (error) {
      _fail('init', error);
    }
  }

  void _onValue() {
    final value = _controller.value;
    if (value.hasError) {
      final description = value.errorDescription ?? '';
      if (_ready && !_started && description.contains('NotAllowed')) {
        if (!_needsTap && mounted) setState(() => _needsTap = true);
        return;
      }
      _fail('play', description);
      return;
    }
    if (!_started && value.isPlaying) {
      _started = true;
      if (_needsTap && mounted) setState(() => _needsTap = false);
      widget.callbacks.onReady(value.duration);
    }
  }

  void _fail(String stage, Object error) {
    if (_failed || _started) return;
    _failed = true;
    Logger.warning('stories:videoFailed', {'stage': stage, 'error': error.toString()});
    widget.callbacks.onError('$stage: $error');
  }

  void _onPaused() {
    if (!_ready) return;
    if (widget.callbacks.paused.value) {
      _controller.pause();
    } else if (!_controller.value.isCompleted) {
      _controller.play();
    }
  }

  @override
  void dispose() {
    widget.callbacks.paused.removeListener(_onPaused);
    _controller.removeListener(_onValue);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)),
        if (_needsTap)
          IconButton(
            key: const Key('story-play'),
            iconSize: 72,
            color: Colors.white,
            icon: const Icon(Icons.play_circle_fill_rounded),
            onPressed: () {
              Logger.action('tap:storyPlay');
              _controller.play();
            },
          ),
      ],
    );
  }
}
