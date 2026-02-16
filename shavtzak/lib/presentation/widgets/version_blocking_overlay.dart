import 'package:flutter/material.dart';

import '../../core/services/app_version_service.dart';

/// A global blocking overlay shown when the local app version is outdated.
class VersionBlockingOverlay extends StatelessWidget {
  final Widget child;

  const VersionBlockingOverlay({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppVersionService.instance,
      builder: (context, _) {
        final isBlocked = AppVersionService.instance.isBlocked;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            children: [
              child,
              if (isBlocked) const _VersionBlockingDialog(),
            ],
          ),
        );
      },
    );
  }
}

class _VersionBlockingDialog extends StatelessWidget {
  const _VersionBlockingDialog();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
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
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.system_update_rounded,
                    size: 40,
                    color: Colors.orange[700],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'נדרשת רענון אפליקציה',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[900],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'זוהתה גרסה חדשה של המערכת.\n'
                  'יש לרענן את האפליקציה כדי להמשיך.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await AppVersionService.instance.refreshApp();
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('רענון האפליקציה'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
