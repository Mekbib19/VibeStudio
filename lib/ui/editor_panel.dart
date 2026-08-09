import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/all.dart' as lang_all;

import '../services/language_service.dart';
import '../state/app_controller.dart';

Mode? _detectLanguage(String path) {
  final key = highlightModeForPath(path);
  if (key == null) return null;
  return lang_all.allLanguages[key];
}

class EditorPanel extends StatefulWidget {
  final AppController controller;

  const EditorPanel(this.controller, {super.key});

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> {
  CodeController? _code;
  String _path = '';
  bool _dirty = false;
  int _seenTick = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _code?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final c = widget.controller;
    if (c.openFile != _path) {
      final old = _code;
      _path = c.openFile ?? '';
      if (_path.isEmpty) {
        _code = null;
        _dirty = false;
      } else {
        _code = CodeController(
          text: c.editorContent,
          language: _detectLanguage(_path),
        );
        _listenToCode();
        _dirty = false;
        _seenTick = c.fileRefreshTick.value;
      }
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
      return;
    }
    if (_code != null && !_dirty && c.fileRefreshTick.value != _seenTick) {
      final newText = c.editorContent;
      if (newText != _code!.text) {
        _code!.value = _code!.value.copyWith(text: newText);
      }
      _seenTick = c.fileRefreshTick.value;
    }
  }

  void _listenToCode() {
    _code!.removeListener(_onCodeEdited);
    _code!.addListener(_onCodeEdited);
  }

  void _onCodeEdited() {
    if (!mounted || _code == null) return;
    setState(() => _dirty = true);
    widget.controller.markEditorDirtyQuiet(_code!.text);
  }

  Future<void> _save() async {
    if (_code == null || _path.isEmpty) return;
    widget.controller.markEditorDirtyQuiet(_code!.text);
    await widget.controller.saveEditor();
    if (mounted) {
      _dirty = false;
      _seenTick = widget.controller.fileRefreshTick.value;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Focus(
      autofocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            HardwareKeyboard.instance.isControlPressed &&
            event.logicalKey == LogicalKeyboardKey.keyS) {
          _save();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          _buildFileBar(),
          const Divider(height: 1, color: Color(0xFF2A2B33)),
          Expanded(
            child: _code == null || c.openFile == null
                ? const Center(
                    child: Text(
                      'Select a file to edit',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : Container(
                    color: const Color(0xFF14151A),
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CodeField(
                            controller: _code!,
                            expands: true,
                            wrap: false,
                            textStyle: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              height: 1.45,
                            ),
                            background: const Color(0xFF14151A),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 12,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0x1FFFFFFF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                languageForPath(_path).icon,
                                size: 16,
                                color: languageForPath(_path).color,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileBar() {
    final c = widget.controller;
    final name = _path.isEmpty ? '' : _path.split('/').last.split('\\').last;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF191A20),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 15, color: Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (_path.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF23242C),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2A2B33)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    languageForPath(_path).icon,
                    size: 12,
                    color: languageForPath(_path).color,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    languageNameForPath(_path),
                    style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
          if (_dirty)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text('•', style: TextStyle(color: Colors.amber, fontSize: 18)),
            ),
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined, size: 15),
            label: const Text('Save'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => c.openFileAt(c.openFile!),
            icon: const Icon(Icons.refresh, size: 16),
            tooltip: 'Reload from disk',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
