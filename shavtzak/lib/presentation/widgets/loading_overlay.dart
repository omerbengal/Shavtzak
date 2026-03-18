import 'package:flutter/material.dart';

/// A loading overlay widget that shows a semi-transparent overlay
/// with a loading indicator and optional message.
class LoadingOverlay extends StatelessWidget {
  final String message;
  final bool isLoading;
  final Color backgroundColor;

  const LoadingOverlay({
    super.key,
    this.message = 'טוען...',
    required this.isLoading,
    this.backgroundColor = const Color(0xCCFFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return const SizedBox.shrink();

    return Container(
      color: backgroundColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
