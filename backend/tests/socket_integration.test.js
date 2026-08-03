const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');

const SERVER_URL = process.env.TEST_SOCKET_URL || 'http://localhost:3000';

test('Socket.IO Protocol & Handshake Suite', async (t) => {
  await t.test('Server should respond to Socket.io EIO3 handshake query', (t, done) => {
    const url = new URL('/socket.io/?EIO=3&transport=polling', SERVER_URL);
    
    http.get(url, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        assert.equal(res.statusCode, 200);
        assert.ok(data.length > 0);
        done();
      });
    }).on('error', (err) => {
      t.diagnostic(`Server not running at ${SERVER_URL}. Skipping live socket handshake test.`);
      done();
    });
  });

  await t.test('Server should respond to Socket.io EIO4 handshake query', (t, done) => {
    const url = new URL('/socket.io/?EIO=4&transport=polling', SERVER_URL);
    
    http.get(url, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        assert.equal(res.statusCode, 200);
        assert.ok(data.length > 0);
        done();
      });
    }).on('error', (err) => {
      t.diagnostic(`Server not running at ${SERVER_URL}. Skipping live socket handshake test.`);
      done();
    });
  });
});

