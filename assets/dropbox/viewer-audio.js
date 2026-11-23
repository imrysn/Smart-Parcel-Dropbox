// ─── Procedural Spatial Audio Engine for Smart Parcel Dropbox ───────────────
// Uses the HTML5 Web Audio API to synthesize authentic physical sounds
// (sharp clicky solenoids, tactile microswitches, resonant slow hinge creaks,
// cardboard & poly mailer impacts, chute friction slides).
// Zero audio files, zero network downloads, instant zero-latency playback.

import { DOOR_OPEN_B64, DOOR_CLOSE_IMPACT_B64, DOOR_CLOSE_FULL_B64 } from './door-audio-data.js';

let audioCtx = null;
let masterGain = null;
let soundEnabled = true;

let decodedDoorOpenBuffer = null;
let decodedDoorCloseImpactBuffer = null;
let decodedDoorCloseFullBuffer = null;
let isDecodingDoorAudio = false;

function decodeBase64ToArrayBuffer(b64) {
  const binaryString = atob(b64);
  const len = binaryString.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}

function predecodeDoorAudio(ctx) {
  if (decodedDoorOpenBuffer || isDecodingDoorAudio || !ctx) return;
  isDecodingDoorAudio = true;
  try {
    const pOpen = ctx.decodeAudioData(decodeBase64ToArrayBuffer(DOOR_OPEN_B64));
    const pImpact = ctx.decodeAudioData(decodeBase64ToArrayBuffer(DOOR_CLOSE_IMPACT_B64));
    const pFull = ctx.decodeAudioData(decodeBase64ToArrayBuffer(DOOR_CLOSE_FULL_B64));
    Promise.all([pOpen, pImpact, pFull]).then(([openBuf, impactBuf, fullBuf]) => {
      decodedDoorOpenBuffer = openBuf;
      decodedDoorCloseImpactBuffer = impactBuf;
      decodedDoorCloseFullBuffer = fullBuf;
      isDecodingDoorAudio = false;
    }).catch(err => {
      console.warn('Pre-decode door audio failed, using acoustic PCM fallback', err);
      isDecodingDoorAudio = false;
    });
  } catch (err) {
    console.warn('Decode door audio failed', err);
    isDecodingDoorAudio = false;
  }
}

function initAudioContext() {
  if (audioCtx) {
    if (audioCtx.state === 'suspended') {
      audioCtx.resume().catch(() => {});
    }
    predecodeDoorAudio(audioCtx);
    return audioCtx;
  }
  if (typeof window === 'undefined') return null;

  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  if (!AudioContextClass) return null;

  try {
    audioCtx = new AudioContextClass();
    masterGain = audioCtx.createGain();
    masterGain.gain.setValueAtTime(soundEnabled ? 0.90 : 0.0, audioCtx.currentTime);
    masterGain.connect(audioCtx.destination);
    predecodeDoorAudio(audioCtx);
  } catch (e) {
    console.warn('Web Audio not available', e);
    return null;
  }

  // Auto-resume on user gesture
  const resume = () => {
    if (audioCtx && audioCtx.state === 'suspended') {
      audioCtx.resume().catch(() => {});
    }
    predecodeDoorAudio(audioCtx);
    window.removeEventListener('pointerdown', resume);
    window.removeEventListener('keydown', resume);
  };
  window.addEventListener('pointerdown', resume, { passive: true });
  window.addEventListener('keydown', resume, { passive: true });

  return audioCtx;
}

function createPanner(ctx, pan = 0) {
  if (ctx && ctx.createStereoPanner) {
    const panner = ctx.createStereoPanner();
    panner.pan.value = Math.max(-0.85, Math.min(0.85, pan));
    panner.connect(masterGain);
    return panner;
  }
  return masterGain;
}

function createNoiseBuffer(ctx, duration) {
  const bufferSize = Math.max(1, Math.floor(ctx.sampleRate * duration));
  const buffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate);
  const output = buffer.getChannelData(0);
  for (let i = 0; i < bufferSize; i++) {
    output[i] = Math.random() * 2 - 1;
  }
  return buffer;
}

// ─── Public Audio Triggers ───────────────────────────────────────────────────

export function setSoundEnabled(enabled) {
  soundEnabled = Boolean(enabled);
  if (masterGain && audioCtx) {
    masterGain.gain.setValueAtTime(soundEnabled ? 0.90 : 0.0, audioCtx.currentTime);
  }
}

export function isSoundEnabled() {
  return soundEnabled;
}

/**
 * Ultra-Clicky Solenoid Electronic Lock Sound.
 * Synthesizes an authentic mechanical steel plunger "CLICK-CLACK" / snap
 * matching real 12V/24V industrial cabinet solenoid latch mechanisms.
 * @param {boolean} unlocked - true on unlock (energize + plunger snap), false on lock (spring bolt strike).
 * @param {number} pan - Stereo panning value (-1.0 to 1.0).
 */
export function playSolenoid(unlocked = true, pan = 0) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;

  const now = ctx.currentTime;
  const panner = createPanner(ctx, pan);

  if (unlocked) {
    // Stage 1: Ultra-sharp high-frequency mechanical micro-snap (tactile plunger release, 6.8 kHz)
    const snap1 = createNoiseBuffer(ctx, 0.012);
    const snapSource1 = ctx.createBufferSource();
    snapSource1.buffer = snap1;
    const filter1 = ctx.createBiquadFilter();
    filter1.type = 'bandpass';
    filter1.frequency.setValueAtTime(6800, now);
    filter1.Q.setValueAtTime(6.5, now);
    const gain1 = ctx.createGain();
    gain1.gain.setValueAtTime(0.95, now);
    gain1.gain.exponentialRampToValueAtTime(0.001, now + 0.012);
    snapSource1.connect(filter1);
    filter1.connect(gain1);
    gain1.connect(panner);
    snapSource1.start(now);

    // Stage 2: Steel pin retraction strike (crisp metallic click, 8ms offset)
    const t2 = now + 0.008;
    const osc2 = ctx.createOscillator();
    const oscGain2 = ctx.createGain();
    osc2.type = 'triangle';
    osc2.frequency.setValueAtTime(3200, t2);
    osc2.frequency.exponentialRampToValueAtTime(1400, t2 + 0.028);
    oscGain2.gain.setValueAtTime(0.75, t2);
    oscGain2.gain.exponentialRampToValueAtTime(0.001, t2 + 0.028);
    osc2.connect(oscGain2);
    oscGain2.connect(panner);
    osc2.start(t2);
    osc2.stop(t2 + 0.028);

    // Stage 3: Secondary latch backstop impact (clicky transient, 15ms offset)
    const t3 = now + 0.015;
    const snap2 = createNoiseBuffer(ctx, 0.018);
    const snapSource2 = ctx.createBufferSource();
    snapSource2.buffer = snap2;
    const filter2 = ctx.createBiquadFilter();
    filter2.type = 'bandpass';
    filter2.frequency.setValueAtTime(5200, t3);
    filter2.Q.setValueAtTime(5.0, t3);
    const gain2 = ctx.createGain();
    gain2.gain.setValueAtTime(0.80, t3);
    gain2.gain.exponentialRampToValueAtTime(0.001, t3 + 0.018);
    snapSource2.connect(filter2);
    filter2.connect(gain2);
    gain2.connect(panner);
    snapSource2.start(t3);

    // Stage 4: High-grade steel ring resonance (2350Hz decaying in 55ms)
    const ring = ctx.createOscillator();
    const ringGain = ctx.createGain();
    ring.type = 'sine';
    ring.frequency.setValueAtTime(2350, now + 0.006);
    ringGain.gain.setValueAtTime(0.28, now + 0.006);
    ringGain.gain.exponentialRampToValueAtTime(0.001, now + 0.06);
    ring.connect(ringGain);
    ringGain.connect(panner);
    ring.start(now + 0.006);
    ring.stop(now + 0.06);
  } else {
    // Locking: Solid spring-loaded latch engagement against strike plate ("KA-CHIK!")
    // 1. Initial wedge bevel scrape/snap against strike plate
    const strike = createNoiseBuffer(ctx, 0.014);
    const strikeSource = ctx.createBufferSource();
    strikeSource.buffer = strike;
    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(5400, now);
    filter.Q.setValueAtTime(5.2, now);
    const strikeGain = ctx.createGain();
    strikeGain.gain.setValueAtTime(0.85, now);
    strikeGain.gain.exponentialRampToValueAtTime(0.001, now + 0.014);
    strikeSource.connect(filter);
    filter.connect(strikeGain);
    strikeGain.connect(panner);
    strikeSource.start(now);

    // 2. Secondary solid seating latch snap (10ms offset, double-click punch)
    const t2 = now + 0.010;
    const click2 = createNoiseBuffer(ctx, 0.022);
    const clickSource2 = ctx.createBufferSource();
    clickSource2.buffer = click2;
    const filter2 = ctx.createBiquadFilter();
    filter2.type = 'bandpass';
    filter2.frequency.setValueAtTime(6200, t2);
    filter2.Q.setValueAtTime(5.8, t2);
    const clickGain2 = ctx.createGain();
    clickGain2.gain.setValueAtTime(0.90, t2);
    clickGain2.gain.exponentialRampToValueAtTime(0.001, t2 + 0.022);
    clickSource2.connect(filter2);
    filter2.connect(clickGain2);
    clickGain2.connect(panner);
    clickSource2.start(t2);

    // 3. Resonant steel door frame thwack (body impact tone)
    const osc = ctx.createOscillator();
    const oscGain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(1750, t2);
    osc.frequency.exponentialRampToValueAtTime(520, t2 + 0.045);
    oscGain.gain.setValueAtTime(0.60, t2);
    oscGain.gain.exponentialRampToValueAtTime(0.001, t2 + 0.045);
    osc.connect(oscGain);
    oscGain.connect(panner);
    osc.start(t2);
    osc.stop(t2 + 0.045);
  }
}

/**
 * Super Clicky Tactile Pushbutton Press (Industrial stainless tactile microswitch).
 */
export function playButtonClick(pan = 0) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;
  const now = ctx.currentTime;
  const panner = createPanner(ctx, pan);

  // 1. Ultra-sharp tactile microswitch snap (6400 Hz impulse, instant rise)
  const click = createNoiseBuffer(ctx, 0.009);
  const clickSource = ctx.createBufferSource();
  clickSource.buffer = click;
  const filter = ctx.createBiquadFilter();
  filter.type = 'bandpass';
  filter.frequency.setValueAtTime(6400, now);
  filter.Q.setValueAtTime(7.0, now);
  const clickGain = ctx.createGain();
  clickGain.gain.setValueAtTime(0.95, now);
  clickGain.gain.exponentialRampToValueAtTime(0.001, now + 0.009);
  clickSource.connect(filter);
  filter.connect(clickGain);
  clickGain.connect(panner);
  clickSource.start(now);

  // 2. Crisp stainless steel button collar ping (4100Hz -> 2100Hz)
  const osc = ctx.createOscillator();
  const oscGain = ctx.createGain();
  osc.type = 'triangle';
  osc.frequency.setValueAtTime(4100, now);
  osc.frequency.exponentialRampToValueAtTime(2100, now + 0.015);
  oscGain.gain.setValueAtTime(0.65, now);
  oscGain.gain.exponentialRampToValueAtTime(0.001, now + 0.015);
  osc.connect(oscGain);
  oscGain.connect(panner);
  osc.start(now);
  osc.stop(now + 0.015);

  // 3. Tactile bottom-out mechanical stop (5ms offset)
  const t2 = now + 0.005;
  const tap = ctx.createOscillator();
  const tapGain = ctx.createGain();
  tap.type = 'sine';
  tap.frequency.setValueAtTime(1800, t2);
  tapGain.gain.setValueAtTime(0.40, t2);
  tapGain.gain.exponentialRampToValueAtTime(0.001, t2 + 0.012);
  tap.connect(tapGain);
  tapGain.connect(panner);
  tap.start(t2);
  tap.stop(t2 + 0.012);
}

/**
 * Tactile Pushbutton Spring Release Click (Button pop-up reset).
 */
export function playButtonRelease(pan = 0) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;
  const now = ctx.currentTime;
  const panner = createPanner(ctx, pan);

  // Sharp spring-loaded reset snap (5600 Hz microswitch disc reset)
  const click = createNoiseBuffer(ctx, 0.008);
  const clickSource = ctx.createBufferSource();
  clickSource.buffer = click;
  const filter = ctx.createBiquadFilter();
  filter.type = 'bandpass';
  filter.frequency.setValueAtTime(5600, now);
  filter.Q.setValueAtTime(6.0, now);
  const clickGain = ctx.createGain();
  clickGain.gain.setValueAtTime(0.65, now);
  clickGain.gain.exponentialRampToValueAtTime(0.001, now + 0.008);
  clickSource.connect(filter);
  filter.connect(clickGain);
  clickGain.connect(panner);
  clickSource.start(now);

  const osc = ctx.createOscillator();
  const oscGain = ctx.createGain();
  osc.type = 'triangle';
  osc.frequency.setValueAtTime(3200, now);
  osc.frequency.exponentialRampToValueAtTime(1800, now + 0.012);
  oscGain.gain.setValueAtTime(0.35, now);
  oscGain.gain.exponentialRampToValueAtTime(0.001, now + 0.012);
  osc.connect(oscGain);
  oscGain.connect(panner);
  osc.start(now);
  osc.stop(now + 0.012);
}

/**
 * Authentic Industrial Scanner Dual-Tone Beep (Honeywell/Zebra style).
 */
export function playScannerBeep(pan = 0) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;
  const now = ctx.currentTime;
  const panner = createPanner(ctx, pan);

  // Tone 1: 1950 Hz
  const osc1 = ctx.createOscillator();
  const gain1 = ctx.createGain();
  osc1.type = 'sine';
  osc1.frequency.setValueAtTime(1950, now);
  gain1.gain.setValueAtTime(0.40, now);
  gain1.gain.exponentialRampToValueAtTime(0.01, now + 0.065);
  osc1.connect(gain1);
  gain1.connect(panner);
  osc1.start(now);
  osc1.stop(now + 0.065);

  // Tone 2: 2450 Hz
  const osc2 = ctx.createOscillator();
  const gain2 = ctx.createGain();
  osc2.type = 'sine';
  osc2.frequency.setValueAtTime(2450, now + 0.07);
  gain2.gain.setValueAtTime(0.45, now + 0.07);
  gain2.gain.exponentialRampToValueAtTime(0.001, now + 0.16);
  osc2.connect(gain2);
  gain2.connect(panner);
  osc2.start(now + 0.07);
  osc2.stop(now + 0.16);
}

let cachedDoorOpenBuffer = null;
let cachedDoorCloseBuffer = null;

/**
 * Pre-computes physically modeled acoustic PCM audio for Opening a Door.
 * Replicates a real physical door: mechanical latch handle click, rubber seal separation,
 * and smooth, natural door swing (no synthetic buzzy tones, no sine oscillators).
 */
function getDoorOpenBuffer(ctx) {
  if (cachedDoorOpenBuffer) return cachedDoorOpenBuffer;
  const sr = ctx.sampleRate;
  const dur = 0.85;
  const N = Math.floor(sr * dur);
  const audioBuf = ctx.createBuffer(1, N, sr);
  const data = audioBuf.getChannelData(0);

  for (let i = 0; i < N; i++) {
    const t = i / sr;
    let s = 0;

    // 1. Mechanical handle / unlatch release clicks (crisp metal clicks)
    if (t >= 0.010 && t < 0.030) {
      const dt = t - 0.010;
      s += (Math.random() * 2 - 1) * Math.exp(-380 * dt) * 0.45;
      s += Math.sin(2 * Math.PI * 3400 * dt) * Math.exp(-420 * dt) * 0.35;
    }
    if (t >= 0.030 && t < 0.055) {
      const dt = t - 0.030;
      s += (Math.random() * 2 - 1) * Math.exp(-320 * dt) * 0.35;
      s += Math.sin(2 * Math.PI * 2200 * dt) * Math.exp(-350 * dt) * 0.25;
    }

    // 2. Rubber weatherseal suction separation (t=0.04 to 0.12)
    if (t >= 0.04 && t < 0.12) {
      const dt = t - 0.04;
      const env = Math.sin(dt / 0.08 * Math.PI);
      s += (Math.random() * 2 - 1) * env * 0.12;
    }

    // 3. Smooth natural door swing air displacement (broadband gentle air movement, NO sine waves)
    if (t >= 0.08 && t < 0.80) {
      const dt = t - 0.08;
      const swingDur = 0.72;
      const env = Math.sin(dt / swingDur * Math.PI);
      // Gentle air friction turbulence
      s += (Math.random() * 2 - 1) * Math.pow(env, 2.0) * 0.12;
    }

    data[i] = Math.max(-0.95, Math.min(0.95, s));
  }
  cachedDoorOpenBuffer = audioBuf;
  return cachedDoorOpenBuffer;
}

/**
 * Pre-computes physically modeled acoustic PCM audio for Closing a Door.
 * Replicates a real physical door: solid cushioned frame impact, strike-plate slap,
 * and spring latch bolt snap ("THUD-CLACK") with zero start latency.
 */
function getDoorCloseBuffer(ctx) {
  if (cachedDoorCloseBuffer) return cachedDoorCloseBuffer;
  const sr = ctx.sampleRate;
  const dur = 0.50;
  const N = Math.floor(sr * dur);
  const audioBuf = ctx.createBuffer(1, N, sr);
  const data = audioBuf.getChannelData(0);

  for (let i = 0; i < N; i++) {
    const t = i / sr;
    let s = 0;

    // Deep cushioned door frame body thud (sheet metal & rubber seal impact)
    const thudFreq = 78 * (1 - 0.35 * Math.min(1, t * 10));
    s += Math.sin(2 * Math.PI * thudFreq * t) * Math.exp(-32 * t) * 0.72;
    s += Math.sin(2 * Math.PI * 145 * t) * Math.exp(-42 * t) * 0.36;

    // Strike plate impact (t=0 to 0.02)
    if (t < 0.02) {
      s += (Math.random() * 2 - 1) * Math.exp(-400 * t) * 0.55;
      s += Math.sin(2 * Math.PI * 4600 * t) * Math.exp(-380 * t) * 0.45;
    }

    // Spring-loaded latch bolt snap into hole at t=0.012
    if (t >= 0.012 && t < 0.045) {
      const dt2 = t - 0.012;
      s += Math.sin(2 * Math.PI * 3400 * dt2) * Math.exp(-320 * dt2) * 0.60;
      s += (Math.random() * 2 - 1) * Math.exp(-350 * dt2) * 0.40;
    }

    // Cabinet frame acoustic ring decay
    s += Math.sin(2 * Math.PI * 240 * t) * Math.exp(-25 * t) * 0.22;

    data[i] = Math.max(-0.95, Math.min(0.95, s));
  }
  cachedDoorCloseBuffer = audioBuf;
  return cachedDoorCloseBuffer;
}

/**
 * Authentic "Opening Door" Sound Effect.
 * Plays genuine recorded acoustic audio (unlatch release clicks, seal peel, and natural smooth door swing).
 * @param {number} pan - Stereo panning value (-1.0 to 1.0).
 */
export function playDoorOpen(pan = 0) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;
  predecodeDoorAudio(ctx);

  const panner = createPanner(ctx, pan);
  const source = ctx.createBufferSource();
  if (decodedDoorOpenBuffer) {
    source.buffer = decodedDoorOpenBuffer;
  } else {
    source.buffer = getDoorOpenBuffer(ctx);
  }
  source.connect(panner);
  source.start(ctx.currentTime);
}

/**
 * Gentle Door Swing Whoosh during closing motion.
 * @param {number} pan - Stereo panning value (-1.0 to 1.0).
 * @param {number} duration - Playback duration in seconds.
 */
export function playDoorCloseSwing(pan = 0, duration = 1.10) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;

  const now = ctx.currentTime;
  const panner = createPanner(ctx, pan);

  // Soft air displacement / gentle door swing whoosh
  const whoosh = createNoiseBuffer(ctx, duration);
  const whooshSrc = ctx.createBufferSource();
  whooshSrc.buffer = whoosh;
  const whooshFilter = ctx.createBiquadFilter();
  whooshFilter.type = 'lowpass';
  whooshFilter.frequency.setValueAtTime(140, now);
  whooshFilter.frequency.linearRampToValueAtTime(240, now + 0.4);
  whooshFilter.frequency.linearRampToValueAtTime(160, now + duration);
  const whooshGain = ctx.createGain();
  whooshGain.gain.setValueAtTime(0.001, now);
  whooshGain.gain.linearRampToValueAtTime(0.08, now + 0.25);
  whooshGain.gain.linearRampToValueAtTime(0.10, now + 0.70);
  whooshGain.gain.exponentialRampToValueAtTime(0.001, now + duration);

  whooshSrc.connect(whooshFilter);
  whooshFilter.connect(whooshGain);
  whooshGain.connect(panner);
  whooshSrc.start(now);
}

/**
 * Authentic "Close Door" Impact & Latch Catch ("THUD-CLACK!").
 * Plays instant recorded acoustic audio: solid cushioned frame thud, strike-plate contact, and spring latch bolt snap.
 * @param {number} pan - Stereo panning value (-1.0 to 1.0).
 */
export function playDoorCloseImpact(pan = 0) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;
  predecodeDoorAudio(ctx);

  const panner = createPanner(ctx, pan);
  const source = ctx.createBufferSource();
  if (decodedDoorCloseImpactBuffer) {
    source.buffer = decodedDoorCloseImpactBuffer;
  } else {
    source.buffer = getDoorCloseBuffer(ctx);
  }
  source.connect(panner);
  source.start(ctx.currentTime);
}

/**
 * Full Complete "Close Door" Sound Effect (Pre-impact swing + THUD-CLACK impact).
 * @param {number} pan - Stereo panning value (-1.0 to 1.0).
 */
export function playDoorClose(pan = 0) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;
  predecodeDoorAudio(ctx);

  const panner = createPanner(ctx, pan);
  const source = ctx.createBufferSource();
  if (decodedDoorCloseFullBuffer) {
    source.buffer = decodedDoorCloseFullBuffer;
    source.connect(panner);
    source.start(ctx.currentTime);
  } else {
    playDoorCloseImpact(pan);
  }
}

/**
 * Slow, Resonant Door Hinge Metal Friction & Creak.
 * Kept for backward compatibility; calls playDoorOpen.
 */
export function playDoorCreak(pan = 0) {
  playDoorOpen(pan);
}

/**
 * Dynamic Parcel Landing / Collision Sound.
 * Supports hollow cardboard boxes, bubble-wrapped parcels, and poly mailer bags.
 * @param {string} parcelType - 'bubble', 'pouch', or 'cardboard'
 * @param {number} velocity - Impact velocity scalar
 * @param {number} pan - Stereo panning value (-1.0 to 1.0)
 */
export function playParcelImpact(parcelType = 'cardboard', velocity = 1.0, pan = 0) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;
  const now = ctx.currentTime;
  const panner = createPanner(ctx, pan);
  const intensity = Math.min(1.0, Math.max(0.18, velocity / 1.7));

  if (parcelType === 'pouch') {
    // Flexible poly mailer pouch: soft crinkle + muffled flat thud
    const crinkle = createNoiseBuffer(ctx, 0.06);
    const crinkleSource = ctx.createBufferSource();
    crinkleSource.buffer = crinkle;
    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(1400, now);
    filter.Q.setValueAtTime(1.5, now);
    const crinkleGain = ctx.createGain();
    crinkleGain.gain.setValueAtTime(0.35 * intensity, now);
    crinkleGain.gain.exponentialRampToValueAtTime(0.001, now + 0.06);
    crinkleSource.connect(filter);
    filter.connect(crinkleGain);
    crinkleGain.connect(panner);
    crinkleSource.start(now);

    const thud = ctx.createOscillator();
    const thudGain = ctx.createGain();
    thud.type = 'sine';
    thud.frequency.setValueAtTime(95, now);
    thud.frequency.exponentialRampToValueAtTime(45, now + 0.09);
    thudGain.gain.setValueAtTime(0.40 * intensity, now);
    thudGain.gain.exponentialRampToValueAtTime(0.001, now + 0.09);
    thud.connect(thudGain);
    thudGain.connect(panner);
    thud.start(now);
    thud.stop(now + 0.09);
  } else if (parcelType === 'bubble') {
    // Black bubble wrap box: cushioned plastic pop/crinkle + damped box thud
    const pop = createNoiseBuffer(ctx, 0.05);
    const popSource = ctx.createBufferSource();
    popSource.buffer = pop;
    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(850, now);
    filter.Q.setValueAtTime(2.5, now);
    const popGain = ctx.createGain();
    popGain.gain.setValueAtTime(0.45 * intensity, now);
    popGain.gain.exponentialRampToValueAtTime(0.001, now + 0.05);
    popSource.connect(filter);
    filter.connect(popGain);
    popGain.connect(panner);
    popSource.start(now);

    const box = ctx.createOscillator();
    const boxGain = ctx.createGain();
    box.type = 'sine';
    box.frequency.setValueAtTime(75, now);
    box.frequency.exponentialRampToValueAtTime(38, now + 0.11);
    boxGain.gain.setValueAtTime(0.52 * intensity, now);
    boxGain.gain.exponentialRampToValueAtTime(0.001, now + 0.11);
    box.connect(boxGain);
    boxGain.connect(panner);
    box.start(now);
    box.stop(now + 0.11);
  } else {
    // Cardboard box: hollow cavity resonance + corrugated impact
    const cavity = ctx.createOscillator();
    const cavityGain = ctx.createGain();
    cavity.type = 'sine';
    const baseFreq = 74 + Math.random() * 20;
    cavity.frequency.setValueAtTime(baseFreq, now);
    cavity.frequency.exponentialRampToValueAtTime(36, now + 0.13);
    cavityGain.gain.setValueAtTime(0.60 * intensity, now);
    cavityGain.gain.exponentialRampToValueAtTime(0.001, now + 0.13);
    cavity.connect(cavityGain);
    cavityGain.connect(panner);
    cavity.start(now);
    cavity.stop(now + 0.13);

    const noise = createNoiseBuffer(ctx, 0.065);
    const noiseSource = ctx.createBufferSource();
    noiseSource.buffer = noise;
    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(320 + Math.random() * 80, now);
    filter.Q.setValueAtTime(2.2, now);
    const noiseGain = ctx.createGain();
    noiseGain.gain.setValueAtTime(0.42 * intensity, now);
    noiseGain.gain.exponentialRampToValueAtTime(0.001, now + 0.065);
    noiseSource.connect(filter);
    filter.connect(noiseGain);
    noiseGain.connect(panner);
    noiseSource.start(now);
  }
}

/**
 * Friction slide of parcel down the chute ramp.
 */
export function playCardboardSlide(pan = 0) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;
  const now = ctx.currentTime;
  const panner = createPanner(ctx, pan);

  const noise = createNoiseBuffer(ctx, 0.28);
  const noiseSource = ctx.createBufferSource();
  noiseSource.buffer = noise;
  const filter = ctx.createBiquadFilter();
  filter.type = 'bandpass';
  filter.frequency.setValueAtTime(460, now);
  filter.frequency.linearRampToValueAtTime(310, now + 0.28);
  filter.Q.setValueAtTime(1.8, now);
  const gain = ctx.createGain();
  gain.gain.setValueAtTime(0.001, now);
  gain.gain.linearRampToValueAtTime(0.26, now + 0.04);
  gain.gain.exponentialRampToValueAtTime(0.001, now + 0.28);
  noiseSource.connect(filter);
  filter.connect(gain);
  gain.connect(panner);
  noiseSource.start(now);
}

/**
 * Motorcycle Scooter 4-Stroke Engine Approach Sound.
 * Synthesizes single-cylinder combustion pulses gliding to a stop.
 */
export function playEngineApproach(pan = 0.5) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;
  const now = ctx.currentTime;
  const panner = createPanner(ctx, pan);
  const duration = 1.6;

  // Single-cylinder firing pulses (4-stroke engine ~42Hz descending to 22Hz idle)
  const osc = ctx.createOscillator();
  const oscGain = ctx.createGain();
  osc.type = 'sawtooth';
  osc.frequency.setValueAtTime(48, now);
  osc.frequency.linearRampToValueAtTime(32, now + 0.8);
  osc.frequency.linearRampToValueAtTime(22, now + duration);

  // Exhaust muffler chamber lowpass filter
  const filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.setValueAtTime(220, now);
  filter.Q.setValueAtTime(3.5, now);

  oscGain.gain.setValueAtTime(0.001, now);
  oscGain.gain.linearRampToValueAtTime(0.32, now + 0.3);
  oscGain.gain.linearRampToValueAtTime(0.24, now + 1.0);
  oscGain.gain.exponentialRampToValueAtTime(0.001, now + duration);

  osc.connect(filter);
  filter.connect(oscGain);
  oscGain.connect(panner);
  osc.start(now);
  osc.stop(now + duration);

  // Exhaust puff noise
  const noise = createNoiseBuffer(ctx, duration);
  const noiseSource = ctx.createBufferSource();
  noiseSource.buffer = noise;
  const noiseFilter = ctx.createBiquadFilter();
  noiseFilter.type = 'bandpass';
  noiseFilter.frequency.setValueAtTime(320, now);
  noiseFilter.Q.setValueAtTime(2.0, now);
  const noiseGain = ctx.createGain();
  noiseGain.gain.setValueAtTime(0.001, now);
  noiseGain.gain.linearRampToValueAtTime(0.08, now + 0.2);
  noiseGain.gain.exponentialRampToValueAtTime(0.001, now + duration);
  noiseSource.connect(noiseFilter);
  noiseFilter.connect(noiseGain);
  noiseGain.connect(panner);
  noiseSource.start(now);
}

/**
 * Motorcycle Scooter Engine Rev & Drive-Away Sound.
 */
export function playEngineDepart(pan = -0.5) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;
  const now = ctx.currentTime;
  const panner = createPanner(ctx, pan);
  const duration = 2.0;

  const osc = ctx.createOscillator();
  const oscGain = ctx.createGain();
  osc.type = 'sawtooth';
  osc.frequency.setValueAtTime(24, now);
  osc.frequency.exponentialRampToValueAtTime(68, now + 1.2);
  osc.frequency.linearRampToValueAtTime(52, now + duration);

  const filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.setValueAtTime(180, now);
  filter.frequency.linearRampToValueAtTime(340, now + 1.2);
  filter.Q.setValueAtTime(3.0, now);

  oscGain.gain.setValueAtTime(0.001, now);
  oscGain.gain.linearRampToValueAtTime(0.35, now + 0.25);
  oscGain.gain.linearRampToValueAtTime(0.38, now + 1.0);
  oscGain.gain.exponentialRampToValueAtTime(0.001, now + duration);

  osc.connect(filter);
  filter.connect(oscGain);
  oscGain.connect(panner);
  osc.start(now);
  osc.stop(now + duration);
}

/**
 * Spring-loaded motorcycle side kickstand snap.
 */
export function playKickstand(pan = 0.4) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;
  const now = ctx.currentTime;
  const panner = createPanner(ctx, pan);

  // Sharp metallic spring clack (3200Hz impulse + 1200Hz body snap)
  const snap = createNoiseBuffer(ctx, 0.02);
  const snapSource = ctx.createBufferSource();
  snapSource.buffer = snap;
  const filter = ctx.createBiquadFilter();
  filter.type = 'bandpass';
  filter.frequency.setValueAtTime(3400, now);
  filter.Q.setValueAtTime(4.5, now);
  const gain = ctx.createGain();
  gain.gain.setValueAtTime(0.70, now);
  gain.gain.exponentialRampToValueAtTime(0.001, now + 0.02);
  snapSource.connect(filter);
  filter.connect(gain);
  gain.connect(panner);
  snapSource.start(now);

  const ring = ctx.createOscillator();
  const ringGain = ctx.createGain();
  ring.type = 'triangle';
  ring.frequency.setValueAtTime(1180, now + 0.005);
  ringGain.gain.setValueAtTime(0.40, now + 0.005);
  ringGain.gain.exponentialRampToValueAtTime(0.001, now + 0.04);
  ring.connect(ringGain);
  ringGain.connect(panner);
  ring.start(now + 0.005);
  ring.stop(now + 0.04);
}

/**
 * Courier Footstep on Ground.
 */
export function playFootstep(pan = 0.1) {
  const ctx = initAudioContext();
  if (!ctx || !soundEnabled) return;
  const now = ctx.currentTime;
  const panner = createPanner(ctx, pan);

  const noise = createNoiseBuffer(ctx, 0.035);
  const noiseSource = ctx.createBufferSource();
  noiseSource.buffer = noise;
  const filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.setValueAtTime(580 + Math.random() * 120, now);
  const gain = ctx.createGain();
  gain.gain.setValueAtTime(0.18, now);
  gain.gain.exponentialRampToValueAtTime(0.001, now + 0.035);
  noiseSource.connect(filter);
  filter.connect(gain);
  gain.connect(panner);
  noiseSource.start(now);
}

