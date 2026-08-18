import * as assert from 'node:assert';
import { createServer, Server } from 'node:http';
import { test } from 'node:test';

import { OpenCodeClient } from '../opencode';

/** A fake `opencode serve` HTTP API on a random local port. */
function stubServer(): Promise<{ server: Server; port: number }> {
  const server = createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://x');
    let body = '';
    req.on('data', (d) => (body += d));
    req.on('end', () => {
      if (req.method === 'GET' && url.pathname === '/session') {
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end('[]');
      } else if (req.method === 'POST' && url.pathname === '/session') {
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ id: 'sess-1' }));
      } else if (url.pathname === '/session/sess-1/message' && req.method === 'POST') {
        const parsed = JSON.parse(body);
        const text = (parsed.parts ?? [])
          .filter((p: { type?: string }) => p.type === 'text')
          .map((p: { text?: string }) => p.text)
          .join('\n');
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(
          JSON.stringify({ parts: [{ type: 'text', text: `echo: ${text}` }] }),
        );
      } else if (url.pathname === '/session/sess-1' && req.method === 'DELETE') {
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end('{}');
      } else {
        res.writeHead(404);
        res.end('not found');
      }
    });
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const addr = server.address();
      resolve({
        server,
        port: typeof addr === 'object' && addr ? addr.port : 0,
      });
    });
  });
}

test('createSession / sendMessage / askOnce against a stub server', async () => {
  const { server, port } = await stubServer();
  try {
    const client = new OpenCodeClient();
    client.port = port;
    client.state = 'running';

    const id = await client.createSession('test');
    assert.equal(id, 'sess-1');

    await client.sendMessage({ sessionId: id, text: 'hello' });

    const reply = await client.askOnce('do the thing');
    assert.equal(reply, 'echo: do the thing');

    await client.deleteSession(id);
    assert.equal(client.state, 'running');
  } finally {
    server.close();
  }
});

test('sendMessage passes the custom model object when configured', async () => {
  const server = createServer((req, res) => {
    let body = '';
    req.on('data', (d) => (body += d));
    req.on('end', () => {
      const parsed = JSON.parse(body);
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ parts: [{ type: 'text', text: 'ok' }] }));
      void parsed;
    });
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', () => r()));
  const addr = server.address();
  const port = typeof addr === 'object' && addr ? addr.port : 0;
  try {
    const client = new OpenCodeClient();
    client.port = port;
    client.state = 'running';
    await client.sendMessage({
      sessionId: 's',
      text: 'hi',
      model: { modelID: 'deepseek-v4-flash', providerID: 'freebuff' },
    });
  } finally {
    server.close();
  }
});
