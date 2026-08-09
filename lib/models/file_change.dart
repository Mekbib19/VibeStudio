/// A single project change detected by VibeStudio (like a GitHub commit/PR
/// entry), so the user can notice when the AI team adds or edits files.
class FileChangeEvent {
  final FileChangeType type;
  final String path;
  final String relPath;
  final DateTime time;
  final int oldSize;
  final int newSize;

  const FileChangeEvent({
    required this.type,
    required this.path,
    required this.relPath,
    required this.time,
    this.oldSize = 0,
    this.newSize = 0,
  });

  String get sizeLabel {
    final diff = newSize - oldSize;
    if (diff == 0) return '';
    final sign = diff > 0 ? '+' : '-';
    return '$sign${diff.abs()} bytes';
  }

  String get label => switch (type) {
        FileChangeType.added => 'added',
        FileChangeType.modified => 'modified',
        FileChangeType.deleted => 'deleted',
      };
}

enum FileChangeType { added, modified, deleted }
