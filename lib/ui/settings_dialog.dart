import 'package:flutter/material.dart';

import '../models/server_config.dart';
import '../state/app_controller.dart';

Future<void> showSettingsDialog(
  BuildContext context,
  AppController controller,
) async {
  final cfg = controller.serverConfig;
  var port = cfg.port == 0 ? '' : '${cfg.port}';
  var providerID = cfg.providerID;
  var baseURL = cfg.baseURL;
  var apiKey = cfg.apiKey;
  var modelID = cfg.modelID;
  var mode = cfg.mode;

  final formKey = GlobalKey<FormState>();

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: const Text('Server settings'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'AI backend',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<AiProviderMode>(
                          value: mode,
                          items: const [
                            DropdownMenuItem(
                              value: AiProviderMode.builtin,
                              child: Text('opencode built-in'),
                            ),
                            DropdownMenuItem(
                              value: AiProviderMode.custom,
                              child: Text('OpenAI-compatible (FreeBuff…)'),
                            ),
                          ],
                          onChanged: (v) => setState(() => mode = v!),
                        ),
                      ],
                    ),
                    if (mode == AiProviderMode.custom) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: providerID,
                        decoration: const InputDecoration(
                          labelText: 'Provider ID',
                          helperText: 'opencode provider id (e.g. freebuff)',
                          isDense: true,
                        ),
                        onChanged: (v) => providerID = v.trim(),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: baseURL,
                        decoration: const InputDecoration(
                          labelText: 'Base URL',
                          helperText:
                              'OpenAI-compatible endpoint, e.g. http://127.0.0.1:8080/v1',
                          isDense: true,
                        ),
                        onChanged: (v) => baseURL = v.trim(),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: apiKey,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'API key',
                          helperText: 'optional, sent as Bearer token',
                          isDense: true,
                        ),
                        onChanged: (v) => apiKey = v,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: modelID,
                        decoration: const InputDecoration(
                          labelText: 'Model ID',
                          helperText: 'e.g. deepseek-v4-flash',
                          isDense: true,
                        ),
                        onChanged: (v) => modelID = v.trim(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Server port',
                        helperText: 'opencode serve port (leave empty for auto)',
                        isDense: true,
                      ),
                      onChanged: (v) => port = v.trim(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsedPort = int.tryParse(port) ?? 0;
                Navigator.of(context).pop();
                controller.applySettings(
                  ServerConfig(
                    port: parsedPort.clamp(0, 65535),
                    mode: mode,
                    providerID: providerID,
                    baseURL: baseURL,
                    apiKey: apiKey,
                    modelID: modelID,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}
