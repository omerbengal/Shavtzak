import 'package:flutter/material.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/environment_service.dart';

/// A widget that displays a blocking dialog when the device is offline.
/// IMPORTANT: This feature is only active in TEST MODE.
/// In production mode, this widget simply passes through its child.
class OfflineBlockingOverlay extends StatelessWidget {
  final Widget child;

  const OfflineBlockingOverlay({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Listen to both environment and connectivity changes
    return ListenableBuilder(
      listenable: EnvironmentService.instance,
      builder: (context, _) {
        final isTestMode = EnvironmentService.instance.isTestMode;

        // In production mode, just return the child without any overlay
        if (!isTestMode) {
          return child;
        }

        // In test mode, wrap with connectivity listener
        return ListenableBuilder(
          listenable: ConnectivityService.instance,
          builder: (context, _) {
            final isOffline = ConnectivityService.instance.isOffline;

            return Stack(
              children: [
                // Always render the app
                child,

                // Show blocking overlay when offline (test mode only)
                if (isOffline)
                  const _OfflineBlockingDialog(),
              ],
            );
          },
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
                  const SizedBox(height: 16),

                  // Test mode indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.yellow[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.yellow[700]!,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.science,
                          size: 16,
                          color: Colors.yellow[800],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'פעיל רק בסביבת בדיקות',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.yellow[900],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
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
