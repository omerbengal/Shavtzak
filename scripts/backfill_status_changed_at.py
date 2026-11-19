"""One-off backfill (Omer, 19/11/2026): `statusChangedAt` on the team tasks.

The "עדכון סטטוס" time chip filters by when a task's status last changed.
The backend writes `statusChangedAt` on every `teamTask.setStatus` from the
merge on; older tasks get it here, from the server's action log (`logs`):
the latest `teamTask.setStatus` entry of each task whose `changes` hold
`status` (a task-level change, not a stored subtask's). A task with no such
entry keeps no field (its status never changed: the app then falls back to
`completedAt` for a done task). Only that one field is written, and only on a
task that has none yet (a status change after the merge already set it).

Dry run by default. `--apply` writes, each task with a precondition on its
`updateTime`, so a task changed in between is skipped, never overwritten.

    python scripts/backfill_status_changed_at.py --env test
    python scripts/backfill_status_changed_at.py --env prod            # dry run
    python scripts/backfill_status_changed_at.py --env prod --apply    # after the merge + deploy

Credentials: the Firebase CLI's own login on this machine, as in
`migrate_subtasks_to_tasks.py`.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from migrate_subtasks_to_tasks import BASE, DOC_ROOT, Firestore, plain  # noqa: E402


def run_query(store, collection, operation):
    """Every log entry of [operation] (one equality filter: no index needed)."""
    body = {'structuredQuery': {
        'from': [{'collectionId': collection}],
        'where': {'fieldFilter': {
            'field': {'fieldPath': 'operation'},
            'op': 'EQUAL',
            'value': {'stringValue': operation},
        }},
    }}
    rows = store._call(f'{BASE}:runQuery', body)
    return [row['document'] for row in rows if 'document' in row]


def latest_status_change(log_docs):
    """entityId -> the latest `timestampUtc` REST value of a task-level change."""
    latest = {}
    for doc in log_docs:
        fields = doc.get('fields', {})
        if plain(fields.get('entityType')) != 'teamTask':
            continue
        changes = plain(fields.get('changes')) or {}
        if 'status' not in changes:
            continue
        stamp = fields.get('timestampUtc', {}).get('timestampValue')
        entity = plain(fields.get('entityId'))
        if not stamp or not entity:
            continue
        if entity not in latest or stamp > latest[entity]:
            latest[entity] = stamp
    return latest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--env', choices=['test', 'prod'], required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    prefix = 'test_' if args.env == 'test' else ''
    store = Firestore()
    tasks = store.list(f'{prefix}teamTasks')
    latest = latest_status_change(run_query(store, f'{prefix}logs', 'teamTask.setStatus'))
    work = []
    for doc in tasks:
        task_id = doc['name'].split('/')[-1]
        fields = doc.get('fields', {})
        if 'statusChangedAt' in fields and plain(fields['statusChangedAt']) is not None:
            continue
        stamp = latest.get(task_id)
        if stamp:
            work.append((doc, stamp))
    print(f'{prefix}teamTasks: {len(tasks)} task(s), {len(latest)} with a status change in the log, '
          f'{len(work)} to fill.')
    for doc, stamp in work:
        fields = doc.get('fields', {})
        print(f'  {doc["name"].split("/")[-1]}: "{plain(fields.get("title"))}"'
              f' status={plain(fields.get("status"))} statusChangedAt={stamp}')
    if not args.apply:
        print('\nDry run: nothing written. Add --apply to write.')
        return
    written = skipped = 0
    for doc, stamp in work:
        write = {
            'update': {'name': doc['name'], 'fields': {'statusChangedAt': {'timestampValue': stamp}}},
            'updateMask': {'fieldPaths': ['statusChangedAt']},
            'currentDocument': {'updateTime': doc['updateTime']},
        }
        try:
            store.commit([write])
            written += 1
        except urllib.error.HTTPError as error:
            # Changed since it was read: its own write set the field already.
            print(f'  skipped {doc["name"].split("/")[-1]}: {error.code}')
            skipped += 1
    print(f'\nDone: {written} written, {skipped} skipped.')


if __name__ == '__main__':
    main()
