import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/debug/logger.dart';
import '../../core/services/assignment_share_image_service.dart';

/// Generic full-screen share-preview dialog: renders a fixed-width card
/// inside a RepaintBoundary, captures it as a PNG, and offers share / copy
/// actions via AssignmentShareImageService.
///
/// Feature wrappers (assignments image, events calendar) supply the card
/// widget, titles, filename, and Logger action names.
class SharePreviewDialog extends StatefulWidget {
  final Widget card;
  final String appBarTitle;
  final String filename;
  final String shareTitle;
  final String shareText;
  final String closeLogAction;
  final String shareLogAction;
  final String copyLogAction;
  final bool autoStartShare;

  const SharePreviewDialog({
    super.key,
    required this.card,
    required this.appBarTitle,
    required this.filename,
    required this.shareTitle,
    required this.shareText,
    required this.closeLogAction,
    required this.shareLogAction,
    required this.copyLogAction,
    this.autoStartShare = true,
  });

  @override
  State<SharePreviewDialog> createState() => _SharePreviewDialogState();
}

class _SharePreviewDialogState extends State<SharePreviewDialog> {
  final GlobalKey _captureKey = GlobalKey();
  _ShareImageAction? _activeAction;
  String _message = 'אפשר לצלם את המסך הזה כתמונה אחת';

  bool get _isBusy => _activeAction != null;

  @override
  void initState() {
    super.initState();
    if (widget.autoStartShare) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _shareImage();
      });
    }
  }

  Future<void> _shareImage() async {
    await _runImageAction(action: _ShareImageAction.share);
  }

  Future<void> _copyImage() async {
    await _runImageAction(action: _ShareImageAction.copy);
  }

  Future<void> _runImageAction({
    required _ShareImageAction action,
  }) async {
    if (!mounted || _isBusy) {
      return;
    }

    setState(() {
      _activeAction = action;
      _message = action == _ShareImageAction.share
          ? 'מכין תמונה לשיתוף...'
          : 'מכין תמונה להעתקה...';
    });

    try {
      final pngBytes = await _capturePngBytes();
      final result = action == _ShareImageAction.share
          ? await const AssignmentShareImageService().sharePng(
              pngBytes: pngBytes,
              filename: widget.filename,
              title: widget.shareTitle,
              text: widget.shareText,
            )
          : await const AssignmentShareImageService().copyPng(
              pngBytes: pngBytes,
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _message = switch (result) {
          AssignmentShareImageResult.shared => 'התמונה נשלחה לשיתוף',
          AssignmentShareImageResult.copiedImage =>
            'התמונה הועתקה. אפשר להדביק אותה בצ׳אט',
          AssignmentShareImageResult.needsManualScreenshot =>
            'אפשר לצלם את המסך הזה כתמונה אחת',
        };
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = 'אפשר לצלם את המסך הזה כתמונה אחת';
      });
    } finally {
      if (mounted) {
        setState(() {
          _activeAction = null;
        });
      }
    }
  }

  Future<Uint8List> _capturePngBytes() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      throw StateError('Share preview is no longer mounted');
    }

    final renderObject = _captureKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('Share card is not ready for capture');
    }

    final image = await renderObject.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (byteData == null) {
      throw StateError('Failed to encode share card as PNG');
    }

    return Uint8List.view(byteData.buffer);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.appBarTitle),
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'סגירה',
              onPressed: () {
                Logger.action(widget.closeLogAction);
                Navigator.of(context).pop();
              },
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    color: const Color(0xFFE2E8F0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: FittedBox(
                              fit: BoxFit.fitWidth,
                              alignment: Alignment.topCenter,
                              child: RepaintBoundary(
                                key: _captureKey,
                                child: widget.card,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isBusy
                                  ? null
                                  : () {
                                      Logger.action(widget.shareLogAction);
                                      _shareImage();
                                    },
                              icon: _activeAction == _ShareImageAction.share
                                  ? const _ButtonProgressIndicator()
                                  : const Icon(Icons.ios_share),
                              label: Text(
                                _activeAction == _ShareImageAction.share
                                    ? 'משתף...'
                                    : 'שתף',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isBusy
                                  ? null
                                  : () {
                                      Logger.action(widget.copyLogAction);
                                      _copyImage();
                                    },
                              icon: _activeAction == _ShareImageAction.copy
                                  ? const _ButtonProgressIndicator()
                                  : const Icon(Icons.copy),
                              label: Text(
                                _activeAction == _ShareImageAction.copy
                                    ? 'מעתיק...'
                                    : 'העתק תמונה',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ShareImageAction {
  share,
  copy,
}

class _ButtonProgressIndicator extends StatelessWidget {
  const _ButtonProgressIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
