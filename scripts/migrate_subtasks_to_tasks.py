"""One-off migration (Omer, 16/11/2026): every team-task subtask becomes a task.

Subtasks were removed from the app. Each stored subtask becomes a regular team
task in the same place as its parent (the parent's link and events), keeping
its own id, title, description, owners, contacts, deadline, status, duplicate
pointer, update log and completion. The parent is then closed as
"לא רלוונטי/בוטל" ("cancelled") with no subtasks and no owners.

Dry run by default: prints what would change. `--apply` writes it, one
Firestore commit per parent (the parent and its new tasks together; the new
tasks must not exist yet, the parent must not have changed since it was read).

    python scripts/migrate_subtasks_to_tasks.py --env test             # dry run on test_teamTasks
    python scripts/migrate_subtasks_to_tasks.py --env test --apply
    python scripts/migrate_subtasks_to_tasks.py --env prod --apply     # only after the merge

`--env test --seed` writes a parent with three subtasks (ids `mig-test-*`) to
`test_teamTasks` to try it on; `--env test --cleanup` deletes them again.

Credentials: the Firebase CLI's own login on this machine
(`~/.config/configstore/firebase-tools.json`, `firebase login`), through the
Firestore REST API. Run it from a machine where `firebase login` was done.
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

PROJECT = 'tsevet-shir-shavtzak'
BASE = f'https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents'
DOC_ROOT = f'projects/{PROJECT}/databases/(default)/documents'
SEED_PREFIX = 'mig-test-'


def cli_client():
    """The Firebase CLI's own OAuth client, read from its installed package
    (`npm root -g`/firebase-tools/lib/api.js), so its login token refreshes."""
    root = subprocess.run('npm root -g', shell=True, capture_output=True, text=True).stdout.strip()
    source = open(os.path.join(root, 'firebase-tools', 'lib', 'api.js'), encoding='utf-8').read()
    client_id = re.search(r'"FIREBASE_CLIENT_ID",\s*"([^"]+)"', source).group(1)
    secret = re.search(r'"FIREBASE_CLIENT_SECRET",\s*"([^"]+)"', source).group(1)
    return client_id, secret


def access_token():
    path = os.path.expanduser('~/.config/configstore/firebase-tools.json')
    config = json.load(open(path, encoding='utf-8'))
    client_id, secret = cli_client()
    data = urllib.parse.urlencode({
        'grant_type': 'refresh_token',
        'refresh_token': config['tokens']['refresh_token'],
        'client_id': client_id,
        'client_secret': secret,
    }).encode()
    return json.load(urllib.request.urlopen('https://oauth2.googleapis.com/token', data))['access_token']


class Firestore:
    def __init__(self):
        self.token = access_token()

    def _call(self, url, body=None):
        request = urllib.request.Request(
            url,
            data=None if body is None else json.dumps(body).encode(),
            headers={'Authorization': f'Bearer {self.token}', 'Content-Type': 'application/json'},
            method='GET' if body is None else 'POST',
        )
        return json.load(urllib.request.urlopen(request))

    def list(self, collection):
        docs, page = [], None
        while True:
            url = f'{BASE}/{collection}?pageSize=300' + (f'&pageToken={page}' if page else '')
            answer = self._call(url)
            docs += answer.get('documents', [])
            page = answer.get('nextPageToken')
            if not page:
                return docs

    def commit(self, writes):
        return self._call(f'{BASE}:commit', {'writes': writes})


# ---- Firestore REST values ----

def s(value):
    return {'stringValue': value}


NULL = {'nullValue': None}


def arr(values):
    return {'arrayValue': {'values': values}} if values else {'arrayValue': {}}


def plain(value):
    """A REST value as plain Python, for reading and printing."""
    if value is None:
        return None
    if 'mapValue' in value:
        return {k: plain(v) for k, v in value['mapValue'].get('fields', {}).items()}
    if 'arrayValue' in value:
        return [plain(v) for v in value['arrayValue'].get('values', [])]
    for key in ('stringValue', 'booleanValue', 'timestampValue', 'integerValue', 'doubleValue'):
        if key in value:
            return value[key]
    return None


def now_value():
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%fZ')
    return {'timestampValue': stamp}


def subtask_as_task(parent_fields, raw, now):
    """The new task document (REST fields) for subtask [raw] of a parent."""
    fields = raw['mapValue'].get('fields', {})
    if 'status' in fields:
        status = plain(fields['status']) or 'open'
    else:
        status = 'done' if plain(fields.get('isDone')) is True else 'open'
    if 'assigneeIds' in fields:
        owners = [o for o in (plain(fields['assigneeIds']) or []) if isinstance(o, str)]
    else:
        legacy = plain(fields.get('assigneeId'))
        owners = [legacy] if isinstance(legacy, str) and legacy else []
    owners = list(dict.fromkeys(owners))
    link = parent_fields.get('link', NULL)
    link_plain = plain(link) or {}
    if link_plain.get('type') == 'event':
        event_ids = plain(parent_fields.get('eventIds')) or [link_plain.get('id')]
        events = parent_fields.get('eventIds') or arr([s(i) for i in event_ids])
    else:
        events = arr([])
    return {
        'title': fields.get('title', s('')),
        'description': fields.get('description', s('')),
        'link': link,
        'eventIds': events,
        'urgency': s('normal'),
        'assigneeIds': arr([s(o) for o in owners]),
        'ownerIds': arr([s(o) for o in owners]),
        'subtasks': arr([]),
        'contacts': fields.get('contacts', arr([])),
        'deadline': fields.get('deadline', NULL),
        'status': s(status),
        'duplicateOfId': fields.get('duplicateOfId', NULL) if status == 'duplicate' else NULL,
        'updates': fields.get('updates', arr([])),
        'completedAt': fields.get('completedAt', NULL),
        'createdAt': parent_fields.get('createdAt', now),
        'createdById': parent_fields.get('createdById', s('')),
        'updatedAt': now,
    }


def plan(docs):
    """[(parent doc, [(new id, new fields)])] for every task with subtasks."""
    existing = {d['name'].split('/')[-1] for d in docs}
    now = now_value()
    result = []
    for doc in docs:
        fields = doc.get('fields', {})
        subtasks = fields.get('subtasks', {}).get('arrayValue', {}).get('values', [])
        if not subtasks:
            continue
        new = []
        for raw in subtasks:
            sub_id = plain(raw['mapValue'].get('fields', {}).get('id'))
            if not sub_id:
                raise SystemExit(f'a subtask of {doc["name"]} has no id')
            if sub_id in existing:
                raise SystemExit(f'task id {sub_id} already exists: stopping, nothing written')
            new.append((sub_id, subtask_as_task(fields, raw, now)))
        result.append((doc, new))
    return result


def parent_closed(doc, now):
    fields = dict(doc.get('fields', {}))
    fields.update({
        'subtasks': arr([]),
        'status': s('cancelled'),
        'duplicateOfId': NULL,
        'completedAt': NULL,
        'assigneeIds': arr([]),
        'ownerIds': arr([]),
        'updatedAt': now,
    })
    return fields


def migrate(store, collection, apply):
    docs = store.list(collection)
    work = plan(docs)
    if not work:
        print(f'{collection}: no task has subtasks. Nothing to do.')
        return
    total = sum(len(new) for _, new in work)
    print(f'{collection}: {len(work)} parent(s), {total} subtask(s) to convert.')
    for doc, new in work:
        fields = doc.get('fields', {})
        print(f'\n  parent {doc["name"].split("/")[-1]}: "{plain(fields.get("title"))}"'
              f' (status {plain(fields.get("status"))}) -> cancelled, no subtasks, no owners')
        for new_id, task in new:
            print(f'    + task {new_id}: "{plain(task["title"])}" status={plain(task["status"])}'
                  f' owners={plain(task["ownerIds"])} deadline={plain(task["deadline"])}'
                  f' updates={len(plain(task["updates"]) or [])}')
    if not apply:
        print('\nDry run: nothing written. Add --apply to write.')
        return
    for doc, new in work:
        now = now_value()
        writes = [{
            'update': {'name': doc['name'], 'fields': parent_closed(doc, now)},
            'currentDocument': {'updateTime': doc['updateTime']},
        }]
        for new_id, task in new:
            task['updatedAt'] = now
            writes.append({
                'update': {'name': f'{DOC_ROOT}/{collection}/{new_id}', 'fields': task},
                'currentDocument': {'exists': False},
            })
        store.commit(writes)
        print(f'  written: parent {doc["name"].split("/")[-1]} + {len(new)} task(s)')
    print('\nDone.')


def seed(store, collection):
    now = now_value()
    update = {'mapValue': {'fields': {
        'id': s(f'{SEED_PREFIX}u1'), 'text': s('עדכון של תת-משימה'), 'at': now,
        'byId': s('seed'), 'byName': s('בדיקה'),
    }}}

    def sub(sub_id, title, fields):
        return {'mapValue': {'fields': {'id': s(sub_id), 'title': s(title), **fields}}}

    parent = {
        'title': s('בדיקת המרת תתי-משימות'),
        'description': s(''),
        'link': NULL,
        'assigneeIds': arr([]),
        'ownerIds': arr([s('seed-a'), s('seed-b')]),
        'subtasks': arr([
            sub(f'{SEED_PREFIX}s1', 'פתוחה עם עדכון', {
                'description': s('מחזור 12.11'), 'assigneeIds': arr([s('seed-a')]),
                'contacts': arr([]), 'deadline': s('2026-11-20'), 'status': s('open'),
                'duplicateOfId': NULL, 'updates': arr([update]), 'completedAt': NULL,
            }),
            sub(f'{SEED_PREFIX}s2', 'בוצעה', {
                'assigneeIds': arr([s('seed-b')]), 'status': s('done'), 'completedAt': now,
            }),
            # A subtask from before round 2: one owner and a tick.
            sub(f'{SEED_PREFIX}s3', 'ישנה', {'assigneeId': s('seed-a'), 'isDone': {'booleanValue': True}}),
        ]),
        'contacts': arr([]),
        'deadline': NULL,
        'status': s('inProgress'),
        'duplicateOfId': NULL,
        'updates': arr([]),
        'completedAt': NULL,
        'createdAt': now,
        'createdById': s('seed'),
        'updatedAt': now,
    }
    store.commit([{
        'update': {'name': f'{DOC_ROOT}/{collection}/{SEED_PREFIX}parent', 'fields': parent},
        'currentDocument': {'exists': False},
    }])
    print(f'seeded {collection}/{SEED_PREFIX}parent with 3 subtasks')


def cleanup(store, collection):
    names = [d['name'] for d in store.list(collection)
             if d['name'].split('/')[-1].startswith(SEED_PREFIX)]
    if names:
        store.commit([{'delete': name} for name in names])
    print(f'deleted {len(names)} seed document(s) from {collection}')


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--env', choices=['test', 'prod'], required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--seed', action='store_true')
    parser.add_argument('--cleanup', action='store_true')
    args = parser.parse_args()
    collection = ('test_' if args.env == 'test' else '') + 'teamTasks'
    store = Firestore()
    if args.seed or args.cleanup:
        if args.env != 'test':
            raise SystemExit('--seed / --cleanup only with --env test')
        (seed if args.seed else cleanup)(store, collection)
        return
    migrate(store, collection, args.apply)


if __name__ == '__main__':
    main()
