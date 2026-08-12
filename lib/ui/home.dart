import 'dart:math' as math;

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
  double _leftWidth = 260;
  double _rightWidth = 380;
  double _bottomHeight = 210;
  final Set<DockablePanel> _hidden = {
    DockablePanel.scripts,
    DockablePanel.changes,
    DockablePanel.backend,
  };
  final Map<DockablePanel, PanelSide> _panelSide = {
    DockablePanel.files: PanelSide.left,
    DockablePanel.agents: PanelSide.right,
    DockablePanel.todos: PanelSide.right,
    DockablePanel.logs: PanelSide.right,
    DockablePanel.terminal: PanelSide.bottom,
    DockablePanel.scripts: PanelSide.center,
    DockablePanel.changes: PanelSide.center,
    DockablePanel.backend: PanelSide.center,
  };
  bool _docking = false;

  /// The center-docked panel currently selected as the active center tab.
  /// Null means the file editor (or the active detail tab) is shown instead.
  DockablePanel? _centerPanel;
  String? _lastDetailTabId;
  String? _lastOpenFile;

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

  /// Center tabs coexist now, so instead of closing one thing to open another
  /// we simply deselect a selected center-docked panel whenever a file or a
  /// detail tab becomes the active center view — the panel tab stays open.
  void _onControllerChanged() {
    final c = widget.controller;
    var changed = false;
    if (c.openFile != _lastOpenFile) {
      _lastOpenFile = c.openFile;
      if (c.openFile != null && _centerPanel != null) {
        _centerPanel = null;
        changed = true;
      }
    }
    final tab = c.activeDetailTab;
    if (tab?.id != _lastDetailTabId) {
      _lastDetailTabId = tab?.id;
      if (tab != null && _centerPanel != null) {
        _centerPanel = null;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  /// Shows/hides a dockable panel (used by the toolbar toggles and keyboard
  /// shortcuts). Opening a panel that lives in the center selects it.
  void _togglePanel(DockablePanel panel) {
    setState(() {
      if (!_hidden.remove(panel)) {
        _hidden.add(panel);
        if (_centerPanel == panel) _centerPanel = null;
      } else if (_panelSide[panel] == PanelSide.center) {
        _centerPanel = panel;
      }
    });
  }

  /// Re-docks a panel onto another side after a drag-drop. Dropping on the
  /// center opens the panel as a center tab and selects it.
  void _dockPanel(DockablePanel panel, PanelSide side) {
    setState(() {
      _panelSide[panel] = side;
      _hidden.remove(panel);
      if (side == PanelSide.center) {
        _centerPanel = panel;
      } else if (_centerPanel == panel) {
        _centerPanel = null;
      }
    });
  }

  /// Hides a panel (close button): it returns to its default dock side and is
  /// marked hidden so it disappears from the layout entirely.
  void _hidePanel(DockablePanel panel) {
    setState(() {
      _hidden.add(panel);
      _panelSide[panel] = _defaultSide(panel);
      if (_centerPanel == panel) _centerPanel = null;
    });
  }

  void _selectEditor() {
    setState(() => _centerPanel = null);
    widget.controller.focusEditor();
  }

  void _selectPanel(DockablePanel panel) {
    setState(() => _centerPanel = panel);
    widget.controller.focusEditor();
  }

  static PanelSide _defaultSide(DockablePanel panel) => switch (panel) {
        DockablePanel.files => PanelSide.left,
        DockablePanel.agents => PanelSide.right,
        DockablePanel.todos => PanelSide.right,
        DockablePanel.logs => PanelSide.right,
        DockablePanel.terminal => PanelSide.bottom,
        DockablePanel.scripts => PanelSide.center,
        DockablePanel.changes => PanelSide.center,
        DockablePanel.backend => PanelSide.center,
      };

  /// Panels that start closed and are only opened on demand (via their toolbar
  /// toggles or the Panels menu).
  static const Set<DockablePanel> _defaultHiddenPanels = {
    DockablePanel.scripts,
    DockablePanel.changes,
    DockablePanel.backend,
  };

  /// True when the user has hidden a panel that is normally visible (files,
  /// agents, todos, logs, terminal). Lights up the Panels menu as a hint that
  /// something is tucked away.
  bool get _hasHiddenPanels {
    for (final p in DockablePanel.values) {
      if (_hidden.contains(p) && !_defaultHiddenPanels.contains(p)) return true;
    }
    return false;
  }

  /// Puts every panel back on its default side and resets the layout sizes.
  /// The escape hatch after hiding/moving panels around.
  void _resetLayout() {
    setState(() {
      for (final p in DockablePanel.values) {
        _panelSide[p] = _defaultSide(p);
      }
      _hidden
        ..clear()
        ..addAll(_defaultHiddenPanels);
      _centerPanel = null;
      _leftWidth = 260;
      _rightWidth = 380;
      _bottomHeight = 210;
    });
    widget.controller.focusEditor();
  }

  List<DockablePanel> _visiblePanelsOn(PanelSide side) => [
        for (final p in DockablePanel.values)
          if (_panelSide[p] == side && !_hidden.contains(p)) p,
      ];

  /// Stacks every panel docked on [side] vertically, each wrapped in a
  /// draggable tab strip (VS Code style) plus the panel body.
  Widget _buildSideColumn(PanelSide side) {
    final panels = _visiblePanelsOn(side);
    if (panels.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (var i = 0; i < panels.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Color(0xFF2A2B33)),
          Expanded(
            flex: _panelFlex(panels[i]),
            child: _DockPanel(
              panel: panels[i],
              controller: controller,
              onDragChanged: (v) => setState(() => _docking = v),
              onClose: () => _hidePanel(panels[i]),
            ),
          ),
        ],
      ],
    );
  }

  int _panelFlex(DockablePanel panel) => switch (panel) {
        DockablePanel.agents => 3,
        DockablePanel.todos => 5,
        DockablePanel.logs => 3,
        _ => 1,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleGlobalKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final maxW = constraints.maxWidth;
                      final maxH = constraints.maxHeight;
                      double clampLeft(double w) => w.clamp(
                            160,
                            math.max(160, maxW - _rightWidth - 340),
                          );
                      double clampRight(double w) => w.clamp(
                            280,
                            math.max(280, maxW - _leftWidth - 340),
                          );
                      final leftPanels = _visiblePanelsOn(PanelSide.left);
                      final rightPanels = _visiblePanelsOn(PanelSide.right);
                      final bottomPanels = _visiblePanelsOn(PanelSide.bottom);
                      return Column(
                        children: [
                          _buildToolbar(context),
                          const Divider(height: 1, color: Color(0xFF2A2B33)),
                          Expanded(
                            child: controller.isProjectOpen
                                ? Row(
                                    children: [
                                      if (leftPanels.isNotEmpty) ...[
                                        RepaintBoundary(
                                          child: SizedBox(
                                            width: clampLeft(_leftWidth),
                                            child: _buildSideColumn(
                                                PanelSide.left),
                                          ),
                                        ),
                                        _ResizeHandle(
                                          axis: Axis.vertical,
                                          onDelta: (dx) => setState(() =>
                                              _leftWidth = clampLeft(
                                                  _leftWidth + dx)),
                                          onDoubleTap: () =>
                                              setState(() => _leftWidth = 260),
                                        ),
                                      ],
                                      Expanded(
                                        child: RepaintBoundary(
                                            child: _buildCenter(context)),
                                      ),
                                      if (rightPanels.isNotEmpty) ...[
                                        _ResizeHandle(
                                          axis: Axis.vertical,
                                          onDelta: (dx) => setState(() =>
                                              _rightWidth = clampRight(
                                                  _rightWidth - dx)),
                                          onDoubleTap: () => setState(
                                              () => _rightWidth = 380),
                                        ),
                                        RepaintBoundary(
                                          child: SizedBox(
                                            width: clampRight(_rightWidth),
                                            child: _buildSideColumn(
                                                PanelSide.right),
                                          ),
                                        ),
                                      ],
                                    ],
                                  )
                                : _buildWelcome(context),
                          ),
                          if (bottomPanels.isNotEmpty) ...[
                            _ResizeHandle(
                              axis: Axis.horizontal,
                              onDelta: (dy) => setState(() =>
                                  _bottomHeight = (_bottomHeight - dy).clamp(
                                      120, math.max(120, maxH * 0.75))),
                              onDoubleTap: () =>
                                  setState(() => _bottomHeight = 210),
                            ),
                            RepaintBoundary(
                              child: SizedBox(
                                height: _bottomHeight,
                                child: _buildSideColumn(PanelSide.bottom),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            // Drop zones: drag a panel's tab to an edge to re-dock it there.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 44,
              child: _DropZone(
                side: PanelSide.left,
                active: _docking,
                onAccept: (p) => _dockPanel(p, PanelSide.left),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 44,
              child: _DropZone(
                side: PanelSide.right,
                active: _docking,
                onAccept: (p) => _dockPanel(p, PanelSide.right),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 44,
              child: _DropZone(
                side: PanelSide.bottom,
                active: _docking,
                onAccept: (p) => _dockPanel(p, PanelSide.bottom),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The center editor area. Doubles as a drop target: drag any panel's tab
  /// here to open it as a tab in the center (VS Code style).
  Widget _buildCenter(BuildContext context) {
    return DragTarget<DockablePanel>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _dockPanel(d.data, PanelSide.center),
      builder: (context, candidates, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: _buildCenterContent()),
            if (candidates.isNotEmpty)
              const IgnorePointer(child: _CenterDropHint()),
          ],
        );
      },
    );
  }

  /// The center column: tab strip (editor + detail tabs + center-docked
  /// panels) on top, the selected view below. Without any tabs it is just the
  /// plain editor.
  Widget _buildCenterContent() {
    final panels = _visiblePanelsOn(PanelSide.center);
    final hasTabs = panels.isNotEmpty || controller.detailTabs.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasTabs) ...[
          _buildCenterTabBar(panels),
          const Divider(height: 1, color: Color(0xFF2A2B33)),
        ],
        Expanded(child: _buildActiveCenterView()),
      ],
    );
  }

  Widget _buildActiveCenterView() {
    final panel = _centerPanel;
    if (panel != null &&
        !_hidden.contains(panel) &&
        _panelSide[panel] == PanelSide.center) {
      return _buildDockedPanel(panel);
    }
    final tab = controller.activeDetailTab;
    if (tab != null) return _buildDetailContent();
    return EditorPanel(controller);
  }

  /// VS Code-style tab strip for the center area. The editor tab is always
  /// first, then live detail tabs, then any panels docked to the center.
  Widget _buildCenterTabBar(List<DockablePanel> panels) {
    return Container(
      height: 34,
      color: const Color(0xFF191A20),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _CenterTab(
            icon: Icons.code,
            iconColor: const Color(0xFF7C4DFF),
            label: _editorTabLabel(),
            active: _centerPanel == null && controller.activeDetailTab == null,
            dirty: controller.openFile != null && controller.editorDirty,
            onTap: _selectEditor,
          ),
          for (final tab in controller.detailTabs)
            _CenterTab(
              icon: tab.icon,
              label: tab.label,
              active: _centerPanel == null &&
                  controller.activeDetailTab?.id == tab.id,
              onTap: () => controller.activateDetailTab(tab.id),
              onClose: () => controller.closeDetailTab(tab.id),
            ),
          for (final panel in panels)
            _DraggableCenterTab(
              panel: panel,
              active: _centerPanel == panel,
              onTap: () => _selectPanel(panel),
              onClose: () => _hidePanel(panel),
              onDragChanged: (v) => setState(() => _docking = v),
            ),
        ],
      ),
    );
  }

  String _editorTabLabel() {
    final path = controller.openFile;
    if (path == null || path.isEmpty) return 'Editor';
    return path.split('/').last.split('\\').last;
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

  /// Builds a dockable panel body in the center area.
  Widget _buildDockedPanel(DockablePanel panel) {
    return _buildDockedPanelBody(controller, panel,
        onClose: () => _hidePanel(panel));
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
          setState(() => _togglePanel(DockablePanel.terminal));
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.keyP:
        if (shift) {
          setState(() => _togglePanel(DockablePanel.scripts));
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.keyB:
        if (shift) {
          setState(() => _togglePanel(DockablePanel.backend));
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.keyG:
        if (shift) {
          setState(() => _togglePanel(DockablePanel.changes));
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
          PopupMenuButton<DockablePanel>(
            tooltip: 'Show / hide panels',
            icon: Icon(
              Icons.view_agenda_outlined,
              size: 20,
              color: _hasHiddenPanels
                  ? const Color(0xFF7C4DFF)
                  : Colors.grey,
            ),
            onSelected: (p) => setState(() => _togglePanel(p)),
            itemBuilder: (context) => [
              for (final p in DockablePanel.values)
                PopupMenuItem<DockablePanel>(
                  value: p,
                  height: 36,
                  child: Row(
                    children: [
                      Icon(
                        _panelMeta(p).$2,
                        size: 16,
                        color: _hidden.contains(p)
                            ? Colors.grey
                            : const Color(0xFF7C4DFF),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _panelMeta(p).$1,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      Icon(
                        _hidden.contains(p)
                            ? Icons.check_box_outline_blank
                            : Icons.check_box,
                        size: 16,
                        color: _hidden.contains(p)
                            ? Colors.grey
                            : const Color(0xFF7C4DFF),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: _resetLayout,
            icon: const Icon(Icons.restart_alt, size: 20, color: Colors.grey),
            tooltip: 'Reset layout (restore hidden panels)',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () =>
                setState(() => _togglePanel(DockablePanel.terminal)),
            icon: Icon(
              _hidden.contains(DockablePanel.terminal)
                  ? Icons.terminal_outlined
                  : Icons.terminal,
              size: 20,
              color: _hidden.contains(DockablePanel.terminal)
                  ? Colors.grey
                  : const Color(0xFF7C4DFF),
            ),
            tooltip: 'Toggle terminal (Ctrl+Shift+T)',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () => setState(() => _togglePanel(DockablePanel.scripts)),
            icon: Icon(
              _hidden.contains(DockablePanel.scripts)
                  ? Icons.directions_run_outlined
                  : Icons.directions_run,
              size: 20,
              color: _hidden.contains(DockablePanel.scripts)
                  ? Colors.grey
                  : const Color(0xFF7C4DFF),
            ),
            tooltip: 'Run scripts (Ctrl+Shift+P)',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () => setState(() => _togglePanel(DockablePanel.backend)),
            icon: Icon(
              _hidden.contains(DockablePanel.backend)
                  ? Icons.bolt_outlined
                  : Icons.bolt,
              size: 20,
              color: _hidden.contains(DockablePanel.backend)
                  ? Colors.grey
                  : const Color(0xFF7C4DFF),
            ),
            tooltip: 'Toggle backend tester (Ctrl+Shift+B)',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () => setState(() => _togglePanel(DockablePanel.changes)),
            icon: Icon(
              _hidden.contains(DockablePanel.changes)
                  ? Icons.commit_outlined
                  : Icons.commit,
              size: 20,
              color: _hidden.contains(DockablePanel.changes)
                  ? Colors.grey
                  : const Color(0xFF7C4DFF),
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
            onPressed: () => controller.openProject(),
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(controller.isProjectOpen ? 'Switch Project' : 'Open Project'),
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

/// Where a dockable panel currently lives. The center is the editor area:
/// panels dropped there appear as tabs alongside the open file.
enum PanelSide { left, right, bottom, center }

/// The dockable panels that can be dragged between sides, VS Code style.
/// Scripts / Changes / Backend tester default to the center (closed) and are
/// shown via their toolbar toggles or by dragging any panel into the center.
enum DockablePanel { files, agents, todos, logs, terminal, scripts, changes, backend }

/// (label, icon) pair for every dockable panel.
(String, IconData) _panelMeta(DockablePanel panel) => switch (panel) {
      DockablePanel.files => ('Files', Icons.folder_outlined),
      DockablePanel.agents => ('Agents', Icons.smart_toy_outlined),
      DockablePanel.todos => ('Todos', Icons.checklist_outlined),
      DockablePanel.logs => ('Logs', Icons.receipt_long_outlined),
      DockablePanel.terminal => ('Terminal', Icons.terminal),
      DockablePanel.scripts => ('Run scripts', Icons.directions_run),
      DockablePanel.changes => ('Changes', Icons.commit),
      DockablePanel.backend => ('Backend tester', Icons.bolt),
    };

/// VS Code-style resize handle. A thin draggable bar between two panels;
/// dragging moves the boundary, stretching/shrinking the panels. Double-click
/// resets the adjacent panel to its default size.
class _ResizeHandle extends StatefulWidget {
  final Axis axis;
  final ValueChanged<double> onDelta;
  final VoidCallback? onDoubleTap;

  const _ResizeHandle({
    required this.axis,
    required this.onDelta,
    this.onDoubleTap,
  });

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onDoubleTap,
        onHorizontalDragUpdate:
            horizontal ? null : (d) => widget.onDelta(d.delta.dx),
        onVerticalDragUpdate:
            horizontal ? (d) => widget.onDelta(d.delta.dy) : null,
        child: Container(
          width: horizontal ? double.infinity : 7,
          height: horizontal ? 7 : double.infinity,
          color: _hover ? const Color(0xFF23242C) : const Color(0xFF191A20),
          child: Center(
            child: Container(
              width: horizontal ? double.infinity : 1,
              height: horizontal ? 1 : double.infinity,
              color: _hover ? const Color(0xFF7C4DFF) : const Color(0xFF2A2B33),
            ),
          ),
        ),
      ),
    );
  }
}

/// A docked panel: slim draggable tab strip on top, panel body below.
class _DockPanel extends StatelessWidget {
  final DockablePanel panel;
  final AppController controller;
  final ValueChanged<bool> onDragChanged;
  final VoidCallback? onClose;

  const _DockPanel({
    required this.panel,
    required this.controller,
    required this.onDragChanged,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelTab(panel: panel, onDragChanged: onDragChanged),
        Expanded(
          child: _buildDockedPanelBody(controller, panel, onClose: onClose),
        ),
      ],
    );
  }
}

/// Builds the body of a dockable panel (used by side docks and center tabs).
Widget _buildDockedPanelBody(
  AppController controller,
  DockablePanel panel, {
  VoidCallback? onClose,
}) {
  return switch (panel) {
    DockablePanel.files => FileTree(controller),
    DockablePanel.agents => AgentPanel(controller),
    DockablePanel.todos => TodoPanel(controller),
    DockablePanel.logs => LogPanel(controller),
    DockablePanel.terminal => TerminalPanel(controller),
    DockablePanel.scripts => ScriptsPanel(controller, onClose: onClose),
    DockablePanel.changes => ChangesPanel(controller, onClose: onClose),
    DockablePanel.backend => BackendTesterPanel(controller),
  };
}

/// The grab bar of a docked panel. Dragging it onto an edge of the window
/// re-docks the panel on that side.
class _PanelTab extends StatelessWidget {
  final DockablePanel panel;
  final ValueChanged<bool> onDragChanged;

  const _PanelTab({required this.panel, required this.onDragChanged});

  @override
  Widget build(BuildContext context) {
    final (label, icon) = _panelMeta(panel);
    return Draggable<DockablePanel>(
      data: panel,
      onDragStarted: () => onDragChanged(true),
      onDragEnd: (_) => onDragChanged(false),
      onDragCompleted: () => onDragChanged(false),
      onDraggableCanceled: (_, _) => onDragChanged(false),
      feedback: _PanelTabPill(label: label, icon: icon),
      childWhenDragging: const Opacity(opacity: 0.35, child: _PanelTabBase()),
      child: Tooltip(
        message: 'Drag to move panel to another side',
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: _PanelTabBase(icon: icon, label: label),
        ),
      ),
    );
  }
}

class _PanelTabBase extends StatelessWidget {
  final IconData? icon;
  final String? label;

  const _PanelTabBase({this.icon, this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1F26),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2B33))),
      ),
      child: Row(
        children: [
          Icon(Icons.drag_indicator, size: 13, color: Colors.white38),
          const SizedBox(width: 4),
          if (icon != null) ...[
            Icon(icon, size: 13, color: const Color(0xFFB39DDB)),
            const SizedBox(width: 5),
          ],
          if (label != null)
            Expanded(
              child: Text(
                label!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Floating preview shown while a panel tab is being dragged.
class _PanelTabPill extends StatelessWidget {
  final String label;
  final IconData icon;

  const _PanelTabPill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF7C4DFF),
      elevation: 6,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edge-of-window drop target that appears while a panel is being dragged.
class _DropZone extends StatelessWidget {
  final PanelSide side;
  final bool active;
  final ValueChanged<DockablePanel> onAccept;

  const _DropZone({
    required this.side,
    required this.active,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !active,
      child: DragTarget<DockablePanel>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (d) => onAccept(d.data),
        builder: (context, candidates, _) {
          final over = candidates.isNotEmpty;
          final (arrow, alignment) = switch (side) {
            PanelSide.left => (Icons.arrow_back, Alignment.centerLeft),
            PanelSide.right => (Icons.arrow_forward, Alignment.centerRight),
            PanelSide.bottom => (Icons.arrow_downward, Alignment.bottomCenter),
            PanelSide.center => (Icons.open_in_full, Alignment.center),
          };
          return Container(
            alignment: alignment,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: over ? const Color(0x667C4DFF) : Colors.transparent,
              border: over
                  ? Border.all(color: const Color(0xFF7C4DFF), width: 2)
                  : null,
            ),
            child: AnimatedOpacity(
              opacity: over ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(arrow, color: Colors.white, size: 20),
            ),
          );
        },
      ),
    );
  }
}

/// One tab in the center tab strip (VS Code style): the editor, a live detail
/// tab, or a panel docked to the center. Tabs that can be closed show an X;
/// closing a detail tab never stops the underlying process.
class _CenterTab extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool active;
  final bool dirty;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final String? tooltip;

  const _CenterTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.iconColor = const Color(0xFF7C4DFF),
    this.dirty = false,
    this.onClose,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: onClose != null ? 150 : 130,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF14151A) : const Color(0xFF191A20),
        border: Border(
          right: const BorderSide(color: Color(0xFF2A2B33)),
          top: BorderSide(
            color: active ? iconColor : const Color(0xFF2A2B33),
            width: active ? 2 : 1,
          ),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 2),
          child: Row(
            children: [
              Icon(
                icon,
                size: 13,
                color: active ? iconColor : Colors.grey,
              ),
              const SizedBox(width: 6),
              if (dirty) ...[
                const Text('•',
                    style: TextStyle(color: Colors.amber, fontSize: 13)),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: active ? Colors.white : Colors.white60,
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close,
                      size: 13, color: Colors.white38),
                  tooltip: 'Close tab',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 24, height: 24),
                ),
            ],
          ),
        ),
      ),
    );
    if (tooltip == null) return content;
    return Tooltip(message: tooltip!, child: content);
  }
}

/// A center tab for a docked panel — it can also be dragged back out onto an
/// edge to re-dock the panel on the left/right/bottom.
class _DraggableCenterTab extends StatelessWidget {
  final DockablePanel panel;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<bool> onDragChanged;

  const _DraggableCenterTab({
    required this.panel,
    required this.active,
    required this.onTap,
    required this.onClose,
    required this.onDragChanged,
  });

  @override
  Widget build(BuildContext context) {
    final (label, icon) = _panelMeta(panel);
    final tab = _CenterTab(
      icon: icon,
      label: label,
      active: active,
      onTap: onTap,
      onClose: onClose,
      tooltip: 'Drag tab to move the panel to a side',
    );
    return Draggable<DockablePanel>(
      data: panel,
      onDragStarted: () => onDragChanged(true),
      onDragEnd: (_) => onDragChanged(false),
      onDragCompleted: () => onDragChanged(false),
      onDraggableCanceled: (_, _) => onDragChanged(false),
      feedback: _PanelTabPill(label: label, icon: icon),
      childWhenDragging: Opacity(opacity: 0.35, child: tab),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: tab,
      ),
    );
  }
}

/// Full-center highlight shown while a panel tab is dragged over the editor:
/// tells the user the drop will open the panel as a center tab.
class _CenterDropHint extends StatelessWidget {
  const _CenterDropHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x2A7C4DFF),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF7C4DFF),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Color(0x667C4DFF), blurRadius: 24),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_full, color: Colors.white, size: 17),
              SizedBox(width: 8),
              Text(
                'Drop to open in the center',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
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
