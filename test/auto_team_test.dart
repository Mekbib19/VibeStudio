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
    // real networking so the OpenAI-compatible stub is reachable.
    HttpOverrides.global = null;

    tempProject = await Directory.systemTemp.createTemp('vibe_auto_');
    File('${tempProject.path}/main.py').writeAsStringSync('print("hi")\n');
    store = VibeStore(filePath: '${tempProject.path}/vibe_store.json');
    await store.load();
    controller = AppController(store: store);
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
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await condition()) return true;
      await Future.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  /// Auto-managed engineers currently in play (stopped/removed ones dropped).
  int activeAuto() => controller.agents
      .where((a) => a.autoManaged && a.status != AgentStatus.stopped)
      .length;

  test('auto team spawns up to maxAutoWorkers and retires them when the queue drains',
      () async {
    const stubPort = 4231;
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

    final opened = await controller.openProjectAt(tempProject.path);
    expect(opened, isTrue);

    // The seeded "explore the project" task triggers the auto team on its own
    // — no manual agent creation needed.
    expect(
      await waitFor(() async => activeAuto() >= 1),
      isTrue,
      reason: 'auto team did not spawn a worker for the seeded task',
    );

    // A burst of tasks tops the auto team up to the cap (3 by default) and
    // never beyond it.
    for (var i = 0; i < 6; i++) {
      await controller.addTodo('task $i', 'write file $i.txt');
    }
    var maxSeen = 0;
    final reachedCap = await waitFor(() async {
      final n = activeAuto();
      if (n > maxSeen) maxSeen = n;
      return n == controller.maxAutoWorkers;
    });
    expect(reachedCap, isTrue, reason: 'auto team never reached the cap');
    expect(maxSeen, lessThanOrEqualTo(controller.maxAutoWorkers));
    expect(
      controller.agents.every(
          (a) => !a.autoManaged || a.role == AgentRole.engineer),
      isTrue,
      reason: 'auto team may only spawn engineer workers',
    );

    // Once every todo is done the auto team retires its workers (removed from
    // the team) so their short-lived servers stop and RAM is freed.
    for (final t in (await controller.todos.load()).todos) {
      await controller.updateTodo(t.copyWith(status: TodoStatus.done));
    }
    final retired = await waitFor(
      () async => controller.agents.every((a) => !a.autoManaged),
    );
    expect(retired, isTrue,
        reason: 'auto team workers were not retired after the queue drained');
  });
}
