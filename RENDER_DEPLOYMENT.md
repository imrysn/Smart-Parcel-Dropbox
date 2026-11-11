# Deploy the SPD backend on Render

The release branch is based on `optimizations` and packages the Express backend from `backend/`. Its spatial-volume reports go only to the authenticated box's paired household. The Android and ESP32 bench builds come from the companion changes in the SPD `dev` checkout.

## Configure the service

- Use the release branch `codex/spd-render-reliability` with root directory `backend`, build command `npm ci`, start command `npm start`, and health check path `/health`.
- Use Node 22, as specified in `backend/package.json`. If Render has a `NODE_VERSION` override, use a Node 22 release there too.
- Keep the existing MongoDB configuration and use a `JWT_SECRET` of at least 32 characters. Set `SPD_DEVICE_KEYS` to a private JSON object that maps each test box's station MAC address to its unique key.
- Store the replacement Firebase service-account JSON from the Android app's Firebase project in the Render secret file `spd-fcm.json`. Set `GOOGLE_APPLICATION_CREDENTIALS` to `/etc/secrets/spd-fcm.json` and leave `SPD_PUSH_ENABLED=false` for the first boot.

## Bench test before switching active units

1. Prepare the updated ESP32 firmware with the same per-device key and Render hostname. The backend requires a device authentication challenge response, so firmware built from the old `optimizations` branch needs the corresponding update before cutover.
2. Install the companion Android build pointed at the same service. For the existing Depth service, use `--dart-define=API_URL=https://smart-parcel-dropbox-depth.onrender.com`.
3. After deployment, check `/health` for MongoDB connectivity. Sign in, pair the box, and confirm that Dropbox Control shows its firmware version, Wi-Fi signal, and uptime. Verify a lock command and an inbound delivery.
4. Enable `SPD_PUSH_ENABLED=true`, redeploy, and reopen the app with notifications allowed so it can register. Perform another delivery with the phone locked. Tap the alert and verify that it opens the delivered parcel for the signed-in owner.

Keep the prior Render deployment available for rollback. A backend rollback also requires the matching firmware for the device protocol used by that deployment.
