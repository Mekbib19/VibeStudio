import 'dart:async';

import 'package:flutter/material.dart';

import '../services/port_service.dart';
import '../services/scripts_service.dart';
import '../services/vibe_store.dart';
import '../state/app_controller.dart';

/// Detail views rendered in the center editor area (Thunder Client style).
/// Nothing here opens a popup or modal — everything is inline.

// ------------------------------------------------------------------ port

class PortDetailPanel extends StatefulWidget {
  final AppController controller;
  final ListenPort port;

  const PortDetailPanel(this.controller, this.port, {super.key});

  @override
  State<PortDetailPanel> createState() => _PortDetailPanelState();
}

class _PortDetailPanelState extends State<PortDetailPanel> {
  String _status = '';

  AppController get controller => widget.controller;

  ScriptRun? _managedScript(ListenPort port) {
    for (final s in controller.scripts.scripts) {
      if (controller.scripts.pidOf(s) == port.pid) return s;
    }
    return null;
  }

  Future<void> _stop(ListenPort port) async {
    setState(() => _status = 'stopping…');
    final managed = _managedScript(port);
    final err = await controller.ports.stopPort(port.port);
    if (managed != null && managed.running) {
      await controller.scripts.stop(managed);
    }
    if (!mounted) return;
    setState(() => _status = err == null
        ? 'stopped port ${port.port}'
        : 'stop failed: $err');
    await controller.ports.refresh();
  }

  Future<void> _restart(ListenPort port) async {
    setState(() => _status = 'restarting…');
    final managed = _managedScript(port);
    final err = await controller.ports.stopPort(port.port);
    if (!mounted) return;
    if (err != null) {
      setState(() => _status = 'stop failed: $err');
      return;
    }
    if (managed != null) {
      await controller.scripts.run(managed);
      setState(() => _status = 'restarted "${managed.name}" on port ${port.port}');
    } else {
      setState(() => _status =
          'stopped port ${port.port} — not a managed script, nothing to restart');
    }
    await controller.ports.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final port = widget.port;
    final managed = _managedScript(port);
    return ListenableBuilder(
      listenable: Listenable.merge([controller.ports, controller.scripts]),
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topBar('Port ${port.port}', 'listening port',
                onClose: controller.closeDetail),
            const Divider(height: 1, color: Color(0xFF2A2B33)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _infoCard(port, managed),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _actionBtn(
                        label: 'Refresh',
                        icon: Icons.refresh,
                        onTap: () => controller.ports.refresh(),
                      ),
                      const SizedBox(width: 8),
                      _actionBtn(
                        label: 'Stop',
                        icon: Icons.stop,
                        color: Colors.redAccent,
                        onTap: () => _stop(port),
                      ),
                      const SizedBox(width: 8),
                      _actionBtn(
                        label: 'Restart',
                        icon: Icons.replay,
                        color: managed != null
                            ? Colors.white70
                            : Colors.white24,
                        onTap: managed != null ? () => _restart(port) : null,
                        tooltip: managed != null
                            ? 'Restart "${managed.name}" on this port'
                            : 'Not a managed script — cannot restart',
                      ),
                    ],
                  ),
                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: _status.startsWith('stop failed')
                            ? Colors.redAccent
                            : Colors.greenAccent,
                      ),
                    ),
                  ],
                  if (managed != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '${managed.name} — live log',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    _LogView(logs: managed.logs, error: managed.lastError),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoCard(ListenPort port, ScriptRun? managed) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2B33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('Port', '${port.port}'),
          _infoRow('PID', port.pid?.toString() ?? 'unknown'),
          _infoRow('Command', port.command ?? 'unknown'),
          _infoRow(
            'Managed script',
            managed == null
                ? 'none'
                : '${managed.name} (${managed.running ? 'running' : 'stopped'})',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- script

class ScriptDetailPanel extends StatefulWidget {
  final AppController controller;
  final ScriptRun script;

  const ScriptDetailPanel(this.controller, this.script, {super.key});

  @override
  State<ScriptDetailPanel> createState() => _ScriptDetailPanelState();
}

class _ScriptDetailPanelState extends State<ScriptDetailPanel> {
  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final script = widget.script;
    final isStandard =
        VibeStore.standardScripts.containsKey(script.name);
    return ListenableBuilder(
      listenable: controller.scripts,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topBar(script.name, script.command,
                onClose: controller.closeDetail),
            const Divider(height: 1, color: Color(0xFF2A2B33)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _buildChips(script),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _actionBtn(
                        label: script.running ? 'Restart' : 'Run',
                        icon: script.running
                            ? Icons.replay
                            : Icons.play_arrow,
                        color: Colors.greenAccent,
                        onTap: () => controller.scripts.runOrRestart(script),
                      ),
                      const SizedBox(width: 8),
                      _actionBtn(
                        label: 'Stop',
                        icon: Icons.stop,
                        color: Colors.redAccent,
                        onTap: () => controller.scripts.stop(script),
                      ),
                      if (!isStandard) ...[
                        const SizedBox(width: 8),
                        _actionBtn(
                          label: 'Remove',
                          icon: Icons.delete_outline,
                          onTap: () {
                            controller.scripts.removeManual(script);
                            controller.closeDetail();
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Output',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  _LogView(logs: script.logs, error: script.lastError),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  List<Widget> _buildChips(ScriptRun script) {
    final chips = <Widget>[
      _chip(
        script.running ? 'RUNNING' : 'STOPPED',
        script.running ? Colors.greenAccent : Colors.grey,
      ),
      if (script.exitCode != null)
        _chip('exit ${script.exitCode}', Colors.grey),
    ];
    final pid = controller.scripts.pidOf(script);
    if (pid != null) chips.add(_chip('pid $pid', Colors.blueGrey));
    if (VibeStore.standardScripts.containsKey(script.name)) {
      chips.add(_chip('standard', const Color(0xFF7C4DFF)));
    }
    return chips;
  }
}

// --------------------------------------------------------------- composer

/// Inline "add manual script" form (code-editor style, no dialog).
class ScriptComposerPanel extends StatefulWidget {
  final AppController controller;

  const ScriptComposerPanel(this.controller, {super.key});

  @override
  State<ScriptComposerPanel> createState() => _ScriptComposerPanelState();
}

class _ScriptComposerPanelState extends State<ScriptComposerPanel> {
  final _name = TextEditingController();
  final _command = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    super.dispose();
  }

  void _add() {
    final cmd = _command.text.trim();
    if (cmd.isEmpty) {
      setState(() => _error = 'command is required');
      return;
    }
    widget.controller.scripts.addManual(_name.text, cmd);
    widget.controller.closeDetail();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _topBar('Add script', 'manual run command',
            onClose: widget.controller.closeDetail),
        const Divider(height: 1, color: Color(0xFF2A2B33)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const Text(
                'Name',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'e.g. Seed database',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Command',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _command,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'e.g. npm run seed',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_error,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.redAccent)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  _actionBtn(
                    label: 'Add script',
                    icon: Icons.add,
                    onTap: _add,
                  ),
                  const SizedBox(width: 8),
                  _actionBtn(
                    label: 'Cancel',
                    icon: Icons.close,
                    onTap: widget.controller.closeDetail,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- shared bits

Widget _topBar(String title, String subtitle, {VoidCallback? onClose}) {
  return Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    color: const Color(0xFF191A20),
    child: Row(
      children: [
        const Icon(Icons.directions_run, size: 17, color: Color(0xFF7C4DFF)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: Colors.grey),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close, size: 17),
          tooltip: 'Back to editor',
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
  );
}

Widget _actionBtn({
  required String label,
  required IconData icon,
  Color color = Colors.white70,
  VoidCallback? onTap,
  String? tooltip,
}) {
  final enabled = onTap != null;
  return Tooltip(
    message: tooltip ?? label,
    child: Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: const Color(0xFF1E1F26),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _LogView extends StatelessWidget {
  final List<String> logs;
  final String? error;

  const _LogView({required this.logs, this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF14151A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2B33)),
      ),
      child: logs.isEmpty && error == null
          ? const Text(
              'no output yet',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            )
          : ListView.builder(
              reverse: true,
              itemCount: logs.length + (error != null ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == logs.length) {
                  return Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.redAccent,
                    ),
                  );
                }
                final l = logs[logs.length - 1 - i];
                return Text(
                  l,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.white60,
                  ),
                );
              },
            ),
    );
  }
}
