import { ApiRequestResult, ApiRequestSpec } from './models';

/** ThunderClient-style API tester. Sends requests from the panel, pretty-prints
 *  JSON responses, and builds a report that can be sent to the main AI so it
 *  turns what the tester learns into new tasks. */
export class ApiTester {
  sending = false;
  last: ApiRequestResult | null = null;

  async send(spec: ApiRequestSpec): Promise<ApiRequestResult> {
    this.sending = true;
    const started = Date.now();
    try {
      const headers: Record<string, string> = { ...spec.headers };
      const res = await fetch(spec.url, {
        method: spec.method.toUpperCase(),
        headers,
        body: spec.body.trim() ? spec.body : undefined,
        signal: AbortSignal.timeout(30_000),
      });
      const rawBody = await res.text();
      const respHeaders: Record<string, string> = {};
      res.headers.forEach((v, k) => {
        respHeaders[k] = v;
      });
      const result: ApiRequestResult = {
        method: spec.method.toUpperCase(),
        url: spec.url,
        statusCode: res.status,
        headers: respHeaders,
        body: prettyBody(rawBody, res.headers.get('content-type') ?? ''),
        elapsedMs: Date.now() - started,
        error: null,
      };
      this.last = result;
      return result;
    } catch (e) {
      const result: ApiRequestResult = {
        method: spec.method.toUpperCase(),
        url: spec.url,
        statusCode: null,
        headers: {},
        body: '',
        elapsedMs: Date.now() - started,
        error: String(e),
      };
      this.last = result;
      return result;
    } finally {
      this.sending = false;
    }
  }

  clear(): void {
    this.last = null;
  }
}

export function prettyBody(body: string, contentType: string): string {
  if (!body) return body;
  if (contentType.includes('json') || body.trimLeft().startsWith('{')) {
    try {
      return JSON.stringify(JSON.parse(body), null, 2);
    } catch {
      // not JSON after all
    }
  }
  return body;
}

export interface BackendReportContext {
  tables: Array<{ name: string; columns: string[] }>;
}

/** The report text sent to the main AI after a backend tester request
 *  (ported from the app's reportBackendResultToMain). */
export function buildBackendReport(
  result: ApiRequestResult,
  ctx: BackendReportContext,
): string {
  const b: string[] = [];
  b.push('Backend tester result.');
  b.push(`Request: ${result.method} ${result.url}`);
  b.push(`Result: ${statusLabel(result)}`);
  b.push(`Outcome: ${isSuccess(result) ? 'OK' : 'FAILURE'}`);
  if (result.body.trim()) {
    const body = result.body.length > 1200 ? result.body.slice(0, 1200) : result.body;
    b.push(`Response body:\n${body}`);
  }
  if (result.error) b.push(`Transport error: ${result.error}`);
  if (ctx.tables.length > 0) {
    b.push('\nCurrent database schema (tables and columns):');
    for (const t of ctx.tables) b.push(`- ${t.name}: ${t.columns.join(', ')}`);
  }
  b.push(
    '\nIf this reveals a problem or an improvement (e.g. a missing table/column, a failing endpoint), split it into new todos with "status": "todo" and "assignee": null so the team works them.',
  );
  return b.join('\n');
}

export function statusLabel(result: ApiRequestResult): string {
  if (result.statusCode === null) return 'no response';
  return `${result.statusCode} (${result.elapsedMs ?? '?'}ms)`;
}

export function isSuccess(result: ApiRequestResult): boolean {
  return (
    result.error === null &&
    result.statusCode !== null &&
    result.statusCode < 400
  );
}
