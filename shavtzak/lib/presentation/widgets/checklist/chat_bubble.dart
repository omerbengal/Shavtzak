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
      // Own message (right side): only top-right sharp, all others rounded
      return const BorderRadius.only(
        topLeft: Radius.circular(12),
        topRight: Radius.circular(4),
        bottomLeft: Radius.circular(12),
        bottomRight: Radius.circular(12),
      );
    } else {
      // Other's message (left side): only top-left sharp, all others rounded
      return const BorderRadius.only(
        topLeft: Radius.circular(4),
        topRight: Radius.circular(12),
        bottomLeft: Radius.circular(12),
        bottomRight: Radius.circular(12),
      );
    }
  }

  double _getMaxWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Use fixed widths for consistent chat appearance
    if (screenWidth < 400) return 180.0;      // Small mobile
    if (screenWidth < 600) return 220.0;      // Large mobile
    return 250.0;                             // Desktop/tablet
  }

  double _getHorizontalPadding(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // For narrow screens, use fixed padding
    if (screenWidth < 600) return 24.0;

    // For wide screens, center a chat column
    // Create a 600px wide chat area in the center for proper bubble spacing
    final targetChatWidth = 600.0;
    final padding = (screenWidth - targetChatWidth) / 2;

    // Minimum 24px padding, but scale up for wider screens
    return padding.clamp(24.0, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = _getMaxWidth(context);
    final horizontalPadding = _getHorizontalPadding(context);

    // In RTL: MainAxisAlignment.start = visually RIGHT (for own messages)
    //         MainAxisAlignment.end = visually LEFT (for others' messages)
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        mainAxisAlignment: alignRight ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Author label - explicitly aligned to same edge as bubble
                if (showAuthorLabel)
                  Align(
                    alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        authorName,
                        textAlign: alignRight ? TextAlign.right : TextAlign.left,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                // Bubble container - explicitly aligned to same edge as author label
                Align(
                  alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: _getBorderRadius(),
                      border: isOwnMessage
                          ? Border.all(
                              color: Colors.blue,
                              width: 2.0,
                            )
                          : null,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Message text with wrapping
                        Text(
                          message,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                          softWrap: true,
                          overflow: TextOverflow.visible,
                        ),
                        // Timestamp (if provided)
                        if (timestamp != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                timestamp!,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
