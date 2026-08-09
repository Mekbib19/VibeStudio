import 'dart:io';

import 'package:file_picker/file_picker.dart';

const _ignoredDirs = {
  '.git',
  '.dart_tool',
  '.idea',
  '.vscode',
  'node_modules',
  'build',
  'dist',
  '.cache',
  '__pycache__',
  '.venv',
  'venv',
  'env',
  '.next',
  'coverage',
};

class FileNode {
  final String name;
  final String path;
  final bool isDir;
  final List<FileNode> children;

  const FileNode({
    required this.name,
    required this.path,
    required this.isDir,
    this.children = const [],
  });
}

/// Minimal gitignore pattern matcher. Handles the common cases:
/// `#` comments, `!` negation, trailing `/` (directory only), leading `/`
/// (anchored to project root), `**`, `*`, `?`. Patterns without a slash match
/// the basename at any depth.
class GitignoreMatcher {
  final List<_Pattern> _patterns = [];

  GitignoreMatcher(List<String> lines) {
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      var negated = false;
      var dirOnly = false;
      var anchored = false;
      var p = line;
      if (p.startsWith('!')) {
        negated = true;
        p = p.substring(1);
      }
      if (p.startsWith('/')) {
        anchored = true;
        p = p.substring(1);
      }
      if (p.endsWith('/')) {
        dirOnly = true;
        p = p.substring(0, p.length - 1);
      }
      if (p.isEmpty) continue;
      _patterns.add(_Pattern(
        regex: _toRegex(p),
        negated: negated,
        dirOnly: dirOnly,
        anchored: anchored,
        hasSlash: p.contains('/'),
      ));
    }
  }

  static const _meta = r'.^$+()[]{}|\';

  static String _toRegex(String p) {
    final buf = StringBuffer();
    final chars = p.split('');
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      if (c == '*') {
        var n = 1;
        while (i + 1 < chars.length && chars[i + 1] == '*') {
          n++;
          i++;
        }
        if (n >= 2 && i + 1 < chars.length && chars[i + 1] == '/') {
          // "**/" at any level: matches zero or more leading directories.
          buf.write('(.*/)?');
          i++;
        } else {
          buf.write(n >= 2 ? '.*' : '[^/]*');
        }
      } else if (c == '?') {
        buf.write('[^/]');
      } else if (_meta.contains(c)) {
        buf.write('\\$c');
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  /// Whether a path relative to the project root is ignored.
  bool isIgnored(String relPath, {required bool isDir}) {
    var ignored = false;
    for (final p in _patterns) {
      if (_match(p, relPath, isDir: isDir)) ignored = !p.negated;
    }
    return ignored;
  }

  bool _match(_Pattern p, String relPath, {required bool isDir}) {
    // A pattern that matches an ancestor directory also excludes everything
    // under it, so check the full path and every parent.
    final segments = relPath.split('/');
    for (var i = 0; i < segments.length; i++) {
      final prefix = segments.sublist(0, i + 1).join('/');
      final isDirSegment = i < segments.length - 1 || isDir;
      if (_matchOne(p, prefix, isDir: isDirSegment)) return true;
    }
    return false;
  }

  bool _matchOne(_Pattern p, String relPath, {required bool isDir}) {
    if (p.dirOnly && !isDir) return false;
    if (p.anchored) {
      // Anchored: must match from the project root.
      return RegExp('^${p.regex}(/.*)?\$').hasMatch(relPath);
    }
    if (!p.hasSlash) {
      // No slash: match any single path segment exactly.
      final re = RegExp('^${p.regex}\$');
      for (final seg in relPath.split('/')) {
        if (re.hasMatch(seg)) return true;
      }
      return false;
    }
    // Slash present: match the whole relative path.
    return RegExp(p.regex).hasMatch(relPath);
  }
}

class _Pattern {
  final String regex;
  final bool negated;
  final bool dirOnly;
  final bool anchored;
  final bool hasSlash;

  const _Pattern({
    required this.regex,
    required this.negated,
    required this.dirOnly,
    required this.anchored,
    required this.hasSlash,
  });
}

class ProjectService {
  Future<String?> pickFolder() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: 'Open a project folder for the AI team',
    );
    return result;
  }

  List<FileNode> scanTree(String root) {
    final ignore = GitignoreMatcher(_readGitignore(root));
    final nodes = <FileNode>[];
    try {
      final dir = Directory(root);
      if (!dir.existsSync()) return nodes;
      for (final entry in dir.listSync(followLinks: false)) {
        final name = entry.path.split(Platform.pathSeparator).last;
        final rel = _relative(root, entry.path);
        if (ignore.isIgnored(rel, isDir: entry is Directory)) continue;
        if (entry is Directory) {
          if (_ignoredDirs.contains(name)) continue;
          nodes.add(FileNode(
            name: name,
            path: entry.path,
            isDir: true,
            children: scanTree(entry.path),
          ));
        } else if (entry is File) {
          nodes.add(FileNode(name: name, path: entry.path, isDir: false));
        }
      }
    } catch (_) {}
    nodes.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return nodes;
  }

  static List<String> _readGitignore(String root) {
    try {
      final f = File('$root${Platform.pathSeparator}.gitignore');
      if (!f.existsSync()) return const [];
      return f.readAsLinesSync();
    } catch (_) {
      return const [];
    }
  }

  static String _relative(String root, String path) {
    final r = root.replaceAll(r'\', '/').replaceAll('//', '/');
    final p = path.replaceAll(r'\', '/');
    return p.startsWith(r) ? p.substring(r.length).replaceFirst('/', '') : p;
  }

  Future<String> readFile(String path) async =>
      File(path).existsSync() ? File(path).readAsString() : '';

  Future<void> writeFile(String path, String content) async {
    await File(path).writeAsString(content, flush: true);
  }

  DateTime? fileModified(String path) {
    try {
      return File(path).lastModifiedSync();
    } catch (_) {
      return null;
    }
  }
}
