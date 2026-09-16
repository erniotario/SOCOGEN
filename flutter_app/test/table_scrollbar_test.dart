import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:socogen/shared/ui/theme/app_theme.dart';
import 'package:socogen/shared/ui/widgets/adaptive_table.dart';

/// Guards the scrollbar on the pages that own their scroll — Produits
/// and the wide layout of Rapports.
///
/// Those build a plain [AdaptiveTable], which scrolls inside its own
/// `ListView`. The list is `primary: false`, so it runs on a controller
/// it creates itself; a `Scrollbar` given no controller falls back to
/// the *primary* one and therefore drives nothing. The thumb still
/// paints from scroll notifications, so the defect only shows when you
/// try to grab it — and on a 655-product catalogue an ungrabbable thumb
/// leaves the wheel as the only way down.
AdaptiveTable _table(int count) => AdaptiveTable(
      columns: const [
        AppColumn('RÉFÉRENCE'),
        AppColumn('DÉSIGNATION'),
        AppColumn.number('STOCK'),
      ],
      rows: [
        for (var i = 0; i < count; i++)
          AppRow(
            cells: [
              Cells.identifier('REF$i'),
              Cells.text('Produit $i'),
              Cells.number(i),
            ],
          ),
      ],
    );

/// [AppTheme.dark] bakes its `scrollbarTheme` from `defaultTargetPlatform`,
/// and widget tests run as Android — where the thumb is deliberately
/// faded and non-interactive. Build the theme under a desktop override
/// so the test exercises the platform this app ships on, then clear the
/// override immediately: `flutter_test` asserts that no foundation debug
/// variable outlives the test body.
ThemeData _desktopTheme() {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  final theme = AppTheme.dark;
  debugDefaultTargetPlatformOverride = null;
  return theme.copyWith(platform: TargetPlatform.windows);
}

Future<void> _pump(WidgetTester tester, Size size, int rows) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: _desktopTheme(),
      home: Scaffold(body: _table(rows)),
    ),
  );
  await tester.pump();
}

void main() {
  group('AdaptiveTable scrollbar', () {
    testWidgets('is the only one in the track', (tester) async {
      await _pump(tester, const Size(1280, 800), 500);

      // MaterialScrollBehavior fits desktop scroll views with a scrollbar
      // of their own; stacked on ours that puts two thumbs in one track.
      expect(find.byType(Scrollbar), findsOneWidget);
    });

    testWidgets('shares a controller with the list it scrolls',
        (tester) async {
      await _pump(tester, const Size(1280, 800), 500);

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      final list = tester.widget<ListView>(find.byType(ListView));

      expect(
        scrollbar.controller,
        isNotNull,
        reason: 'a Scrollbar with no controller cannot be dragged',
      );
      expect(
        list.controller,
        same(scrollbar.controller),
        reason: 'thumb and list must move the same ScrollPosition',
      );
    });

    testWidgets('thumb drags the list', (tester) async {
      await _pump(tester, const Size(1280, 800), 500);

      final controller =
          tester.widget<Scrollbar>(find.byType(Scrollbar)).controller!;
      expect(controller.offset, 0);

      // The thumb only becomes hit-testable once it has been painted.
      await tester.pump(const Duration(milliseconds: 100));

      // 500 rows against a ~760px viewport park the thumb just under the
      // header, in the rightmost ~9px. The thumb drag runs on a
      // press-and-hold recogniser, so the gesture has to settle before
      // it moves.
      final gesture = await tester.startGesture(
        const Offset(1274, 48),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(const Offset(0, 250));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        greaterThan(0),
        reason: 'dragging the thumb should scroll the catalogue',
      );
    });
  });
}
