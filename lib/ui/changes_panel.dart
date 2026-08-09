import 'package:flutter/material.dart';

import '../models/file_change.dart';
import '../state/app_controller.dart';

/// GitHub-style activity feed of project changes (added / modified / deleted
/// files), so the user can notice what the AI team did while it worked.
class ChangesPanel extends StatefulWidget {
  final AppController controller;
  final VoidCallback? onClose;

  const ChangesPanel(this.controller, {super.key, this.onClose});

  @override
  State<ChangesPanel> createState() => _ChangesPanelState();
}

class _ChangesPanelState extends State<ChangesPanel> {
  FileChangeType? _filter;

  @override
  Widget build(BuildContext context) {
    final events = widget.controller.activity
        .where((e) => _filter == null || e.type == _filter)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: const Color(0xFF191A20),
          child: Row(
            children: [
              const Icon(Icons.commit, size: 15, color: Color(0xFF7C4DFF)),
              const SizedBox(width: 8),
              const Text(
                'Changes',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${widget.controller.activity.length} change(s)',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              IconButton(
                onPressed: widget.controller.clearActivity,
                icon: const Icon(Icons.delete_sweep, size: 16),
                tooltip: 'Clear activity',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Close',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: const Color(0xFF15161B),
          child: Row(
            children: [
              _filterChip(null, 'All'),
              const SizedBox(width: 4),
              _filterChip(FileChangeType.added, 'Added'),
              const SizedBox(width: 4),
              _filterChip(FileChangeType.modified, 'Modified'),
              const SizedBox(width: 4),
              _filterChip(FileChangeType.deleted, 'Deleted'),
              const Spacer(),
              const Icon(Icons.sync, size: 12, color: Colors.grey),
              const SizedBox(width: 4),
              const Text(
                'auto-refreshes',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: events.isEmpty
              ? const Center(
                  child: Text(
                    'No changes yet.\nThe AI team\'s file edits will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: events.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 44),
                  itemBuilder: (context, i) => _ChangeRow(
                    event: events[i],
                    controller: widget.controller,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(FileChangeType? type, String label) {
    final active = _filter == type;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      selected: active,
      onSelected: (_) => setState(() => _filter = type),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: const Color(0xFF1E1F26),
      selectedColor: const Color(0xFF7C4DFF).withValues(alpha: 0.3),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final FileChangeEvent event;
  final AppController controller;

  const _ChangeRow({required this.event, required this.controller});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (event.type) {
      FileChangeType.added => (Icons.add_circle, Colors.greenAccent),
      FileChangeType.modified => (Icons.edit, Colors.amber),
      FileChangeType.deleted => (Icons.remove_circle, Colors.redAccent),
    };
    final time = event.time;
    final minutes = DateTime.now().difference(time).inMinutes;
    final timeLabel = minutes < 1
        ? 'just now'
        : minutes < 60
            ? '$minutes min ago'
            : '${(minutes / 60).round()} h ago';

    return InkWell(
      onTap: event.type == FileChangeType.deleted
          ? null
          : () => controller.openFileAt(event.path),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.relPath,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '${event.label} · $timeLabel',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (event.type == FileChangeType.modified &&
                event.sizeLabel.isNotEmpty)
              Text(
                event.sizeLabel,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}
