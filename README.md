# Smart Parcel Dropbox

Smart Parcel Dropbox is a Flutter mobile app and ESP32-S3 parcel cabinet for contactless deliveries and pickups. The app uses the Express and MongoDB backend in `backend/`. Socket.IO carries live device, tracking, and notification events.

## Run the mobile app

1. Copy `backend/.env.example` to `backend/.env` and set `MONGODB_URI` and a unique `JWT_SECRET` of at least 32 characters. Use the same signing secret across restarts. Set `EMAIL_USER` and `EMAIL_PASS` for password reset emails.
2. From the repo root, install and start the backend.

   ```powershell
   npm --prefix backend ci
   npm --prefix backend start
   ```

   Check `/health` for MongoDB connection status before signing in.

3. Run Flutter against the intended backend. An Android emulator can reach a local backend on the development computer at `10.0.2.2`.

   ```powershell
   flutter pub get
   flutter run --dart-define=API_URL=http://10.0.2.2:3000
   ```

   For a physical phone, use the test backend's HTTPS URL or the development computer's reachable LAN address. Use the same server for the phone and ESP32. Debug builds use the local API by default. Release builds use the configured production URL unless `API_URL` is set. Sign in again after upgrading from a build that stored sessions without a server URL.

## Provision the ESP32

The backend accepts hardware commands and telemetry only after the device proves possession of its configured key. Provision the firmware and backend together.

1. Identify the ESP32 station MAC address and generate a separate random key of at least 32 characters for each box.
2. In the backend's private environment, set `SPD_DEVICE_KEYS` to a JSON object mapping each MAC to its key. Preserve existing entries when adding another box.
3. In `backend/hardware/ESP32SR_UNO/`, create the ignored `device_secrets.h` with the matching key and the host name of the backend.

   ```cpp
   #pragma once
   #define SPD_DEVICE_KEY "<the matching device key>"
   #define SERVER_HOST "<the backend host name without https://>"
   ```

4. Build and flash the ESP32 sketch. Confirm the serial monitor reports device authentication, then pair with the box's LCD code from the app. The phone displays lock changes after the ESP32 confirms the command. The door sensor reading is shown separately.

The sketch uses its existing TLS Socket.IO transport. Legacy hardware REST endpoints also require matching device credentials. Leave the device keys and JWT signing secret out of Git.

### Bluetooth Wi-Fi setup

On an unregistered box without Wi-Fi, press the blue button to display a setup QR. Scan it in **Register Dropbox** on Android or iOS and enter the network name and password. The app encrypts the credentials for that setup window. The box saves them after it joins the network. After it restarts, press blue and scan the registration QR to link it to the account.

To recover a registered box, wake it while offline, hold blue for two seconds, and select **Wi-Fi Setup** with blue. In **Dropbox Control**, open **Bluetooth Wi-Fi setup** and scan the box's QR. A failed connection attempt keeps the previously saved Wi-Fi settings.

### Offline emergency unlock

While the box is online, the primary owner opens **Dropbox Control → Offline unlock → Prepare offline access**. This saves an eight-hour grant to that phone. During an outage, wake the box, hold blue for two seconds, and press red on **Offline Settings**. Open **Offline unlock** on the phone and approve the unlock with the phone's screen lock. Only the received-parcel door opens, and the firmware relocks it automatically.

The box needs one authenticated server connection after each reboot to establish time. During an outage, a saved grant remains usable until it expires. Build the Bluetooth firmware with Arduino ESP32 core 3.3.6 and an application partition large enough for Wi-Fi and Bluetooth, such as **Huge APP** on a compatible ESP32-S3 board.

## Verify the demo

Run `flutter test` and `npm --prefix backend test`. The paired-door integration test uses two simulated boxes and a local server. On a real phone and box, verify pairing, sign-out and sign-in, an inbound delivery, an outbound pickup, and a disconnect during a lock request.

**Copy Pickup Pass** copies the rider message for manual sharing. The notification inbox refreshes when the app reconnects or resumes, and an active owner alert can be replayed before it expires.

### Android delivery alerts

1. Use the Android app's Firebase project for both `android/app/google-services.json` and backend credentials. Enable Firebase Cloud Messaging in that project. Provide Application Default Credentials to the backend, for example by pointing `GOOGLE_APPLICATION_CREDENTIALS` at a private service-account file mounted by the host.
2. Set `SPD_PUSH_ENABLED=true` on the backend and restart it. Install the Android build, allow notifications, and sign in so the app can register its installation.
3. Deliver a parcel with the phone locked. Tap the alert to confirm it opens the parcel. Repeat in the foreground and after switching accounts. Android Settings force-stop can suspend delivery until the app is reopened.

### Hardware diagnostics

Set `SPD_FIRMWARE_VERSION` in `device_secrets.h` to the version you are flashing. The authenticated firmware reports version, connected Wi-Fi RSSI, and uptime every 30 seconds. In **Dropbox Control**, check the last report and disconnect the box to verify that the reading becomes stale. Reconnect it and verify that the timestamp updates.

## Source map

- `lib/screens/` contains mobile screens.
- `lib/services/` contains authentication, REST, Socket.IO, and notification code.
- `backend/server.js` starts the active API and device event handlers.
- `backend/hardware/ESP32SR_UNO/` contains the ESP32 firmware.
