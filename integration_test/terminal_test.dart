import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vibe_studio/state/app_controller.dart';
import 'package:vibe_studio/ui/home.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('embedded terminal starts a shell and runs freebuff + opencode',
      (tester) async {
    final controller = AppController();
    final dir = Directory.systemTemp.createTempSync('vsterm');
    await controller.openProjectAt(dir.path);
    await tester.pumpWidget(MaterialApp(home: HomePage(controller: controller)));
    await tester.pump(const Duration(seconds: 1));

    await controller.terminal.ensureStarted();
    await tester.pump(const Duration(seconds: 2));

    expect(controller.terminal.isRunning, isTrue,
        reason: 'bash shell should be running in the embedded terminal');

    // freebuff is a full TUI; it should render (produce output) without
    // throwing inside the xterm widget.
    controller.terminal.write('freebuff\n');
    await tester.pump(const Duration(seconds: 4));

    // kill the TUI, then exercise `opencode serve --port` as the user would.
    controller.terminal.write('\x03');
    await tester.pump(const Duration(milliseconds: 500));
    controller.terminal.write('opencode serve --port 4119\n');
    await tester.pump(const Duration(seconds: 3));
    controller.terminal.write('\x03');
    controller.terminal.write('exit\n');

    await controller.closeProject();
    controller.dispose();
  });
}
