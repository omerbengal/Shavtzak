import 'package:flutter/material.dart';

/// A loading overlay widget that shows a semi-transparent overlay
/// with a loading indicator and optional message.
class LoadingOverlay extends StatelessWidget {
  final String message;
  final bool isLoading;

  const LoadingOverlay({
    super.key,
    this.message = 'טוען...',
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return const SizedBox.shrink();

    return Container(
      color: Colors.white.withOpacity(0.8),
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
