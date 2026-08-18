import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

/** Which AI backend the opencode server should talk to. */
export type AiProviderMode = 'builtin' | 'custom';

export interface ServerConfig {
  port: number;
  mode: AiProviderMode;
  providerID: string;
  baseURL: string;
  apiKey: string;
  modelID: string;
}

export function defaultServerConfig(): ServerConfig {
  return {
    port: 0,
    mode: 'builtin',
    providerID: 'freebuff',
    baseURL: 'http://127.0.0.1:8080/v1',
    apiKey: '',
    modelID: '',
  };
}

export function usesCustomModel(cfg: ServerConfig): boolean {
  return cfg.mode === 'custom' && cfg.modelID.trim().length > 0;
}

/** Inline opencode config that registers the custom provider and makes it the
 *  default model. Passed to `opencode serve` via OPENCODE_CONFIG_CONTENT. */
export function opencodeConfigContent(cfg: ServerConfig): string | null {
  if (!usesCustomModel(cfg)) return null;
  const pid = cfg.providerID.trim();
  const mid = cfg.modelID.trim();
  const options: Record<string, unknown> = { baseURL: cfg.baseURL.trim() };
  if (cfg.apiKey.trim().length > 0) options.apiKey = cfg.apiKey.trim();
  return JSON.stringify({
    provider: {
      [pid]: {
        npm: '@ai-sdk/openai-compatible',
        name: `${pid} (OpenAI-compatible)`,
        options,
        models: { [mid]: { name: mid } },
      },
    },
    model: `${pid}/${mid}`,
  });
}

/** Shape of the `model` object to send on each message so the server resolves
 *  this custom model (required for custom providers). */
export function messageModel(cfg: ServerConfig): Record<string, string> | null {
  if (!usesCustomModel(cfg)) return null;
  return { modelID: cfg.modelID.trim(), providerID: cfg.providerID.trim() };
}

export function settingsFile(): string {
  return path.join(os.homedir(), '.vibestudio', 'settings.json');
}

export function loadSettings(): ServerConfig {
  try {
    const raw = fs.readFileSync(settingsFile(), 'utf8');
    const json = JSON.parse(raw) as Record<string, unknown>;
    return {
      port: (json.port as number) ?? 0,
      mode: json.mode === 'custom' ? 'custom' : 'builtin',
      providerID: (json.providerID as string) ?? 'freebuff',
      baseURL: (json.baseURL as string) ?? 'http://127.0.0.1:8080/v1',
      apiKey: (json.apiKey as string) ?? '',
      modelID: (json.modelID as string) ?? '',
    };
  } catch {
    return defaultServerConfig();
  }
}

export function saveSettings(cfg: ServerConfig): void {
  try {
    const dir = path.join(os.homedir(), '.vibestudio');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      settingsFile(),
      JSON.stringify(
        {
          port: cfg.port,
          mode: cfg.mode,
          providerID: cfg.providerID,
          baseURL: cfg.baseURL,
          apiKey: cfg.apiKey,
          modelID: cfg.modelID,
        },
        null,
        2,
      ),
      'utf8',
    );
  } catch {
    // best effort
  }
}
