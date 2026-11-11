#!/usr/bin/env node
/**
 * port-switch.js
 * Toggles ALL server URLs between LOCAL (localhost) and PRODUCTION (Render.com).
 * Affects: api_config.dart, config.h, NetworkController.ino
 *
 * Usage: npm run port:switch
 */

const fs = require('fs');
const path = require('path');

// ─── CONFIG ────────────────────────────────────────────────────────────────
const ROOT = path.resolve(__dirname, '..', '..');

const FILES = {
    dart: path.join(ROOT, 'lib', 'config', 'api_config.dart'),
    config: path.join(ROOT, 'backend', 'hardware', 'ESP32SR_UNO', 'config.h'),
    net: path.join(ROOT, 'backend', 'hardware', 'ESP32SR_UNO', 'NetworkController.ino'),
};

const LOCAL = {
    label: 'LOCAL (10.63.248.205:3000)',
    dartBase: "http://10.63.248.205:3000/api",
    dartSocket: "http://10.63.248.205:3000",
    inoHost: "10.63.248.205",
    inoPort: "3000",
    inoBegin: "socketIO.begin(",
};

const RENDER = {
    label: 'PRODUCTION (Render.com)',
    dartBase: "https://smart-parcel-dropbox-depth.onrender.com/api",
    dartSocket: "https://smart-parcel-dropbox-depth.onrender.com",
    inoHost: "smart-parcel-dropbox-depth.onrender.com",
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
    console.log(`  ✅ api_config.dart     → ${to.dartBase}`);
}

// ─── SWITCH config.h ────────────────────────────────────────────────────────
function switchConfig(from, to) {
    let content = fs.readFileSync(FILES.config, 'utf8');

    // #define SERVER_HOST
    content = content.replace(
        new RegExp(`(#define SERVER_HOST\\s*")[^"]+(")`),
        `$1${to.inoHost}$2`
    );
    // #define SERVER_PORT
    content = content.replace(
        new RegExp(`(#define SERVER_PORT\\s*)${from.inoPort}`),
        `$1${to.inoPort}`
    );

    fs.writeFileSync(FILES.config, content, 'utf8');
    console.log(`  ✅ config.h            → ${to.inoHost}:${to.inoPort}`);
}

// ─── SWITCH NetworkController ───────────────────────────────────────────────
function switchNet(from, to) {
    let content = fs.readFileSync(FILES.net, 'utf8');

    // socketIO.begin( vs beginSSL(
    content = content.replace(from.inoBegin, to.inoBegin);

    fs.writeFileSync(FILES.net, content, 'utf8');
    console.log(`  ✅ NetworkController   → ${to.inoBegin}...`);
}

// ─── MAIN ───────────────────────────────────────────────────────────────────
const current = detectMode();

if (current === 'local') {
    console.log('\n🔄 Switching: LOCAL → PRODUCTION\n');
    switchDart(LOCAL, RENDER);
    switchConfig(LOCAL, RENDER);
    switchNet(LOCAL, RENDER);
    console.log(`\n✅ Done! Now pointing to ${RENDER.label}`);
    console.log('   → Push changes to GitHub and wait for Render deploy');
    console.log('   → Reflash ESP32 with the updated PRODUCTION settings\n');
} else {
    console.log('\n🔄 Switching: PRODUCTION → LOCAL\n');
    switchDart(RENDER, LOCAL);
    switchConfig(RENDER, LOCAL);
    switchNet(RENDER, LOCAL);
    console.log(`\n✅ Done! Now pointing to ${LOCAL.label}`);
    console.log('   → Run "node server.js" in the backend folder');
    console.log('   → Reflash ESP32 with the updated LOCAL settings\n');
}
