import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/navigation_menu.dart';
import '../../../core/debug/logger.dart';
import '../../../core/services/environment_service.dart';

/// Home screen with navigation cards to main sections
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('שבצק - ניהול צוות ואירועים'),
          centerTitle: true,
          actions: const [
            NavigationMenu(),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'ברוכים הבאים לשבצק',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'מערכת ניהול צוות ושיבוצים לאירועים',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: 300,
                  height: 120,
                  child: Card(
                    elevation: 4,
                    child: InkWell(
                      onTap: () {
                        Logger.action('tap:teamSection');
                        final envPrefix = EnvironmentService.instance.routePrefix;
                        context.go('$envPrefix/admin/team-members');
                      },
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people, size: 48, color: Colors.blue),
                          SizedBox(height: 8),
                          Text(
                            'צוות',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 300,
                  height: 120,
                  child: Card(
                    elevation: 4,
                    child: InkWell(
                      onTap: () {
                        Logger.action('tap:eventsSection');
                        final envPrefix = EnvironmentService.instance.routePrefix;
                        context.go('$envPrefix/admin/events');
                      },
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event, size: 48, color: Colors.green),
                          SizedBox(height: 8),
                          Text(
                            'אירועים',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 300,
                  height: 120,
                  child: Card(
                    elevation: 4,
                    child: InkWell(
                      onTap: () {
                        Logger.action('tap:assignmentsSection');
                        final envPrefix = EnvironmentService.instance.routePrefix;
                        context.go('$envPrefix/admin/assignments');
                      },
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.assignment, size: 48, color: Colors.purple),
                          SizedBox(height: 8),
                          Text(
                            'שיבוצים',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
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
