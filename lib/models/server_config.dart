import 'dart:convert';

/// Which AI backend the opencode server should talk to.
enum AiProviderMode {
  /// opencode's built-in auth/model selection (default).
  builtin,

  /// Any OpenAI-compatible proxy (e.g. a FreeBuff proxy).
  custom,
}

class ServerConfig {
  /// Port for `opencode serve`. 0 means pick an automatic port.
  int port;

  AiProviderMode mode;
  String providerID;
  String baseURL;
  String apiKey;
  String modelID;

  /// Command used by the Backend Tester's migration checker
  /// (e.g. `npx prisma migrate status`).
  String migrationCheckCommand;

  ServerConfig({
    this.port = 0,
    this.mode = AiProviderMode.builtin,
    this.providerID = 'freebuff',
    this.baseURL = 'http://127.0.0.1:8080/v1',
    this.apiKey = '',
    this.modelID = '',
    this.migrationCheckCommand = '',
  });

  bool get usesCustomModel =>
      mode == AiProviderMode.custom && modelID.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'port': port,
        'mode': mode.name,
        'providerID': providerID,
        'baseURL': baseURL,
        'apiKey': apiKey,
        'modelID': modelID,
        'migrationCheckCommand': migrationCheckCommand,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        port: (json['port'] as num?)?.toInt() ?? 0,
        mode: json['mode'] == 'custom'
            ? AiProviderMode.custom
            : AiProviderMode.builtin,
        providerID: (json['providerID'] as String?) ?? 'freebuff',
        baseURL: (json['baseURL'] as String?) ?? 'http://127.0.0.1:8080/v1',
        apiKey: (json['apiKey'] as String?) ?? '',
        modelID: (json['modelID'] as String?) ?? '',
        migrationCheckCommand:
            (json['migrationCheckCommand'] as String?) ?? '',
      );

  ServerConfig copyWith({
    int? port,
    AiProviderMode? mode,
    String? providerID,
    String? baseURL,
    String? apiKey,
    String? modelID,
    String? migrationCheckCommand,
  }) =>
      ServerConfig(
        port: port ?? this.port,
        mode: mode ?? this.mode,
        providerID: providerID ?? this.providerID,
        baseURL: baseURL ?? this.baseURL,
        apiKey: apiKey ?? this.apiKey,
        modelID: modelID ?? this.modelID,
        migrationCheckCommand:
            migrationCheckCommand ?? this.migrationCheckCommand,
      );

  /// Inline opencode config that registers the custom provider and makes it
  /// the default model. Passed to `opencode serve` via OPENCODE_CONFIG_CONTENT.
  String? get opencodeConfigContent {
    if (!usesCustomModel) return null;
    final pid = providerID.trim();
    final mid = modelID.trim();
    return jsonEncode({
      'provider': {
        pid: {
          'npm': '@ai-sdk/openai-compatible',
          'name': '$pid (OpenAI-compatible)',
          'options': {
            'baseURL': baseURL.trim(),
            if (apiKey.trim().isNotEmpty) 'apiKey': apiKey.trim(),
          },
          'models': {
            mid: {'name': mid},
          },
        },
      },
      'model': '$pid/$mid',
    });
  }

  /// Shape of the `model` object to send on each message so the server
  /// resolves this custom model (required for custom providers).
  Map<String, String>? get messageModel {
    if (!usesCustomModel) return null;
    return {
      'modelID': modelID.trim(),
      'providerID': providerID.trim(),
    };
  }
}
