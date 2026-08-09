import 'dart:convert' as dart_convert;
import 'dart:io';

import 'package:flutter/foundation.dart';

class DbTable {
  final String name;
  final List<String> columns;
  const DbTable(this.name, this.columns);
}

/// Loads the project's `.env`/`.env.local` files and detects the project's
/// database + docker-compose setup. The result is fed to the terminal, the
/// opencode server, and the agents' system prompts.
class EnvService extends ChangeNotifier {
  String? projectDir;

  /// KEY=VALUE pairs merged from `.env` (lowest priority) then `.env.local`.
  Map<String, String> vars = {};

  /// Detected database engines, e.g. ['postgres', 'redis'].
  List<String> databases = [];

  /// Path of the docker compose file, if the project has one.
  String? composeFile;

  /// Table/column layout discovered from prisma schema and migration SQL.
  List<DbTable> tables = [];

  int get envCount => vars.length;

  Future<void> load(String dir) async {
    projectDir = dir;
    vars = await loadEnvVars(dir);
    databases = detectDatabases(dir, vars);
    composeFile = findComposeFile(dir);
    tables = detectTables(dir);
    notifyListeners();
  }

  Future<void> reload() async {
    if (projectDir == null) return;
    await load(projectDir!);
  }

  Future<void> reset() async {
    projectDir = null;
    vars = {};
    databases = [];
    composeFile = null;
    tables = [];
    notifyListeners();
  }

  // ---------------------------------------------------------------- .env

  static Future<Map<String, String>> loadEnvVars(String dir) async {
    final result = <String, String>{};
    for (final name in const ['.env', '.env.local']) {
      final file = File('$dir${Platform.pathSeparator}$name');
      if (!file.existsSync()) continue;
      String content;
      try {
        content = await file.readAsString();
      } catch (_) {
        continue;
      }
      for (final raw in content.split('\n')) {
        final kv = parseEnvLine(raw);
        if (kv != null) result[kv.$1] = kv.$2;
      }
    }
    return result;
  }

  /// Parses one `.env` line: `export KEY=value`, comments, and quotes.
  static (String, String)? parseEnvLine(String raw) {
    var line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) return null;
    if (line.startsWith('export ')) line = line.substring(7).trim();
    final eq = line.indexOf('=');
    if (eq <= 0) return null;
    final key = line.substring(0, eq).trim();
    var value = line.substring(eq + 1).trim();
    // strip inline comment that follows a value (space-prefixed #)
    final hash = value.indexOf(' #');
    if (hash > 0) value = value.substring(0, hash).trim();
    if (value.length >= 2) {
      final first = value.codeUnitAt(0);
      final last = value.codeUnitAt(value.length - 1);
      if ((first == 34 && last == 34) || (first == 39 && last == 39)) {
        value = value.substring(1, value.length - 1);
      }
    }
    return (key, value);
  }

  // ---------------------------------------------------------- databases

  static const Map<String, String> _dbByDep = {
    'pg': 'postgres',
    'postgres': 'postgres',
    'postgresql': 'postgres',
    'pg-promise': 'postgres',
    'mysql': 'mysql',
    'mysql2': 'mysql',
    'mysql-server': 'mysql',
    'sqlite3': 'sqlite',
    'better-sqlite3': 'sqlite',
    'sql.js': 'sqlite',
    'mongodb': 'mongodb',
    'mongoose': 'mongodb',
    'redis': 'redis',
    'ioredis': 'redis',
    'knex': 'knex',
    'prisma': 'prisma',
    'sequelize': 'sequelize',
    'sequelize-cli': 'sequelize',
    'typeorm': 'typeorm',
  };

  static List<String> detectDatabases(String dir, Map<String, String> env) {
    final found = <String>{};

    // package.json dependencies
    final pkg = _readJsonFile('$dir${Platform.pathSeparator}package.json');
    if (pkg != null) {
      for (final section in const ['dependencies', 'devDependencies']) {
        final deps = pkg[section];
        if (deps is Map) {
          for (final dep in deps.keys) {
            final mapped = _dbByDep[dep];
            if (mapped != null) found.add(mapped);
          }
        }
      }
    }

    // prisma schema provider
    final schema =
        File('$dir${Platform.pathSeparator}${['prisma', 'schema.prisma'].join(Platform.pathSeparator)}');
    if (schema.existsSync()) {
      try {
        final text = schema.readAsStringSync();
        if (RegExp(r'provider\s*=\s*"(postgres|postgresql)"').hasMatch(text)) {
          found.add('postgres');
        } else if (RegExp(r'provider\s*=\s*"mysql"').hasMatch(text)) {
          found.add('mysql');
        } else if (RegExp(r'provider\s*=\s*"sqlite"').hasMatch(text)) {
          found.add('sqlite');
        }
      } catch (_) {}
    }

    // connection URLs in .env values
    for (final value in env.values) {
      final lower = value.toLowerCase();
      if (lower.startsWith('postgres://') || lower.startsWith('postgresql://')) {
        found.add('postgres');
      } else if (lower.startsWith('mysql://')) {
        found.add('mysql');
      } else if (lower.startsWith('sqlite:')) {
        found.add('sqlite');
      } else if (lower.startsWith('mongodb')) {
        found.add('mongodb');
      } else if (lower.startsWith('redis://')) {
        found.add('redis');
      }
    }

    // docker-compose services
    final compose = findComposeFile(dir);
    if (compose != null) {
      try {
        final text = File(compose).readAsStringSync();
        if (text.contains('postgres') || text.contains('postgis')) {
          found.add('postgres');
        }
        if (text.contains('mysql') || text.contains('mariadb')) {
          found.add('mysql');
        }
        if (text.contains('mongo')) found.add('mongodb');
        if (text.contains('redis')) found.add('redis');
      } catch (_) {}
    }

    return found.toList()..sort();
  }

  static Map<String, dynamic>? _readJsonFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final decoded = dart_convert.jsonDecode(file.readAsStringSync());
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  // --------------------------------------------------------- schema tables

  static List<DbTable> detectTables(String dir) {
    final merged = <String, DbTable>{};

    void addTable(String name, Iterable<String> columns) {
      final existing = merged[name];
      if (existing != null) {
        final cols = <String>{...existing.columns, ...columns};
        merged[name] = DbTable(name, cols.toList()..sort());
      } else {
        final cols = columns.toSet().toList()..sort();
        merged[name] = DbTable(name, cols);
      }
    }

    // prisma schema
    final schemaFile = File('$dir${Platform.pathSeparator}${[
      'prisma',
      'schema.prisma'
    ].join(Platform.pathSeparator)}');
    if (schemaFile.existsSync()) {
      try {
        final text = schemaFile.readAsStringSync();
        final re = RegExp(r'model\s+([A-Za-z0-9_]+)\s*\{([^{}]*)\}', dotAll: true);
        for (final m in re.allMatches(text)) {
          final name = m.group(1)!;
          final cols = m.group(2)!
              .split('\n')
              .map((l) => l.trim())
              .where((l) =>
                  l.isNotEmpty &&
                  !l.startsWith('@') &&
                  !l.startsWith('//') &&
                  !l.startsWith('@@'))
              .map((l) => l.split(RegExp(r'\s+')).first)
              .toList();
          if (cols.isNotEmpty) addTable(name, cols);
        }
      } catch (_) {}
    }

    // SQL migration files
    for (final entry in _findSqlFiles(dir)) {
      try {
        final text = entry.readAsStringSync();
        final re = RegExp(
          r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?["`]?([A-Za-z0-9_.]+)["`]?\s*\((.*?)\)\s*;',
          dotAll: true,
          caseSensitive: false,
        );
        for (final m in re.allMatches(text)) {
          final name = m.group(1)!.split('.').last;
          final cols = m.group(2)!
              .split('\n')
              .map((l) => l.trim())
              .where((l) {
                if (l.isEmpty) return false;
                final upper = l.toUpperCase();
                return !upper.startsWith('PRIMARY KEY') &&
                    !upper.startsWith('FOREIGN KEY') &&
                    !upper.startsWith('CONSTRAINT') &&
                    !upper.startsWith('UNIQUE') &&
                    !upper.startsWith('CHECK') &&
                    !upper.startsWith('KEY ') &&
                    !upper.startsWith('INDEX') &&
                    !l.startsWith('--') &&
                    !l.startsWith('/*');
              })
              .map((l) => l.split(RegExp(r'\s+')).first
                  .replaceAll('"', '')
                  .replaceAll('`', ''))
              .toList();
          if (cols.isNotEmpty) addTable(name, cols);
        }
      } catch (_) {}
    }

    final tables = merged.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return tables;
  }

  static List<File> _findSqlFiles(String dir) {
    final out = <File>[];
    final roots = ['migrations', 'db', 'database', 'sql', 'prisma/migrations'];
    for (final root in roots) {
      final d = Directory('$dir${Platform.pathSeparator}$root');
      if (!d.existsSync()) continue;
      try {
        for (final e in d.listSync(recursive: true, followLinks: false)) {
          if (e is File && e.path.endsWith('.sql')) out.add(e);
        }
      } catch (_) {}
    }
    return out;
  }

  // ----------------------------------------------------------- compose

  static String? findComposeFile(String dir) {
    for (final name in const [
      'compose.yaml',
      'compose.yml',
      'docker-compose.yaml',
      'docker-compose.yml',
    ]) {
      final path = '$dir${Platform.pathSeparator}$name';
      if (File(path).existsSync()) return path;
    }
    return null;
  }
}
