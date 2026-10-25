import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/search_utils.dart';

void main() {
  group('nameMatchesSearch', () {
    test('empty or blank query matches every name', () {
      expect(nameMatchesSearch('אבי אסרף', ''), isTrue);
      expect(nameMatchesSearch('אבי אסרף', '   '), isTrue);
    });

    test('matches a part of the name', () {
      expect(nameMatchesSearch('אבי אסרף', 'אסר'), isTrue);
      expect(nameMatchesSearch('אבי אסרף', 'לוי'), isFalse);
    });

    test('ignores punctuation such as geresh', () {
      expect(nameMatchesSearch("ג'ורג' כהן", 'גורג'), isTrue);
      expect(nameMatchesSearch('גורג כהן', "ג'ורג"), isTrue);
    });

    test('is case-insensitive', () {
      expect(nameMatchesSearch('Dana Levi', 'dana'), isTrue);
    });
  });
}
