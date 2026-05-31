import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/environment_service.dart';
import '../../core/debug/logger.dart';
import 'dart:developer' as developer;

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
            Logger.action('toggle:environment', {'on': !isTestMode});
            // Get current route
            final currentRoute = GoRouterState.of(context).uri.path;
            developer.log('EnvironmentSwitcherButton: Pressed! currentRoute=$currentRoute, isTestMode=$isTestMode', name: 'EnvironmentSwitcher');

            // Convert current route to opposite environment
            String targetRoute;
            bool newTestMode;
            if (isTestMode) {
              // From test to production - remove /test prefix
              targetRoute = currentRoute.startsWith('/test')
                  ? currentRoute.substring(4) // Remove '/test'
                  : currentRoute;
              newTestMode = false;
            } else {
              // From production to test - add /test prefix
              targetRoute = currentRoute.startsWith('/test')
                  ? currentRoute
                  : '/test${
                      currentRoute.startsWith('/') ? currentRoute : '/$currentRoute'
                    }';
              newTestMode = true;
            }

            developer.log('EnvironmentSwitcherButton: targetRoute=$targetRoute, newTestMode=$newTestMode', name: 'EnvironmentSwitcher');

            // IMPORTANT: Update EnvironmentService immediately BEFORE navigation
            // This triggers immediate BLoC recreation with correct environment
            developer.log('EnvironmentSwitcherButton: Calling setTestMode($newTestMode)...', name: 'EnvironmentSwitcher');
            EnvironmentService.instance.setTestMode(newTestMode);

            // Navigate to the opposite environment
            developer.log('EnvironmentSwitcherButton: Navigating to $targetRoute...', name: 'EnvironmentSwitcher');
            context.go(targetRoute);
          },
        );
      },
    );
  }
}
