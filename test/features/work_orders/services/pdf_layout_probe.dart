// Probe: parses an UNCOMPRESSED report PDF (built with compress: false)
// into canonical layout geometry for golden comparison.
//
// Our pdf output is highly regular: every text span is an explicitly
// positioned single-TJ `BT...ET` block, borders are filled rects, and fonts
// carry ToUnicode CMaps — so a small tokenizer plus graphics/text state
// tracking fully captures layout without a general PDF engine.
//
// Canonical JSON: per fixture {words, rects, lines}; geometry rounded to
// 0.01pt. Words: text (ToUnicode-decoded), baseline x/y, font (BaseFont),
// size, colour. Rects/lines: user-space boxes/segments with colours.
library;

import 'dart:convert';
import 'dart:typed_data';

double _r2(double v) => (v * 100).round() / 100;

String _hexColor(List<double> rgb) {
  String h(double c) =>
      (c * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${h(rgb[0])}${h(rgb[1])}${h(rgb[2])}';
}

/// 2D affine matrix [a b c d e f] (PDF row-vector convention).
class _M {
  _M(this.a, this.b, this.c, this.d, this.e, this.f);
  double a, b, c, d, e, f;

  _M mul(_M m) => _M(
        a * m.a + b * m.c,
        a * m.b + b * m.d,
        c * m.a + d * m.c,
        c * m.b + d * m.d,
        e * m.a + f * m.c + m.e,
        e * m.b + f * m.d + m.f,
      );

  List<double> apply(double x, double y) =>
      [a * x + c * y + e, b * x + d * y + f];

  _M clone() => _M(a, b, c, d, e, f);
}

class _GState {
  _M ctm = _M(1, 0, 0, 1, 0, 0);
  List<double> fill = [0, 0, 0];
  List<double> stroke = [0, 0, 0];
  double lineWidth = 1;
  String fontRes = '';
  double fontSize = 0;
  _M line = _M(1, 0, 0, 1, 0, 0);

  _GState clone() {
    final g = _GState();
    g.ctm = ctm.clone();
    g.fill = List.of(fill);
    g.stroke = List.of(stroke);
    g.lineWidth = lineWidth;
    g.fontRes = fontRes;
    g.fontSize = fontSize;
    g.line = line.clone();
    return g;
  }
}

sealed class _Tok {}

class _Num extends _Tok {
  _Num(this.v);
  final double v;
}

class _Name extends _Tok {
  _Name(this.v);
  final String v;
}

class _Hex extends _Tok {
  _Hex(this.v);
  final String v;
}

class _Lit extends _Tok {
  _Lit(this.v);
  final String v;
}

class _Op extends _Tok {
  _Op(this.v);
  final String v;
}

class _Arr extends _Tok {
  _Arr(this.v);
  final List<_Tok> v;
}

List<_Tok> _tokenize(String s) {
  final out = <_Tok>[];
  var i = 0;
  bool isDelim(String c) => ' \t\n\r\f()<>[]{}/%'.contains(c);
  while (i < s.length) {
    final c = s[i];
    if (c == '%') {
      while (i < s.length && s[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c.trim().isEmpty) {
      i++;
      continue;
    }
    if (c == '<' && i + 1 < s.length && s[i + 1] == '<') {
      i += 2;
      continue;
    }
    if (c == '>' && i + 1 < s.length && s[i + 1] == '>') {
      i += 2;
      continue;
    }
    if (c == '<') {
      final j = s.indexOf('>', i);
      out.add(_Hex(s.substring(i + 1, j < 0 ? s.length : j)));
      i = j < 0 ? s.length : j + 1;
      continue;
    }
    if (c == '(') {
      final buf = StringBuffer();
      var depth = 0;
      i++;
      while (i < s.length) {
        final d = s[i];
        if (d == '\\' && i + 1 < s.length) {
          buf.write(s[i + 1]);
          i += 2;
          continue;
        }
        if (d == '(') depth++;
        if (d == ')') {
          if (depth == 0) break;
          depth--;
        }
        buf.write(d);
        i++;
      }
      out.add(_Lit(buf.toString()));
      i++;
      continue;
    }
    if (c == '[') {
      var depth = 0;
      final start = i;
      while (i < s.length) {
        if (s[i] == '[') depth++;
        if (s[i] == ']') {
          depth--;
          if (depth == 0) break;
        }
        if (s[i] == '<' && !(i + 1 < s.length && s[i + 1] == '<')) {
          final j = s.indexOf('>', i);
          i = j < 0 ? s.length : j;
        } else if (s[i] == '(') {
          var dd = 0;
          i++;
          while (i < s.length) {
            if (s[i] == '\\') {
              i += 2;
              continue;
            }
            if (s[i] == '(') dd++;
            if (s[i] == ')') {
              if (dd == 0) break;
              dd--;
            }
            i++;
          }
        }
        i++;
      }
      final inner = s.substring(start + 1, i);
      i++;
      out.add(_Arr(_tokenize(inner)));
      continue;
    }
    if (c == '/') {
      var j = i + 1;
      while (j < s.length && !isDelim(s[j])) {
        j++;
      }
      out.add(_Name(s.substring(i + 1, j)));
      i = j;
      continue;
    }
    final numRe = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)');
    final m = numRe.firstMatch(s.substring(i));
    if (m != null) {
      out.add(_Num(double.parse(m.group(0)!)));
      i += m.group(0)!.length;
      continue;
    }
    var j = i;
    while (j < s.length && !isDelim(s[j]) && s[j] != '[' && s[j] != ']') {
      j++;
    }
    if (j > i) {
      final word = s.substring(i, j);
      if (word != 'true' && word != 'false' && word != 'null') {
        out.add(_Op(word));
      }
    }
    i = j;
  }
  return out;
}

/// Parses object `num`'s body from the raw file text (text-only objects).
String? _objBody(String src, int num) {
  final m = RegExp('\\b$num 0 obj\\r?\\n(.*?)endobj', dotAll: true)
      .firstMatch(src);
  return m?.group(1);
}

/// Canonical layout snapshot of an uncompressed PDF.
Map<String, dynamic> probePdfLayout(Uint8List bytes) {
  final src = latin1.decode(bytes);

  // --- fonts: resource -> object, object -> base name, ToUnicode maps ---
  final resFonts = <String, int>{};
  final baseFonts = <int, String>{};
  final cmaps = <int, Map<int, String>>{};
  final codeLens = <int, int>{};
  final pageObjs = <int>[];
  for (final m
      in RegExp(r'\b(\d+) 0 obj(.*?)endobj', dotAll: true).allMatches(src)) {
    final num = int.parse(m.group(1)!);
    final body = m.group(2)!;
    if (RegExp(r'/Type\s*/Page([^s]|$)').hasMatch(body)) {
      pageObjs.add(num);
      // Resource names are plain tokens; the character class keeps `/F`
      // inside `/Font` from matching.
      for (final f
          in RegExp(r'/F([A-Za-z0-9+\-]+)\s+(\d+) 0 R').allMatches(body)) {
        resFonts['F${f.group(1)}'] = int.parse(f.group(2)!);
      }
    }
    final base = RegExp(r'/BaseFont\s*/([A-Za-z0-9+\-]+)').firstMatch(body);
    if (base != null) baseFonts[num] = base.group(1)!;
    if (body.contains('beginbfchar') || body.contains('beginbfrange')) {
      final parsed = _parseCMap(body);
      cmaps[num] = parsed.map;
      codeLens[num] = parsed.codeLen;
    }
  }
  // ToUnicode object -> owning font object.
  final cmapOwner = <int, int>{};
  for (final m in RegExp(r'\b(\d+) 0 obj(.*?)endobj', dotAll: true)
      .allMatches(src)) {
    final num = int.parse(m.group(1)!);
    final body = m.group(2)!;
    for (final t in RegExp(r'/ToUnicode\s+(\d+)').allMatches(body)) {
      cmapOwner[int.parse(t.group(1)!)] = num;
    }
  }

  int _cmapForRes(String res) {
    final obj = resFonts[res] ?? -1;
    for (final e in cmapOwner.entries) {
      if (e.value == obj) return e.key;
    }
    return obj;
  }

  String decodeForRes(String res, String hex) {
    final cmapObj = _cmapForRes(res);
    final cmap = cmaps[cmapObj];
    final clean = hex.replaceAll(RegExp(r'\s'), '');
    if (cmap == null || cmap.isEmpty || clean.isEmpty) return '?$clean?';
    final width = codeLens[cmapObj] ?? 4;
    final buf = StringBuffer();
    for (var i = 0; i + width <= clean.length; i += width) {
      final code = int.tryParse(clean.substring(i, i + width), radix: 16);
      final uni = code == null ? null : cmap[code];
      buf.write(uni ?? '?');
    }
    return buf.toString();
  }

  String fontBase(String res) {
    final obj = resFonts[res] ?? -1;
    return baseFonts[obj] ?? res;
  }

  final words = <Map<String, dynamic>>[];
  final rects = <Map<String, dynamic>>[];
  final lines = <Map<String, dynamic>>[];

  // --- walk content streams in page order ---
  for (var page = 0; page < pageObjs.length; page++) {
    final body = _objBody(src, pageObjs[page]) ?? '';
    var contents = <int>[];
    final arr =
        RegExp(r'/Contents\s*\[([^\]]*)\]').firstMatch(body)?.group(1) ?? '';
    for (final r in RegExp(r'(\d+) 0 R').allMatches(arr)) {
      contents.add(int.parse(r.group(1)!));
    }
    if (contents.isEmpty) {
      final single =
          RegExp(r'/Contents\s+(\d+) 0 R').firstMatch(body)?.group(1);
      if (single != null) contents = [int.parse(single)];
    }
    var stack = <_GState>[];
    var g = _GState();
    var inText = false;
    final btText = StringBuffer();
    var btFont = '';
    var btSize = 0.0;
    var btColor = '#000000';
    var btX = 0.0;
    var btY = 0.0;
    var btHasPos = false;
    var path = <List<double>>[];
    List<double>? pendingRect;

    void flushText() {
      final t = btText.toString();
      if (t.isNotEmpty && btHasPos) {
        words.add({
          'page': page,
          'text': t,
          'x': _r2(btX),
          'y': _r2(btY),
          'font': fontBase(btFont),
          'size': _r2(btSize),
          'color': btColor,
        });
      }
      btText.clear();
      btHasPos = false;
    }

    void paintShapes({required bool fill, required bool stroke}) {
      if (pendingRect != null) {
        final r = pendingRect!;
        rects.add({
          'page': page,
          'x': _r2(r[0]),
          'y': _r2(r[1]),
          'w': _r2(r[2] - r[0]),
          'h': _r2(r[3] - r[1]),
          if (fill) 'fill': _hexColor(g.fill),
          if (stroke) 'stroke': _hexColor(g.stroke),
          if (stroke) 'width': _r2(g.lineWidth),
        });
      } else if (path.length >= 2) {
        if (fill) {
          var x0 = path.first[0], y0 = path.first[1];
          var x1 = x0, y1 = y0;
          for (final p in path) {
            if (p[0] < x0) x0 = p[0];
            if (p[1] < y0) y0 = p[1];
            if (p[0] > x1) x1 = p[0];
            if (p[1] > y1) y1 = p[1];
          }
          rects.add({
            'page': page,
            'x': _r2(x0),
            'y': _r2(y0),
            'w': _r2(x1 - x0),
            'h': _r2(y1 - y0),
            'fill': _hexColor(g.fill),
          });
        }
        if (stroke) {
          for (var i = 0; i + 1 < path.length; i++) {
            if ((path[i][0] - path[i + 1][0]).abs() < 1e-9 &&
                (path[i][1] - path[i + 1][1]).abs() < 1e-9) {
              continue;
            }
            lines.add({
              'page': page,
              'x1': _r2(path[i][0]),
              'y1': _r2(path[i][1]),
              'x2': _r2(path[i + 1][0]),
              'y2': _r2(path[i + 1][1]),
              'stroke': _hexColor(g.stroke),
              'width': _r2(g.lineWidth),
            });
          }
        }
      }
      pendingRect = null;
      path = [];
    }

    for (final ref in contents) {
      final streamBody = _objBody(src, ref) ?? '';
      final sm = RegExp(r'stream\r?\n(.*)endstream', dotAll: true)
          .firstMatch(streamBody);
      if (sm == null) continue;
      final dict = streamBody.substring(0, sm.start);
      if (dict.contains('/Subtype/Image') ||
          dict.contains('/Subtype /Image') ||
          dict.contains('/Length1')) {
        continue;
      }
      final toks = _tokenize(sm.group(1)!);
      final args = <_Tok>[];
      for (final t in toks) {
        if (t is _Op) {
          final op = t.v;
          List<double> nums() =>
              args.whereType<_Num>().map((e) => e.v).toList();
          switch (op) {
            case 'q':
              stack.add(g.clone());
            case 'Q':
              if (stack.isNotEmpty) g = stack.removeLast();
            case 'cm':
              final n = nums();
              if (n.length >= 6) {
                g.ctm = g.ctm.mul(_M(n[0], n[1], n[2], n[3], n[4], n[5]));
              }
            case 'rg':
              final n = nums();
              if (n.length >= 3) g.fill = [n[0], n[1], n[2]];
            case 'RG':
              final n = nums();
              if (n.length >= 3) g.stroke = [n[0], n[1], n[2]];
            case 'g':
              final n = nums();
              if (n.isNotEmpty) g.fill = [n[0], n[0], n[0]];
            case 'G':
              final n = nums();
              if (n.isNotEmpty) g.stroke = [n[0], n[0], n[0]];
            case 'w':
              final n = nums();
              if (n.isNotEmpty) g.lineWidth = n[0];
            case 'BT':
              inText = true;
              g.line = _M(1, 0, 0, 1, 0, 0);
              btText.clear();
              btHasPos = false;
            case 'ET':
              flushText();
              inText = false;
            case 'Tf':
              if (args.length >= 2 &&
                  args[args.length - 2] is _Name &&
                  args[args.length - 1] is _Num) {
                g.fontRes = (args[args.length - 2] as _Name).v;
                g.fontSize = (args[args.length - 1] as _Num).v;
              }
            case 'Td':
            case 'TD':
              final n = nums();
              if (n.length >= 2) {
                g.line = g.line
                    .mul(_M(1, 0, 0, 1, n[n.length - 2], n[n.length - 1]));
              }
            case 'Tm':
              final n = nums();
              if (n.length >= 6) {
                g.line = _M(n[0], n[1], n[2], n[3], n[4], n[5]);
              }
            case 'T*':
              g.line = g.line.mul(_M(1, 0, 0, 1, 0, 0));
            case 'Tj':
              if (inText && args.isNotEmpty) {
                final a = args.last;
                final s = a is _Hex
                    ? decodeForRes(g.fontRes, a.v)
                    : a is _Lit
                        ? a.v
                        : '';
                if (s.isNotEmpty) {
                  if (!btHasPos) {
                    final p = g.ctm.apply(g.line.e, g.line.f);
                    btX = p[0];
                    btY = p[1];
                    btFont = g.fontRes;
                    btSize = g.fontSize;
                    btColor = _hexColor(g.fill);
                    btHasPos = true;
                  }
                  btText.write(s);
                }
              }
            case 'TJ':
              if (inText && args.isNotEmpty && args.last is _Arr) {
                for (final e in (args.last as _Arr).v) {
                  String s = '';
                  if (e is _Hex) {
                    s = decodeForRes(g.fontRes, e.v);
                  } else if (e is _Lit) {
                    s = e.v;
                  }
                  if (s.isEmpty) continue;
                  if (!btHasPos) {
                    final p = g.ctm.apply(g.line.e, g.line.f);
                    btX = p[0];
                    btY = p[1];
                    btFont = g.fontRes;
                    btSize = g.fontSize;
                    btColor = _hexColor(g.fill);
                    btHasPos = true;
                  }
                  btText.write(s);
                }
              }
            case 're':
              final n = nums();
              if (n.length >= 4) {
                final p1 = g.ctm.apply(n[0], n[1]);
                final p2 = g.ctm.apply(n[0] + n[2], n[1] + n[3]);
                pendingRect = [p1[0], p1[1], p2[0], p2[1]];
                path = [];
              }
            case 'm':
              final n = nums();
              if (n.length >= 2) {
                final p = g.ctm.apply(n[0], n[1]);
                path.add([p[0], p[1]]);
              }
            case 'l':
              final n = nums();
              if (n.length >= 2) {
                final p = g.ctm.apply(n[0], n[1]);
                path.add([p[0], p[1]]);
              }
            case 'h':
              if (path.isNotEmpty) path.add(List.of(path.first));
            case 'f':
            case 'F':
              paintShapes(fill: true, stroke: false);
            case 'S':
            case 's':
              paintShapes(fill: false, stroke: true);
            case 'B':
            case 'b':
              paintShapes(fill: true, stroke: true);
            case 'n':
              pendingRect = null;
              path = [];
            default:
              break;
          }
          args.clear();
        } else {
          args.add(t);
        }
      }
      if (inText) {
        flushText();
        inText = false;
      }
    }
  }

  return {
    'words': words,
    'rects': rects,
    'lines': lines,
  };
}

class _CMap {
  _CMap(this.map, this.codeLen);
  final Map<int, String> map;
  final int codeLen;
}

/// Parses a ToUnicode CMap body into code -> string plus code width.
_CMap _parseCMap(String body) {
  final map = <int, String>{};
  var codeLen = 4;
  final csr = RegExp(r'begincodespacerange\s*<([0-9A-Fa-f]+)>')
      .firstMatch(body);
  if (csr != null) {
    codeLen = csr.group(1)!.length;
    if (codeLen.isOdd) codeLen++;
  }

  String dehex(String h) {
    final clean = h.replaceAll(RegExp(r'\s'), '');
    final buf = StringBuffer();
    for (var i = 0; i + 4 <= clean.length; i += 4) {
      final cp = int.tryParse(clean.substring(i, i + 4), radix: 16) ?? 0;
      buf.writeCharCode(cp);
    }
    return buf.toString();
  }

  // bfchar blocks hold exact pairs only.
  for (final block in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true)
      .allMatches(body)) {
    for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
        .allMatches(block.group(1)!)) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      if (code != null) map[code] = dehex(m.group(2)!);
    }
  }
  // bfrange blocks hold range triples.
  for (final block in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true)
      .allMatches(body)) {
    final text = block.group(1)!;
    // Array destinations first.
    for (final m in RegExp(
            r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[((?:\s*<[0-9A-Fa-f]+>)+)\s*\]')
        .allMatches(text)) {
      final start = int.tryParse(m.group(1)!, radix: 16) ?? 0;
      final arr = RegExp(r'<([0-9A-Fa-f]+)>')
          .allMatches(m.group(3)!)
          .map((e) => e.group(1)!)
          .toList();
      for (var i = 0; i < arr.length; i++) {
        map[start + i] = dehex(arr[i]);
      }
    }
    // Single-destination ranges (skip ones already covered by arrays).
    final arraySpans = RegExp(
            r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[((?:\s*<[0-9A-Fa-f]+>)+)\s*\]')
        .allMatches(text)
        .toList();
    bool inArray(int offset) =>
        arraySpans.any((a) => offset >= a.start && offset < a.end);
    for (final m in RegExp(
            r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
        .allMatches(text)) {
      if (inArray(m.start)) continue;
      final start = int.tryParse(m.group(1)!, radix: 16) ?? 0;
      final end = int.tryParse(m.group(2)!, radix: 16) ?? -1;
      final clean = m.group(3)!;
      if (end >= start && clean.length == 4) {
        final base = int.tryParse(clean, radix: 16) ?? 0;
        for (var c = start; c <= end; c++) {
          map.putIfAbsent(c, () => String.fromCharCode(base + (c - start)));
        }
      }
    }
  }
  return _CMap(map, codeLen);
}

/// Canonical JSON string of [probePdfLayout] (0.01 rounding at record time).
String probeLayoutJson(Uint8List bytes) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(probePdfLayout(bytes))}\n';
}
