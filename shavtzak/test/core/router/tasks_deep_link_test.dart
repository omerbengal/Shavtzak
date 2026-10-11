import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/router/app_router.dart';

void main() {
  group('AppRouter.pendingTasksLinkFor', () {
    test('recognises the production tasks link', () {
      expect(AppRouter.pendingTasksLinkFor('#/tasks'), '/tasks');
    });

    test('recognises the test-environment tasks link', () {
      expect(AppRouter.pendingTasksLinkFor('#/test/tasks'), '/test/tasks');
    });

    test('ignores a query string and a trailing slash', () {
      expect(AppRouter.pendingTasksLinkFor('#/tasks?x=1'), '/tasks');
      expect(AppRouter.pendingTasksLinkFor('#/tasks/'), '/tasks');
      expect(AppRouter.pendingTasksLinkFor('#/test/tasks/?x=1'), '/test/tasks');
    });

    test('accepts a hash without the leading #', () {
      expect(AppRouter.pendingTasksLinkFor('/tasks'), '/tasks');
    });

    test('is null for every other route', () {
      for (final hash in [
        null,
        '',
        '#',
        '#/',
        '#/admin/events',
        '#/user/assignments',
        '#/tasks-old',
        '#/user/tasks',
        '#/test',
        '#/db',
      ]) {
        expect(
          AppRouter.pendingTasksLinkFor(hash),
          isNull,
          reason: 'hash: $hash',
        );
      }
    });
  });

  group('AppRouter.postAuthDestination', () {
    tearDown(() => AppRouter.debugSetPendingDeepLink(null));

    test('is the member\'s home when no link is pending', () {
      expect(AppRouter.postAuthDestination('/admin'), '/admin');
    });

    test('is the pending tasks link instead of home', () {
      AppRouter.debugSetPendingDeepLink('/tasks');
      expect(AppRouter.postAuthDestination('/admin'), '/tasks');
    });

    test('uses the link once: the next sign-in goes home', () {
      AppRouter.debugSetPendingDeepLink('/test/tasks');
      expect(AppRouter.postAuthDestination('/test/admin'), '/test/tasks');
      expect(AppRouter.postAuthDestination('/test/admin'), '/test/admin');
    });

    test('arriving on the tasks screen clears the pending link', () {
      AppRouter.debugSetPendingDeepLink('/tasks');
      AppRouter.clearPendingDeepLinkIfArrived('/tasks');
      expect(AppRouter.postAuthDestination('/admin'), '/admin');
    });

    test('a signed-out visit to the tasks route is remembered', () {
      // Covers a tab where the app is already loaded: the link arrives as a
      // hash change, not a cold start, so there is no initial hash to read.
      AppRouter.rememberTasksLink('/tasks');
      expect(AppRouter.postAuthDestination('/admin'), '/tasks');

      AppRouter.rememberTasksLink('/test/tasks');
      expect(AppRouter.postAuthDestination('/test/admin'), '/test/tasks');
    });

    test('a signed-out visit to any other route is not remembered', () {
      AppRouter.rememberTasksLink('/admin/events');
      AppRouter.rememberTasksLink('/whoami');
      expect(AppRouter.postAuthDestination('/admin'), '/admin');
    });

    test('visiting another route does not forget a remembered tasks link', () {
      AppRouter.rememberTasksLink('/tasks');
      AppRouter.rememberTasksLink('/whoami');
      expect(AppRouter.postAuthDestination('/admin'), '/tasks');
    });

    test('arriving anywhere else keeps the pending link', () {
      AppRouter.debugSetPendingDeepLink('/tasks');
      AppRouter.clearPendingDeepLinkIfArrived('/whoami');
      expect(AppRouter.postAuthDestination('/admin'), '/tasks');
    });
  });
}
