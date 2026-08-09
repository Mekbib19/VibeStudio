import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_studio/models/agent.dart';
import 'package:vibe_studio/models/server_config.dart';
import 'package:vibe_studio/models/todo.dart';
import 'package:vibe_studio/state/app_controller.dart';
import 'package:vibe_studio/services/vibe_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempProject;
  late AppController controller;
  late VibeStore store;
  Process? stubProc;

  setUp(() async {
    // flutter_test replaces HttpClient with a 400-returning mock; restore
    // real networking so the live opencode serve API is reachable.
    HttpOverrides.global = null;

    tempProject = await Directory.systemTemp.createTemp('vibe_e2e_');
    File('${tempProject.path}/main.py').writeAsStringSync(
      'def greet(name):\n'
      '    return f"hello {name}"\n',
    );
    store = VibeStore(
      filePath: '${tempProject.path}/vibe_store.json',
    );
    await store.load();
    controller = AppController(store: store);
    // These tests exercise the manual-agent workflow, so keep the auto team
    // from spawning its own workers on top (auto team is covered by
    // test/auto_team_test.dart).
    controller.autoTeam = false;
  });

  tearDown(() async {
    await controller.closeProject();
    controller.dispose();
    store.dispose();
    stubProc?.kill();
    try {
      tempProject.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<bool> waitFor(
    Future<bool> Function() condition, {
    Duration timeout = const Duration(minutes: 6),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await condition()) return true;
      await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  test('two agents pick up todos, work them, and mark them done',
      () async {
    final opened = await controller.openProjectAt(tempProject.path);
    if (!opened) {
      // ignore: avoid_print
      print('server state: ${controller.server.state}');
      // ignore: avoid_print
      print('server error: ${controller.server.errorMessage}');
      for (final e in controller.systemLog) {
        // ignore: avoid_print
        print('log: ${e.text}');
      }
    }
    expect(opened, isTrue);

    await controller.addTodo(
      'Create file notes.txt',
      'Create a file named notes.txt in the project root containing exactly '
      'the line: team work works',
    );
    await controller.addTodo(
      'Create file report.txt',
      'Create a file named report.txt in the project root containing exactly '
      'the line: done by agent',
    );
    await controller.addTodo(
      'Create file bonus.txt',
      'Create a file named bonus.txt in the project root containing exactly '
      'the line: extra task',
    );

    await controller.addAgent(name: 'E2E-Agent-1', role: AgentRole.engineer);
    await controller.addAgent(name: 'E2E-Agent-2', role: AgentRole.engineer);

    final done = await waitFor(() async {
      final ledger = await controller.todos.load();
      final targets = ledger.todos
          .where((t) =>
              t.title.contains('notes.txt') ||
              t.title.contains('report.txt') ||
              t.title.contains('bonus.txt'))
          .toList();
      return targets.length == 3 &&
          targets.every((t) => t.status == TodoStatus.done);
    }, timeout: const Duration(minutes: 4));

    if (!done) {
      final ledger = await controller.todos.load();
      for (final t in ledger.todos) {
        // ignore: avoid_print
        print('TODO ${t.id} status=${t.status.wire} assignee=${t.assignee}');
      }
      for (final a in controller.agents) {
        // ignore: avoid_print
        print('AGENT ${a.name} status=${a.status.label} session=${a.sessionId} '
            'task=${a.currentTask} errors=${a.lastError}');
        for (final e in a.log.skip(a.log.length > 15 ? a.log.length - 15 : 0)) {
          // ignore: avoid_print
          print('  log: ${e.text}');
        }
      }
      for (final s in controller.systemLog) {
        // ignore: avoid_print
        print('sys: ${s.text}');
      }
    }

    expect(done, isTrue, reason: 'todos were not all marked done in time');
    expect(File('${tempProject.path}/notes.txt').existsSync(), isTrue);
    expect(File('${tempProject.path}/report.txt').existsSync(), isTrue);
    expect(File('${tempProject.path}/bonus.txt').existsSync(), isTrue);
    expect(controller.agents, hasLength(2));
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('custom OpenAI-compatible provider routes messages to its baseURL',
      () async {
    const stubPort = 4211;
    stubProc = await Process.start(
      'node',
      ['/tmp/opencode/stub/server.js'],
      environment: {'PORT': '$stubPort'},
    );

    controller.serverConfig = ServerConfig(
      mode: AiProviderMode.custom,
      providerID: 'freebuff',
      baseURL: 'http://127.0.0.1:$stubPort/v1',
      apiKey: 'stub-key',
      modelID: 'deepseek-v4-flash',
    );
    expect(controller.serverConfig.opencodeConfigContent, isNotNull);

    final opened = await controller.openProjectAt(tempProject.path);
    expect(opened, isTrue);

    await controller.addAgent(name: 'Stub-Agent', role: AgentRole.engineer);

    // Workers now spawn a short-lived server per job, so give the stub agent
    // a task to trigger its first message (the stub replies HI FROM STUB).
    await controller.addTodo(
      'stub task',
      'Create a file named stub.txt in the project root.',
    );

    final replied = await waitFor(() async {
      return controller.agents.any((a) =>
          a.log.any((e) => e.text.contains('HI FROM STUB')));
    }, timeout: const Duration(minutes: 2));

    if (!replied) {
      for (final a in controller.agents) {
        // ignore: avoid_print
        print('AGENT ${a.name} status=${a.status.label} errors=${a.lastError}');
        for (final e in a.log.skip(a.log.length > 15 ? a.log.length - 15 : 0)) {
          // ignore: avoid_print
          print('  log: ${e.text}');
        }
      }
    }
    expect(replied, isTrue, reason: 'stub reply was never observed');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
