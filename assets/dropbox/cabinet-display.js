import {
  CanvasTexture, Mesh, MeshBasicMaterial, PlaneGeometry, SRGBColorSpace,
} from './three-viewer-engine.js';

const width = 320;
const height = 240;
const scanTimeout = 60_000;
const colors = {
  black: '#000000', card: '#080808', divider: '#181c18', white: '#ffffff',
  cyan: '#00ffff', red: '#ff0000', green: '#00ff00', gold: '#ffff00',
  grey: '#7b7d7b', muted: '#52616d',
};

function createPainter(ctx, canvas) {
  function rect(x, y, w, h, color) {
    ctx.fillStyle = color;
    ctx.fillRect(x, y, w, h);
  }

  function rounded(x, y, w, h, radius, fill, stroke) {
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.arcTo(x + w, y, x + w, y + h, radius);
    ctx.arcTo(x + w, y + h, x, y + h, radius);
    ctx.arcTo(x, y + h, x, y, radius);
    ctx.arcTo(x, y, x + w, y, radius);
    ctx.closePath();
    if (fill) {
      ctx.fillStyle = fill;
      ctx.fill();
    }
    if (stroke) {
      ctx.strokeStyle = stroke;
      ctx.lineWidth = 1;
      ctx.stroke();
    }
  }

  function circle(x, y, radius, color) {
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
  }

  function line(points, color, thickness) {
    ctx.beginPath();
    ctx.moveTo(...points[0]);
    for (const point of points.slice(1)) ctx.lineTo(...point);
    ctx.strokeStyle = color;
    ctx.lineWidth = thickness;
    ctx.stroke();
  }

  function text(label, x, y, color, bold = false, maxWidth = width - 16) {
    ctx.font = bold ? 'bold 23px Arial, sans-serif' : '17px Arial, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = color;
    ctx.fillText(label, x, y, maxWidth);
  }

  function lock(x, y, size, color, open = false) {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(size, size);
    ctx.beginPath();
    ctx.arc(open ? -6 : 0, -14, 14, Math.PI, 0);
    ctx.lineTo(open ? 8 : 14, open ? -5 : 4);
    ctx.moveTo(open ? -20 : -14, -14);
    ctx.lineTo(open ? -20 : -14, 4);
    ctx.lineWidth = 3;
    ctx.strokeStyle = color;
    ctx.stroke();
    rounded(-22, 1, 44, 34, 6, color);
    circle(0, 13, 4, colors.black);
    rect(-2, 14, 4, 9, colors.black);
    ctx.restore();
  }

  function statusBar(online, unlocked) {
    rect(0, 23, width, 1, colors.divider);
    for (let i = 0; i < 4; i++) {
      const height = 4 + i * 3;
      rect(130 + i * 4, 20 - height, 2, height, online ? colors.green : colors.muted);
    }
    const cloud = online ? colors.green : colors.red;
    circle(156, 13, 3, cloud);
    circle(160, 11, 4, cloud);
    circle(164, 13, 3, cloud);
    rect(154, 13, 13, 3, cloud);
    lock(184, 12, 0.21, unlocked ? colors.gold : colors.muted, unlocked);
  }

  function home() {
    rounded(20, 36, 134, 188, 16, colors.card, colors.cyan);
    rounded(166, 36, 134, 188, 16, colors.card, colors.red);
    rounded(65, 70, 44, 30, 4, '#101010', colors.cyan);
    rect(65, 85, 44, 1, colors.cyan);
    rect(83, 81, 8, 8, colors.cyan);
    line([[81, 108], [87, 114], [93, 108]], colors.cyan, 2);
    lock(233, 85, 0.72, colors.red);
    text('DROP-OFF', 87, 142, colors.cyan, true);
    text('PICK-UP', 233, 142, colors.red, true);
    text('Touch / BTN 1', 87, 172, colors.white);
    text('Touch / BTN 2', 233, 172, colors.white);
    circle(87, 202, 5, colors.cyan);
    circle(233, 202, 5, colors.red);
  }

  function delivered() {
    rounded(45, 54, 230, 108, 16, colors.card, colors.green);
    circle(160, 84, 18, colors.green);
    line([[151, 83], [158, 90], [169, 78]], colors.white, 3);
    text('Parcel Delivered', 160, 122, colors.green, true);
    text('Detected by Ultrasonic Sensor', 160, 142, colors.grey, false, 208);
  }

  function scanning(mode) {
    const dropOff = mode === 'drop-off';
    const accent = dropOff ? colors.cyan : colors.red;
    text(dropOff ? 'DROP-OFF' : 'PICK-UP', 160, 45, accent, true);
    text("Please scan the Parcel's QR below.", 160, 70, colors.white);

    // This is the scanner prompt's pictogram, with no encoded content.
    rounded(134, 88, 52, 52, 4, colors.white);
    for (const [x, y] of [[138, 92], [170, 92], [138, 124]]) {
      rect(x, y, 12, 12, colors.black);
      rect(x + 3, y + 3, 6, 6, colors.white);
      rect(x + 5, y + 5, 2, 2, colors.black);
    }
    for (const [x, y, w, h] of [[155, 106, 11, 4], [158, 114, 4, 14], [171, 115, 8, 5], [174, 127, 7, 7], [152, 131, 8, 4]]) {
      rect(x, y, w, h, colors.black);
    }
    line([[146, 156], [160, 168], [174, 156]], accent, 3);
    text('Press', 136, 218, colors.grey);
    circle(158, 218, 4, colors.red);
    text('to exit.', 187, 218, colors.grey);
  }

  return (page, online, unlocked, scanMode) => {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    rect(0, 0, canvas.width, canvas.height, colors.black);
    ctx.translate((canvas.width - width) / 2, (canvas.height - height) / 2);
    statusBar(online, unlocked);
    if (page === 'delivered') delivered();
    else if (page === 'scanning') scanning(scanMode);
    else if (page === 'home') home();
    else {
      const open = page === 'unlocked';
      lock(160, 91, 1, open ? colors.gold : colors.green, open);
      text(open ? 'UNLOCKED' : 'LOCKED', 160, 155, colors.white, true);
    }
  };
}

export function createCabinetDisplay(glass, requestRender, setScannerLit) {
  if (!glass?.isMesh) return;
  glass.geometry.computeBoundingBox();
  const { min, max } = glass.geometry.boundingBox;
  const faceWidth = max.x - min.x;
  const faceHeight = max.y - min.y;
  const aspect = faceWidth / faceHeight;
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(width, Math.round(height * aspect));
  canvas.height = Math.max(height, Math.round(width / aspect));
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const texture = new CanvasTexture(canvas);
  texture.colorSpace = SRGBColorSpace;
  const face = new Mesh(new PlaneGeometry(faceWidth, faceHeight), new MeshBasicMaterial({
    map: texture, toneMapped: false,
  }));
  face.name = 'TFT LCD display';
  face.position.set((min.x + max.x) / 2, (min.y + max.y) / 2, max.z + 0.00015);
  glass.add(face);

  const paint = createPainter(ctx, canvas);
  let online = false;
  let unlocked = null;
  let page = 'home';
  let scanMode;
  let previousFrame;
  let lastDelivery;
  let timeout;

  function draw() {
    const frame = `${page}/${online}/${unlocked}/${scanMode}`;
    if (frame === previousFrame) return;
    previousFrame = frame;
    paint(page, online, unlocked, scanMode);
    texture.needsUpdate = true;
    requestRender();
  }

  function show(nextPage, duration = 0) {
    window.clearTimeout(timeout);
    if ((page === 'scanning') !== (nextPage === 'scanning')) {
      setScannerLit(nextPage === 'scanning');
    }
    page = nextPage;
    if (page !== 'scanning') scanMode = undefined;
    if (duration > 0) timeout = window.setTimeout(() => show('home'), duration);
    draw();
  }

  draw();

  return {
    press(mode) {
      if (page === 'scanning' && mode === 'pick-up') show('home');
      else if (page === 'home') {
        scanMode = mode;
        show('scanning', scanTimeout);
      }
    },
    update(state, changedDoorOpen) {
      if (!state) return;
      const nextOnline = state.online === true;
      const nextUnlocked = nextOnline && typeof state.unlocked === 'boolean' ? state.unlocked : null;
      const connectionChanged = online !== nextOnline;
      const lockChanged = unlocked !== null && nextUnlocked !== null && unlocked !== nextUnlocked;
      online = nextOnline;
      unlocked = nextUnlocked;
      const deliveredAt = state.deliveredAt;
      const newDelivery = Number.isSafeInteger(deliveredAt) && deliveredAt !== lastDelivery;
      if (newDelivery) lastDelivery = deliveredAt;

      const lockNotice = unlocked ? 'unlocked' : 'locked';
      if (online && newDelivery && Math.abs(Date.now() - deliveredAt) < 2500) {
        show('delivered', 2500);
      } else if (changedDoorOpen !== undefined && !connectionChanged) {
        show(changedDoorOpen ? 'unlocked' : 'locked', 1800);
      } else if (connectionChanged && page !== 'scanning') {
        show('home');
      } else if (lockChanged && page !== 'delivered' && page !== lockNotice) {
        show(lockNotice, 1800);
      } else {
        draw();
      }
    },
  };
}
