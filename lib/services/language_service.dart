import 'package:flutter/material.dart';

import 'project_service.dart';

/// A programming language known to Vibe Studio: how to recognize a file by
/// extension or exact filename, the highlight.js mode for the editor, and the
/// icon/color shown in the file tree.
class ProgramLanguage {
  final String name;
  final List<String> exts;
  final Set<String> filenames;
  final String? highlight;
  final Color color;
  final IconData icon;

  const ProgramLanguage({
    required this.name,
    this.exts = const [],
    this.filenames = const {},
    this.highlight,
    required this.color,
    required this.icon,
  });

  bool matches(String fileName, String ext) =>
      filenames.contains(fileName) || exts.contains(ext);
}

/// Fallback for unknown file types.
const ProgramLanguage _unknown = ProgramLanguage(
  name: 'File',
  color: Color(0xFF78909C),
  icon: Icons.insert_drive_file_outlined,
);

/// File type groups. Order matters: exact filenames and more specific
/// extensions are checked first.
const List<ProgramLanguage> _languages = [
  ProgramLanguage(
    name: 'Dart',
    exts: ['dart'],
    highlight: 'dart',
    color: Color(0xFF40C4FF),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'C++',
    exts: ['cpp', 'cc', 'cxx', 'c++', 'hpp', 'hh', 'hxx'],
    highlight: 'cpp',
    color: Color(0xFF6FA9E0),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'C',
    exts: ['c', 'h'],
    highlight: 'c',
    color: Color(0xFF5A7DB8),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'C#',
    exts: ['cs', 'csx'],
    highlight: 'csharp',
    color: Color(0xFF68217A),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'Go',
    exts: ['go'],
    highlight: 'go',
    color: Color(0xFF00ADD8),
    icon: Icons.bolt,
  ),
  ProgramLanguage(
    name: 'Rust',
    exts: ['rs'],
    highlight: 'rust',
    color: Color(0xFFDEA584),
    icon: Icons.extension,
  ),
  ProgramLanguage(
    name: 'Python',
    exts: ['py', 'pyw', 'pyi'],
    highlight: 'python',
    color: Color(0xFF4B8BBE),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'JavaScript',
    exts: ['js', 'jsx', 'mjs', 'cjs'],
    highlight: 'javascript',
    color: Color(0xFFF0DB4F),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'TypeScript',
    exts: ['ts', 'tsx', 'mts', 'cts'],
    highlight: 'typescript',
    color: Color(0xFF3178C6),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'HTML',
    exts: ['html', 'htm'],
    highlight: 'xml',
    color: Color(0xFFE34F26),
    icon: Icons.language,
  ),
  ProgramLanguage(
    name: 'CSS',
    exts: ['css', 'scss', 'sass', 'less', 'styl'],
    highlight: 'css',
    color: Color(0xFF2965F1),
    icon: Icons.palette,
  ),
  ProgramLanguage(
    name: 'Vue',
    exts: ['vue'],
    highlight: 'xml',
    color: Color(0xFF42B883),
    icon: Icons.view_quilt,
  ),
  ProgramLanguage(
    name: 'Svelte',
    exts: ['svelte'],
    highlight: 'xml',
    color: Color(0xFFFF3E00),
    icon: Icons.auto_awesome,
  ),
  ProgramLanguage(
    name: 'Java',
    exts: ['java'],
    highlight: 'java',
    color: Color(0xFFB07219),
    icon: Icons.coffee,
  ),
  ProgramLanguage(
    name: 'Kotlin',
    exts: ['kt', 'kts'],
    highlight: 'kotlin',
    color: Color(0xFF7F52FF),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'Swift',
    exts: ['swift'],
    highlight: 'swift',
    color: Color(0xFFFA7343),
    icon: Icons.phone_iphone,
  ),
  ProgramLanguage(
    name: 'Ruby',
    exts: ['rb', 'rake', 'gemspec'],
    highlight: 'ruby',
    color: Color(0xFFCC342D),
    icon: Icons.diamond_outlined,
  ),
  ProgramLanguage(
    name: 'PHP',
    exts: ['php'],
    highlight: 'php',
    color: Color(0xFF777BB4),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'Lua',
    exts: ['lua'],
    highlight: 'lua',
    color: Color(0xFF4A6C9C),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'Scala',
    exts: ['scala', 'sc'],
    highlight: 'scala',
    color: Color(0xFFDC322F),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'Zig',
    exts: ['zig'],
    highlight: 'zig',
    color: Color(0xFFF7A41D),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'R',
    exts: ['r', 'rmd'],
    highlight: 'r',
    color: Color(0xFF276DC3),
    icon: Icons.biotech,
  ),
  ProgramLanguage(
    name: 'Julia',
    exts: ['jl'],
    highlight: 'julia',
    color: Color(0xFF9558B2),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'Perl',
    exts: ['pl', 'pm'],
    highlight: 'perl',
    color: Color(0xFF428BCA),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'Shell',
    exts: ['sh', 'bash', 'zsh', 'fish'],
    highlight: 'bash',
    color: Color(0xFF89E051),
    icon: Icons.terminal,
  ),
  ProgramLanguage(
    name: 'SQL',
    exts: ['sql'],
    highlight: 'sql',
    color: Color(0xFFD4A017),
    icon: Icons.storage,
  ),
  ProgramLanguage(
    name: 'JSON',
    exts: ['json', 'jsonc', 'webmanifest', 'geojson'],
    highlight: 'json',
    color: Color(0xFFC7A84B),
    icon: Icons.data_object,
  ),
  ProgramLanguage(
    name: 'YAML',
    exts: ['yaml', 'yml'],
    highlight: 'yaml',
    color: Color(0xFFAB47BC),
    icon: Icons.data_object,
  ),
  ProgramLanguage(
    name: 'TOML',
    exts: ['toml'],
    highlight: 'ini',
    color: Color(0xFF9FA8A8),
    icon: Icons.data_object,
  ),
  ProgramLanguage(
    name: 'INI',
    exts: ['ini', 'cfg', 'conf', 'properties'],
    highlight: 'ini',
    color: Color(0xFF9FA8A8),
    icon: Icons.tune,
  ),
  ProgramLanguage(
    name: 'XML',
    exts: ['xml', 'svg', 'plist', 'xaml'],
    highlight: 'xml',
    color: Color(0xFFEF6C00),
    icon: Icons.code,
  ),
  ProgramLanguage(
    name: 'Markdown',
    exts: ['md', 'markdown', 'mdx'],
    highlight: 'markdown',
    color: Color(0xFF9E9E9E),
    icon: Icons.description_outlined,
  ),
  ProgramLanguage(
    name: 'Text',
    exts: ['txt', 'log', 'rtf'],
    highlight: null,
    color: Color(0xFF757575),
    icon: Icons.description_outlined,
  ),
  ProgramLanguage(
    name: 'Groovy',
    exts: ['groovy', 'gradle'],
    highlight: 'groovy',
    color: Color(0xFF02303A),
    icon: Icons.coffee,
  ),
  ProgramLanguage(
    name: 'Docker',
    filenames: {'Dockerfile'},
    exts: ['dockerfile'],
    highlight: null,
    color: Color(0xFF2496ED),
    icon: Icons.anchor,
  ),
  ProgramLanguage(
    name: 'Make',
    filenames: {'Makefile', 'GNUmakefile'},
    exts: ['mk'],
    highlight: null,
    color: Color(0xFF808080),
    icon: Icons.handyman_outlined,
  ),
  ProgramLanguage(
    name: 'CMake',
    filenames: {'CMakeLists.txt'},
    exts: ['cmake'],
    highlight: null,
    color: Color(0xFF3467A8),
    icon: Icons.architecture,
  ),
  ProgramLanguage(
    name: 'Image',
    exts: ['png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'ico', 'bmp'],
    highlight: null,
    color: Color(0xFF8E8EA0),
    icon: Icons.image_outlined,
  ),
];

/// The language recognized for a file path, or a generic fallback.
ProgramLanguage languageForPath(String path) {
  final name = _baseName(path);
  final dot = name.lastIndexOf('.');
  final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  for (final lang in _languages) {
    if (lang.matches(name, ext)) return lang;
  }
  return _unknown;
}

/// The language label for a file path (used as an editor badge).
String languageNameForPath(String path) => languageForPath(path).name;

/// The highlight.js mode key for a file path, or null when none applies.
String? highlightModeForPath(String path) {
  return languageForPath(path).highlight;
}

/// Dominant language of a project tree, or null when nothing recognizable
/// exists (e.g. an empty folder).
String? detectProjectLanguage(List<FileNode> nodes) {
  final counts = <String, int>{};
  _countFiles(nodes, counts);
  String? best;
  var bestCount = 0;
  counts.forEach((name, count) {
    if (count > bestCount) {
      best = name;
      bestCount = count;
    }
  });
  return best;
}

void _countFiles(List<FileNode> nodes, Map<String, int> counts) {
  for (final node in nodes) {
    if (node.isDir) {
      _countFiles(node.children, counts);
    } else {
      final name = languageForPath(node.path).name;
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
}

String _baseName(String path) =>
    path.split('/').last.split('\\').last;
