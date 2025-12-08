import 'package:flutter/material.dart';
import '../../core/services/environment_service.dart';

/// A widget that displays a yellow banner when the app is running in test environment
/// Reactively updates when environment changes
class TestEnvironmentIndicator extends StatelessWidget {
  final Widget child;

  const TestEnvironmentIndicator({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EnvironmentService.instance,
      builder: (context, _) {
        final isTestMode = EnvironmentService.instance.isTestMode;

        if (!isTestMode) {
          return child;
        }

        return Column(
          children: [
            // Yellow banner for test environment
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.yellow.shade700,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.science,
                    color: Colors.black87,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'סביבת בדיקות (TEST ENVIRONMENT)',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.science,
                    color: Colors.black87,
                    size: 20,
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
