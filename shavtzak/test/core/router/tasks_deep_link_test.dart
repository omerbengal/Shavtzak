import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/router/app_router.dart';
import 'package:shavtzak/presentation/screens/team_task/team_tasks_place.dart';

import '../../support/task_fixtures.dart';

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

    test('reads the link "מי את/ה?" carries, so a reload keeps it', () {
      expect(
        AppRouter.pendingTasksLinkFor('#/whoami?next=%2Fdu-yomi%2Fe1'),
        '/du-yomi/e1',
      );
      expect(
        AppRouter.pendingTasksLinkFor(
            '#/test/whoami?next=%2Ftest%2Fuser%2Fdu-yomi%2Fe1'),
        '/test/user/du-yomi/e1',
      );
      expect(AppRouter.pendingTasksLinkFor('#/whoami?next=%2Ftasks'), '/tasks');
    });

    test('ignores a carried link that is not one worth keeping', () {
      for (final hash in [
        '#/whoami',
        '#/whoami?next=%2Fadmin',
        '#/whoami?next=https%3A%2F%2Fevil.example',
        '#/whoami?next=%E0%A4%A',
        '#/admin?next=%2Fdu-yomi%2Fe1',
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

  group('AppRouter.whoamiRoute', () {
    tearDown(() => AppRouter.debugSetPendingDeepLink(null));

    test('is plain "מי את/ה?" when no link is pending', () {
      expect(AppRouter.whoamiRoute(''), '/whoami');
      expect(AppRouter.whoamiRoute('/test'), '/test/whoami');
    });

    test('carries the pending link, and reading it back gives the link', () {
      AppRouter.debugSetPendingDeepLink('/du-yomi/e1');
      final route = AppRouter.whoamiRoute('');
      expect(route, '/whoami?next=%2Fdu-yomi%2Fe1');
      expect(AppRouter.pendingTasksLinkFor('#$route'), '/du-yomi/e1');

      AppRouter.debugSetPendingDeepLink('/test/du-yomi/e1');
      final testRoute = AppRouter.whoamiRoute('/test');
      expect(AppRouter.pendingTasksLinkFor('#$testRoute'), '/test/du-yomi/e1');
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

  // A tap on a "שובצת למשימה" notification while the iPhone app is closed
  // starts the app at #/team-tasks?task=<id>. Auth is still loading then, so
  // the link must survive "מי את/ה?" like the checklist's (bug 17/11/2026:
  // Omer landed on /admin).
  group('team task link from a notification', () {
    tearDown(() => AppRouter.debugSetPendingDeepLink(null));

    test('is kept with its task, in both environments', () {
      expect(AppRouter.pendingTasksLinkFor('#/team-tasks?task=0f4c1cef-ab12'),
          '/team-tasks?task=0f4c1cef-ab12');
      expect(AppRouter.pendingTasksLinkFor('#/test/team-tasks?task=t1'),
          '/test/team-tasks?task=t1');
      expect(AppRouter.pendingTasksLinkFor('#/team-tasks'), '/team-tasks');
      expect(AppRouter.pendingTasksLinkFor('#/team-tasks/?task=t1'),
          '/team-tasks?task=t1');
    });

    test('keeps only a plain task id, nothing else from the query', () {
      expect(AppRouter.pendingTasksLinkFor('#/team-tasks?task=t1&x=2'),
          '/team-tasks?task=t1');
      expect(AppRouter.pendingTasksLinkFor('#/team-tasks?x=2'), '/team-tasks');
      expect(
          AppRouter.pendingTasksLinkFor(
              '#/team-tasks?task=https%3A%2F%2Fevil.example'),
          '/team-tasks');
      expect(AppRouter.pendingTasksLinkFor('#/team-tasks?task=%E0%A4%A'),
          '/team-tasks');
      expect(AppRouter.pendingTasksLinkFor('#/team-tasks/x'), isNull);
    });

    test('cold start with auth loading: "מי את/ה?" carries it, then an admin '
        'lands on the task', () {
      for (final env in ['', '/test']) {
        // router(): the hash push.js put in place before Flutter started.
        AppRouter.debugSetPendingDeepLink(
            AppRouter.pendingTasksLinkFor('#$env/team-tasks?task=0f4c'));
        // Auth still loading: the redirect sends the visitor to sign-in.
        final whoami = AppRouter.whoamiRoute(env);
        expect(AppRouter.pendingTasksLinkFor('#$whoami'),
            '$env/team-tasks?task=0f4c', reason: whoami);
        // Signed in on "מי את/ה?": the admin goes to the task, not /admin.
        final dest = AppRouter.postAuthDestination('$env/admin');
        expect(dest, '$env/team-tasks?task=0f4c');
        final uri = Uri.parse(dest);
        expect(uri.queryParameters['task'], '0f4c');
        final stripped =
            env.isEmpty ? uri.path : uri.path.substring(env.length);
        expect(teamTasksRedirect(stripped, buildMember(isAdmin: true)), isNull);
      }
    });

    test('a member who is not an admin lands on the task in the "משימות" tab',
        () {
      AppRouter.debugSetPendingDeepLink('/team-tasks?task=t1');
      final dest = AppRouter.postAuthDestination('/user/assignments');
      expect(dest, '/team-tasks?task=t1');
      // The router sends them to the tab and keeps the query.
      expect(teamTasksRedirect(Uri.parse(dest).path, buildMember()),
          '/user/team-tasks');
    });

    test("a link to the members' tab is kept with its task too", () {
      expect(AppRouter.pendingTasksLinkFor('#/user/team-tasks?task=t1'),
          '/user/team-tasks?task=t1');
      expect(AppRouter.pendingTasksLinkFor('#/test/user/team-tasks?task=t1'),
          '/test/user/team-tasks?task=t1');
    });

    test('a signed-out visit (app already open) is remembered with its task',
        () {
      AppRouter.rememberTasksLink('/team-tasks?task=t9');
      expect(AppRouter.postAuthDestination('/admin'), '/team-tasks?task=t9');
    });

    test('arriving on the task clears it, matched by path and query', () {
      AppRouter.debugSetPendingDeepLink('/team-tasks?task=t1');
      AppRouter.clearPendingDeepLinkIfArrived('/team-tasks?task=t1');
      expect(AppRouter.postAuthDestination('/admin'), '/admin');
    });
  });
}
