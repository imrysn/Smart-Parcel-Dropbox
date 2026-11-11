const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');

const { once } = require('node:events');
let baseUrl = process.env.TEST_API_URL;

/**
 * Helper to execute HTTP request for testing
 */
function makeRequest(path, method = 'GET', body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, baseUrl);
    const reqHeaders = { 'Content-Type': 'application/json', ...headers };
    let postData = null;
    if (body) {
      postData = JSON.stringify(body);
      reqHeaders['Content-Length'] = Buffer.byteLength(postData);
    }

    const req = (url.protocol === 'https:' ? require('node:https') : http).request(
      url,
      {
        method,
        headers: reqHeaders,
        timeout: 5000
      },
      (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          try {
            const parsed = data ? JSON.parse(data) : {};
            resolve({ statusCode: res.statusCode, headers: res.headers, body: parsed });
          } catch (e) {
            resolve({ statusCode: res.statusCode, headers: res.headers, body: data });
          }
        });
      }
    );

    req.on('error', (err) => reject(err));
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timed out'));
    });

    if (postData) req.write(postData);
    req.end();
  });
}

test('REST API Integration Suite', async (t) => {
  if (!baseUrl) {
    t.mock.method(console, 'log', () => {});
    const { server, io } = require('../server');
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    baseUrl = `http://127.0.0.1:${server.address().port}`;
    t.after(() => new Promise(resolve => io.close(resolve)));
  }

  await t.test('GET /health returns server status', async () => {
    const res = await makeRequest('/health');
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.status, 'online');
    assert.ok(res.body.timestamp);
  });

  await t.test('GET / returns API metadata', async () => {
    const res = await makeRequest('/');
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.name, 'Smart Parcel Drop Box API');
  });

  await t.test('login rejects an empty request', async () => {
    const res = await makeRequest('/api/users/login', 'POST', {});
    assert.equal(res.statusCode, 400);
  });

  await t.test('device control requires a session', async () => {
    const res = await makeRequest('/device-control');
    assert.equal(res.statusCode, 401);
  });
});
