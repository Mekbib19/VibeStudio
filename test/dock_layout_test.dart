import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_studio/main.dart';
import 'package:vibe_studio/state/app_controller.dart';

void main() {
  testWidgets('dockable panels render and can be re-docked', (tester) async {
    final controller = AppController();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    controller.projectDir = '/tmp/opencode/docktest';
    controller.fileNodes = [];
    await tester.pumpWidget(VibeStudioApp(controller: controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Files'), findsWidgets);
    expect(find.text('Agents'), findsWidgets);
    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;

    // Terminal starts docked at the bottom (tab strip spans the full width).
    final termRect = tester.getRect(find.text('Terminal'));
    expect(termRect.left, lessThan(width * 0.5));
    expect(termRect.center.dy, greaterThan(height * 0.5));

    // Drag the terminal tab onto the right edge -> docks right.
    await _dragTo(tester, find.text('Terminal'), Offset(width - 10, termRect.center.dy));
    expect(tester.getRect(find.text('Terminal')).left, greaterThan(width * 0.5));

    // Todos starts on the right side; drag it onto the left edge.
    final todosRect = tester.getRect(find.text('Todos'));
    expect(todosRect.left, greaterThan(width * 0.5));
    await _dragTo(tester, find.text('Todos'), Offset(10, todosRect.center.dy));
    expect(tester.getRect(find.text('Todos')).left, lessThan(width * 0.5));

    // Logs starts on the right; drag it onto the bottom edge.
    final logsRect = tester.getRect(find.text('Logs'));
    expect(logsRect.left, greaterThan(width * 0.5));
    await _dragTo(tester, find.text('Logs'), Offset(width / 2, height - 10));
    final logsRect2 = tester.getRect(find.text('Logs'));
    expect(logsRect2.left, lessThan(width * 0.5));
    expect(logsRect2.center.dy, greaterThan(height * 0.5));

    controller.dispose();
  });

  testWidgets('panels can be docked into the center as tabs', (tester) async {
    final controller = AppController();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    controller.projectDir = '/tmp/opencode/docktest';
    controller.fileNodes = [];
    await tester.pumpWidget(VibeStudioApp(controller: controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;

    // Logs starts docked on the right (tab near the bottom of the window).
    expect(tester.getRect(find.text('Logs')).center.dy, greaterThan(height * 0.5));

    // Drag the Logs tab into the center -> opens as a center tab near the top.
    await _dragTo(tester, find.text('Logs'), Offset(width / 2, height / 2));
    final logsRect = tester.getRect(find.text('Logs'));
    expect(logsRect.center.dx, greaterThan(width * 0.25));
    expect(logsRect.center.dx, lessThan(width * 0.75));
    expect(logsRect.center.dy, lessThan(height * 0.2));

    // The panel body moved into the center alongside the tab: its header is
    // left-aligned at the start of the center column (it used to sit far
    // right, in the right-hand dock).
    expect(find.text('System Log'), findsOneWidget);
    expect(tester.getRect(find.text('System Log')).center.dx,
        lessThan(width * 0.5));

    // The Logs center tab can be dragged back out onto an edge.
    await _dragTo(tester, find.text('Logs'), Offset(10, logsRect.center.dy));
    expect(tester.getRect(find.text('Logs')).left, lessThan(width * 0.5));

    controller.dispose();
  });
}

/// Starts a gesture on [from], drags it to [to] in small steps so the drag
/// recognizer and drop zones register it, then releases.
Future<void> _dragTo(WidgetTester tester, Finder from, Offset to) async {
  final start = tester.getCenter(from);
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 50));
  const steps = 10;
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    await gesture.moveTo(Offset.lerp(start, to, t)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}
