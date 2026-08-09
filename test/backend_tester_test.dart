import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_studio/services/backend_tester_service.dart';
import 'package:vibe_studio/services/env_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GET returns status, headers, and body', () async {
    HttpOverrides.global = null; // restore real networking
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response
        ..headers.contentType = ContentType.json
        ..write('{"ok":true}')
        ..close();
    });
    final svc = BackendTesterService();
    await svc.send(
      method: 'GET',
      url: 'http://127.0.0.1:${server.port}/ping',
    );
    expect(svc.last, isNotNull);
    expect(svc.last!.statusCode, 200);
    expect(svc.last!.success, isTrue);
    expect(svc.last!.body, contains('"ok": true'));
    expect(svc.last!.error, isNull);
    svc.dispose();
    await server.close(force: true);
  });

  test('POST sends the request body', () async {
    HttpOverrides.global = null;
    String? receivedBody;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      receivedBody = await utf8.decoder.bind(req).join();
      req.response..statusCode = 201..write('created')..close();
    });
    final svc = BackendTesterService();
    await svc.send(
      method: 'POST',
      url: 'http://127.0.0.1:${server.port}/items',
      headers: {'Content-Type': 'application/json'},
      body: '{"name":"widget"}',
    );
    expect(receivedBody, '{"name":"widget"}');
    expect(svc.last!.statusCode, 201);
    expect(svc.last!.success, isTrue);
    svc.dispose();
    await server.close(force: true);
  });

  test('transport error is captured without crashing', () async {
    HttpOverrides.global = null;
    final svc = BackendTesterService();
    await svc.send(method: 'GET', url: 'http://127.0.0.1:1/unreachable');
    expect(svc.last, isNotNull);
    expect(svc.last!.statusCode, isNull);
    expect(svc.last!.success, isFalse);
    expect(svc.last!.error, isNotNull);
    svc.dispose();
  });

  test('guessMigrationCommand picks the npm script or prisma fallback',
      () async {
    HttpOverrides.global = null;
    final dir = await Directory.systemTemp.createTemp('vibe_mig_');
    File('${dir.path}/package.json').writeAsStringSync(
      '{"scripts": {"migrate:check": "prisma migrate status"}}\n',
    );
    final env = EnvService();
    env.databases = const ['prisma'];
    expect(
      BackendTesterService.guessMigrationCommand(dir.path, env),
      'npm run migrate:check',
    );
    env.dispose();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
}
