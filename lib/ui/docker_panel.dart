import 'package:flutter/material.dart';

import '../services/docker_service.dart';

/// Docker compose panel shown in a modal bottom sheet.
///
/// Start/stop the project stack and watch its logs. Everything is best-effort;
/// if `docker` is not installed the service reports it instead of crashing.
class DockerPanel extends StatefulWidget {
  final DockerService docker;

  const DockerPanel(this.docker, {super.key});

  @override
  State<DockerPanel> createState() => _DockerPanelState();
}

class _DockerPanelState extends State<DockerPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.docker.refreshStatus();
    widget.docker.startLogs();
  }

  @override
  void dispose() {
    widget.docker.stopLogs();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.docker,
      builder: (context, _) {
        final docker = widget.docker;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.architecture, color: Color(0xFF42A5F5), size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Docker compose',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: docker.refreshStatus,
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Refresh status',
                    visualDensity: VisualDensity.compact,
                  ),
                  OutlinedButton.icon(
                    onPressed: docker.down,
                    icon: const Icon(Icons.stop, size: 15),
                    label: const Text('Down'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: docker.up,
                    icon: const Icon(Icons.play_arrow, size: 15),
                    label: const Text('Up'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                docker.statusLine.isEmpty
                    ? (docker.lastError ?? 'checking…')
                    : docker.statusLine,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: docker.composeActive
                      ? Colors.greenAccent
                      : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: docker.logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No container logs yet.\nPress Up to start the stack.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(10),
                      itemCount: docker.logs.length,
                      itemBuilder: (context, i) => Text(
                        docker.logs[i],
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.white70,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
