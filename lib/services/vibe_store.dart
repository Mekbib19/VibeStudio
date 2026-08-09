import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// VibeStudio's own small database, stored at `~/.vibestudio/store.json`
/// (outside any project, so nothing is written into the project folder).
///
/// Holds, per project path:
///   - the standard run commands: Run / Stop / Migration (saved permanently
///     after the one-time AI bootstrap — never asked again),
///   - extra manual scripts,
///   - the project's AI footprint (memory),
/// and the global recent-project list.
class VibeStore extends ChangeNotifier {
  static const standardScripts = <String, String>{
    'Run': 'start the app for development',
    'Stop': 'stop the running app',
    'Migration': 'run the database migrations',
  };

  VibeStore({String? filePath}) : _file = filePath == null ? null : File(filePath);

  File? _file;
  Map<String, dynamic> _data = {'recent': <String>[], 'projects': <String, dynamic>{}};

  File get file {
    final cached = _file;
    if (cached != null) return cached;
    final home = Platform.environment['HOME'] ?? '.';
    final f = File('$home${Platform.pathSeparator}.vibestudio'
        '${Platform.pathSeparator}store.json');
    _file = f;
    return f;
  }

  Future<void> load() async {
    try {
      final f = file;
      if (await f.exists()) {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _data = {
          'recent': (json['recent'] as List?)?.cast<String>() ?? <String>[],
          'projects': (json['projects'] as Map<String, dynamic>?) ?? {},
        };
      }
    } catch (_) {
      _data = {'recent': <String>[], 'projects': <String, dynamic>{}};
    }
    notifyListeners();
  }

  Future<void> save() async {
    try {
      final f = file;
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(_data), flush: true);
    } catch (_) {}
  }

  Map<String, dynamic> _project(String path) =>
      (_data['projects'] as Map<String, dynamic>)[path] as Map<String, dynamic>? ??
      {};

  // ------------------------------------------------------------- commands

  String? commandFor(String project, String name) {
    final cmds = _project(project)['commands'] as Map<String, dynamic>? ?? {};
    final v = cmds[name];
    return v is String && v.trim().isNotEmpty ? v : null;
  }

  Map<String, String> commandsFor(String project) {
    final cmds = _project(project)['commands'] as Map<String, dynamic>? ?? {};
    return cmds.map((k, v) => MapEntry(k, v is String ? v : ''));
  }

  Future<void> setCommand(String project, String name, String command) async {
    final projects = _data['projects'] as Map<String, dynamic>;
    final p = (projects[project] as Map<String, dynamic>?) ?? {};
    final cmds = (p['commands'] as Map<String, dynamic>?) ?? {};
    cmds[name] = command.trim();
    p['commands'] = cmds;
    projects[project] = p;
    notifyListeners();
    await save();
  }

  /// Sets all three standard commands at once (used after the AI bootstrap).
  Future<void> setCommands(
      String project, Map<String, String> commands) async {
    for (final e in commands.entries) {
      if (e.value.trim().isNotEmpty) {
        await setCommand(project, e.key, e.value);
      }
    }
  }

  // ---------------------------------------------------------- manual scripts

  List<Map<String, String>> manualScriptsFor(String project) {
    final list = _project(project)['manual'] as List? ?? [];
    return list
        .map((e) => (e as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v.toString())))
        .toList();
  }

  Future<void> addManualScript(
      String project, String name, String command) async {
    final projects = _data['projects'] as Map<String, dynamic>;
    final p = (projects[project] as Map<String, dynamic>?) ?? {};
    final list = (p['manual'] as List?) ?? [];
    list.add({'name': name.trim(), 'command': command.trim()});
    p['manual'] = list;
    projects[project] = p;
    notifyListeners();
    await save();
  }

  Future<void> removeManualScript(String project, String name) async {
    final projects = _data['projects'] as Map<String, dynamic>;
    final p = (projects[project] as Map<String, dynamic>?) ?? {};
    final list = (p['manual'] as List?) ?? [];
    list.removeWhere(
        (e) => (e as Map<String, dynamic>)['name'] == name);
    p['manual'] = list;
    projects[project] = p;
    notifyListeners();
    await save();
  }

  // --------------------------------------------------------------- footprint

  String? footprintFor(String project) {
    final v = _project(project)['footprint'];
    return v is String ? v : null;
  }

  Future<void> setFootprint(String project, String content) async {
    final projects = _data['projects'] as Map<String, dynamic>;
    final p = (projects[project] as Map<String, dynamic>?) ?? {};
    p['footprint'] = content;
    projects[project] = p;
    notifyListeners();
    await save();
  }

  /// Whether the AI has already produced a full project-analysis summary
  /// (first open analyzes once and stores it; later opens read it).
  bool isAnalyzed(String project) => _project(project)['analyzed'] == true;

  Future<void> setAnalyzed(String project, bool value) async {
    final projects = _data['projects'] as Map<String, dynamic>;
    final p = (projects[project] as Map<String, dynamic>?) ?? {};
    p['analyzed'] = value;
    projects[project] = p;
    notifyListeners();
    await save();
  }

  /// Stored AI project-analysis summary injected into agent contexts on
  /// later opens so workers are never re-analyzing from scratch.
  String? analysisFor(String project) {
    final v = _project(project)['analysis'];
    return v is String ? v : null;
  }

  Future<void> setAnalysis(String project, String summary) async {
    final projects = _data['projects'] as Map<String, dynamic>;
    final p = (projects[project] as Map<String, dynamic>?) ?? {};
    p['analysis'] = summary;
    p['analyzed'] = true;
    projects[project] = p;
    notifyListeners();
    await save();
  }

  // -------------------------------------------------------------- recent

  List<String> get recentProjects =>
      List<String>.from(_data['recent'] as List? ?? <String>[]);

  Future<void> addRecent(String path) async {
    final recent = _data['recent'] as List? ?? <String>[];
    recent.remove(path);
    recent.insert(0, path);
    _data['recent'] = recent;
    notifyListeners();
    await save();
  }

  Future<void> removeRecent(String path) async {
    final recent = _data['recent'] as List? ?? <String>[];
    recent.remove(path);
    _data['recent'] = recent;
    notifyListeners();
    await save();
  }
}
