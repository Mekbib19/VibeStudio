import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/agent.dart';
import '../models/detail_tab.dart';
import '../services/server_service.dart';
import '../state/app_controller.dart';
import 'agent_panel.dart';
import 'backend_tester_panel.dart';
import 'changes_panel.dart';
import 'docker_panel.dart';
import 'editor_panel.dart';
import 'file_tree.dart';
import 'log_panel.dart';
import 'script_detail_panels.dart';
import 'scripts_panel.dart';
import 'settings_dialog.dart';
import 'terminal_panel.dart';
import 'todo_panel.dart';

class HomePage extends StatefulWidget {
  final AppController controller;

  const HomePage({super.key, required this.controller});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  _BottomPanel _bottom = _BottomPanel.terminal;
  bool _showBackendTester = false;
  bool _showScripts = false;
  bool _showChanges = false;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// When a detail tab opens, drop any full-center panel (run scripts /
  /// changes / backend tester) so the new tab is visible immediately — no
  /// overlap and no need to close one thing before opening another.
  void _onControllerChanged() {
    if (widget.controller.detailTabs.isEmpty) return;
    if (!_showBackendTester && !_showScripts && !_showChanges) return;
    setState(() {
      _showBackendTester = false;
      _showScripts = false;
      _showChanges = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleGlobalKey,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            return Column(
              children: [
                _buildToolbar(context),
                const Divider(height: 1, color: Color(0xFF2A2B33)),
                Expanded(
                  child: controller.isProjectOpen
                      ? Row(
                          children: [
                            SizedBox(width: 260, child: FileTree(controller)),
                            const VerticalDivider(width: 1),
                            Expanded(child: _buildCenter(context)),
                            const VerticalDivider(width: 1),
                            SizedBox(
                              width: 380,
                              child: Column(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: AgentPanel(controller),
                                  ),
                                  const Divider(height: 1),
                                  Expanded(
                                    flex: 5,
                                    child: TodoPanel(controller),
                                  ),
                                  const Divider(height: 1),
                                  Expanded(
                                    flex: 3,
                                    child: LogPanel(controller),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : _buildWelcome(context),
                ),
                if (_bottom != _BottomPanel.none) ...[
                  const Divider(height: 1, color: Color(0xFF2A2B33)),
                  SizedBox(
                    height: 210,
                    child: TerminalPanel(controller),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCenter(BuildContext context) {
    if (_showBackendTester) {
      return BackendTesterPanel(controller);
    }
    if (_showScripts) {
      return ScriptsPanel(controller,
          onClose: () => setState(() => _showScripts = false));
    }
    if (_showChanges) {
      return ChangesPanel(controller,
          onClose: () => setState(() => _showChanges = false));
    }
    return _buildDetailArea(context);
  }

  /// The detail-tab strip above the editor (VS Code style). Falls back to the
  /// plain editor when no detail tabs are open.
  Widget _buildDetailArea(BuildContext context) {
    final tabs = controller.detailTabs;
    if (tabs.isEmpty) return EditorPanel(controller);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailTabBar(controller: controller),
        const Divider(height: 1, color: Color(0xFF2A2B33)),
        Expanded(child: _buildDetailContent()),
      ],
    );
  }

  Widget _buildDetailContent() {
    final tab = controller.activeDetailTab;
    if (tab == null) return EditorPanel(controller);
    switch (tab.kind) {
      case DetailTabKind.port:
        final port = controller.activePort;
        if (port == null) {
          return const _DetailGoneMessage(
            icon: Icons.bolt_outlined,
            message: 'This port is no longer listening.',
          );
        }
        return PortDetailPanel(controller, port);
      case DetailTabKind.script:
        final script = controller.activeScript;
        if (script == null) {
          return const _DetailGoneMessage(
            icon: Icons.directions_run,
            message: 'This script is no longer available.',
          );
        }
        return ScriptDetailPanel(controller, script);
      case DetailTabKind.composer:
        return ScriptComposerPanel(controller);
    }
  }

  /// App-wide keyboard shortcuts (editor keeps its own Ctrl+S).
  KeyEventResult _handleGlobalKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (!ctrl) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyT:
        if (shift) {
          setState(() => _bottom = _bottom == _BottomPanel.terminal
              ? _BottomPanel.none
              : _BottomPanel.terminal);
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.keyP:
        if (shift) {
          setState(() => _showScripts = !_showScripts);
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.keyB:
        if (shift) {
          setState(() => _showBackendTester = !_showBackendTester);
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.keyG:
        if (shift) {
          setState(() => _showChanges = !_showChanges);
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.keyF:
        if (shift) {
          controller.collapseAllDirs();
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.keyN:
        if (!shift) {
          _addAgentFlow();
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.keyS:
        if (shift) {
          controller.stopAll();
          return KeyEventResult.handled;
        }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _addAgentFlow() async {
    if (!controller.isProjectOpen) return;
    final details = await _askAgentDetails(context);
    if (details == null) return;
    controller.addAgent(
      name: details.name,
      role: details.role,
      isMain: details.isMain,
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final statusColor = switch (controller.server.state) {
      ServerState.running => Colors.greenAccent,
      ServerState.error => Colors.redAccent,
      ServerState.starting => Colors.amber,
      ServerState.stopped => Colors.grey,
    };
    return Container(
      height: 48,
      decoration: const BoxDecoration(color: Color(0xFF191A20)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.dashboard_customize, color: Color(0xFF7C4DFF), size: 22),
            const SizedBox(width: 8),
            const Text(
              'Vibe Studio',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(width: 16),
            if (controller.projectDir != null) ...[
              SizedBox(
                width: 240,
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        controller.projectDir!,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else
              const SizedBox(width: 12),
            const SizedBox(width: 12),
          if (controller.isProjectOpen) ...[
            if (controller.env.databases.isNotEmpty)
              _ToolChip(
                icon: Icons.storage,
                text: controller.env.databases.join(', '),
                tooltip: 'Detected databases',
              ),
            if (controller.env.envCount > 0)
              _ToolChip(
                icon: Icons.key,
                text: 'env ${controller.env.envCount}',
                tooltip: '${controller.env.envCount} variables loaded from .env',
                onPressed: controller.reloadEnv,
              ),
            if (controller.env.composeFile != null) ...[
              IconButton(
                onPressed: _openDockerSheet,
                icon: const Icon(Icons.architecture, size: 20, color: Color(0xFF42A5F5)),
                tooltip: 'Docker compose',
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
            ],
            const SizedBox(width: 8),
          ],
          _StatusDot(color: statusColor),
          const SizedBox(width: 6),
          Text(
            controller.serverStatusLabel,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: () => setState(() => _bottom = _bottom == _BottomPanel.terminal
                ? _BottomPanel.none
                : _BottomPanel.terminal),
            icon: Icon(
              _bottom == _BottomPanel.terminal
                  ? Icons.terminal
                  : Icons.terminal_outlined,
              size: 20,
              color: _bottom == _BottomPanel.terminal
                  ? const Color(0xFF7C4DFF)
                  : Colors.grey,
            ),
            tooltip: 'Toggle terminal (Ctrl+Shift+T)',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () => setState(() => _showScripts = !_showScripts),
            icon: Icon(
              _showScripts ? Icons.directions_run : Icons.directions_run_outlined,
              size: 20,
              color: _showScripts ? const Color(0xFF7C4DFF) : Colors.grey,
            ),
            tooltip: 'Run scripts (Ctrl+Shift+P)',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () => setState(() => _showBackendTester = !_showBackendTester),
            icon: Icon(
              _showBackendTester ? Icons.bolt : Icons.bolt_outlined,
              size: 20,
              color: _showBackendTester ? const Color(0xFF7C4DFF) : Colors.grey,
            ),
            tooltip: 'Toggle backend tester (Ctrl+Shift+B)',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () => setState(() => _showChanges = !_showChanges),
            icon: Icon(
              _showChanges ? Icons.commit : Icons.commit_outlined,
              size: 20,
              color: _showChanges ? const Color(0xFF7C4DFF) : Colors.grey,
            ),
            tooltip: 'Project changes (Ctrl+Shift+G)',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => showSettingsDialog(context, controller),
            icon: const Icon(Icons.settings, size: 20, color: Colors.grey),
            tooltip: 'Server & AI settings',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          if (controller.isProjectOpen)
            OutlinedButton.icon(
              onPressed: _addAgentFlow,
              icon: const Icon(Icons.smart_toy, size: 16),
              label: const Text('Add Agent'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          const SizedBox(width: 8),
          if (controller.isProjectOpen)
            TextButton.icon(
              onPressed: controller.stopAll,
              icon: const Icon(Icons.stop, size: 16),
              label: const Text('Stop All'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: controller.isProjectOpen
                ? null
                : () => controller.openProject(),
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(controller.isProjectOpen ? 'Project Open' : 'Open Project'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          ListenableBuilder(
            listenable: controller.store,
            builder: (context, _) {
              final recents = controller.store.recentProjects
                  .where((p) => p != controller.projectDir)
                  .toList();
              if (recents.isEmpty) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                tooltip: 'Recent projects',
                icon: const Icon(Icons.history, size: 18),
                onSelected: (dir) => controller.openProjectAt(dir),
                itemBuilder: (context) => recents
                    .map((p) => PopupMenuItem<String>(
                          value: p,
                          child: Row(
                            children: [
                              const Icon(Icons.folder, size: 16),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 320),
                                child: Text(
                                  p,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  void _openDockerSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF191A20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: DockerPanel(controller.docker),
      ),
    );
  }

  Widget _buildWelcome(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.dashboard_customize,
              size: 72, color: Color(0xFF7C4DFF)),
          const SizedBox(height: 16),
          const Text(
            'Vibe Studio',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'A code editor where a team of AI agents\nwork through a shared todo list.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => controller.openProject(),
            icon: const Icon(Icons.folder_open),
            label: const Text('Open a project folder'),
          ),
        ],
      ),
    );
  }
}

enum _BottomPanel { terminal, none }

/// VS Code-style tab strip for the center editor area. Each tab has an X that
/// closes only the view — the underlying process keeps running.
class _DetailTabBar extends StatelessWidget {
  final AppController controller;

  const _DetailTabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final activeId = controller.activeDetailTab?.id;
    return Container(
      height: 34,
      color: const Color(0xFF191A20),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final tab in controller.detailTabs)
            _buildTab(tab, tab.id == activeId),
        ],
      ),
    );
  }

  Widget _buildTab(DetailTab tab, bool active) {
    return Container(
      width: 150,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF14151A) : const Color(0xFF191A20),
        border: Border(
          right: const BorderSide(color: Color(0xFF2A2B33)),
          top: BorderSide(
            color: active ? const Color(0xFF7C4DFF) : const Color(0xFF2A2B33),
            width: active ? 2 : 1,
          ),
        ),
      ),
      child: InkWell(
        onTap: () => controller.activateDetailTab(tab.id),
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 2),
          child: Row(
            children: [
              Icon(
                tab.icon,
                size: 13,
                color: active ? const Color(0xFF7C4DFF) : Colors.grey,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tab.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: active ? Colors.white : Colors.white60,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => controller.closeDetailTab(tab.id),
                icon: const Icon(Icons.close, size: 13, color: Colors.white38),
                tooltip: 'Close tab (process keeps running)',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                    width: 24, height: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder shown when the item behind an open tab is gone (e.g. the port
/// stopped listening). The tab stays until the user closes it.
class _DetailGoneMessage extends StatelessWidget {
  final IconData icon;
  final String message;

  const _DetailGoneMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: Colors.grey),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ToolChip({
    required this.icon,
    required this.text,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF23242C),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2A2B33)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: const Color(0xFFB39DDB)),
              const SizedBox(width: 5),
              Text(
                text,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<_AgentDetails?> _askAgentDetails(BuildContext context) async {
  final nameController = TextEditingController();
  var isMain = false;
  var role = AgentRole.engineer;
  final details = await showDialog<_AgentDetails>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Add AI agent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Agent name',
                hintText: 'e.g. Architect',
              ),
              onSubmitted: (v) => Navigator.of(context).pop(
                _AgentDetails(nameController.text, role, isMain),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<AgentRole>(
              initialValue: role,
              decoration: const InputDecoration(
                labelText: 'Role',
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              items: const [
                DropdownMenuItem(
                  value: AgentRole.engineer,
                  child: Text('Engineer — writes code (routes, models, controllers)'),
                ),
                DropdownMenuItem(
                  value: AgentRole.tester,
                  child: Text('Tester — QA, verifies finished work'),
                ),
                DropdownMenuItem(
                  value: AgentRole.coordinator,
                  child: Text('Coordinator — main AI, orchestrates the team'),
                ),
              ],
              onChanged: (v) => setState(() => role = v ?? role),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: isMain,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              secondary: const Icon(Icons.star, color: Colors.amber),
              title: const Text('Main agent (orchestrator)'),
              subtitle: const Text(
                'Only one can be active; it assigns tasks, never shuts down.',
                style: TextStyle(fontSize: 11),
              ),
              onChanged: (v) => setState(() => isMain = v ?? false),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              _AgentDetails(nameController.text, role, isMain),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
  nameController.dispose();
  if (details == null || details.name.trim().isEmpty) return null;
  return details;
}

class _AgentDetails {
  final String name;
  final AgentRole role;
  final bool isMain;
  const _AgentDetails(this.name, this.role, this.isMain);
}
