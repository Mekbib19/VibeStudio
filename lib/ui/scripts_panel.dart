import 'package:flutter/material.dart';

import '../services/port_service.dart';
import '../services/scripts_service.dart';
import '../services/vibe_store.dart';
import '../state/app_controller.dart';

/// Bottom launcher for the project's reusable scripts.
///
/// Shows the three standard actions — Run (start.sh), Stop (stop.sh),
/// Migration (migration.sh). If they are missing, opencode is opened on its
/// own to write them. Clicking a script or a live port opens a detail view in
/// the editor area (Thunder Client style, never a popup or modal).
class ScriptsPanel extends StatefulWidget {
  final AppController controller;
  final VoidCallback? onClose;

  const ScriptsPanel(this.controller, {super.key, this.onClose});

  @override
  State<ScriptsPanel> createState() => _ScriptsPanelState();
}

class _ScriptsPanelState extends State<ScriptsPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.ports.refresh();
      _autoBootstrap();
    });
  }

  void _autoBootstrap() {
    final scripts = widget.controller.scripts;
    if (scripts.bootstrapNeeded && !scripts.bootstrapping) {
      widget.controller.bootstrapScripts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.controller.scripts,
        widget.controller.ports,
      ]),
      builder: (context, _) {
        final scripts = widget.controller.scripts.scripts;
        final ports = widget.controller.ports;
        return DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(scripts.length, ports),
              const Divider(height: 1),
              _StandardBar(controller: widget.controller),
              _BootstrapBanner(controller: widget.controller),
              const Divider(height: 1),
              const TabBar(
                tabs: [
                  Tab(text: 'Scripts'),
                  Tab(text: 'Live Ports'),
                ],
                labelStyle: TextStyle(fontSize: 11),
                indicatorSize: TabBarIndicatorSize.label,
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildScriptsList(scripts),
                    _buildPortsList(ports),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------- scripts tab

  Widget _buildScriptsList(List<ScriptRun> scripts) {
    if (scripts.isEmpty) {
      return const Center(
        child: Text(
          'No scripts yet.\nAsk the AI to write them, or add one manually.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: scripts.length,
      itemBuilder: (context, i) => _ScriptTile(
        script: scripts[i],
        controller: widget.controller,
      ),
    );
  }

  // -------------------------------------------------------------- ports tab

  Widget _buildPortsList(PortService ports) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ports.ports.isEmpty
              ? Center(
                  child: ports.refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'No TCP ports in use right now.',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: ports.ports.length,
                  itemBuilder: (context, i) => _PortTile(
                    port: ports.ports[i],
                    controller: widget.controller,
                  ),
                ),
        ),
        const Divider(height: 1),
        _ManualPortBar(controller: widget.controller),
      ],
    );
  }

  // --------------------------------------------------------------- header

  Widget _buildHeader(int count, PortService ports) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF191A20),
      child: Row(
        children: [
          const Icon(Icons.directions_run, size: 15, color: Color(0xFF7C4DFF)),
          const SizedBox(width: 8),
          const Text(
            'Run Scripts',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            '$count script(s) · ${ports.ports.length} port(s)',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          IconButton(
            onPressed: () => widget.controller.ports.refresh(),
            icon: const Icon(Icons.refresh, size: 16),
            tooltip: 'Refresh ports',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: widget.controller.openScriptComposer,
            icon: const Icon(Icons.add, size: 16),
            tooltip: 'Add manual script',
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
    );
  }
}

/// The three standard actions: Run (start.sh), Stop (stop.sh),
/// Migration (migration.sh). Run restarts when the script is already running.
class _StandardBar extends StatelessWidget {
  final AppController controller;

  const _StandardBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scripts = controller.scripts;
    final run = scripts.standardScript('Run');
    final stop = scripts.standardScript('Stop');
    final migration = scripts.standardScript('Migration');

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      color: const Color(0xFF15161B),
      child: Row(
        children: [
          _standardButton(
            label: 'Run',
            icon: Icons.play_arrow,
            color: run?.running == true ? Colors.greenAccent : Colors.white,
            bg: run?.running == true
                ? Colors.greenAccent.withValues(alpha: 0.12)
                : null,
            tooltip: run == null
                ? 'start.sh missing'
                : 'Run start.sh (click again to restart)',
            enabled: run != null,
            onPressed: () {
              if (run != null) scripts.runOrRestart(run);
            },
          ),
          const SizedBox(width: 8),
          _standardButton(
            label: 'Stop',
            icon: Icons.stop,
            color: Colors.redAccent,
            tooltip: stop == null
                ? 'stop.sh missing'
                : 'Run stop.sh (also force-stops start.sh)',
            enabled: stop != null,
            onPressed: () => scripts.stopProject(),
          ),
          const SizedBox(width: 8),
          _standardButton(
            label: 'Migration',
            icon: Icons.data_object,
            color:
                migration?.running == true ? Colors.greenAccent : Colors.white,
            tooltip: migration == null
                ? 'migration.sh missing'
                : 'Run migration.sh',
            enabled: migration != null,
            onPressed: () {
              if (migration != null) scripts.run(migration);
            },
          ),
          const Spacer(),
          if (scripts.bootstrapNeeded) ...[
            Text(
              '${VibeStore.standardScripts.keys.where((k) => scripts.standardScript(k) == null).length} script(s) missing',
              style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _standardButton({
    required String label,
    required IconData icon,
    required Color color,
    Color? bg,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Material(
          color: bg ?? const Color(0xFF1E1F26),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
}

/// Banner shown while the standard scripts are missing and opencode is writing
/// them (or offering to). It always surfaces the real error and the AI's full
/// reply/log so the user can see exactly what went wrong.
class _BootstrapBanner extends StatelessWidget {
  final AppController controller;

  const _BootstrapBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scripts = controller.scripts;
    final hasLog = scripts.bootstrapLog.trim().isNotEmpty;
    if (!scripts.bootstrapNeeded && !scripts.bootstrapping) {
      return const SizedBox.shrink();
    }
    final error = scripts.bootstrapError;
    if (scripts.bootstrapping) {
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        color: const Color(0xFF1A1812),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'AI is writing start.sh / stop.sh / migration.sh…',
                style: TextStyle(fontSize: 11, color: Colors.orangeAccent),
              ),
            ),
            if (error != null)
              Flexible(
                child: Text(error,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.redAccent)),
              ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      color: const Color(0xFF1A1812),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(error == null
                  ? Icons.auto_awesome
                  : Icons.error_outline,
                  size: 13,
                  color: error == null ? Colors.orangeAccent : Colors.redAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error ?? 'start.sh / stop.sh / migration.sh not found',
                  style: TextStyle(
                    fontSize: 11,
                    color: error == null ? Colors.orangeAccent : Colors.redAccent,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => controller.bootstrapScripts(),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Generate with AI',
                    style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          if (error != null || hasLog) ...[
            const SizedBox(height: 2),
            Container(
              constraints: const BoxConstraints(maxHeight: 110),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF111216),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  hasLog
                      ? scripts.bootstrapLog
                      : (error ?? 'no log captured'),
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Quick stop/restart for a typed-in port. Feedback is inline (never a popup);
/// when the port is live it opens the port detail in the editor area instead.
class _ManualPortBar extends StatefulWidget {
  final AppController controller;

  const _ManualPortBar({required this.controller});

  @override
  State<_ManualPortBar> createState() => _ManualPortBarState();
}

class _ManualPortBarState extends State<_ManualPortBar> {
  final _port = TextEditingController();
  String _status = '';

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  Future<void> _act() async {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port <= 0) {
      setState(() => _status = 'enter a valid port number');
      return;
    }
    final entry =
        widget.controller.ports.ports.where((p) => p.port == port).firstOrNull;
    if (entry != null) {
      widget.controller.openPortDetail(entry);
      setState(() => _status = '');
      return;
    }
    setState(() => _status = 'nothing listening on port $port');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      child: Row(
        children: [
          const Text('Port',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(width: 6),
          SizedBox(
            width: 76,
            child: TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'e.g. 3000',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
              onSubmitted: (_) => _act(),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _act,
            icon: const Icon(Icons.open_in_full, size: 14),
            label: const Text('Open', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

/// A live port row. Tapping it opens the port detail in the editor area.
class _PortTile extends StatelessWidget {
  final ListenPort port;
  final AppController controller;

  const _PortTile({required this.port, required this.controller});

  @override
  Widget build(BuildContext context) {
    final managed = controller.scripts.scripts
        .any((s) => controller.scripts.pidOf(s) == port.pid);
    return InkWell(
      onTap: () => controller.openPortDetail(port),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 3, 8, 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1F26),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2A2B33)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${port.port}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: Color(0xFFB39DDB),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                [
                  if (port.command != null) port.command!,
                  if (port.pid != null) 'pid ${port.pid}',
                  if (managed) '· managed',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white60),
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

/// A script row. Tapping it opens the script detail in the editor area.
class _ScriptTile extends StatelessWidget {
  final ScriptRun script;
  final AppController controller;

  const _ScriptTile({required this.script, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isStandard = VibeStore.standardScripts.containsKey(script.name);
    return InkWell(
      onTap: () => controller.openScriptDetail(script),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 3, 8, 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1F26),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2A2B33)),
        ),
        child: Row(
          children: [
            _statusDot(script),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          script.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isStandard) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C4DFF)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'standard',
                            style: TextStyle(fontSize: 9, color: Color(0xFFB39DDB)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    script.command,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _statusDot(ScriptRun script) {
    final color = script.running ? Colors.greenAccent : Colors.grey;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
