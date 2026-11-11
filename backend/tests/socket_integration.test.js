const test = require('node:test');
const assert = require('node:assert/strict');

const { once } = require('node:events');

test('Socket.IO protocol handshakes', async (t) => {
  let serverUrl = process.env.TEST_SOCKET_URL;
  if (!serverUrl) {
    const { server, io } = require('../server');
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    serverUrl = `http://127.0.0.1:${server.address().port}`;
    t.after(() => new Promise(resolve => io.close(resolve)));
  }

  for (const version of [3, 4]) {
    await t.test(`accepts Engine.IO v${version} polling handshake`, async () => {
      const url = new URL(`/socket.io/?EIO=${version}&transport=polling`, serverUrl);
      const result = await fetch(url, { signal: AbortSignal.timeout(5000) });
      assert.equal(result.status, 200);
      assert.match(await result.text(), /"sid":/);
    });
  }
});
