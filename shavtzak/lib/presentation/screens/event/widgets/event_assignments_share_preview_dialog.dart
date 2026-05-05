import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/services/assignment_share_image_service.dart';
import 'event_assignments_share_card.dart';
import 'event_assignments_share_models.dart';

class EventAssignmentsSharePreviewDialog extends StatefulWidget {
  final EventAssignmentsShareData data;
  final bool autoStartShare;

  const EventAssignmentsSharePreviewDialog({
    super.key,
    required this.data,
    this.autoStartShare = true,
  });

  @override
  State<EventAssignmentsSharePreviewDialog> createState() =>
      _EventAssignmentsSharePreviewDialogState();
}

class _EventAssignmentsSharePreviewDialogState
    extends State<EventAssignmentsSharePreviewDialog> {
  final GlobalKey _captureKey = GlobalKey();
  bool _isSharing = false;
  String _message = 'אפשר לצלם את המסך הזה כתמונה אחת';

  @override
  void initState() {
    super.initState();
    if (widget.autoStartShare) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _shareImage();
      });
    }
  }

  Future<void> _shareImage() async {
    if (_isSharing) {
      return;
    }

    setState(() {
      _isSharing = true;
      _message = 'מכין תמונה לשיתוף...';
    });

    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return;
      }

      final renderObject = _captureKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('Share card is not ready for capture');
      }

      final image = await renderObject.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (!mounted) {
        return;
      }

      if (byteData == null) {
        throw StateError('Failed to encode share card as PNG');
      }

      final pngBytes = Uint8List.view(byteData.buffer);
      final result = await const AssignmentShareImageService().sharePng(
        pngBytes: pngBytes,
        filename: _buildFilename(widget.data.eventName),
        title: 'תמונת שיבוצים',
        text: 'שיבוצים ל${widget.data.eventName}',
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
          _isSharing = false;
        });
      }
    }
  }

  String _buildFilename(String eventName) {
    final safeName = eventName
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final suffix = safeName.isEmpty ? 'event' : safeName;
    return 'shavtzak_assignments_$suffix.png';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('תמונת שיבוצים'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'סגירה',
              onPressed: () => Navigator.of(context).pop(),
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
                                child: EventAssignmentsShareCard(
                                  data: widget.data,
                                ),
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
                      FilledButton.icon(
                        onPressed: _isSharing ? null : _shareImage,
                        icon: _isSharing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.ios_share),
                        label:
                            Text(_isSharing ? 'מכין תמונה...' : 'נסה לשתף שוב'),
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
