import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'env_service.dart';

class BackendRequestResult {
  final String method;
  final String url;
  final int? statusCode;
  final Map<String, String> headers;
  final String body;
  final Duration? elapsed;
  final String? error;

  const BackendRequestResult({
    required this.method,
    required this.url,
    this.statusCode,
    this.headers = const {},
    this.body = '',
    this.elapsed,
    this.error,
  });

  bool get success => error == null && statusCode != null && statusCode! < 400;
  String get statusLabel => statusCode == null
      ? 'no response'
      : '$statusCode (${elapsed?.inMilliseconds ?? '?'}ms)';
}

/// Built-in API client ("backend tester") plus a configurable migration
/// checker. Successful requests can be reported to the main AI so it can
/// turn what the tester learns into new tasks.
class BackendTesterService extends ChangeNotifier {
  http.Client? _client;
  bool sending = false;
  BackendRequestResult? last;

  bool migrating = false;
  String migrateCommand = '';
  String migrateOutput = '';
  String? migrateError;
  int? migrateExitCode;

  Future<void> send({
    required String method,
    required String url,
    Map<String, String> headers = const {},
    String body = '',
  }) async {
    sending = true;
    notifyListeners();
    final stopwatch = Stopwatch()..start();
    try {
      final client = _client ??= http.Client();
      final request = http.Request(method.toUpperCase(), Uri.parse(url));
      request.headers.addAll(headers);
      if (body.trim().isNotEmpty) request.body = body;
      final streamed = await client.send(request).timeout(
        const Duration(seconds: 30),
      );
      final res = await http.Response.fromStream(streamed);
      last = BackendRequestResult(
        method: method.toUpperCase(),
        url: url,
        statusCode: res.statusCode,
        headers: res.headers,
        body: _prettyBody(res.body, res.headers['content-type'] ?? ''),
        elapsed: stopwatch.elapsed,
      );
    } catch (e) {
      last = BackendRequestResult(
        method: method.toUpperCase(),
        url: url,
        error: '$e',
        elapsed: stopwatch.elapsed,
      );
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  static String _prettyBody(String body, String contentType) {
    if (body.isEmpty) return body;
    if (contentType.contains('json') || body.trimLeft().startsWith('{')) {
      try {
        return const JsonEncoder.withIndent('  ').convert(jsonDecode(body));
      } catch (_) {}
    }
    return body;
  }

  void clear() {
    last = null;
    notifyListeners();
  }

  void setMigrateCommand(String cmd) {
    if (cmd == migrateCommand) return;
    migrateCommand = cmd.trim();
    notifyListeners();
  }

  /// Picks a sensible default migration-check command for the project.
  static String guessMigrationCommand(String dir, EnvService env) {
    final pkg = File('$dir${Platform.pathSeparator}package.json');
    if (pkg.existsSync()) {
      try {
        final json = jsonDecode(pkg.readAsStringSync()) as Map<String, dynamic>;
        final scripts = (json['scripts'] as Map?)?.cast<String, dynamic>() ?? {};
        for (final name in const [
          'migrate:check',
          'migration:check',
          'db:migrate:status',
          'migrate:status',
        ]) {
          if (scripts.containsKey(name)) return 'npm run $name';
        }
      } catch (_) {}
    }
    if (env.databases.contains('prisma')) return 'npx prisma migrate status';
    if (env.databases.contains('sequelize')) {
      return 'npx sequelize-cli db:migrate:status';
    }
    if (env.databases.contains('knex')) return 'npx knex migrate:list';
    if (env.databases.contains('typeorm')) return 'npx typeorm migration:show';
    return '';
  }

  Future<void> runMigrationCheck(String dir) async {
    final cmd = migrateCommand.trim();
    if (cmd.isEmpty) {
      migrateError = 'No migration-check command set. Type one and run again.';
      notifyListeners();
      return;
    }
    migrating = true;
    migrateError = null;
    migrateExitCode = null;
    notifyListeners();
    try {
      final parts = cmd.split(RegExp(r'\s+'));
      final executable = parts.first;
      final args = parts.sublist(1);
      final res = await Process.run(
        executable,
        args,
        workingDirectory: dir,
        runInShell: executable == 'npm' || executable == 'npx',
      );
      migrateExitCode = res.exitCode;
      final out = '${res.stdout}'.trim();
      final err = '${res.stderr}'.trim();
      migrateOutput = [if (out.isNotEmpty) out, if (err.isNotEmpty) err].join('\n');
      if (res.exitCode != 0 && migrateOutput.isEmpty) {
        migrateError = 'command failed with exit code ${res.exitCode}';
      }
    } catch (e) {
      migrateError = '$e';
      migrateOutput = '';
    } finally {
      migrating = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }
}
