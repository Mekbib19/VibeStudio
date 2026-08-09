import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/server_config.dart';

class ServerEvent {
  final String type;
  final Map<String, dynamic> properties;

  const ServerEvent(this.type, this.properties);

  factory ServerEvent.fromJson(Map<String, dynamic> json) => ServerEvent(
        (json['type'] as String?) ?? 'unknown',
        ((json['properties'] as Map?) ?? {})
            .map((k, v) => MapEntry(k.toString(), v)),
      );
}

enum ServerState { stopped, starting, running, error }

class ServerService {
  ServerState state = ServerState.stopped;
  String? errorMessage;
  int port = 0;

  Process? _process;
  int? _procExitCode;
  http.Client? _client;
  StreamSubscription<String>? _eventSub;
  bool _stopping = false;
  ServerConfig? _config;

  final _events = StreamController<ServerEvent>.broadcast();
  Stream<ServerEvent> get events => _events.stream;

  Uri _base() => Uri.parse('http://127.0.0.1:$port');

  bool get isRunning => state == ServerState.running;

  Future<void> start({
    required String projectDir,
    ServerConfig? config,
    Map<String, String>? environment,
    int? overridePort,
  }) async {
    await stop();
    _stopping = false;
    _procExitCode = null;
    state = ServerState.starting;
    _client = http.Client();
    _config = config;

    port = overridePort ??
        ((config?.port ?? 0) > 0
            ? config!.port
            : 4100 + DateTime.now().millisecondsSinceEpoch % 800);
    final env = <String, String>{
      ...Platform.environment,
      'OPENCODE_DEBUG': 'false',
      ...?environment,
    };
    final configContent = config?.opencodeConfigContent;
    if (configContent != null) {
      env['OPENCODE_CONFIG_CONTENT'] = configContent;
    }
    var proc = await Process.start(
      'opencode',
      ['serve', '--port', '$port'],
      workingDirectory: projectDir,
      environment: env,
    );
    _process = proc;

    proc.exitCode.then((code) {
      _procExitCode = code;
      if (_stopping) return;
      if (state != ServerState.error) {
        state = ServerState.error;
        errorMessage = 'opencode server exited (code $code)';
      }
      _events.add(ServerEvent('server.exit', {'code': code}));
    });
    proc.stderr.transform(utf8.decoder).listen((chunk) {
      _events.add(ServerEvent('server.stderr', {'text': chunk}));
    });

    await _waitUntilReady(timeout: const Duration(seconds: 45));
    _startEventStream();

    state = ServerState.running;
    errorMessage = null;
    _events.add(ServerEvent('server.ready', {'port': port}));
  }

  Future<void> _waitUntilReady({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_procExitCode != null) {
        throw StateError(
            'opencode server failed to start (exit code $_procExitCode)');
      }
      try {
        final res = await _client!
            .get(_base().replace(path: '/session'))
            .timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) return;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('opencode server did not become ready in time');
  }

  void _startEventStream() {
    _eventSub?.cancel();
    Future(() => _streamEvents()).catchError((_) {});
  }

  Future<void> _streamEvents() async {
    final client = http.Client();
    final request = http.Request('GET', _base().replace(path: '/event'));
    final res = await client.send(request);
    if (res.statusCode != 200) {
      client.close();
      return;
    }
    final lines = res.stream.transform(utf8.decoder).transform(
          const LineSplitter(),
        );
    final buffer = StringBuffer();
    await for (final line in lines) {
      if (_stopping) break;
      final trimmed = line.trim();
      if (trimmed.startsWith('data:')) {
        buffer.write(trimmed.substring(5).trim());
        buffer.write('\n');
        _tryParseBuffer(buffer);
      } else if (trimmed.isEmpty) {
        buffer.clear();
      } else if (trimmed.startsWith(':')) {
        // SSE comment / keep-alive
      }
    }
    client.close();
    if (!_stopping) {
      // stream dropped; reconnect
      _eventSub?.cancel();
      _startEventStream();
    }
  }

  void _tryParseBuffer(StringBuffer buffer) {
    final raw = buffer.toString().trim();
    if (raw.isEmpty) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _events.add(ServerEvent.fromJson(json));
      buffer.clear();
    } catch (_) {
      // incomplete chunk; keep buffering
    }
  }

  Future<String> createSession({required String title}) async {
    final res = await _client!.post(
      _base().replace(path: '/session'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'title': title}),
    );
    if (res.statusCode != 200) {
      throw StateError('createSession failed: ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['id'] as String;
  }

  Future<void> sendMessage({
    required String sessionId,
    required String text,
    Map<String, String>? model,
  }) async {
    final body = <String, dynamic>{
      'parts': [
        {'type': 'text', 'text': text}
      ]
    };
    final resolved = model ?? _config?.messageModel;
    if (resolved != null) {
      body['model'] = resolved;
    }
    final res = await _client!.post(
      _base().replace(path: '/session/$sessionId/message'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw StateError('sendMessage failed (${res.statusCode}): ${res.body}');
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      await _client!.delete(
        _base().replace(path: '/session/$sessionId'),
        headers: {'content-type': 'application/json'},
        body: '{}',
      );
    } catch (_) {}
  }

  /// One-shot ask to the already-running opencode server (no random port, no
  /// extra process): create a session, send the prompt, read the text reply
  /// parts, and delete the session. Mirrors the project-side `_call_opencode`.
  Future<String> askOnce(
    String prompt, {
    String title = 'vibestudio ask',
  }) async {
    final client = _client;
    if (client == null || state != ServerState.running) {
      throw StateError('opencode server is not running');
    }
    final sessionId = await createSession(title: title);
    try {
      final res = await client.post(
        _base().replace(path: '/session/$sessionId/message'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'parts': [
            {'type': 'text', 'text': prompt}
          ]
        }),
      );
      if (res.statusCode != 200) {
        throw StateError('askOnce failed (${res.statusCode}): ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final parts = (data['parts'] as List? ?? []);
      final buffer = StringBuffer();
      for (final p in parts) {
        if (p is Map<String, dynamic> && p['type'] == 'text') {
          buffer.writeln(p['text'] as String? ?? '');
        }
      }
      final text = buffer.toString().trim();
      if (text.isEmpty) {
        throw StateError('no text reply from opencode');
      }
      return text;
    } finally {
      await deleteSession(sessionId);
    }
  }

  Future<void> stop() async {
    _stopping = true;
    await _eventSub?.cancel();
    _eventSub = null;
    final proc = _process;
    _process = null;
    if (proc == null) return;
    try {
      proc.kill(ProcessSignal.sigterm);
      await proc.exitCode.timeout(const Duration(seconds: 4), onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      });
    } catch (_) {}
    _client?.close();
    _client = null;
    if (state != ServerState.error) state = ServerState.stopped;
  }

  void dispose() {
    _stopping = true;
    _events.close();
  }
}
