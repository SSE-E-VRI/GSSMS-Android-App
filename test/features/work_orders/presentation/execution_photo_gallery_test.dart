import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/execution_photo_gallery.dart';

void main() {
  testWidgets('viewer includes other lines in the same group', (tester) async {
    const before = ExecutionPhoto(id: 1, kind: 'BEFORE');
    const after = ExecutionPhoto(id: 2, kind: 'AFTER');
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: ExecutionPhotoGallery(
        maxPerKind: 5,
        photos: [before],
        galleryPhotos: [before, after],
      )),
    ));
    expect(find.byKey(const Key('preview_exec_photo_2')), findsNothing);
    await tester.tap(find.byKey(const Key('preview_exec_photo_1')));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('execution_photo_pager')), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.text('After · Photo #2'), findsOneWidget);
    expect(find.text('2 / 2 · Swipe left or right'), findsOneWidget);
  });

  testWidgets('photos form a grid and swipe across the before/after boundary',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: ExecutionPhotoGallery(
        maxPerKind: 5,
        photos: [
          ExecutionPhoto(id: 4, kind: 'AFTER'),
          ExecutionPhoto(id: 1, kind: 'BEFORE'),
          ExecutionPhoto(id: 2, kind: 'BEFORE'),
          ExecutionPhoto(id: 3, kind: 'BEFORE'),
          ExecutionPhoto(id: 5, kind: 'AFTER'),
        ],
      ))),
    ));
    final first =
        tester.getTopLeft(find.byKey(const Key('preview_exec_photo_1')));
    final second =
        tester.getTopLeft(find.byKey(const Key('preview_exec_photo_2')));
    expect(first.dy, second.dy);
    expect(second.dx, greaterThan(first.dx));
    expect(find.text('Before photos (3/5)'), findsOneWidget);
    expect(find.text('After photos (2/5)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('preview_exec_photo_3')));
    await tester.pumpAndSettle();
    expect(find.text('Before · Photo #3'), findsOneWidget);
    expect(find.text('3 / 5 · Swipe left or right'), findsOneWidget);
    await tester.drag(
        find.byKey(const Key('execution_photo_pager')), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('After · Photo #4'), findsOneWidget);
    expect(find.text('4 / 5 · Swipe left or right'), findsOneWidget);
    await tester.drag(
        find.byKey(const Key('execution_photo_pager')), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Before · Photo #3'), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('execution_photo_grid_BEFORE')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
