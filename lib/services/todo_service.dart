import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/todo.dart';

/// The shared ledger file both the app and the agents read/write.
/// All mutations go through [update] so concurrent agent edits are preserved.
class TodoService {
  String? projectDir;

  String? get filePath =>
      projectDir == null ? null : '$projectDir/vibestudio.json';

  Future<TodoLedger> load() async {
    final path = filePath;
    if (path == null || !File(path).existsSync()) {
      return const TodoLedger(todos: []);
    }
    try {
      final raw = await File(path).readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return TodoLedger.fromJson(json);
    } catch (_) {
      return const TodoLedger(todos: []);
    }
  }

  Future<void> save(TodoLedger ledger) async {
    final path = filePath;
    if (path == null) return;
    final tmp = '$path.tmp';
    await File(tmp).writeAsString(todoLedgerToJson(ledger), flush: true);
    await File(tmp).rename(path);
  }

  /// Loads the current on-disk ledger, applies [mutate], writes back atomically.
  Future<void> update(
    FutureOr<void> Function(TodoLedger ledger) mutate,
  ) async {
    final ledger = await load();
    await mutate(ledger);
    await save(ledger);
  }

  Future<void> seedIfMissing() async {
    final path = filePath;
    if (path == null) return;
    if (File(path).existsSync()) return;
    final ledger = TodoLedger(todos: [
      TodoItem(
        id: _newId(),
        title: 'Explore the project and summarize its structure',
        description:
            'Read the codebase, understand the stack, and leave a short '
            'summary of the project in the description (prefix DONE:).',
      ),
    ]);
    await save(ledger);
  }

  static String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-'
      '${DateTime.now().microsecondsSinceEpoch % 100000}';

  static String newId() => _newId();
}
