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

    test('ignores anything under the link: events moved to the דו יומי tab',
        () {
      for (final hash in [
        '#/tasks/9d130a08-cc9c-4052',
        '#/test/tasks/e1/?x=1',
        '#/tasks/a/b',
      ]) {
        expect(AppRouter.pendingTasksLinkFor(hash), isNull, reason: hash);
      }
    });

    test('recognises a דו יומי event link, in both places and environments',
        () {
      for (final path in [
        '/du-yomi/4be102b6-e5c8-408a-a4b2-a77b73975ed2',
        '/user/du-yomi/4be102b6-e5c8-408a-a4b2-a77b73975ed2',
        '/test/du-yomi/e1',
        '/test/user/du-yomi/e1',
        '/du-yomi/e1/edit',
        '/test/user/du-yomi/e1/edit',
      ]) {
        expect(AppRouter.pendingTasksLinkFor('#$path'), path, reason: path);
      }
    });

    test('keeps a דו יומי event link without its query or trailing slash', () {
      expect(AppRouter.pendingTasksLinkFor('#/du-yomi/e1/?x=1'), '/du-yomi/e1');
    });

    test('ignores the דו יומי list and anything deeper than an event', () {
      for (final hash in [
        '#/du-yomi',
        '#/user/du-yomi',
        '#/du-yomi/e1/other',
        '#/du-yomi/e1/edit/x',
        '#/admin/du-yomi/e1',
      ]) {
        expect(AppRouter.pendingTasksLinkFor(hash), isNull, reason: hash);
      }
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

    test('a signed-out visit to a דו יומי event is remembered', () {
      AppRouter.rememberTasksLink('/du-yomi/e1');
      expect(AppRouter.postAuthDestination('/user/assignments'), '/du-yomi/e1');

      AppRouter.rememberTasksLink('/test/user/du-yomi/e1');
      expect(
        AppRouter.postAuthDestination('/test/admin'),
        '/test/user/du-yomi/e1',
      );
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
