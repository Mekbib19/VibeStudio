import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class ListenPort {
  final int port;
  final int? pid;
  final String? command;

  const ListenPort({required this.port, this.pid, this.command});
}

/// Discovers TCP ports currently in use on the machine so the user can stop or
/// restart the process listening on a given port (from the list or typed by
/// hand). Uses `ss -tlnp` with an `lsof` fallback.
class PortService extends ChangeNotifier {
  bool refreshing = false;
  String? lastError;
  List<ListenPort> ports = [];

  Future<void> refresh() async {
    refreshing = true;
    lastError = null;
    notifyListeners();
    try {
      ports = await _collect();
    } catch (e) {
      lastError = '$e';
    }
    refreshing = false;
    notifyListeners();
  }

  Future<List<ListenPort>> _collect() async {
    final ss = await _run(['ss', '-tlnp']);
    if (ss != null && ss.trim().isNotEmpty) return parseSs(ss);
    final lsof = await _run(['lsof', '-iTCP', '-sTCP:LISTEN', '-Pn']);
    if (lsof != null && lsof.trim().isNotEmpty) return parseLsof(lsof);
    return [];
  }

  Future<String?> _run(List<String> cmd) async {
    try {
      final res = await Process.run(
        cmd.first,
        cmd.skip(1).toList(),
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 4));
      if (res.exitCode != 0) return null;
      return res.stdout as String;
    } catch (_) {
      return null;
    }
  }

  /// Kills the process listening on [port]. Returns null on success or an
  /// error message.
  Future<String?> stopPort(int port) async {
    try {
      final res = await Process.run(
        'fuser',
        ['-k', '$port/tcp'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 5));
      await refresh();
      if (res.exitCode == 0) return null;
      final err = (res.stderr as String).trim();
      return err.isEmpty ? 'no process listening on port $port' : err;
    } catch (e) {
      return 'failed to stop port $port: $e';
    }
  }

  // ------------------------------------------------------------- parsers

  static List<ListenPort> parseSs(String out) {
    final ports = <ListenPort>[];
    for (final line in out.split('\n')) {
      if (!line.contains('LISTEN')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 5) continue;
      final port = portFromToken(parts[3]);
      if (port == null) continue;
      int? pid;
      String? command;
      final pm = RegExp(r'pid=(\d+)').firstMatch(line);
      final cm = RegExp(r'"([^"]+)"').firstMatch(line);
      if (pm != null) pid = int.tryParse(pm.group(1)!);
      if (cm != null) command = cm.group(1);
      ports.add(ListenPort(port: port, pid: pid, command: command));
    }
    return _dedupe(ports);
  }

  static List<ListenPort> parseLsof(String out) {
    final ports = <ListenPort>[];
    for (final line in out.split('\n')) {
      if (line.isEmpty || line.startsWith('COMMAND')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 9) continue;
      final name = parts[8];
      final m = RegExp(r':(\d+)\s*\(?LISTEN').firstMatch(name);
      final port = m != null ? int.tryParse(m.group(1)!) : portFromToken(name);
      if (port == null) continue;
      final pid = int.tryParse(parts[1]);
      final command = parts[0];
      ports.add(ListenPort(port: port, pid: pid, command: command));
    }
    return _dedupe(ports);
  }

  static int? portFromToken(String token) {
    final m = RegExp(r':(\d+)$').firstMatch(token);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static List<ListenPort> _dedupe(List<ListenPort> ports) {
    final seen = <int>{};
    return ports.where((p) => seen.add(p.port)).toList();
  }
}
