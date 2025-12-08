import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/environment_service.dart';

/// Button to switch between production and test environments
/// Reactively updates UI when environment changes
class EnvironmentSwitcherButton extends StatelessWidget {
  const EnvironmentSwitcherButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EnvironmentService.instance,
      builder: (context, child) {
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
      },
    );
  }
}
