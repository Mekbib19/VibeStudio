import 'package:flutter/material.dart';

import '../services/language_service.dart';
import '../services/project_service.dart';
import '../state/app_controller.dart';

class FileTree extends StatelessWidget {
  final AppController controller;

  const FileTree(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 2),
          child: Row(
            children: [
              const Text(
                'Files',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              if (controller.projectLanguage.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF23242C),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2A2B33)),
                  ),
                  child: Text(
                    controller.projectLanguage,
                    style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                onPressed: controller.collapseAllDirs,
                icon: const Icon(Icons.unfold_less, size: 16),
                tooltip: 'Collapse all folders (Ctrl+Shift+F)',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: controller.fileRefreshTick,
            builder: (context, _, _) => ListView(
              children: [
                for (final node in controller.fileNodes)
                  _FileRow(node: node, controller: controller),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final FileNode node;
  final AppController controller;
  final String? indent;

  const _FileRow({required this.node, required this.controller, this.indent});

  @override
  Widget build(BuildContext context) {
    final isOpen = controller.openFile == node.path;
    final expanded = controller.expandedDirs.contains(node.path);

    Widget row = InkWell(
      onTap: node.isDir
          ? () => controller.toggleDir(node.path)
          : () => controller.openFileAt(node.path),
      child: Container(
        color: isOpen ? const Color(0xFF23242C) : Colors.transparent,
        padding: EdgeInsets.only(
          left: 6 + ((indent?.length ?? 0) * 12),
          right: 6,
          top: 2,
          bottom: 2,
        ),
        child: Row(
          children: [
            Icon(
              node.isDir
                  ? (expanded ? Icons.folder_open : Icons.folder)
                  : languageForPath(node.path).icon,
              size: 15,
              color: node.isDir
                  ? const Color(0xFFB39DDB)
                  : languageForPath(node.path).color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );

    if (!node.isDir || !expanded) return row;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        for (final child in node.children)
          _FileRow(
            node: child,
            controller: controller,
            indent: '${indent ?? ''} ',
          ),
      ],
    );
  }
}
