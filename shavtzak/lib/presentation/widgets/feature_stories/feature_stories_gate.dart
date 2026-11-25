import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/debug/logger.dart';
import '../../../core/services/app_version_service.dart';
import '../../../core/utils/feature_stories.dart';
import '../../../domain/entities/team_member.dart';
import 'feature_stories_viewer.dart';
import 'story_media.dart';

/// Where the gate gets the stories list and the "seen" marks.
/// Default: [AppVersionService]; tests pass their own.
abstract class FeatureStoriesSource implements Listenable {
  /// `utilities/information` has been read since sign-in.
  bool get ready;
  List<FeatureStory> get stories;

  /// Stories may open now (not while the browser waits for a refresh).
  bool get mayOpen;

  /// The story files this browser already opened; null = unknown (none open).
  Future<Set<String>?> seenFiles();

  /// Called with the stories' files as the screen opens (not on a
  /// `?stories=` link).
  Future<void> markSeen(Iterable<String> files);
}

class _VersionServiceSource implements FeatureStoriesSource {
  final AppVersionService service;
  const _VersionServiceSource(this.service);

  @override
  bool get ready => service.hasRemoteData;
  @override
  List<FeatureStory> get stories => service.stories;
  @override
  bool get mayOpen => service.storiesMayOpen;
  @override
  Future<Set<String>?> seenFiles() => service.seenStoryFilesHere();
  @override
  Future<void> markSeen(Iterable<String> files) => service.markStoriesSeen(files);
  @override
  void addListener(VoidCallback listener) => service.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => service.removeListener(listener);
}

/// Opens [FeatureStoriesViewer] over the app once per app session, when the
/// standing stories list has stories for this member (`storiesFor`) that this
/// browser has not opened yet (`unseenStories`, Omer 26/11/2026: a story
/// added later shows alone), or when the address asks for some
/// (`?stories=`, previews; these never set the mark).
/// Sits in `MaterialApp.router`'s builder, above every screen.
class FeatureStoriesGate extends StatefulWidget {
  final Widget child;

  /// The member signed in now (null = nobody), and its changes.
  final TeamMember? Function() currentUser;
  final Stream<Object?> userChanges;

  final FeatureStoriesSource? source;

  /// `?stories=` of the address; null = none.
  final String? queryStories;
  final StoryMediaBuilder mediaBuilder;

  const FeatureStoriesGate({
    super.key,
    required this.child,
    required this.currentUser,
    required this.userChanges,
    this.source,
    this.queryStories,
    this.mediaBuilder = defaultStoryMedia,
  });

  static _FeatureStoriesGateState? _active;

  /// Completes when the stories screen is not in the way: decided not to
  /// show (or nothing decided within [decideWithin]), or closed. Other
  /// popups on start (the notifications one) wait for it.
  static Future<void> whenIdle({Duration decideWithin = const Duration(seconds: 8)}) async {
    final gate = _active;
    if (gate == null) return;
    if (!gate._decided.isCompleted) {
      await gate._decided.future.timeout(decideWithin, onTimeout: () {});
    }
    final closed = _active?._closed;
    if (closed != null) await closed.future;
  }

  @override
  State<FeatureStoriesGate> createState() => _FeatureStoriesGateState();
}

class _FeatureStoriesGateState extends State<FeatureStoriesGate> {
  late final FeatureStoriesSource _source;
  StreamSubscription<Object?>? _userSub;
  final Completer<void> _decided = Completer<void>();
  bool _deciding = false;
  List<FeatureStory>? _showing;
  bool _fromQuery = false;

  /// Pending while the stories are on screen.
  Completer<void>? _closed;

  @override
  void initState() {
    super.initState();
    FeatureStoriesGate._active = this;
    _source = widget.source ?? _VersionServiceSource(AppVersionService.instance);
    _source.addListener(_maybeDecide);
    _userSub = widget.userChanges.listen((_) => _maybeDecide());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeDecide());
  }

  Future<void> _maybeDecide() async {
    if (_deciding || _decided.isCompleted || !mounted) return;
    final user = widget.currentUser();
    if (user == null) return;
    final fromQuery = storiesFromQuery(widget.queryStories);
    if (fromQuery == null && !_source.ready) return;
    _deciding = true;
    List<FeatureStory> stories = const [];
    if (fromQuery != null) {
      stories = fromQuery;
    } else if (_source.mayOpen) {
      final seen = await _source.seenFiles();
      if (seen != null) {
        stories = unseenStories(
          storiesFor(_source.stories, isAdmin: user.isAdmin, isPermanent: user.isPermanent),
          seen,
        );
        // Marked as the screen opens, so a tab closed mid-story never loops.
        // Only the stories shown: one not for this member stays unmarked
        // (they may join its audience later).
        if (stories.isNotEmpty) await _source.markSeen([for (final s in stories) s.file]);
      }
    }
    if (!mounted) return;
    Logger.action('stories:decided', {'count': stories.length, 'query': fromQuery != null});
    if (stories.isNotEmpty) {
      _fromQuery = fromQuery != null;
      _closed = Completer<void>();
      setState(() => _showing = stories);
    }
    _decided.complete();
  }

  void _close() {
    setState(() => _showing = null);
    _closed?.complete();
    _closed = null;
  }

  @override
  void dispose() {
    if (FeatureStoriesGate._active == this) FeatureStoriesGate._active = null;
    _source.removeListener(_maybeDecide);
    _userSub?.cancel();
    if (!_decided.isCompleted) _decided.complete();
    if (_closed?.isCompleted == false) _closed!.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showing = _showing;
    return Stack(
      textDirection: TextDirection.rtl,
      children: [
        Positioned.fill(child: widget.child),
        if (showing != null)
          Positioned.fill(
            child: FeatureStoriesViewer(
              stories: showing,
              onClose: _close,
              mediaBuilder: widget.mediaBuilder,
              // A preview link (`?stories=`) shows why a story was skipped.
              showErrors: _fromQuery,
            ),
          ),
      ],
    );
  }
}
