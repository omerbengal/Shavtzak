import 'package:flutter/material.dart';

/// A chat-style message bubble for displaying notes in checklist items
/// Supports RTL layout, alignment, ownership highlighting, and responsive design
class ChatBubble extends StatelessWidget {
  final String authorName;
  final String message;
  final Color bubbleColor;
  final bool isOwnMessage;
  final bool alignRight;
  final String? timestamp;
  final bool showAuthorLabel;

  const ChatBubble({
    super.key,
    required this.authorName,
    required this.message,
    required this.bubbleColor,
    this.isOwnMessage = false,
    this.alignRight = false,
    this.timestamp,
    this.showAuthorLabel = true,
  });

  BorderRadius _getBorderRadius() {
    if (alignRight) {
      return const BorderRadius.only(
        topLeft: Radius.circular(12),
        topRight: Radius.circular(4),
        bottomLeft: Radius.circular(12),
        bottomRight: Radius.circular(12),
      );
    } else {
      return const BorderRadius.only(
        topLeft: Radius.circular(4),
        topRight: Radius.circular(12),
        bottomLeft: Radius.circular(12),
        bottomRight: Radius.circular(12),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use Align + FractionallySizedBox for responsive width without MediaQuery
    return Align(
      alignment: alignRight ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: FractionallySizedBox(
        widthFactor: 0.7,
        child: Align(
          alignment: alignRight ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: alignRight ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              // Author label
              if (showAuthorLabel)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    authorName,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // Bubble container
              Container(
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: _getBorderRadius(),
                  border: isOwnMessage
                      ? Border.all(color: Colors.blue, width: 2.0)
                      : null,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                      softWrap: true,
                    ),
                    if (timestamp != null) ...[
                      const SizedBox(height: 4),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          timestamp!,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
