import 'package:flutter/material.dart';
import '../../core/services/connectivity_service.dart';

/// A widget that displays a blocking dialog when the device is offline.
/// Shows in both test and production modes.
class OfflineBlockingOverlay extends StatelessWidget {
  final Widget child;

  const OfflineBlockingOverlay({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConnectivityService.instance,
      builder: (context, _) {
        final isOffline = ConnectivityService.instance.isOffline;

        // Wrap with Directionality for cases where this widget is above MaterialApp
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            children: [
              // Always render the app
              child,

              // Show blocking overlay when offline
              if (isOffline)
                const _OfflineBlockingDialog(),
            ],
          ),
        );
      },
    );
  }
}

/// The actual blocking dialog that appears when offline
class _OfflineBlockingDialog extends StatelessWidget {
  const _OfflineBlockingDialog();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.black54,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Offline icon with animation
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.wifi_off_rounded,
                      size: 40,
                      color: Colors.red[600],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    'אין חיבור לאינטרנט',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[900],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Description
                  Text(
                    'לא ניתן להשתמש באפליקציה ללא חיבור לאינטרנט.\n'
                    'אנא בדוק את החיבור שלך ונסה שוב.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Loading indicator and waiting message
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey[400],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'ממתין לחיבור...',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
