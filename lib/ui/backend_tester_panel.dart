import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/backend_tester_service.dart';
import '../state/app_controller.dart';

enum _AuthType { none, bearer, basic, apiKey }

/// Built-in API client ("backend tester"), Thunder Client style. Lives in the
/// editor area (not a modal). Compose a request with Params / Headers / Auth /
/// Body tabs, send it, and inspect the response in Body / Headers tabs.
/// Completed requests are reported to the main AI so it can improve tasks.
class BackendTesterPanel extends StatefulWidget {
  final AppController controller;

  const BackendTesterPanel(this.controller, {super.key});

  @override
  State<BackendTesterPanel> createState() => _BackendTesterPanelState();
}

class _KV {
  final TextEditingController key;
  final TextEditingController value;
  _KV([String k = '', String v = ''])
      : key = TextEditingController(text: k),
        value = TextEditingController(text: v);

  void dispose() {
    key.dispose();
    value.dispose();
  }
}

class _BackendTesterPanelState extends State<BackendTesterPanel> {
  static const _methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];

  String _method = 'GET';
  final _url = TextEditingController();
  final _body = TextEditingController();
  final _params = <_KV>[];
  final _headers = <_KV>[];

  _AuthType _auth = _AuthType.none;
  final _bearer = TextEditingController();
  final _basicUser = TextEditingController();
  final _basicPass = TextEditingController();
  final _apiKeyName = TextEditingController();
  final _apiKeyValue = TextEditingController();

  BackendTesterService get svc => widget.controller.backendTester;

  @override
  void dispose() {
    _url.dispose();
    _body.dispose();
    for (final kv in [..._params, ..._headers]) {
      kv.dispose();
    }
    _bearer.dispose();
    _basicUser.dispose();
    _basicPass.dispose();
    _apiKeyName.dispose();
    _apiKeyValue.dispose();
    super.dispose();
  }

  String _buildUrl() {
    final base = _url.text.trim();
    if (base.isEmpty) return '';
    final params = _params
        .where((kv) => kv.key.text.trim().isNotEmpty)
        .map((kv) => '${kv.key.text.trim()}=${kv.value.text.trim()}')
        .join('&');
    if (params.isEmpty) return base;
    final sep = base.contains('?') ? '&' : '?';
    return '$base$sep$params';
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{};
    for (final kv in _headers) {
      final k = kv.key.text.trim();
      if (k.isNotEmpty) headers[k] = kv.value.text.trim();
    }
    switch (_auth) {
      case _AuthType.bearer:
        if (_bearer.text.trim().isNotEmpty) {
          headers['Authorization'] = 'Bearer ${_bearer.text.trim()}';
        }
      case _AuthType.basic:
        final creds =
            base64Encode(utf8.encode('${_basicUser.text}:${_basicPass.text}'));
        headers['Authorization'] = 'Basic $creds';
      case _AuthType.apiKey:
        final name = _apiKeyName.text.trim();
        if (name.isNotEmpty) headers[name] = _apiKeyValue.text.trim();
      case _AuthType.none:
        break;
    }
    return headers;
  }

  Future<void> _send() async {
    final url = _buildUrl();
    if (url.isEmpty) return;
    await svc.send(
      method: _method,
      url: url,
      headers: _buildHeaders(),
      body: _body.text,
    );
    final last = svc.last;
    if (last != null) {
      widget.controller.reportBackendResultToMain(last);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar(),
            const Divider(height: 1, color: Color(0xFF2A2B33)),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _buildRequestSide(),
                  ),
                  const VerticalDivider(width: 1, color: Color(0xFF2A2B33)),
                  Expanded(
                    flex: 6,
                    child: _buildResponseSide(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF191A20),
      child: Row(
        children: [
          const Icon(Icons.bolt, size: 17, color: Color(0xFF7C4DFF)),
          const SizedBox(width: 8),
          const Text(
            'Backend Tester',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: _method,
            dropdownColor: const Color(0xFF23242C),
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
            underline: const SizedBox.shrink(),
            items: [
              for (final m in _methods)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) => setState(() => _method = v ?? _method),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _url,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'http://localhost:3000/api',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: svc.sending ? null : _send,
            icon: svc.sending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send, size: 15),
            label: const Text('Send'),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: svc.last == null ? null : svc.clear,
            icon: const Icon(Icons.clear_all, size: 17),
            tooltip: 'Clear response',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- request side

  Widget _buildRequestSide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Request',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: Colors.grey.withValues(alpha: 0.9),
            ),
          ),
        ),
        Expanded(
          child: DefaultTabController(
            length: 4,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Params'),
                    Tab(text: 'Headers'),
                    Tab(text: 'Auth'),
                    Tab(text: 'Body'),
                  ],
                  labelStyle: TextStyle(fontSize: 11),
                  indicatorSize: TabBarIndicatorSize.label,
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _kvEditor(_params, 'Query parameters'),
                      _kvEditor(_headers, 'Request headers'),
                      _authEditor(),
                      _bodyEditor(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kvEditor(List<_KV> rows, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    'No $hint yet.',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rows[i].key,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'key',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                          ),
                          style: const TextStyle(
                              fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: rows[i].value,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'value',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                          ),
                          style: const TextStyle(
                              fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          rows[i].dispose();
                          rows.removeAt(i);
                        }),
                        icon: const Icon(Icons.remove_circle_outline, size: 15),
                        tooltip: 'Remove',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: OutlinedButton.icon(
            onPressed: () => setState(() => rows.add(_KV())),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('Add'),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
      ],
    );
  }

  Widget _authEditor() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        DropdownButtonFormField<_AuthType>(
          initialValue: _auth,
          decoration: const InputDecoration(
            labelText: 'Auth type',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12),
          ),
          items: const [
            DropdownMenuItem(value: _AuthType.none, child: Text('None')),
            DropdownMenuItem(value: _AuthType.bearer, child: Text('Bearer Token')),
            DropdownMenuItem(value: _AuthType.basic, child: Text('Basic Auth')),
            DropdownMenuItem(value: _AuthType.apiKey, child: Text('API Key')),
          ],
          onChanged: (v) => setState(() => _auth = v ?? _AuthType.none),
        ),
        const SizedBox(height: 12),
        switch (_auth) {
          _AuthType.none => const Text(
              'No authorization is sent.',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          _AuthType.bearer => _authField(_bearer, 'Token'),
          _AuthType.basic => Column(
              children: [
                _authField(_basicUser, 'Username'),
                const SizedBox(height: 8),
                _authField(_basicPass, 'Password', obscure: true),
              ],
            ),
          _AuthType.apiKey => Column(
              children: [
                _authField(_apiKeyName, 'Header name'),
                const SizedBox(height: 8),
                _authField(_apiKeyValue, 'Value'),
              ],
            ),
        },
      ],
    );
  }

  Widget _authField(TextEditingController c, String label, {bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
    );
  }

  Widget _bodyEditor() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: TextField(
        controller: _body,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          hintText: '{"key": "value"}',
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.all(8),
        ),
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }

  // ---------------------------------------------------------- response side

  Widget _buildResponseSide() {
    final last = svc.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                'Response',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: Colors.grey.withValues(alpha: 0.9),
                ),
              ),
              const Spacer(),
              if (last != null)
                _statusPill(last),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Body'),
                    Tab(text: 'Headers'),
                  ],
                  labelStyle: TextStyle(fontSize: 11),
                  indicatorSize: TabBarIndicatorSize.label,
                ),
                Expanded(child: _responseContent()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusPill(BackendRequestResult last) {
    final ok = last.success;
    final Color c = last.error != null
        ? Colors.redAccent
        : (ok ? Colors.greenAccent : Colors.redAccent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        last.error != null
            ? 'ERROR · ${last.elapsed?.inMilliseconds ?? '?'} ms'
            : '${last.statusCode} · ${last.elapsed?.inMilliseconds ?? '?'} ms',
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          color: c,
        ),
      ),
    );
  }

  Widget _responseContent() {
    final last = svc.last;
    if (last == null) {
      return const Center(
        child: Text(
          'No request yet.\nSend one and the response appears here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      );
    }
    return TabBarView(
      children: [
        Container(
          color: const Color(0xFF14151A),
          child: last.error != null
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    last.error!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent,
                        fontFamily: 'monospace'),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    last.body.isEmpty ? '(empty body)' : last.body,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      fontFamily: 'monospace',
                      color: Colors.white70,
                    ),
                  ),
                ),
        ),
        Container(
          color: const Color(0xFF14151A),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: last.headers.isEmpty
                ? const Text('(no response headers)',
                    style: TextStyle(color: Colors.grey, fontSize: 12))
                : SelectableText(
                    last.headers.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('\n'),
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      fontFamily: 'monospace',
                      color: Colors.blueGrey,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
