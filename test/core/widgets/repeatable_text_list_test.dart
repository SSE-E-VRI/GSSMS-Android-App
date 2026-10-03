import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/repeatable_text_list.dart';

void main() {
  late List<String> latest;

  Future<GlobalKey<RepeatableTextListState>> pump(
    WidgetTester tester, {
    List<String> initial = const [],
  }) async {
    latest = List.of(initial);
    final key = GlobalKey<RepeatableTextListState>();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Column(
          children: [
            RepeatableTextList(
              key: key,
              keyPrefix: 'r',
              label: 'Remarks',
              initial: initial,
              onChanged: (v) => latest = v,
            ),
            const TextField(key: Key('other')),
          ],
        ),
      ),
    ));
    return key;
  }

  testWidgets('add and remove entries', (tester) async {
    await pump(tester, initial: ['first']);
    expect(find.text('1. first'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('r_field')), 'second');
    await tester.tap(find.byKey(const Key('r_add')));
    await tester.pump();
    expect(find.text('2. second'), findsOneWidget);
    expect(latest, ['first', 'second']);

    await tester.tap(find.byKey(const Key('r_remove_0')));
    await tester.pump();
    expect(latest, ['second']);
    expect(find.text('1. second'), findsOneWidget);
  });

  testWidgets('typed text is committed on blur', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('r_field')));
    await tester.enterText(find.byKey(const Key('r_field')), 'typed');
    await tester.pump();
    expect(latest, isEmpty);

    await tester.tap(find.byKey(const Key('other')));
    await tester.pump();
    expect(latest, ['typed']);
    expect(find.text('1. typed'), findsOneWidget);
  });

  testWidgets('commitPending returns the full list', (tester) async {
    final key = await pump(tester, initial: ['a']);
    await tester.enterText(find.byKey(const Key('r_field')), 'b');
    expect(key.currentState!.commitPending(), ['a', 'b']);
    await tester.pump();
    expect(latest, ['a', 'b']);
  });
}
