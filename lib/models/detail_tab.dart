import 'package:flutter/material.dart';

/// A tab opened in the center editor area (VS Code style): a live port, a
/// managed script run, or the inline "add script" form. Closing a tab never
/// stops the underlying process.
enum DetailTabKind { port, script, composer }

class DetailTab {
  final DetailTabKind kind;
  final int? portNumber;
  final String? scriptName;

  const DetailTab.port(this.portNumber)
      : kind = DetailTabKind.port,
        scriptName = null;

  const DetailTab.script(this.scriptName)
      : kind = DetailTabKind.script,
        portNumber = null;

  const DetailTab.composer()
      : kind = DetailTabKind.composer,
        portNumber = null,
        scriptName = null;

  String get id => switch (kind) {
        DetailTabKind.port => 'port:$portNumber',
        DetailTabKind.script => 'script:$scriptName',
        DetailTabKind.composer => 'composer',
      };

  String get label => switch (kind) {
        DetailTabKind.port => 'Port $portNumber',
        DetailTabKind.script => scriptName!,
        DetailTabKind.composer => 'Add script',
      };

  IconData get icon => switch (kind) {
        DetailTabKind.port => Icons.bolt,
        DetailTabKind.script => Icons.directions_run,
        DetailTabKind.composer => Icons.add,
      };
}
