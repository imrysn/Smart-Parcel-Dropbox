#!/usr/bin/env node
/**
 * port-switch.js
 * Toggles ALL server URLs between LOCAL (localhost) and PRODUCTION (Render.com).
 * Affects: api_config.dart, ESP32SR_UNO.ino
 *
 * Usage: npm run port:switch
 */

const fs = require('fs');
const path = require('path');

// ─── CONFIG ────────────────────────────────────────────────────────────────
const ROOT = path.resolve(__dirname, '..', '..');

const FILES = {
    dart: path.join(ROOT, 'lib', 'config', 'api_config.dart'),
    ino: path.join(ROOT, 'backend', 'hardware', 'ESP32SR_UNO', 'ESP32SR_UNO.ino'),
};

const LOCAL = {
    label: 'LOCAL (10.222.49.205:3000)',
    dartBase: "http://10.222.49.205:3000/api",
    dartSocket: "http://10.222.49.205:3000",
    inoHost: "10.222.49.205",
    inoPort: "3000",
    inoBegin: "socketIO.begin(",
};

const RENDER = {
    label: 'PRODUCTION (Render.com)',
    dartBase: "https://smart-parcel-dropbox.onrender.com/api",
    dartSocket: "https://smart-parcel-dropbox.onrender.com",
    inoHost: "smart-parcel-dropbox.onrender.com",
    inoPort: "443",
    inoBegin: "socketIO.beginSSL(",
};

// ─── DETECT CURRENT MODE ────────────────────────────────────────────────────
function detectMode() {
    const dart = fs.readFileSync(FILES.dart, 'utf8');
    return dart.includes(LOCAL.dartBase) ? 'local' : 'render';
}

// ─── SWITCH dart ────────────────────────────────────────────────────────────
function switchDart(from, to) {
    let content = fs.readFileSync(FILES.dart, 'utf8');
    content = content.replace(from.dartBase, to.dartBase);
    content = content.replace(from.dartSocket, to.dartSocket);
    fs.writeFileSync(FILES.dart, content, 'utf8');
    console.log(`  ✅ api_config.dart  → ${to.dartBase}`);
}

// ─── SWITCH ino ─────────────────────────────────────────────────────────────
function switchIno(from, to) {
    let content = fs.readFileSync(FILES.ino, 'utf8');

    // HOST
    content = content.replace(
        new RegExp(`(const char\\* SERVER_HOST\\s*=\\s*")[^"]+(";)`),
        `$1${to.inoHost}$2`
    );
    // PORT
    content = content.replace(
        new RegExp(`(const uint16_t SERVER_PORT\\s*=\\s*)${from.inoPort}(;)`),
        `$1${to.inoPort}$2`
    );
    // begin / beginSSL
    content = content.replace(from.inoBegin, to.inoBegin);

    // SERVER_PATH: EIO=3 for both, no &transport=websocket for Render
    if (to === RENDER) {
        content = content.replace(
            /const char\* SERVER_PATH\s*=\s*"[^"]+";/,
            `const char* SERVER_PATH = "/socket.io/?EIO=3";`
        );
    }

    fs.writeFileSync(FILES.ino, content, 'utf8');
    console.log(`  ✅ ESP32SR_UNO.ino  → ${to.inoHost}:${to.inoPort}`);
}

// ─── MAIN ───────────────────────────────────────────────────────────────────
const current = detectMode();

if (current === 'local') {
    console.log('\n🔄 Switching: LOCAL → PRODUCTION\n');
    switchDart(LOCAL, RENDER);
    switchIno(LOCAL, RENDER);
    console.log(`\n✅ Done! Now pointing to ${RENDER.label}`);
    console.log('   → Push backend/server.js to GitHub and wait for Render deploy');
    console.log('   → Reflash ESP32 with the updated SERVER_HOST\n');
} else {
    console.log('\n🔄 Switching: PRODUCTION → LOCAL\n');
    switchDart(RENDER, LOCAL);
    switchIno(RENDER, LOCAL);
    console.log(`\n✅ Done! Now pointing to ${LOCAL.label}`);
    console.log('   → Run "node server.js" in the backend folder');
    console.log('   → Reflash ESP32 with the updated SERVER_HOST\n');
}
