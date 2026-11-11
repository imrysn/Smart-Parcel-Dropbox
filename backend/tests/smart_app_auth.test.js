const test = require('node:test');
const assert = require('node:assert/strict');
process.env.JWT_SECRET = require('node:crypto').randomBytes(32).toString('hex');
const User = require('../models/User');
const Dropbox = require('../models/Dropbox');
const { generateToken, verifyToken, authMiddleware } = require('../utils/auth');
const userController = require('../controllers/userController');
const { pendingRegistrations } = require('../controllers/hardwareController');
const { router: deviceControlRouter } = require('../routes/deviceControl');
const dropboxRouter = require('../routes/dropboxRoutes');

function mockRes() {
  const res = {
    statusCode: 200,
    payload: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.payload = body;
      return this;
    },
  };
  return res;
}

test('JWT Auth Utils & Middleware', async (t) => {
  await t.test('generateToken and verifyToken round-trip userId', () => {
    const token = generateToken('user-123');
    const decoded = verifyToken(token);
    assert.equal(decoded.userId, 'user-123');
  });

  await t.test('authMiddleware rejects missing or invalid token with 401', () => {
    const resMissing = mockRes();
    let nextCalled = false;
    authMiddleware({ headers: {} }, resMissing, () => {
      nextCalled = true;
    });
    assert.equal(resMissing.statusCode, 401);
    assert.equal(nextCalled, false);

    const resInvalid = mockRes();
    authMiddleware({ headers: { authorization: 'Bearer invalid.jwt.token' } }, resInvalid, () => {
      nextCalled = true;
    });
    assert.equal(resInvalid.statusCode, 401);
    assert.equal(nextCalled, false);
  });

  await t.test('deviceControl router enforces authMiddleware', () => {
    const hasAuthLayer = deviceControlRouter.stack.some(
      (layer) => layer.route && layer.route.stack.some((s) => s.handle === authMiddleware)
    );
    assert.equal(hasAuthLayer, true);
  });
});

test('UserController Input Validation & Reset Lockout', async (t) => {
  await t.test('loginUser rejects missing email/password with 400 cleanly', async () => {
    const res = mockRes();
    await userController.loginUser({ body: {} }, res);
    assert.equal(res.statusCode, 400);
    assert.match(res.payload.message, /required/i);
  });

  await t.test('registerUser validates email format and password length with 400', async () => {
    const resBadEmail = mockRes();
    await userController.registerUser({ body: { email: 'not-an-email', password: 'password123' } }, resBadEmail);
    assert.equal(resBadEmail.statusCode, 400);

    const resShortPass = mockRes();
    await userController.registerUser({ body: { email: 'user@example.com', password: '123' } }, resShortPass);
    assert.equal(resShortPass.statusCode, 400);
  });

  await t.test('verifyResetCode clears reset code after 5 failed attempts', async () => {
    const originalFindOne = User.findOne;
    const fakeUser = {
      resetCode: '654321',
      resetCodeExpiry: new Date(Date.now() + 60_000),
      resetCodeAttempts: 4,
      saved: 0,
      async save() {
        this.saved += 1;
      },
    };
    User.findOne = async () => fakeUser;

    try {
      const resFail = mockRes();
      await userController.verifyResetCode({ body: { email: 'user@example.com', code: '000000' } }, resFail);
      assert.equal(resFail.statusCode, 400);
      assert.equal(fakeUser.resetCodeAttempts, 5);
      assert.equal(fakeUser.resetCode, null);

      const resLocked = mockRes();
      await userController.verifyResetCode({ body: { email: 'user@example.com', code: '654321' } }, resLocked);
      assert.equal(resLocked.statusCode, 429);
    } finally {
      User.findOne = originalFindOne;
    }
  });
});

function getDropboxHandler(path, method) {
  const layer = dropboxRouter.stack.find(
    (l) => l.route && l.route.path === path && l.route.methods[method]
  );
  assert.ok(layer, `Expected route ${method.toUpperCase()} ${path} to exist`);
  return layer.route.stack[layer.route.stack.length - 1].handle;
}

test('Primary-Owner In-App Household Member Registration & Invite Routes', async (t) => {
  await t.test('POST /:deviceId/members blocks non-primary owner with 403 and adds registered member by email', async () => {
    const handler = getDropboxHandler('/:deviceId/members', 'post');
    const origDropboxFindOne = Dropbox.findOne;
    const origDropboxUpdateOne = Dropbox.updateOne;
    const origDropboxFindById = Dropbox.findById;
    const origUserFindOne = User.findOne;

    const fakeDropbox = {
      _id: 'db-1',
      deviceId: 'AA:BB:CC:DD:EE:FF',
      name: 'Front Gate Box',
      primaryUserId: 'owner-1',
      userIds: ['owner-1'],
      isRegistered: true,
    };

    const emittedEvents = [];
    const fakeIo = {
      to(room) {
        return {
          emit(event, data) {
            emittedEvents.push({ room, event, data });
          },
        };
      },
    };
    const fakeApp = { get: (k) => (k === 'io' ? fakeIo : null) };

    try {
      Dropbox.findOne = async (query) => {
        if (query.deviceId && typeof query.deviceId === 'object' && query.deviceId.$ne) {
          return null; // Not paired to another dropbox
        }
        return fakeDropbox;
      };
      User.findOne = () => ({
        select: async () => ({ _id: 'member-2', fullName: 'Jamie', email: 'jamie@example.com' }),
      });

      let updatedWith = null;
      Dropbox.updateOne = async (filter, update) => {
        updatedWith = { filter, update };
      };
      Dropbox.findById = async () => ({
        ...fakeDropbox,
        userIds: ['owner-1', 'member-2'],
      });

      // 1. Non-primary caller rejected with 403
      const resForbidden = mockRes();
      await handler(
        {
          userId: 'other-user',
          params: { deviceId: fakeDropbox.deviceId },
          body: { email: 'jamie@example.com' },
          app: fakeApp,
        },
        resForbidden
      );
      assert.equal(resForbidden.statusCode, 403);

      // 2. Primary owner adds member cleanly with 201 and emits live sync event
      const resOk = mockRes();
      await handler(
        {
          userId: 'owner-1',
          params: { deviceId: fakeDropbox.deviceId },
          body: { email: 'Jamie@Example.com' },
          app: fakeApp,
        },
        resOk
      );
      assert.equal(resOk.statusCode, 201);
      assert.equal(resOk.payload.member.id, 'member-2');
      assert.equal(updatedWith.update.$addToSet.userIds, 'member-2');
      assert.equal(emittedEvents.length, 1);
      assert.equal(emittedEvents[0].room, 'member-2');
      assert.equal(emittedEvents[0].event, 'deviceRegistered');
      assert.equal(emittedEvents[0].data.alreadyConnected, true);

      // 3. Unknown account email returns 404
      User.findOne = () => ({ select: async () => null });
      const resNotFound = mockRes();
      await handler(
        {
          userId: 'owner-1',
          params: { deviceId: fakeDropbox.deviceId },
          body: { email: 'missing@example.com' },
          app: fakeApp,
        },
        resNotFound
      );
      assert.equal(resNotFound.statusCode, 404);
    } finally {
      Dropbox.findOne = origDropboxFindOne;
      Dropbox.updateOne = origDropboxUpdateOne;
      Dropbox.findById = origDropboxFindById;
      User.findOne = origUserFindOne;
    }
  });

  await t.test('POST /:deviceId/invite creates 6-digit invite token for primary owner and claim preserves owner box name', async () => {
    const inviteHandler = getDropboxHandler('/:deviceId/invite', 'post');
    const claimHandler = getDropboxHandler('/claim', 'post');
    const origDropboxFindOne = Dropbox.findOne;

    const fakeDropbox = {
      _id: 'db-2',
      deviceId: '11:22:33:44:55:66',
      name: 'Porch Gate Unit',
      primaryUserId: 'owner-1',
      userIds: ['owner-1'],
      isRegistered: true,
      wifiSSID: 'HomeWiFi',
      status: 'online',
      saved: 0,
      async save() {
        this.saved += 1;
      },
    };

    const emittedEvents = [];
    const fakeIo = {
      to(room) {
        return {
          emit(event, data) {
            emittedEvents.push({ room, event, data });
          },
        };
      },
    };
    const fakeApp = { get: (k) => (k === 'io' ? fakeIo : null) };

    let generatedToken = null;
    try {
      Dropbox.findOne = async () => fakeDropbox;

      // Non-primary cannot mint invites
      const resForbidden = mockRes();
      await inviteHandler(
        { userId: 'member-2', params: { deviceId: fakeDropbox.deviceId }, app: fakeApp },
        resForbidden
      );
      assert.equal(resForbidden.statusCode, 403);

      // Primary owner creates in-app invite
      const resInvite = mockRes();
      await inviteHandler(
        { userId: 'owner-1', params: { deviceId: fakeDropbox.deviceId }, app: fakeApp },
        resInvite
      );
      assert.equal(resInvite.statusCode, 201);
      assert.match(resInvite.payload.token, /^SPDB-REG-\d{6}$/);
      assert.match(resInvite.payload.pin, /^\d{6}$/);
      generatedToken = resInvite.payload.token;
      const storedEntry = pendingRegistrations.get(generatedToken);
      assert.ok(storedEntry);
      assert.equal(storedEntry.isHouseholdInvite, true);
      assert.equal(storedEntry.alreadyConnected, true);

      // Invited household member claims with default name -> preserves owner's box name and skips Wi-Fi setup
      const resClaim = mockRes();
      await claimHandler(
        {
          userId: 'member-2',
          body: { token: generatedToken, name: 'My Smart Parcel Dropbox' },
          app: fakeApp,
        },
        resClaim
      );
      assert.equal(resClaim.statusCode, 200);
      assert.equal(resClaim.payload.alreadyConnected, true);
      assert.equal(fakeDropbox.name, 'Porch Gate Unit');
      assert.ok(fakeDropbox.userIds.includes('member-2'));
      assert.equal(pendingRegistrations.get(generatedToken), undefined);
      // Hardware box itself is not spuriously signaled for a remote household invite
      assert.equal(emittedEvents.some((e) => e.room === 'esp32_device'), false);
    } finally {
      if (generatedToken) pendingRegistrations.delete(generatedToken);
      Dropbox.findOne = origDropboxFindOne;
    }
  });
});
