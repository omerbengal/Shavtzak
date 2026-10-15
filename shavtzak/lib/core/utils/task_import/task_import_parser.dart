import 'package:equatable/equatable.dart';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/entities/event.dart';
import '../../../domain/entities/imported_stage.dart';
import '../../../domain/entities/stage.dart';
import '../../../domain/entities/subtask.dart';
import '../../../domain/entities/task_item.dart';
import '../../../domain/entities/team_member.dart';
import '../task_utils.dart';
import 'assignee_matcher.dart';
import 'cell_values.dart';
import 'contact_cell_parser.dart';

/// Reads an import workbook into stages and tasks for one event, or into the
/// list of everything wrong with it. Nothing here saves anything.

const String stagesSheetName = 'שלבים';
const String tasksSheetName = 'משימות';
const int maxImportStages = 60;
const int maxImportTasks = 400;
const int maxImportFileBytes = 5 * 1024 * 1024;

abstract final class StageColumns {
  static const number = 'מספר שלב';
  static const title = 'שם';
  static const date = 'תאריך';
  static const start = 'שעת התחלה';
  static const end = 'שעת סיום';
  static const requirements = 'דרישות מהמלון ולוגיסטיקה';
  static const location = 'מיקום במלון';
  static const notes = 'הערות';
  static const contacts = 'אנשי קשר';

  static const all = [
    number,
    title,
    date,
    start,
    end,
    requirements,
    location,
    notes,
    contacts,
  ];
  static const required = [number, title, date];

  /// The headers the official template writes: list columns carry how to
  /// fill them. The hint in parentheses is ignored when reading.
  static const templateHeaders = [
    number,
    title,
    date,
    start,
    end,
    '$requirements $_eachThingPerLine',
    location,
    notes,
    '$contacts $_eachPersonPerLine',
  ];
}

const String _eachThingPerLine = '(כל דבר בכוכבית נפרדת בשורה נפרדת)';
const String _eachPersonPerLine = '(כל אחד בכוכבית נפרדת בשורה נפרדת)';
const String _eachItemPerLine = '(כל אחת בכוכבית נפרדת בשורה נפרדת)';

abstract final class TaskColumns {
  static const number = 'מספר שלב';
  static const title = 'משימה';
  static const description = 'תיאור';
  static const assignees = 'אחראי/ים';
  static const assembly = 'שעת התייצבות';
  static const subtasks = 'תתי משימות';

  static const all = [number, title, description, assignees, assembly, subtasks];
  static const required = [number, title];

  /// See [StageColumns.templateHeaders].
  static const templateHeaders = [
    number,
    title,
    description,
    '$assignees $_eachPersonPerLine',
    assembly,
    '$subtasks $_eachItemPerLine',
  ];
}

/// One thing wrong with the file. [row] is the Excel row number.
class ImportProblem extends Equatable {
  const ImportProblem(this.message, {this.sheet, this.row});

  final String message;
  final String? sheet;
  final int? row;

  String get text {
    if (sheet == null) return message;
    if (row == null) return '$sheet: $message';
    return '$sheet, שורה $row: $message';
  }

  @override
  List<Object?> get props => [message, sheet, row];
}

class TaskImportResult {
  const TaskImportResult({required this.stages, required this.problems});

  final List<ImportedStage> stages;
  final List<ImportProblem> problems;

  bool get isValid => problems.isEmpty && stages.isNotEmpty;

  int get taskCount =>
      stages.fold(0, (sum, imported) => sum + imported.tasks.length);

  int get contactCount =>
      stages.fold(0, (sum, imported) => sum + imported.stage.contacts.length);
}

const String _unreadable = 'הקובץ אינו קובץ אקסל תקין';

TaskImportResult parseTaskImport(
  List<int> bytes, {
  required Event event,
  required List<TeamMember> candidates,
  required String currentUserId,
  required DateTime now,
  String Function()? newId,
}) {
  final makeId = newId ?? const Uuid().v4;
  if (bytes.length > maxImportFileBytes) {
    return const TaskImportResult(
      stages: [],
      problems: [ImportProblem('הקובץ גדול מ-5MB')],
    );
  }
  final Excel workbook;
  try {
    workbook = Excel.decodeBytes(bytes);
  } catch (_) {
    return const TaskImportResult(
      stages: [],
      problems: [ImportProblem(_unreadable)],
    );
  }

  final problems = <ImportProblem>[];
  final stageSheet = _findSheet(workbook, stagesSheetName);
  final taskSheet = _findSheet(workbook, tasksSheetName);
  if (stageSheet == null) {
    problems.add(const ImportProblem('חסר גיליון "$stagesSheetName"'));
  }
  if (taskSheet == null) {
    problems.add(const ImportProblem('חסר גיליון "$tasksSheetName"'));
  }
  if (stageSheet == null || taskSheet == null) {
    return TaskImportResult(stages: const [], problems: problems);
  }

  final stageTable =
      _Table.read(stageSheet, stagesSheetName, StageColumns.required, problems);
  final taskTable =
      _Table.read(taskSheet, tasksSheetName, TaskColumns.required, problems);
  if (stageTable == null || taskTable == null) {
    return TaskImportResult(stages: const [], problems: problems);
  }

  final days = eventDays(event);
  final drafts = <_StageDraft>[];
  final draftByNumber = <int, _StageDraft>{};
  final firstRowOfNumber = <int, int>{};

  for (final row in stageTable.rows) {
    void at(String message) => problems
        .add(ImportProblem(message, sheet: stagesSheetName, row: row.number));

    final number = _stageNumber(row, at);
    var isDuplicate = false;
    if (number != null) {
      final first = firstRowOfNumber[number];
      if (first != null) {
        at('מספר שלב $number מופיע פעמיים (גם בשורה $first)');
        isDuplicate = true;
      } else {
        firstRowOfNumber[number] = row.number;
      }
    }

    final title = row.text(StageColumns.title);
    if (title.isEmpty) {
      at('חסר שם לשלב');
    } else {
      _limit(title, 200, StageColumns.title, at);
    }
    final date = _readDate(row, days, at);
    final start = _readTime(row, StageColumns.start, at);
    final end = _readTime(row, StageColumns.end, at);
    if (end != null && row.text(StageColumns.start).isEmpty) {
      at('שעת סיום דורשת שעת התחלה');
    } else if (start != null && end != null && end.compareTo(start) <= 0) {
      at('שעת הסיום חייבת להיות אחרי שעת ההתחלה');
    }
    final requirements = row.text(StageColumns.requirements);
    _limit(requirements, 5000, StageColumns.requirements, at);
    final location = row.text(StageColumns.location);
    _limit(location, 200, StageColumns.location, at);
    final notes = row.text(StageColumns.notes);
    _limit(notes, 5000, StageColumns.notes, at);
    final contacts =
        parseContactCell(row.text(StageColumns.contacts), newId: makeId);
    contacts.problems.forEach(at);

    if (number == null || isDuplicate || title.isEmpty || date == null) {
      continue;
    }
    final draft = _StageDraft(Stage(
      id: makeId(),
      eventId: event.id,
      title: title,
      date: date,
      startTime: start,
      endTime: end,
      requirements: requirements,
      hotelLocation: location,
      notes: notes,
      contacts: contacts.contacts,
      createdAt: now,
      createdById: currentUserId,
      updatedAt: now,
    ));
    drafts.add(draft);
    draftByNumber[number] = draft;
  }

  if (stageTable.rows.isEmpty) {
    problems.add(
      const ImportProblem('אין שלבים בקובץ', sheet: stagesSheetName),
    );
  } else if (stageTable.rows.length > maxImportStages) {
    problems.add(ImportProblem(
      'בקובץ ${stageTable.rows.length} שלבים; אפשר לייבא עד $maxImportStages',
      sheet: stagesSheetName,
    ));
  }

  for (final row in taskTable.rows) {
    void at(String message) => problems
        .add(ImportProblem(message, sheet: tasksSheetName, row: row.number));

    final number = _stageNumber(row, at);
    if (number != null && !firstRowOfNumber.containsKey(number)) {
      at('מספר שלב $number לא קיים בגיליון "$stagesSheetName"');
    }
    final title = row.text(TaskColumns.title);
    if (title.isEmpty) {
      at('חסרה כותרת למשימה');
    } else {
      _limit(title, 200, TaskColumns.title, at);
    }
    final description = row.text(TaskColumns.description);
    _limit(description, 5000, TaskColumns.description, at);
    final assembly = _readTime(row, TaskColumns.assembly, at);

    final subtaskTitles = _pieces(row.text(TaskColumns.subtasks));
    if (subtaskTitles.length > 50) at('יותר מ-50 תתי משימות');
    for (final subtask in subtaskTitles) {
      if (subtask.length > 200) {
        at('תת המשימה "${subtask.substring(0, 20)}…" ארוכה מ-200 תווים');
      }
    }

    final written = _pieces(row.text(TaskColumns.assignees));
    // The backend refuses a task with nobody responsible for it.
    if (written.isEmpty) at('חסר אחראי למשימה');
    final assignees = <TeamMember>[];
    for (final name in written) {
      switch (matchAssignee(name, candidates)) {
        case AssigneeFound(:final member):
          if (!assignees.contains(member)) assignees.add(member);
        case AssigneeNotFound():
          at('"$name" אינו משובץ לאירוע');
        case AssigneeAmbiguous(:final members):
          at('"$name" תואם כמה משובצים: '
              '${members.map((member) => member.name).join(', ')}');
      }
    }

    final draft = number == null ? null : draftByNumber[number];
    if (draft == null || title.isEmpty) continue;
    draft.tasks.add(TaskItem(
      id: makeId(),
      eventId: event.id,
      stageId: draft.stage.id,
      title: title,
      description: description,
      subtasks: [
        for (final subtask in subtaskTitles)
          Subtask(id: makeId(), title: subtask),
      ],
      assemblyTime: assembly,
      assigneeIds: [for (final member in assignees) member.id],
      createdAt: now,
      createdById: currentUserId,
      updatedAt: now,
      event: event,
      stage: draft.stage,
      assignees: assignees,
    ));
  }

  if (taskTable.rows.length > maxImportTasks) {
    problems.add(ImportProblem(
      'בקובץ ${taskTable.rows.length} משימות; אפשר לייבא עד $maxImportTasks',
      sheet: tasksSheetName,
    ));
  }

  return TaskImportResult(
    stages: [
      for (final draft in drafts)
        ImportedStage(
          stage: draft.stage,
          tasks: List.unmodifiable(draft.tasks),
        ),
    ],
    problems: problems,
  );
}

class _StageDraft {
  _StageDraft(this.stage);

  final Stage stage;
  final List<TaskItem> tasks = [];
}

Sheet? _findSheet(Excel workbook, String name) {
  for (final entry in workbook.tables.entries) {
    if (cleanText(entry.key).trim() == name) return entry.value;
  }
  return null;
}

final RegExp _spaces = RegExp(r'\s+');
final RegExp _trailingColon = RegExp(r'\s*:\s*$');
// "אחראי/ים (כל אחד בכוכבית נפרדת בשורה נפרדת)": the hint is not the name.
final RegExp _trailingHint = RegExp(r'\s*\([^)]*\)\s*$');

String _header(String text) => text
    .replaceAll(_spaces, ' ')
    .replaceAll(_trailingHint, '')
    .replaceAll(_trailingColon, '')
    .trim();

/// A sheet's header row and the rows worth reading.
class _Table {
  _Table(this.rows);

  final List<_Row> rows;

  static _Table? read(
    Sheet sheet,
    String name,
    List<String> required,
    List<ImportProblem> problems,
  ) {
    final all = sheet.rows;
    final columns = <String, int>{};
    if (all.isNotEmpty) {
      for (var i = 0; i < all.first.length; i++) {
        final header = _header(cellText(all.first[i]?.value));
        if (header.isNotEmpty) columns.putIfAbsent(header, () => i);
      }
    }
    final missing = required.where((h) => !columns.containsKey(h)).toList();
    for (final header in missing) {
      problems.add(ImportProblem('חסרה עמודה "$header"', sheet: name, row: 1));
    }
    if (missing.isNotEmpty) return null;

    // A row whose only filled cell is the stage number is a placeholder.
    final numberColumn = columns[StageColumns.number];
    final rows = <_Row>[];
    for (var index = 1; index < all.length; index++) {
      final cells = all[index];
      var hasContent = false;
      for (var i = 0; i < cells.length; i++) {
        if (i != numberColumn && !isBlankCell(cells[i]?.value)) {
          hasContent = true;
          break;
        }
      }
      if (hasContent) rows.add(_Row(index + 1, cells, columns));
    }
    return _Table(rows);
  }
}

class _Row {
  _Row(this.number, this._cells, this._columns);

  /// The Excel row number, as the person sees it.
  final int number;
  final List<Data?> _cells;
  final Map<String, int> _columns;

  CellValue? operator [](String header) {
    final index = _columns[header];
    if (index == null || index >= _cells.length) return null;
    return _cells[index]?.value;
  }

  String text(String header) => cellText(this[header]);
}

int? _stageNumber(_Row row, void Function(String) at) {
  final text = row.text(StageColumns.number);
  if (text.isEmpty) {
    at('חסר מספר שלב');
    return null;
  }
  final number = cellWholeNumber(row[StageColumns.number]);
  if (number == null) at('מספר השלב "$text" אינו מספר שלם');
  return number;
}

DateTime? _readDate(_Row row, List<DateTime> days, void Function(String) at) {
  final text = row.text(StageColumns.date);
  if (text.isEmpty) {
    at('חסר תאריך');
    return null;
  }
  final date = cellDate(row[StageColumns.date]);
  if (date == null) {
    at('התאריך "$text" אינו תאריך תקין');
    return null;
  }
  if (!days.contains(date)) {
    final range = days.length == 1
        ? formatImportDay(days.single)
        : '${formatImportDay(days.first)} – ${formatImportDay(days.last)}';
    at('התאריך ${formatImportDay(date)} אינו מתאריכי האירוע ($range)');
    return null;
  }
  return date;
}

String? _readTime(_Row row, String header, void Function(String) at) {
  final text = row.text(header);
  if (text.isEmpty) return null;
  final time = cellTime(row[header]);
  if (time == null) at('"$header" אינה שעה תקינה: "$text"');
  return time;
}

void _limit(String text, int max, String header, void Function(String) at) {
  if (text.length > max) at('הטקסט בעמודה "$header" ארוך מ-$max תווים');
}

/// A list cell: one item per line, each optionally after a "*" bullet (the
/// official format), or items separated by `|`.
List<String> _pieces(String cell) => splitImportList(cleanText(cell));
