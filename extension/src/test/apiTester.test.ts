import * as assert from 'node:assert';
import { createServer } from 'node:http';
import { test } from 'node:test';

import { ApiTester, buildBackendReport, prettyBody } from '../apiTester';
import { ApiRequestResult } from '../models';
import { parseBootstrapJson } from '../scripts';

test('prettyBody indents JSON responses', () => {
  assert.equal(prettyBody('{"a":1}', 'application/json'), '{\n  "a": 1\n}');
  assert.equal(prettyBody('plain text', 'text/plain'), 'plain text');
});

test('apiTester sends a request and records status + body', async () => {
  const server = createServer((req, res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ hello: 'world' }));
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', () => r()));
  const addr = server.address();
  const port = typeof addr === 'object' && addr ? addr.port : 0;
  try {
    const tester = new ApiTester();
    const result = await tester.send({
      method: 'GET',
      url: `http://127.0.0.1:${port}/api`,
      headers: {},
      body: '',
    });
    assert.equal(result.statusCode, 200);
    assert.match(result.body, /hello/);
    assert.equal(result.error, null);
    assert.equal(tester.last, result);
    tester.clear();
    assert.equal(tester.last, null);
  } finally {
    server.close();
  }
});

test('apiTester records transport errors', async () => {
  const tester = new ApiTester();
  const result = await tester.send({
    method: 'GET',
    url: 'http://127.0.0.1:1/nope',
    headers: {},
    body: '',
  });
  assert.equal(result.statusCode, null);
  assert.ok(result.error);
});

test('buildBackendReport includes the verdict and schema context', () => {
  const result: ApiRequestResult = {
    method: 'GET',
    url: 'http://x/api/users',
    statusCode: 500,
    headers: {},
    body: 'boom',
    elapsedMs: 12,
    error: null,
  };
  const report = buildBackendReport(result, {
    tables: [{ name: 'users', columns: ['id', 'email'] }],
  });
  assert.match(report, /Request: GET http:\/\/x\/api\/users/);
  assert.match(report, /Outcome: FAILURE/);
  assert.match(report, /- users: id, email/);
  assert.match(report, /split it into new todos/);
});

test('parseBootstrapJson handles raw JSON, fences, and trailing text', () => {
  assert.deepEqual(parseBootstrapJson('{"Run":"npm start","Stop":"","Migration":""}'), {
    Run: 'npm start',
    Stop: '',
    Migration: '',
  });
  assert.deepEqual(
    parseBootstrapJson('```json\n{"Run": "a", "Stop": "b", "Migration": "c"}\n```'),
    { Run: 'a', Stop: 'b', Migration: 'c' },
  );
  assert.deepEqual(
    parseBootstrapJson('Here you go: {"Run":"x","Stop":"y","Migration":"z"} thanks'),
    { Run: 'x', Stop: 'y', Migration: 'z' },
  );
  assert.deepEqual(parseBootstrapJson('no json here'), {});
});
