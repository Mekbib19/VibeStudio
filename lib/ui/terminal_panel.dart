import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../services/terminal_service.dart';
import '../state/app_controller.dart';

/// Embedded interactive terminal (PTY shell) for the project.
///
/// Type anything here — e.g. `opencode serve --port 4066` or `freebuff`
/// (FreeBuff opens as its interactive TUI right in this panel).
class TerminalPanel extends StatefulWidget {
  final AppController controller;

  const TerminalPanel(this.controller, {super.key});

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final TextEditingController _port = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cfgPort = widget.controller.serverConfig.port;
    _port.text = cfgPort > 0 ? '$cfgPort' : '';
    widget.controller.terminal.ensureStarted();
  }

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  String get _resolvedPort {
    final p = _port.text.trim();
    return p.isEmpty ? '4066' : p;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller.terminal,
      builder: (context, _) {
        final terminal = widget.controller.terminal;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(terminal),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cols =
                      (constraints.maxWidth / 8.5).floor().clamp(20, 600);
                  final rows =
                      (constraints.maxHeight / 16.5).floor().clamp(5, 300);
                  terminal.resize(rows, cols);
                  return TerminalView(
                    terminal.terminal,
                    autofocus: true,
                    backgroundOpacity: 0,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(TerminalService terminal) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFF191A20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.terminal, size: 16, color: Color(0xFF7C4DFF)),
            const SizedBox(width: 8),
            const Text(
              'Agent Terminal',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            if (!terminal.isRunning)
              const Text(
                'shell not running',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            const SizedBox(width: 8),
            Container(
              width: 68,
              margin: const EdgeInsets.only(right: 6),
              child: TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'port',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 6),
                ),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
            _LaunchButton(
              label: '▶ opencode serve',
              onPressed: () =>
                  terminal.write('opencode serve --port $_resolvedPort\n'),
            ),
            const SizedBox(width: 6),
            _LaunchButton(
              label: '▶ freebuff',
              onPressed: () => terminal.write('freebuff\n'),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: terminal.sendCtrlC,
              icon: const Icon(Icons.stop_circle_outlined, size: 17),
              tooltip: 'Send Ctrl+C',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: terminal.clear,
              icon: const Icon(Icons.clear_all, size: 17),
              tooltip: 'Clear screen',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: terminal.isRunning
                  ? () => terminal.write('exit\n')
                  : () => widget.controller.terminal.ensureStarted(),
              icon: const Icon(Icons.replay, size: 17),
              tooltip: terminal.isRunning ? 'Exit shell' : 'Start shell',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _LaunchButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _LaunchButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}
