import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/environment_service.dart';

/// Button to switch between production and test environments
/// Always redirects to the whoami screen of the opposite environment
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
        context.go(targetRoute);
      },
    );
  }
}
