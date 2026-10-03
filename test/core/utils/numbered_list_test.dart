import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/utils/numbered_list.dart';

void main() {
  test('join numbers items and empty list joins to empty string', () {
    expect(joinNumberedList(['first', 'second']), '1. first\n2. second');
    expect(joinNumberedList(const []), '');
  });

  test('split round-trips a joined list', () {
    const items = ['first', 'second', 'third'];
    expect(splitNumberedList(joinNumberedList(items)), items);
  });

  test('split strips prefixes and drops blank lines', () {
    expect(splitNumberedList('  1. a\n\n 2.   b  \n'), ['a', 'b']);
  });

  test('legacy paragraph stays a single item', () {
    expect(splitNumberedList('Replaced fuse.\nChecked wiring.'),
        ['Replaced fuse.\nChecked wiring.']);
    expect(splitNumberedList('1. only first numbered\nplain'),
        ['1. only first numbered\nplain']);
  });

  test('null and empty give an empty list', () {
    expect(splitNumberedList(null), isEmpty);
    expect(splitNumberedList('   '), isEmpty);
  });
}
