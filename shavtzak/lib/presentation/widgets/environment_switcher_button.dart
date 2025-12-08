import 'package:flutter/material.dart';
import 'dart:html' as html;
import '../../core/services/environment_service.dart';

/// Button to switch between production and test environments
/// Forces a full page reload to ensure all services reinitialize with new environment
class EnvironmentSwitcherButton extends StatelessWidget {
  const EnvironmentSwitcherButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isTestMode = EnvironmentService.instance.isTestMode;

    return IconButton(
      icon: Icon(
        isTestMode ? Icons.public : Icons.science,
        color: isTestMode ? Colors.yellow.shade700 : Colors.grey.shade700,
      ),
      tooltip: isTestMode ? 'עבור לסביבת ייצור' : 'עבור לסביבת בדיקות',
      onPressed: () {
        // Navigate to the opposite environment's whoami screen
        final targetRoute = isTestMode ? '/whoami' : '/test/whoami';

        // Force a full page reload to reinitialize all services with new environment
        // This ensures Firestore collections, cache keys, and all widgets update properly
        html.window.location.href = '#$targetRoute';
        html.window.location.reload();
      },
    );
  }
}
