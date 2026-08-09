import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_studio/services/scripts_service.dart';
import 'package:vibe_studio/services/vibe_store.dart';

void main() {
  late Directory dir;
  late VibeStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('scripts_test');
    store = VibeStore(
      filePath: '${dir.path}${Platform.pathSeparator}store.json',
    );
    await store.load();
  });

  tearDown(() async {
    store.dispose();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  File sh(String name) => File('${dir.path}${Platform.pathSeparator}$name');

  test('marks bootstrap needed when start.sh is missing', () async {
    final svc = ScriptsService(store: store);
    await svc.setProjectDir(dir.path);
    expect(svc.bootstrapNeeded, isTrue);
    expect(svc.scripts, isEmpty);
    svc.dispose();
  });

  test('loads the .sh scripts that exist in the project root', () async {
    sh('start.sh').writeAsStringSync('npm run dev\n');
    sh('migration.sh').writeAsStringSync('npm run migrate\n');
    final svc = ScriptsService(store: store);
    await svc.setProjectDir(dir.path);

    expect(svc.bootstrapNeeded, isFalse); // start.sh exists
    expect(svc.standardScript('Run'), isNotNull);
    expect(svc.standardScript('Run')!.command, 'bash start.sh');
    expect(svc.standardScript('Stop'), isNull); // stop.sh still missing
    expect(svc.standardScript('Migration'), isNotNull);
    expect(svc.standardScript('Migration')!.command, 'bash migration.sh');
    svc.dispose();
  });

  test('no bootstrap needed when all three scripts exist', () async {
    sh('start.sh').writeAsStringSync('a\n');
    sh('stop.sh').writeAsStringSync('b\n');
    sh('migration.sh').writeAsStringSync('c\n');
    final svc = ScriptsService(store: store);
    await svc.setProjectDir(dir.path);
    expect(svc.bootstrapNeeded, isFalse);
    expect(svc.scripts.length, 3);
    svc.dispose();
  });

  test('clears scripts and bootstrap state when project closes', () async {
    sh('start.sh').writeAsStringSync('a\n');
    final svc = ScriptsService(store: store);
    await svc.setProjectDir(dir.path);
    expect(svc.scripts, isNotEmpty);
    await svc.setProjectDir('');
    expect(svc.scripts, isEmpty);
    expect(svc.bootstrapNeeded, isFalse);
    svc.dispose();
  });

  test('bootstrap writes the .sh files and caches commands permanently',
      () async {
    final svc = ScriptsService(store: store);
    svc.asker = (_) async =>
        '{"Run":"npm run dev","Stop":"npm run stop","Migration":"npm run migrate"}';
    await svc.setProjectDir(dir.path);
    expect(svc.bootstrapNeeded, isTrue);

    await svc.bootstrap(context: 'test context');

    expect(svc.bootstrapError, isNull);
    expect(svc.bootstrapNeeded, isFalse);
    expect(sh('start.sh').existsSync(), isTrue);
    expect(sh('stop.sh').existsSync(), isTrue);
    expect(sh('migration.sh').existsSync(), isTrue);
    expect(sh('start.sh').readAsStringSync(), contains('npm run dev'));
    expect(store.commandFor(dir.path, 'Run'), 'npm run dev');
    expect(svc.scripts.length, 3);

    // Reopening the project: no bootstrap needed, files still load.
    final svc2 = ScriptsService(store: store);
    await svc2.setProjectDir(dir.path);
    expect(svc2.bootstrapNeeded, isFalse);
    expect(svc2.standardScript('Run')!.command, 'bash start.sh');
    svc.dispose();
    svc2.dispose();
  });

  test('bootstrap surfaces a real error and never asks twice on bad reply',
      () async {
    final svc = ScriptsService(store: store);
    svc.asker = (_) async => 'I could not figure out the commands.';
    await svc.setProjectDir(dir.path);

    await svc.bootstrap(context: 'test context');

    expect(svc.bootstrapError, isNotNull);
    expect(svc.bootstrapNeeded, isTrue);
    expect(sh('start.sh').existsSync(), isFalse);
    expect(svc.bootstrapLog, contains('I could not figure out'));
    svc.dispose();
  });
}
