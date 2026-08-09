import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_studio/models/server_config.dart';

void main() {
  group('ServerConfig', () {
    test('defaults to builtin mode with auto port', () {
      final cfg = ServerConfig();
      expect(cfg.mode, AiProviderMode.builtin);
      expect(cfg.port, 0);
      expect(cfg.usesCustomModel, isFalse);
      expect(cfg.opencodeConfigContent, isNull);
      expect(cfg.messageModel, isNull);
    });

    test('custom mode produces opencode config content and message model',
        () {
      final cfg = ServerConfig(
        port: 4066,
        mode: AiProviderMode.custom,
        providerID: 'freebuff',
        baseURL: 'http://127.0.0.1:4190/v1',
        apiKey: 'stub-key',
        modelID: 'deepseek-v4-flash',
      );
      expect(cfg.usesCustomModel, isTrue);

      final content =
          jsonDecode(cfg.opencodeConfigContent!) as Map<String, dynamic>;
      final provider = content['provider']!['freebuff'] as Map<String, dynamic>;
      expect(provider['npm'], '@ai-sdk/openai-compatible');
      expect((provider['options'] as Map)['baseURL'], 'http://127.0.0.1:4190/v1');
      expect((provider['options'] as Map)['apiKey'], 'stub-key');
      expect((provider['models'] as Map).keys, contains('deepseek-v4-flash'));
      expect(content['model'], 'freebuff/deepseek-v4-flash');

      expect(cfg.messageModel, {
        'modelID': 'deepseek-v4-flash',
        'providerID': 'freebuff',
      });
    });

    test('json round-trip', () {
      final cfg = ServerConfig(
        port: 4066,
        mode: AiProviderMode.custom,
        providerID: 'freebuff',
        baseURL: 'http://127.0.0.1:8080/v1',
        apiKey: 'k',
        modelID: 'm',
      );
      final restored = ServerConfig.fromJson(cfg.toJson());
      expect(restored.port, cfg.port);
      expect(restored.mode, cfg.mode);
      expect(restored.providerID, cfg.providerID);
      expect(restored.baseURL, cfg.baseURL);
      expect(restored.apiKey, cfg.apiKey);
      expect(restored.modelID, cfg.modelID);
    });

    test('custom mode without model id stays inert', () {
      final cfg = ServerConfig(
        mode: AiProviderMode.custom,
        modelID: '  ',
      );
      expect(cfg.usesCustomModel, isFalse);
      expect(cfg.opencodeConfigContent, isNull);
      expect(cfg.messageModel, isNull);
    });
  });
}
