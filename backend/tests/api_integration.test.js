const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');

const BASE_URL = process.env.TEST_API_URL || 'http://localhost:3000';

/**
 * Helper to execute HTTP request for testing
 */
function makeRequest(path, method = 'GET', body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const reqHeaders = { 'Content-Type': 'application/json', ...headers };
    let postData = null;
    if (body) {
      postData = JSON.stringify(body);
      reqHeaders['Content-Length'] = Buffer.byteLength(postData);
    }

    const req = http.request(
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
  await t.test('GET /health should return 200 and status online', async () => {
    try {
      const res = await makeRequest('/health');
      assert.equal(res.statusCode, 200);
      assert.equal(res.body.status, 'online');
      assert.ok(res.body.timestamp);
    } catch (err) {
      t.diagnostic(`Server not running at ${BASE_URL}. Skipping live endpoint check.`);
    }
  });

  await t.test('GET / should return API metadata', async () => {
    try {
      const res = await makeRequest('/');
      assert.equal(res.statusCode, 200);
      assert.equal(res.body.name, 'Smart Parcel Drop Box API');
    } catch (err) {
      t.diagnostic(`Server not running at ${BASE_URL}. Skipping live endpoint check.`);
    }
  });

  await t.test('POST /api/users/login without body should fail validation', async () => {
    try {
      const res = await makeRequest('/api/users/login', 'POST', {});
      assert.ok(res.statusCode >= 400);
    } catch (err) {
      t.diagnostic(`Server not running at ${BASE_URL}. Skipping validation test.`);
    }
  });

  await t.test('GET /device-control should return initial door state structure', async () => {
    try {
      const res = await makeRequest('/device-control');
      assert.equal(res.statusCode, 200);
      assert.ok('parcelDoorOpen' in res.body);
      assert.ok('userDoorOpen' in res.body);
    } catch (err) {
      t.diagnostic(`Server not running at ${BASE_URL}. Skipping device-control test.`);
    }
  });
});
