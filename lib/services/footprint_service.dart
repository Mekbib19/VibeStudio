import 'package:flutter/foundation.dart';

import 'env_service.dart';
import 'vibe_store.dart';

/// Hidden "project memory" for AI agents.
///
/// The memory is stored in the VibeStudio database (see [VibeStore]) — nothing
/// is written into the project folder. Its content is injected into every
/// agent system prompt (AI can see it) and updated automatically from agent
/// summaries. When an AI analyzes the project it should reuse this memory
/// instead of re-analyzing everything, which saves time and tokens.
class FootprintService extends ChangeNotifier {
  FootprintService({required this.store});

  final VibeStore store;

  String? projectDir;
  String? content;

  bool get exists => content != null;

  /// Reads the footprint for [dir] from the store, seeding a starter one from
  /// the detected stack info when the project has none yet.
  Future<void> load(String dir, EnvService env) async {
    projectDir = dir;
    content = store.footprintFor(dir);
    if (dir.isEmpty) {
      notifyListeners();
      return;
    }
    if (content == null) {
      content = _seed(env);
      await save(content!);
    }
    notifyListeners();
  }

  Future<void> save(String newContent) async {
    content = newContent;
    final dir = projectDir;
    if (dir == null || dir.isEmpty) return;
    await store.setFootprint(dir, newContent);
    notifyListeners();
  }

  /// Merges an agent summary into the footprint (append new durable facts,
  /// keep the file under a sane size).
  Future<void> appendAgentNote(String note) async {
    final dir = projectDir;
    if (dir == null || dir.isEmpty) return;
    final trimmed = note.trim();
    if (trimmed.isEmpty) return;
    final existing = content ?? '';
    final merged = existing.isEmpty
        ? trimmed
        : '$existing\n\n${trimmed.startsWith('- ') ? trimmed : '- $trimmed'}';
    final lines = merged.split('\n');
    await save(
      lines.length > 90 ? lines.sublist(lines.length - 90).join('\n') : merged,
    );
  }

  /// Starter memory so a first agent does not analyze everything from zero.
  String _seed(EnvService env) {
    final b = StringBuffer();
    b.writeln('# AI Footprint');
    b.writeln('');
    b.writeln(
        'This is the project memory for AI agents. Reuse it before deep '
        'analysis; it is updated as the team works. Keep additions to ~80 lines.');
    b.writeln('');
    if (env.databases.isNotEmpty) {
      b.writeln('## Databases');
      b.writeln('- ${env.databases.join(', ')}');
    }
    if (env.tables.isNotEmpty) {
      b.writeln('');
      b.writeln('## Schema');
      for (final t in env.tables) {
        b.writeln('- ${t.name}: ${t.columns.join(', ')}');
      }
    }
    if (env.composeFile != null) {
      b.writeln('');
      b.writeln('## Docker');
      b.writeln('- Compose file: ${env.composeFile}');
    }
    b.writeln('');
    b.writeln('## Stack (agent notes)');
    return b.toString().trimRight();
  }
}
