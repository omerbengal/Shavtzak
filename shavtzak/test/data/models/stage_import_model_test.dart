import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/models/stage_import_model.dart';
import 'package:shavtzak/domain/entities/imported_stage.dart';

import '../../support/task_fixtures.dart';

void main() {
  test('the payload carries the event and every stage with its tasks', () {
    final stage =
        buildStage(id: 's1', eventId: 'e1', date: DateTime(2026, 6, 15));
    final task = buildTask(id: 't1', eventId: 'e1', stageId: 's1');
    final payload = StageImportModel.toMutationPayload('e1', [
      ImportedStage(stage: stage, tasks: [task]),
    ]);

    expect(payload['eventId'], 'e1');
    final stages = payload['stages'] as List;
    expect(stages, hasLength(1));
    final entry = stages.single as Map<String, dynamic>;
    expect((entry['stage'] as Map)['id'], 's1');
    expect((entry['stage'] as Map)['date'], '2026-06-15');
    expect(((entry['tasks'] as List).single as Map)['stageId'], 's1');
  });
}
