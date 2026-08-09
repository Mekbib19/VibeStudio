import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

/// A real interactive shell (PTY) that runs inside the project folder.
///
/// This is the "terminal for the agents": you can type things like
/// `opencode serve --port 4066` or `freebuff` (FreeBuff opens as its
/// interactive TUI right inside the app).
class TerminalService extends ChangeNotifier {
  Terminal terminal = Terminal(maxLines: 10000);
  Pty? pty;
  String? projectDir;

  StreamSubscription<Uint8List>? _outSub;
  bool _starting = false;
  int? _lastRows;
  int? _lastCols;
  Map<String, String> _env = {};

  bool get isRunning => pty != null;
  bool get isStarting => _starting;

  /// Directory the shell is rooted at (defaults to the project folder).
  String get workingDir => projectDir ?? Platform.environment['HOME'] ?? '.';

  Future<void> start({
    String? projectDir,
    Map<String, String>? environment,
  }) async {
    _env = environment ?? _env;
    this.projectDir = projectDir ?? this.projectDir;
    await stop();
    _starting = true;
    notifyListeners();
    try {
      final p = Pty.start(
        'bash',
        workingDirectory: workingDir,
        environment: {
          'TERM': 'xterm-256color',
          'LANG': 'en_US.UTF-8',
          ..._env,
        },
        rows: 25,
        columns: 100,
      );
      pty = p;
      _outSub = p.output.listen((data) {
        terminal.write(utf8.decode(data, allowMalformed: true));
      });
      terminal.onOutput = (out) {
        p.write(utf8.encode(out));
      };
      p.exitCode.then((code) {
        if (pty == p) {
          pty = null;
          _outSub?.cancel();
          _outSub = null;
        }
        notifyListeners();
      });

      terminal.write('\x1b[2J\x1b[3J\x1b[H');
      terminal.write(
          '\r\n\x1b[1;36mVibe Studio agent terminal — $workingDir\x1b[0m\r\n');
      terminal.write(
          '\x1b[2mTip: run \x1b[1mopencode serve --port 4066\x1b[0m\x1b[2m or \x1b[1mfreebuff\x1b[0m\x1b[2m to connect an AI backend.\x1b[0m\r\n\r\n');
    } catch (e) {
      _starting = false;
      terminal.write('failed to start shell: $e\r\n');
      notifyListeners();
      return;
    }
    _starting = false;
    notifyListeners();
  }

  /// Starts the shell if it is not already running.
  Future<void> ensureStarted() async {
    if (pty != null || _starting) return;
    await start();
  }

  void write(String text) {
    pty?.write(utf8.encode(text));
  }

  void sendCtrlC() => write('\x03');

  void resize(int rows, int cols) {
    if (rows < 2) rows = 2;
    if (cols < 2) cols = 2;
    if (_lastRows == rows && _lastCols == cols) return;
    _lastRows = rows;
    _lastCols = cols;
    pty?.resize(rows, cols);
  }

  void clear() => terminal.write('\x1b[2J\x1b[3J\x1b[H');

  Future<void> restart({Map<String, String>? environment}) async {
    final dir = projectDir;
    await start(projectDir: dir, environment: environment);
  }

  Future<void> stop() async {
    _starting = false;
    final p = pty;
    pty = null;
    _outSub?.cancel();
    _outSub = null;
    if (p != null) {
      p.kill();
      try {
        await p.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        p.kill(ProcessSignal.sigkill);
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
