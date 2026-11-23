import { BoxGeometry, CanvasTexture, Group, Mesh, MeshStandardMaterial, SRGBColorSpace, Vector3 } from './three-viewer-engine.js';
import { Body, Box, Material, Plane, SAPBroadphase, Vec3, World } from './cannon-es.min.js';
import { playCardboardSlide, playParcelImpact } from './viewer-audio.js';

const stepSeconds = 1 / 120;
const rearEdge = -0.30;
const defaultBoxSize = [0.096, 0.076, 0.082];

// ─── Procedural Realistic E-Commerce Packaging Textures ──────────────────────

/**
 * Procedural Kraft Corrugated Cardboard Canvas.
 */
function createCardboardCanvas(w, h, baseTone) {
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');

  // Kraft gradient
  const grad = ctx.createLinearGradient(0, 0, w, h);
  grad.addColorStop(0, baseTone.light);
  grad.addColorStop(1, baseTone.dark);
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, w, h);

  // Horizontal corrugation lines
  ctx.fillStyle = 'rgba(0, 0, 0, 0.04)';
  for (let y = 0; y < h; y += 4) {
    ctx.fillRect(0, y, w, 1);
  }
  ctx.fillStyle = 'rgba(255, 255, 255, 0.035)';
  for (let y = 1; y < h; y += 4) {
    ctx.fillRect(0, y, w, 1);
  }

  // Pulp speckles
  ctx.fillStyle = 'rgba(50, 30, 10, 0.07)';
  for (let i = 0; i < 90; i++) {
    const rx = (Math.sin(i * 19.3) * 0.5 + 0.5) * w;
    const ry = (Math.cos(i * 41.7) * 0.5 + 0.5) * h;
    ctx.fillRect(rx, ry, 1.5, 1.5);
  }

  return { canvas, ctx };
}

/**
 * Procedural Black Bubble-Wrapped E-Commerce Parcel Canvas.
 * Accurately models glossy black bubble wrap / stretch film wrapping used by
 * Shopee, Lazada, and electronics sellers.
 */
function createBlackBubbleWrapCanvas(w, h) {
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');

  // Deep glossy charcoal-black base
  const grad = ctx.createLinearGradient(0, 0, w, h);
  grad.addColorStop(0, '#16171a');
  grad.addColorStop(0.5, '#22242a');
  grad.addColorStop(1, '#18191c');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, w, h);

  // Hexagonal/staggered air bubble grid
  const spacing = 15;
  const radius = 5.2;
  ctx.save();
  for (let y = 8; y < h; y += spacing) {
    const rowOffset = (Math.floor(y / spacing) % 2 === 0) ? 0 : spacing * 0.5;
    for (let x = 8 + rowOffset; x < w; x += spacing) {
      // Bubble shadow rim (bottom-right)
      ctx.beginPath();
      ctx.arc(x + 0.5, y + 0.5, radius, -Math.PI * 0.1, Math.PI * 0.85, false);
      ctx.strokeStyle = 'rgba(0, 0, 0, 0.65)';
      ctx.lineWidth = 1.8;
      ctx.stroke();

      // Bubble specular highlight rim (top-left)
      ctx.beginPath();
      ctx.arc(x - 0.5, y - 0.5, radius, Math.PI * 0.85, Math.PI * 1.85, false);
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.22)';
      ctx.lineWidth = 1.4;
      ctx.stroke();

      // Bubble center sheen
      ctx.fillStyle = 'rgba(255, 255, 255, 0.12)';
      ctx.fillRect(x - 1.5, y - 1.5, 2.5, 2.5);
    }
  }

  // Heat-sealed plastic tape seam across center
  const seamX = Math.floor(w / 2);
  ctx.fillStyle = 'rgba(255, 255, 255, 0.08)';
  ctx.fillRect(seamX - 18, 0, 36, h);
  ctx.fillStyle = 'rgba(255, 255, 255, 0.22)';
  ctx.fillRect(seamX - 18, 0, 1.5, h);
  ctx.fillRect(seamX + 17, 0, 1.5, h);
  ctx.restore();

  return { canvas, ctx };
}

/**
 * Procedural Poly Mailer Courier Pouch / Flyer Bag Canvas.
 * Accurately models flexible grey/charcoal e-commerce courier bags with
 * welded crimped edges and subtle plastic flex wrinkles.
 */
function createPolyMailerCanvas(w, h) {
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');

  // Matte dark slate-grey polyethylene flyer base
  const grad = ctx.createLinearGradient(0, 0, 0, h);
  grad.addColorStop(0, '#2e3037');
  grad.addColorStop(0.5, '#383b44');
  grad.addColorStop(1, '#2c2e35');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, w, h);

  ctx.save();
  // Heat-welded crimped seam margins on left and right edges
  ctx.fillStyle = 'rgba(0, 0, 0, 0.45)';
  ctx.fillRect(0, 0, 7, h);
  ctx.fillRect(w - 7, 0, 7, h);
  ctx.fillStyle = 'rgba(255, 255, 255, 0.14)';
  ctx.fillRect(6, 0, 1.5, h);
  ctx.fillRect(w - 7.5, 0, 1.5, h);

  // Serrated crimp weld dots
  for (let y = 3; y < h; y += 5) {
    ctx.fillStyle = 'rgba(0, 0, 0, 0.6)';
    ctx.fillRect(2, y, 3, 2);
    ctx.fillRect(w - 5, y, 3, 2);
    ctx.fillStyle = 'rgba(255, 255, 255, 0.15)';
    ctx.fillRect(2, y + 2, 3, 1);
    ctx.fillRect(w - 5, y + 2, 3, 1);
  }

  // Fold-over adhesive flap line across top
  ctx.fillStyle = 'rgba(0, 0, 0, 0.35)';
  ctx.fillRect(0, 22, w, 2);
  ctx.fillStyle = 'rgba(255, 255, 255, 0.18)';
  ctx.fillRect(0, 24, w, 1);

  // Red tamper-evident pull-to-open warning strip
  ctx.fillStyle = '#b72222';
  ctx.fillRect(10, 10, w - 20, 9);
  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 6.5px sans-serif';
  ctx.fillText('▲ SEALED COURIER POUCH - DO NOT ACCEPT IF OPENED ▲', 14, 17);

  // Diagonal poly bag wrinkles/creases
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.07)';
  ctx.lineWidth = 2.0;
  ctx.beginPath();
  ctx.moveTo(14, 35); ctx.bezierCurveTo(45, 60, 90, 70, 130, 95);
  ctx.moveTo(w - 18, 50); ctx.bezierCurveTo(w - 50, 85, w - 90, 110, w - 140, 140);
  ctx.moveTo(25, 170); ctx.bezierCurveTo(70, 185, 120, 195, 180, 215);
  ctx.stroke();

  ctx.strokeStyle = 'rgba(0, 0, 0, 0.16)';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(15, 37); ctx.bezierCurveTo(46, 62, 91, 72, 131, 97);
  ctx.moveTo(w - 17, 52); ctx.bezierCurveTo(w - 49, 87, w - 89, 112, w - 139, 142);
  ctx.stroke();
  ctx.restore();

  return { canvas, ctx };
}

function drawFlapSeam(ctx, w, h, vertical = true) {
  ctx.save();
  if (vertical) {
    const cx = Math.floor(w / 2);
    ctx.fillStyle = 'rgba(0, 0, 0, 0.28)';
    ctx.fillRect(cx - 1, 0, 2, h);
    ctx.fillStyle = 'rgba(255, 255, 255, 0.15)';
    ctx.fillRect(cx + 1, 0, 1, h);
  } else {
    const cy = Math.floor(h / 2);
    ctx.fillStyle = 'rgba(0, 0, 0, 0.28)';
    ctx.fillRect(0, cy - 1, w, 2);
    ctx.fillStyle = 'rgba(255, 255, 255, 0.15)';
    ctx.fillRect(0, cy + 1, w, 1);
  }
  ctx.restore();
}

function drawTape(ctx, x, y, w, h, style = 'clear') {
  ctx.save();
  if (style === 'security') {
    // Red security tape with white warning text
    ctx.fillStyle = '#c02424';
    ctx.fillRect(x, y, w, h);
    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 9px sans-serif';
    const text = '▲ FRAGILE - HANDLE WITH CARE ▲';
    if (w > h) {
      for (let tx = x + 10; tx < x + w; tx += 180) {
        ctx.fillText(text, tx, y + h / 2 + 3);
      }
    } else {
      ctx.save();
      ctx.translate(x + h / 2, y + 10);
      ctx.rotate(Math.PI / 2);
      ctx.fillText(text, 0, 3);
      ctx.restore();
    }
    ctx.fillStyle = 'rgba(255, 255, 255, 0.25)';
    ctx.fillRect(x, y, w, 1);
  } else if (style === 'reinforced') {
    // Tan reinforced paper tape with fiberglass cross-threads
    ctx.fillStyle = '#ae7f4e';
    ctx.fillRect(x, y, w, h);
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.22)';
    ctx.lineWidth = 1;
    for (let d = -h; d < w + h; d += 12) {
      ctx.beginPath();
      ctx.moveTo(x + d, y);
      ctx.lineTo(x + d + h, y + h);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(x + d, y + h);
      ctx.lineTo(x + d + h, y);
      ctx.stroke();
    }
  } else {
    // Clear glossy packaging tape
    ctx.fillStyle = 'rgba(230, 200, 130, 0.42)';
    ctx.fillRect(x, y, w, h);
    ctx.fillStyle = 'rgba(255, 255, 255, 0.38)';
    ctx.fillRect(x, y, w, 1.5);
    ctx.fillStyle = 'rgba(0, 0, 0, 0.12)';
    ctx.fillRect(x, y + h - 1, w, 1);
  }
  ctx.restore();
}

/**
 * Authentic Courier Air Waybill (Thermal Shipping Sticker).
 */
function drawAirWaybill(ctx, x, y, w, h, data) {
  ctx.save();
  // White thermal sticker label with soft shadow and crisp border
  ctx.fillStyle = 'rgba(0, 0, 0, 0.16)';
  ctx.fillRect(x + 2, y + 2, w, h);
  ctx.fillStyle = '#fbfbfa';
  ctx.fillRect(x, y, w, h);
  ctx.strokeStyle = '#c8c2b5';
  ctx.lineWidth = 1;
  ctx.strokeRect(x, y, w, h);

  // Carrier Banner Header
  ctx.fillStyle = data.bannerColor || '#c82020';
  ctx.fillRect(x, y, w, 24);
  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 11.5px sans-serif';
  ctx.fillText(data.carrier, x + 8, y + 16);

  // Air Waybill Tag
  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 8px monospace';
  ctx.fillText('AIR WAYBILL', x + w - 66, y + 16);

  // Service Badge & Cashless Tag
  ctx.fillStyle = '#111111';
  ctx.font = 'bold 9px monospace';
  ctx.fillText(data.service, x + 8, y + 36);
  ctx.fillStyle = '#1e7e34';
  ctx.fillRect(x + w - 50, y + 27, 44, 14);
  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 7.5px sans-serif';
  ctx.fillText('PAID/CASHLESS', x + w - 48, y + 37);

  // 1D Barcode
  const barY = y + 44;
  const barH = 34;
  const barStartX = x + 8;
  const barWidth = w - 16;
  ctx.fillStyle = '#111111';
  let curX = barStartX;
  const pattern = [2, 1, 1, 3, 1, 2, 1, 1, 4, 1, 2, 3, 1, 2, 1, 3, 2, 1, 1, 2, 4, 1, 2, 1, 3, 1, 2, 2, 1, 3, 1, 1];
  for (let i = 0; i < pattern.length && curX < barStartX + barWidth - 10; i++) {
    const pw = pattern[i];
    if (i % 2 === 0) {
      ctx.fillRect(curX, barY, pw, barH);
    }
    curX += pw + 1;
  }
  // Tracking text
  ctx.fillStyle = '#222222';
  ctx.font = 'bold 8.5px monospace';
  ctx.fillText(data.tracking, x + 10, barY + barH + 11);

  // 2D QR Code stamp in upper-right
  const qrX = x + w - 46;
  const qrY = y + 92;
  const qrS = 38;
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(qrX - 2, qrY - 2, qrS + 4, qrS + 4);
  ctx.fillStyle = '#111111';
  ctx.fillRect(qrX, qrY, qrS, qrS);
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(qrX + 3, qrY + 3, qrS - 6, qrS - 6);
  function drawFinder(fx, fy) {
    ctx.fillStyle = '#111111';
    ctx.fillRect(fx, fy, 10, 10);
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(fx + 2, fy + 2, 6, 6);
    ctx.fillStyle = '#111111';
    ctx.fillRect(fx + 3, fy + 3, 4, 4);
  }
  drawFinder(qrX + 2, qrY + 2);
  drawFinder(qrX + qrS - 12, qrY + 2);
  drawFinder(qrX + 2, qrY + qrS - 12);
  ctx.fillStyle = '#111111';
  for (let r = 0; r < 5; r++) {
    for (let c = 0; c < 5; c++) {
      if ((r + c) % 2 === 0) ctx.fillRect(qrX + 14 + c * 4, qrY + 14 + r * 4, 3, 3);
    }
  }

  // Address block
  ctx.fillStyle = '#222222';
  ctx.font = '8px sans-serif';
  ctx.fillText('TO: SMART DROPBOX RESIDENCE', x + 8, y + 104);
  ctx.fillText('PARCEL VAULT · CHUTE A', x + 8, y + 116);
  ctx.fillText('REF: ' + (data.ref || 'ECOM-9912'), x + 8, y + 128);

  // Routing stamp box
  ctx.strokeStyle = '#222222';
  ctx.lineWidth = 1.5;
  ctx.strokeRect(x + 8, y + 134, 62, 20);
  ctx.fillStyle = '#111111';
  ctx.font = 'bold 9.5px monospace';
  ctx.fillText(data.postal, x + 11, y + 148);

  ctx.restore();
}

function drawHandlingStamp(ctx, x, y, type) {
  ctx.save();
  ctx.fillStyle = '#1c1b18';
  ctx.strokeStyle = '#1c1b18';
  ctx.lineWidth = 2;
  if (type === 'arrows') {
    ctx.beginPath();
    ctx.moveTo(x + 6, y + 20); ctx.lineTo(x + 6, y + 6);
    ctx.moveTo(x + 2, y + 10); ctx.lineTo(x + 6, y + 4); ctx.lineTo(x + 10, y + 10);
    ctx.moveTo(x + 18, y + 20); ctx.lineTo(x + 18, y + 6);
    ctx.moveTo(x + 14, y + 10); ctx.lineTo(x + 18, y + 4); ctx.lineTo(x + 22, y + 10);
    ctx.stroke();
    ctx.fillRect(x + 2, y + 23, 20, 2.5);
  } else if (type === 'glass') {
    ctx.beginPath();
    ctx.moveTo(x + 4, y + 4);
    ctx.bezierCurveTo(x + 4, y + 15, x + 20, y + 15, x + 20, y + 4);
    ctx.closePath();
    ctx.stroke();
    ctx.fillRect(x + 11, y + 15, 2, 8);
    ctx.fillRect(x + 6, y + 23, 12, 2);
  } else if (type === 'umbrella') {
    ctx.beginPath();
    ctx.arc(x + 12, y + 12, 10, Math.PI, 0, false);
    ctx.closePath();
    ctx.stroke();
    ctx.fillRect(x + 11, y + 12, 2, 8);
    ctx.beginPath();
    ctx.arc(x + 9, y + 20, 3, 0, Math.PI, false);
    ctx.stroke();
  } else if (type === 'recycle') {
    ctx.strokeRect(x + 2, y + 2, 22, 22);
    ctx.font = 'bold 8px sans-serif';
    ctx.fillText('20 PAP', x + 4, y + 16);
  } else if (type === 'poly') {
    ctx.strokeRect(x + 2, y + 2, 22, 22);
    ctx.font = 'bold 7.5px sans-serif';
    ctx.fillText('04 PE', x + 4, y + 16);
  }
  ctx.restore();
}

let cachedPouchGeometry = null;
function getPouchGeometry() {
  if (cachedPouchGeometry) return cachedPouchGeometry;
  // Subdivided mesh with 12 segments along X and Z, 4 along Y to allow pillowed deformation
  const geom = new BoxGeometry(1, 1, 1, 12, 4, 12);
  const pos = geom.getAttribute('position');
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i);
    const y = pos.getY(i);
    const z = pos.getZ(i);
    const dx = 0.5 - Math.abs(x);
    const dz = 0.5 - Math.abs(z);
    const edgeDist = Math.min(dx, dz);
    if (edgeDist < 0.08) {
      // Pinched heat-sealed welded margin (flat edges of courier polymailer bag)
      pos.setY(i, y * 0.14);
    } else {
      // Smooth organic pillow bulge in bag center
      const u = Math.sin((x + 0.5) * Math.PI);
      const v = Math.sin((z + 0.5) * Math.PI);
      const bulge = Math.sqrt(Math.max(0, u * v));
      pos.setY(i, y * (0.35 + 0.92 * bulge));
    }
  }
  geom.computeVertexNormals();
  cachedPouchGeometry = geom;
  return cachedPouchGeometry;
}

let cachedPaddedMailerGeometry = null;
function getPaddedMailerGeometry() {
  if (cachedPaddedMailerGeometry) return cachedPaddedMailerGeometry;
  const geom = new BoxGeometry(1, 1, 1, 10, 4, 10);
  const pos = geom.getAttribute('position');
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i);
    const y = pos.getY(i);
    const z = pos.getZ(i);
    const dx = 0.5 - Math.abs(x);
    const dz = 0.5 - Math.abs(z);
    const edgeDist = Math.min(dx, dz);
    if (edgeDist < 0.06) {
      // Heat-pressed border
      pos.setY(i, y * 0.18);
    } else {
      const u = Math.sin((x + 0.5) * Math.PI);
      const v = Math.sin((z + 0.5) * Math.PI);
      pos.setY(i, y * (0.50 + 0.65 * Math.sqrt(Math.max(0, u * v))));
    }
  }
  geom.computeVertexNormals();
  cachedPaddedMailerGeometry = geom;
  return cachedPaddedMailerGeometry;
}

// ─── Parcel Packaging Variant Builders ───────────────────────────────────────

/**
 * Style 0: Black Bubble-Wrapped Box + Waybill
 */
function buildBlackBubbleWrapStyle(options) {
  if (typeof document === 'undefined') {
    const mat = new MeshStandardMaterial({ color: 0x18191c, roughness: 0.45 });
    return { type: 'bubble', size: options.size, mass: options.mass, materials: [mat, mat, mat, mat, mat, mat] };
  }

  // 1. Top face (bubble wrap + thermal Air Waybill)
  const top = createBlackBubbleWrapCanvas(256, 256);
  drawAirWaybill(top.ctx, 30, 24, 196, 168, options.label);
  const topTex = new CanvasTexture(top.canvas);
  topTex.colorSpace = SRGBColorSpace;
  const topMat = new MeshStandardMaterial({ map: topTex, roughness: 0.42, metalness: 0.08 });

  // 2. Bottom face (bubble wrap + sealed tape seam)
  const btm = createBlackBubbleWrapCanvas(256, 256);
  const btmTex = new CanvasTexture(btm.canvas);
  btmTex.colorSpace = SRGBColorSpace;
  const btmMat = new MeshStandardMaterial({ map: btmTex, roughness: 0.45, metalness: 0.08 });

  // 3. Side faces (bubble wrap + fragile stamp)
  const side = createBlackBubbleWrapCanvas(256, 256);
  side.ctx.fillStyle = '#ff3b30';
  side.ctx.fillRect(20, 25, 80, 24);
  side.ctx.fillStyle = '#ffffff';
  side.ctx.font = 'bold 9.5px sans-serif';
  side.ctx.fillText('▲ FRAGILE ▲', 26, 40);
  const sideTex = new CanvasTexture(side.canvas);
  sideTex.colorSpace = SRGBColorSpace;
  const sideMat = new MeshStandardMaterial({ map: sideTex, roughness: 0.45, metalness: 0.08 });

  // 4. Front face (bubble wrap + handling arrows)
  const front = createBlackBubbleWrapCanvas(256, 256);
  const frontTex = new CanvasTexture(front.canvas);
  frontTex.colorSpace = SRGBColorSpace;
  const frontMat = new MeshStandardMaterial({ map: frontTex, roughness: 0.45, metalness: 0.08 });

  // 5. Back face
  const back = createBlackBubbleWrapCanvas(256, 256);
  const backTex = new CanvasTexture(back.canvas);
  backTex.colorSpace = SRGBColorSpace;
  const backMat = new MeshStandardMaterial({ map: backTex, roughness: 0.45, metalness: 0.08 });

  return {
    type: 'bubble',
    size: options.size,
    mass: options.mass,
    materials: [sideMat, sideMat, topMat, btmMat, frontMat, backMat],
  };
}

/**
 * Style 1: Poly Mailer Pouch / Courier Bag + Waybill
 */
function buildPolyMailerStyle(options) {
  if (typeof document === 'undefined') {
    const mat = new MeshStandardMaterial({ color: 0x30333a, roughness: 0.55 });
    return { type: 'pouch', size: options.size, mass: options.mass, materials: [mat, mat, mat, mat, mat, mat] };
  }

  // 1. Top/Front face (poly flyer pouch with welded margins + Air Waybill)
  const top = createPolyMailerCanvas(256, 256);
  drawAirWaybill(top.ctx, 32, 28, 192, 168, options.label);
  const topTex = new CanvasTexture(top.canvas);
  topTex.colorSpace = SRGBColorSpace;
  const topMat = new MeshStandardMaterial({ map: topTex, roughness: 0.50, metalness: 0.04 });

  // 2. Bottom/Back face (poly flyer flap fold)
  const btm = createPolyMailerCanvas(256, 256);
  const btmTex = new CanvasTexture(btm.canvas);
  btmTex.colorSpace = SRGBColorSpace;
  const btmMat = new MeshStandardMaterial({ map: btmTex, roughness: 0.54, metalness: 0.04 });

  // 3. Side faces (welded crimp margins)
  const side = createPolyMailerCanvas(256, 256);
  drawHandlingStamp(side.ctx, 24, 28, 'poly');
  const sideTex = new CanvasTexture(side.canvas);
  sideTex.colorSpace = SRGBColorSpace;
  const sideMat = new MeshStandardMaterial({ map: sideTex, roughness: 0.52, metalness: 0.04 });

  const front = createPolyMailerCanvas(256, 256);
  const frontTex = new CanvasTexture(front.canvas);
  frontTex.colorSpace = SRGBColorSpace;
  const frontMat = new MeshStandardMaterial({ map: frontTex, roughness: 0.52, metalness: 0.04 });

  const back = createPolyMailerCanvas(256, 256);
  const backTex = new CanvasTexture(back.canvas);
  backTex.colorSpace = SRGBColorSpace;
  const backMat = new MeshStandardMaterial({ map: backTex, roughness: 0.52, metalness: 0.04 });

  return {
    type: 'pouch',
    geometry: getPouchGeometry(),
    size: options.size,
    mass: options.mass,
    materials: [sideMat, sideMat, topMat, btmMat, frontMat, backMat],
  };
}

/**
 * Style 2: Kraft Corrugated Cardboard Box + Security Tape + Waybill
 */
function buildKraftBoxStyle(options) {
  if (typeof document === 'undefined') {
    const mat = new MeshStandardMaterial({ color: 0xcaa373, roughness: 0.88 });
    return { type: 'cardboard', size: options.size, mass: options.mass, materials: [mat, mat, mat, mat, mat, mat] };
  }

  // 1. Top face (with shipping label + flap seam + tape)
  const top = createCardboardCanvas(256, 256, options.baseTone);
  drawFlapSeam(top.ctx, 256, 256, true);
  drawAirWaybill(top.ctx, 32, 24, 192, 168, options.label);
  drawTape(top.ctx, 114, 0, 28, 256, options.tapeStyle);
  const topTex = new CanvasTexture(top.canvas);
  topTex.colorSpace = SRGBColorSpace;
  const topMat = new MeshStandardMaterial({ map: topTex, roughness: 0.78, metalness: 0.04 });

  // 2. Bottom face (flap seam + tape)
  const btm = createCardboardCanvas(256, 256, options.baseTone);
  drawFlapSeam(btm.ctx, 256, 256, true);
  drawTape(btm.ctx, 114, 0, 28, 256, options.tapeStyle);
  const btmTex = new CanvasTexture(btm.canvas);
  btmTex.colorSpace = SRGBColorSpace;
  const btmMat = new MeshStandardMaterial({ map: btmTex, roughness: 0.85, metalness: 0.02 });

  // 3. Side faces (with handling stamps)
  const side = createCardboardCanvas(256, 256, options.baseTone);
  drawHandlingStamp(side.ctx, 24, 30, options.stamps[0] || 'arrows');
  if (options.stamps[1]) drawHandlingStamp(side.ctx, 60, 30, options.stamps[1]);
  const sideTex = new CanvasTexture(side.canvas);
  sideTex.colorSpace = SRGBColorSpace;
  const sideMat = new MeshStandardMaterial({ map: sideTex, roughness: 0.88, metalness: 0.02 });

  // 4. Front face
  const front = createCardboardCanvas(256, 256, options.baseTone);
  drawHandlingStamp(front.ctx, 24, 24, 'arrows');
  const frontTex = new CanvasTexture(front.canvas);
  frontTex.colorSpace = SRGBColorSpace;
  const frontMat = new MeshStandardMaterial({ map: frontTex, roughness: 0.86, metalness: 0.02 });

  // 5. Back face
  const back = createCardboardCanvas(256, 256, options.baseTone);
  drawHandlingStamp(back.ctx, 24, 24, 'recycle');
  const backTex = new CanvasTexture(back.canvas);
  backTex.colorSpace = SRGBColorSpace;
  const backMat = new MeshStandardMaterial({ map: backTex, roughness: 0.88, metalness: 0.02 });

  return {
    type: 'cardboard',
    size: options.size,
    mass: options.mass,
    materials: [sideMat, sideMat, topMat, btmMat, frontMat, backMat],
  };
}

/**
 * Style 3: Padded Golden Kraft Bubble Mailer / Jiffy Bag + Waybill
 */
function buildPaddedMailerStyle(options) {
  if (typeof document === 'undefined') {
    const mat = new MeshStandardMaterial({ color: 0xd9a859, roughness: 0.85 });
    return { type: 'bubble', size: options.size, mass: options.mass, materials: [mat, mat, mat, mat, mat, mat] };
  }

  const top = createCardboardCanvas(256, 256, { light: '#dfaa5d', dark: '#c79246' });
  drawAirWaybill(top.ctx, 30, 24, 196, 168, options.label);
  const topTex = new CanvasTexture(top.canvas);
  topTex.colorSpace = SRGBColorSpace;
  const topMat = new MeshStandardMaterial({ map: topTex, roughness: 0.82, metalness: 0.02 });

  const btm = createCardboardCanvas(256, 256, { light: '#dfaa5d', dark: '#c79246' });
  drawFlapSeam(btm.ctx, 256, 256, false);
  const btmTex = new CanvasTexture(btm.canvas);
  btmTex.colorSpace = SRGBColorSpace;
  const btmMat = new MeshStandardMaterial({ map: btmTex, roughness: 0.85, metalness: 0.02 });

  const side = createCardboardCanvas(256, 256, { light: '#dfaa5d', dark: '#c79246' });
  drawHandlingStamp(side.ctx, 24, 28, 'poly');
  const sideTex = new CanvasTexture(side.canvas);
  sideTex.colorSpace = SRGBColorSpace;
  const sideMat = new MeshStandardMaterial({ map: sideTex, roughness: 0.84, metalness: 0.02 });

  return {
    type: 'bubble',
    geometry: getPaddedMailerGeometry(),
    size: options.size,
    mass: options.mass,
    materials: [sideMat, sideMat, topMat, btmMat, sideMat, sideMat],
  };
}

/**
 * Style 4: Premium White Glossy E-Commerce Express Box + Waybill
 */
function buildWhiteBoxStyle(options) {
  if (typeof document === 'undefined') {
    const mat = new MeshStandardMaterial({ color: 0xf5f5f5, roughness: 0.55 });
    return { type: 'cardboard', size: options.size, mass: options.mass, materials: [mat, mat, mat, mat, mat, mat] };
  }

  const top = createCardboardCanvas(256, 256, { light: '#fcfcfc', dark: '#ebebeb' });
  drawFlapSeam(top.ctx, 256, 256, true);
  drawAirWaybill(top.ctx, 32, 24, 192, 168, options.label);
  drawTape(top.ctx, 114, 0, 28, 256, 'clear');
  const topTex = new CanvasTexture(top.canvas);
  topTex.colorSpace = SRGBColorSpace;
  const topMat = new MeshStandardMaterial({ map: topTex, roughness: 0.48, metalness: 0.04 });

  const btm = createCardboardCanvas(256, 256, { light: '#fcfcfc', dark: '#ebebeb' });
  drawFlapSeam(btm.ctx, 256, 256, true);
  drawTape(btm.ctx, 114, 0, 28, 256, 'clear');
  const btmTex = new CanvasTexture(btm.canvas);
  btmTex.colorSpace = SRGBColorSpace;
  const btmMat = new MeshStandardMaterial({ map: btmTex, roughness: 0.55, metalness: 0.02 });

  const side = createCardboardCanvas(256, 256, { light: '#fcfcfc', dark: '#ebebeb' });
  drawHandlingStamp(side.ctx, 24, 30, 'arrows');
  const sideTex = new CanvasTexture(side.canvas);
  sideTex.colorSpace = SRGBColorSpace;
  const sideMat = new MeshStandardMaterial({ map: sideTex, roughness: 0.50, metalness: 0.02 });

  return {
    type: 'cardboard',
    size: options.size,
    mass: options.mass,
    materials: [sideMat, sideMat, topMat, btmMat, sideMat, sideMat],
  };
}

let cachedBoxStyles = null;

function getBoxStyles() {
  if (cachedBoxStyles) return cachedBoxStyles;

  cachedBoxStyles = [
    // Variant 0: Black Bubble-Wrapped E-Commerce Box + Air Waybill (Shopee/Lazada style)
    buildBlackBubbleWrapStyle({
      size: [0.098, 0.076, 0.082],
      mass: 0.26,
      label: {
        carrier: 'J&T EXPRESS',
        service: 'PARCEL DROP · NEXT DAY',
        bannerColor: '#d32f2f',
        tracking: 'MY-JNT-9824-7361',
        ref: 'ECOM-8841',
        postal: '50450-MY',
      },
    }),
    // Variant 1: Flexible Pillowed Poly Mailer Courier Pouch + Air Waybill (Flash/SPX style)
    buildPolyMailerStyle({
      size: [0.126, 0.038, 0.098],
      mass: 0.17,
      label: {
        carrier: 'FLASH EXPRESS',
        service: 'FLYER POUCH · STANDARD',
        bannerColor: '#e65100',
        tracking: 'MY-SPX-5045-8120',
        ref: 'BAG-2204',
        postal: '50450-MY',
      },
    }),
    // Variant 2: Kraft Corrugated Box + "FRAGILE" Security Tape + Waybill
    buildKraftBoxStyle({
      size: [0.088, 0.082, 0.080],
      mass: 0.30,
      baseTone: { light: '#be8c54', dark: '#ad7a42' },
      tapeStyle: 'security',
      label: {
        carrier: 'PRIORITY COURIER',
        service: 'NEXT DAY GUARANTEED',
        bannerColor: '#0a2540',
        tracking: 'PRI-420-5820-MY',
        ref: 'SEC-7741',
        postal: '94107-USA',
      },
      stamps: ['umbrella', 'arrows'],
    }),
    // Variant 3: Padded Golden Kraft Bubble Mailer / Jiffy Bag + Shopee Xpress Waybill
    buildPaddedMailerStyle({
      size: [0.122, 0.032, 0.092],
      mass: 0.15,
      label: {
        carrier: 'SHOPEE XPRESS',
        service: 'STANDARD DELIVERY',
        bannerColor: '#ee4d2d',
        tracking: 'SPX-MY-8921-3482',
        ref: 'ENV-1109',
        postal: '50450-MY',
      },
    }),
    // Variant 4: Premium White Glossy E-Commerce Express Box + Lazada Express (LEX)
    buildWhiteBoxStyle({
      size: [0.102, 0.072, 0.078],
      mass: 0.25,
      label: {
        carrier: 'LEX MY',
        service: 'PRIORITY EXPRESS DROP',
        bannerColor: '#0f146d',
        tracking: 'LEX-9902-4102-MY',
        ref: 'LUX-3912',
        postal: '50450-MY',
      },
    }),
    // Variant 5: Slim Book / Electronics Cardboard Mailer + Waybill
    buildKraftBoxStyle({
      size: [0.116, 0.052, 0.088],
      mass: 0.22,
      baseTone: { light: '#caa373', dark: '#ba905e' },
      tapeStyle: 'reinforced',
      label: {
        carrier: 'ECO LOGISTICS',
        service: 'CARBON NEUTRAL GROUND',
        bannerColor: '#1e5631',
        tracking: 'ECO-1092-4820-MY',
        ref: 'ECO-3382',
        postal: '10001-USA',
      },
      stamps: ['arrows', 'recycle'],
    }),
  ];

  return cachedBoxStyles;
}

// ─── Main Parcel Physics & Stacking System ───────────────────────────────────

export function createParcelPhysics(cabinet, groundHeight, reducedMotion) {
  const group = new Group();
  cabinet.add(group);
  const geometry = new BoxGeometry(1, 1, 1);
  const boxStyles = getBoxStyles();
  const cardboard = new Material({ friction: 0.52, restitution: 0.18 });
  const world = new World({ gravity: new Vec3(0, -9.81, 0), allowSleep: true });
  world.broadphase = new SAPBroadphase(world);
  world.solver.iterations = 12;
  world.defaultContactMaterial.friction = 0.16;
  world.defaultContactMaterial.restitution = 0.12;

  function addBox(x, y, z, width, height, depth) {
    const body = new Body({
      position: new Vec3(x, y, z),
      shape: new Box(new Vec3(width / 2, height / 2, depth / 2)),
    });
    world.addBody(body);
    return body;
  }

  // Approximate the lined bin surfaces and leave the rear hatch opening clear.
  addBox(0, -0.012, -0.146, 0.55, 0.06, 0.256);
  addBox(-0.294, 0.4, -0.146, 0.04, 0.8, 0.31);
  addBox(0.294, 0.4, -0.146, 0.04, 0.8, 0.31);
  addBox(0, 0.329, 0.012, 0.556, 0.658, 0.06);
  addBox(0, 0.587, -0.306, 0.55, 0.424, 0.04);
  addBox(-0.15, 0.198, -0.306, 0.252, 0.354, 0.04);
  addBox(0, 0.002, -0.287, 0.55, 0.046, 0.026);
  const doorBlocker = addBox(0.125, 0.2, -0.304, 0.3, 0.35, 0.036);

  let ramp;
  cabinet.traverse(node => {
    if (node.userData.name === 'Silver foam lining on sloped platform') ramp = node;
  });
  if (ramp) {
    const rotation = ramp.getWorldQuaternion(ramp.quaternion.clone());
    const position = ramp.getWorldPosition(new Vector3())
      .add(new Vector3(0, -0.014, 0).applyQuaternion(rotation));
    const surface = addBox(position.x, position.y, position.z, 0.254, 0.036, 0.41);
    surface.material = new Material({ friction: 0.02, restitution: 0.04 });
    surface.quaternion.set(rotation.x, rotation.y, rotation.z, rotation.w);
    surface.aabbNeedsUpdate = true;
  }

  const ground = new Body({ position: new Vec3(0, groundHeight, 0), shape: new Plane() });
  ground.quaternion.setFromEuler(-Math.PI / 2, 0, 0);
  world.addBody(ground);

  const parcels = [];
  let density = 1;
  let initialized = false;
  let rearOpen = false;
  let pendingCount = 0;
  let arrivalDelay = 0;
  let tiltRemaining = 0;
  let previousFrame;
  let accumulated = 0;

  function place(parcel, index) {
    const columns = 4 * density;
    const rows = 2 * density;
    const { body, mesh, style } = parcel;
    const boxH = style ? style.size[1] : defaultBoxSize[1];
    body.position.set(
      ((columns - 1) / 2 - index % columns) * 0.113 / density,
      0.018 + (Math.floor(index / (columns * rows)) + 0.5) * boxH / density,
      -0.255 + (Math.floor(index / columns) % rows + 0.5) * 0.118 / density,
    );
    body.quaternion.set(0, 0, 0, 1);
    body.sleep();
    body.aabbNeedsUpdate = true;
    mesh.position.copy(body.position);
    mesh.quaternion.copy(body.quaternion);
  }

  function addParcel(animate) {
    const style = boxStyles[parcels.length % boxStyles.length];
    const mesh = new Mesh(style.geometry || geometry, style.materials);
    mesh.scale.set(...style.size).divideScalar(density);
    group.add(mesh);
    const body = new Body({
      mass: style.mass,
      material: cardboard,
      shape: new Box(new Vec3(mesh.scale.x / 2, mesh.scale.y / 2, mesh.scale.z / 2)),
      linearDamping: 0.20,
      angularDamping: 0.38,
      sleepSpeedLimit: 0.04,
      sleepTimeLimit: 0.65,
    });
    body.addEventListener('collide', event => {
      const vel = Math.abs(event.contact?.getImpactVelocityAlongNormal() || 0);
      if (vel > 0.14) {
        playParcelImpact(style.type || 'cardboard', vel, Math.max(-0.8, Math.min(0.8, body.position.x * 2.5)));
      }
    });
    const parcel = { mesh, body, style, pending: animate };
    mesh.visible = !animate;
    if (animate) {
      pendingCount++;
    } else {
      place(parcel, parcels.length);
      world.addBody(body);
    }
    parcels.push(parcel);
  }

  function removeParcel() {
    const { mesh, body, pending } = parcels.pop();
    mesh.removeFromParent();
    if (pending) pendingCount--;
    else world.removeBody(body);
  }

  function setCount(count) {
    const previousCount = parcels.length;
    const nextDensity = Math.max(1, Math.ceil(Math.cbrt(count / 24)));
    if (nextDensity !== density) {
      while (parcels.length) removeParcel();
      density = nextDensity;
    }
    while (parcels.length > count) removeParcel();
    while (parcels.length < count) {
      addParcel(initialized && !reducedMotion && parcels.length >= previousCount);
    }
    initialized = true;
  }

  function setRearOpen(open) {
    if (open === rearOpen) return;
    rearOpen = open;
    doorBlocker.collisionFilterMask = open ? 0 : -1;
    if (!open) tiltRemaining = 0;
    if (!open && parcels.some(({ body, pending }) => !pending && body.position.z < rearEdge + 0.05)) {
      // Return the visual parcels when the hatch closes. The app owns the count.
      parcels.forEach((parcel, index) => {
        if (!parcel.pending && parcel.body.position.y < 0.375) place(parcel, index);
      });
    }
  }

  function jostle() {
    if (reducedMotion || !rearOpen || !parcels.length) return false;
    tiltRemaining = 0.85;
    for (const { body, pending } of parcels) {
      if (pending || body.position.z < rearEdge || body.position.y > 0.375) continue;
      body.wakeUp();
      body.velocity.x += (0.125 - body.position.x) * 3.5;
      body.velocity.y = Math.max(body.velocity.y, 0.65);
      body.velocity.z = Math.min(body.velocity.z, -0.92);
      body.angularVelocity.x += 2.4;
    }
    return true;
  }

  function hasMotion() {
    return group.visible && !reducedMotion && parcels.length > 0 &&
      (pendingCount > 0 || world.hasActiveBodies || tiltRemaining > 0);
  }

  function advance(now) {
    const elapsed = previousFrame === undefined ? 0 : (now - previousFrame) / 1000;
    previousFrame = now;
    if (!hasMotion()) return;
    accumulated += Math.min(elapsed, 0.05);
    while (accumulated >= stepSeconds) {
      arrivalDelay -= stepSeconds;
      if (pendingCount && arrivalDelay <= 0) {
        const index = parcels.findIndex(parcel => parcel.pending);
        const { mesh, body } = parcels[index];
        const lane = (index % 3) - 1;
        const roll = lane * 0.08 + ((index * 31) % 11 - 5) * 0.01;
        const pitch = -0.43 + ((index * 17) % 9 - 4) * 0.01;
        const yaw = ((index * 23) % 15 - 7) * 0.01;
        body.position.set(-0.12 + lane * 0.037, 0.89, 0.185);
        body.quaternion.setFromEuler(pitch, yaw, roll);
        body.velocity.set(lane * 0.03, 0, -0.45);
        body.angularVelocity.set((index % 2 === 0 ? 0.6 : -0.6), yaw * 1.2, roll * 1.5);
        world.addBody(body);
        parcels[index].pending = false;
        pendingCount--;
        mesh.visible = true;
        arrivalDelay = 0.45;
        playCardboardSlide(lane * 0.35);
      }
      if (tiltRemaining > 0) {
        for (const { body, pending } of parcels) {
          if (pending || body.position.y > 0.375 || body.position.z < rearEdge) continue;
          body.force.x += body.mass * (0.125 - body.position.x) * 16;
          body.force.z -= body.mass * 6.8;
        }
        tiltRemaining = Math.max(0, tiltRemaining - stepSeconds);
      }
      world.step(stepSeconds);
      accumulated -= stepSeconds;
    }
    for (const { mesh, body, pending } of parcels) {
      if (pending) continue;
      mesh.position.copy(body.position);
      mesh.quaternion.copy(body.quaternion);
    }
  }

  return {
    setCount, setRearOpen, jostle, advance, hasMotion,
    setVisible(visible) { group.visible = visible; },
  };
}
