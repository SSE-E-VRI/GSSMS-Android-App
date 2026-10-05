import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'pdf_layout_probe.dart';

Uint8List _pdf(String body) =>
    Uint8List.fromList(latin1.encode('%PDF-1.4\n$body\ntrailer<</Root 1 0 R>>'));

void main() {
  test('probe decodes words, rects and lines', () {
    final bytes = _pdf('''
1 0 obj
<</Type/Catalog/Pages 2 0 R>>
endobj
2 0 obj
<</Type/Pages/Kids[3 0 R]/Count 1>>
endobj
3 0 obj
<</Type/Page/Parent 2 0 R/Resources<</Font<</F1 5 0 R>>>>/MediaBox[0 0 100 100]/Contents 4 0 R>>
endobj
5 0 obj
<</Type/Font/Subtype/Type1/BaseFont/Helvetica/ToUnicode 6 0 R>>
endobj
6 0 obj
<</Length 80>>
stream
1 begincodespacerange<00> <FF>endcodespacerange
5 beginbfchar<48> <0048><65> <0065><6C> <006C><6F> <006F>endbfchar
endstream
endobj
4 0 obj
<</Length 120>>
stream
BT /F1 12 Tf 1 0 0 rg 10 20 Td <48656C6C6F> Tj ET
0 0 1 RG 2 w 5 5 m 10 10 l S
7 8 20 4 re f
endstream
endobj''');
    final snap = probePdfLayout(bytes);
    final words = snap['words'] as List;
    expect(words.length, 1);
    expect(words.first['text'], 'Hello');
    expect(words.first['x'], 10.0);
    expect(words.first['y'], 20.0);
    expect(words.first['font'], 'Helvetica');
    expect(words.first['size'], 12.0);
    expect(words.first['color'], '#ff0000');
    final lines = snap['lines'] as List;
    expect(lines.length, 1);
    expect(lines.first['stroke'], '#0000ff');
    final rects = snap['rects'] as List;
    expect(rects.length, 1);
    expect(rects.first['w'], 20.0);
  });
}
