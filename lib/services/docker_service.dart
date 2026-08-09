import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Runs and inspects the project's docker compose stack. Every method is
/// best-effort: if `docker` is missing the service just reports it.
class DockerService extends ChangeNotifier {
  String? composeFile;

  /// Raw output of `docker compose ps` (one line per container).
  String statusLine = '';

  /// True when at least one container is up.
  bool composeActive = false;

  String? lastError;

  /// Tail of `docker compose logs -f`.
  final List<String> logs = [];

  Process? _proc;
  StreamSubscription<String>? _logSub;

  bool get hasCompose => composeFile != null;
  String? get _workDir => composeFile == null
      ? null
      : Directory(composeFile!).parent.path;

  Future<void> setComposeFile(String? path) async {
    if (path == composeFile) return;
    composeFile = path;
    if (path == null) {
      await _reset();
      return;
    }
    await refreshStatus();
  }

  Future<void> _reset() async {
    await stopLogs();
    statusLine = '';
    composeActive = false;
    lastError = null;
    notifyListeners();
  }

  Future<void> refreshStatus() async {
    final dir = _workDir;
    if (dir == null) return;
    try {
      final res = await Process.run(
        'docker',
        ['compose', 'ps', '--format', '{{.Name}}  {{.State}}'],
        workingDirectory: dir,
      );
      if (res.exitCode != 0) {
        final msg = '${res.stderr}'.trim();
        throw StateError(msg.isEmpty ? 'docker compose ps failed' : msg);
      }
      final out = '${res.stdout}'.trim();
      statusLine = out.isEmpty ? 'no containers' : out;
      composeActive = out.isNotEmpty;
      lastError = null;
    } catch (e) {
      statusLine = 'docker unavailable';
      composeActive = false;
      lastError = '$e';
    }
    notifyListeners();
  }

  Future<void> up() async {
    final dir = _workDir;
    if (dir == null) return;
    _logLine(r'$ docker compose up -d');
    final res = await Process.run(
      'docker',
      ['compose', 'up', '-d'],
      workingDirectory: dir,
    );
    _logRes(res);
    await refreshStatus();
  }

  Future<void> down() async {
    final dir = _workDir;
    if (dir == null) return;
    _logLine(r'$ docker compose down');
    final res = await Process.run(
      'docker',
      ['compose', 'down'],
      workingDirectory: dir,
    );
    _logRes(res);
    await refreshStatus();
  }

  Future<void> startLogs() async {
    final dir = _workDir;
    if (dir == null || _proc != null) return;
    try {
      final proc = await Process.start(
        'docker',
        ['compose', 'logs', '-f'],
        workingDirectory: dir,
        mode: ProcessStartMode.normal,
      );
      _proc = proc;
      _logSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_logLine, onError: (_) {});
      proc.exitCode.then((_) => _onLogsEnded());
    } catch (e) {
      lastError = '$e';
      notifyListeners();
    }
  }

  void _onLogsEnded() {
    _logSub?.cancel();
    _logSub = null;
    _proc = null;
  }

  Future<void> stopLogs() async {
    final sub = _logSub;
    _logSub = null;
    await sub?.cancel();
    final proc = _proc;
    _proc = null;
    if (proc != null) {
      try {
        proc.kill();
        await proc.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  void _logRes(ProcessResult res) {
    final out = '${res.stdout}'.trim();
    final err = '${res.stderr}'.trim();
    if (out.isNotEmpty) _logLine(out);
    if (err.isNotEmpty) _logLine(err);
    lastError = res.exitCode != 0 ? (err.isEmpty ? 'exit ${res.exitCode}' : err) : null;
    notifyListeners();
  }

  void _logLine(String line) {
    for (final l in line.split('\n')) {
      logs.add(l);
    }
    if (logs.length > 2000) logs.removeRange(0, logs.length - 2000);
    notifyListeners();
  }

  @override
  void dispose() {
    stopLogs();
    super.dispose();
  }
}
