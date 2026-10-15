import '../../../domain/entities/team_member.dart';
import '../search_utils.dart';
import 'cell_values.dart';

/// Matching a name written in an import file to one of the members assigned
/// to the event.

sealed class AssigneeMatch {
  const AssigneeMatch();
}

class AssigneeFound extends AssigneeMatch {
  const AssigneeFound(this.member);
  final TeamMember member;
}

class AssigneeNotFound extends AssigneeMatch {
  const AssigneeNotFound();
}

class AssigneeAmbiguous extends AssigneeMatch {
  const AssigneeAmbiguous(this.members);
  final List<TeamMember> members;
}

/// An exact full name first. Otherwise a member matches when every word of
/// [written] is a whole word of their name; exactly one such member is a
/// match, more than one is ambiguous.
AssigneeMatch matchAssignee(String written, List<TeamMember> candidates) {
  final words = _words(written);
  if (words.isEmpty) return const AssigneeNotFound();
  final key = words.join(' ');

  final exact = candidates
      .where((member) => _words(member.name).join(' ') == key)
      .toList();
  if (exact.length == 1) return AssigneeFound(exact.single);
  if (exact.length > 1) return AssigneeAmbiguous(exact);

  final partial = candidates.where((member) {
    final nameWords = _words(member.name).toSet();
    return words.every(nameWords.contains);
  }).toList();
  if (partial.length == 1) return AssigneeFound(partial.single);
  if (partial.isEmpty) return const AssigneeNotFound();
  return AssigneeAmbiguous(partial);
}

final RegExp _whitespace = RegExp(r'\s+');

List<String> _words(String text) => normalizeForSearch(
      cleanText(text).replaceAll(_whitespace, ' '),
    ).toLowerCase().split(' ').where((word) => word.isNotEmpty).toList();
