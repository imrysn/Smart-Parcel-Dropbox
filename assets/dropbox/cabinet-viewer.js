import {
  ACESFilmicToneMapping, Box3, DirectionalLight, GLTFLoader,
  HemisphereLight, MathUtils, OrbitControls,
  PerspectiveCamera, PointLight, Raycaster, Scene, Vector2, Vector3, WebGLRenderer,
} from './three-viewer-engine.js';
import { createParcelPhysics } from './parcel-physics.js';
import { createCordPhysics } from './cord-physics.js';
import { createRainEffects } from './rain-effects.js';
import { createFloodEffects } from './flood-effects.js';
import { createFloodPhysics } from './flood-physics.js';
import { createOutdoorEnvironment } from './outdoor-environment.js';
import { createCabinetDisplay } from './cabinet-display.js';
import {
  playButtonClick, playButtonRelease, playCardboardSlide, playDoorCloseImpact, playDoorCloseSwing, playDoorOpen, playScannerBeep, playSolenoid, setSoundEnabled,
} from './viewer-audio.js';

const canvas = document.querySelector('canvas');
const doorNames = {
  top: 'Upper door hinge pivot',
  pickup: 'Front pickup door hinge pivot',
  received: 'Rear left retrieval door hinge pivot',
};
const panelButtonModes = new Map([
  ['Blue button', 'drop-off'],
  ['Red button', 'pick-up'],
]);
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const mobileBridge = window.SpdDoorSelection;
const windowsBridge = window.chrome?.webview;
const exteriorPanels = new Set([
  'Left side panel', 'Right side panel', 'Upper rear panel', 'Inset top panel',
  'Parcel entry door', 'Controls panel', 'Front pickup door', 'Rear drop-off retrieval door',
  'Bottom front upper panel', 'Bottom front left panel', 'Bottom front right panel',
  'Rear fixed upper panel', 'Rear fixed right panel',
]);
const rainSurfaces = new Set([
  ...exteriorPanels, '25 mm corner post', 'Horizontal frame rail', 'Depth frame rail',
  'Inner floor panel', 'Entry door insulation lining', 'Pickup door silver foam lining',
  'Drop-off door silver foam lining', 'Silver foam lining on sloped platform',
]);

function send(message) {
  if (mobileBridge) mobileBridge.postMessage(message);
  else if (windowsBridge) windowsBridge.postMessage(message);
  else if (window.parent !== window) window.parent.postMessage(message, location.origin);
}

function receive(callback) {
  window.setCabinetState = callback;
  if (!mobileBridge && !windowsBridge) {
    window.addEventListener('message', event => {
      if (event.source === window.parent && event.origin === location.origin) callback(event.data);
    });
  }
}

function attachScannerLight(strip) {
  if (!strip?.material?.isMeshStandardMaterial) return () => {};
  const original = strip.material;
  const lit = original.clone();
  lit.color.setHex(0xfff2d6);
  lit.emissive.setHex(0xffe9bd);
  lit.emissiveIntensity = 2;
  const spill = new PointLight(0xffe9bd, 0.004, 0.095);
  spill.name = 'Scanner illumination';
  spill.position.z = 0.022;
  spill.visible = false;
  strip.add(spill);

  return active => {
    strip.material = active ? lit : original;
    spill.visible = active;
    if (active) playScannerBeep(0.12);
  };
}

try {
  await startViewer();
} catch (error) {
  console.error('Dropbox viewer could not start', error);
  send('viewer-error: ' + (error?.message || error));
}

async function startViewer() {
  const renderer = new WebGLRenderer({ canvas, alpha: true, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.toneMapping = ACESFilmicToneMapping;
  canvas.addEventListener('webglcontextlost', () => send('viewer-error'), { once: true });
  const scene = new Scene();
  const ambient = new HemisphereLight();
  scene.add(ambient);
  const key = new DirectionalLight();
  scene.add(key);
  const fill = new DirectionalLight(0xffffff, 1.2);
  fill.position.set(-3, 3, -4);
  scene.add(fill);

  const { scene: cabinet } = await new GLTFLoader().loadAsync('smart-parcel-dropbox.glb');
  scene.add(cabinet);
  const panelFinishes = new Map();
  const enclosure = new Box3();
  const rainTargets = [];
  const doors = {};
  const panelButtons = new Map();
  let lcdGlass;
  let scannerStrip;
  cabinet.traverse(node => {
    const name = node.userData.name;
    if (node.isMesh && rainSurfaces.has(name)) rainTargets.push(node);
    if (name === 'TFT LCD glass') lcdGlass = node;
    if (name === 'MH-ET illuminator strip') scannerStrip = node;
    const mode = panelButtonModes.get(name?.replace(/ mounting ring$/, ''));
    if (node.isMesh && mode) {
      node.userData.panelButton = mode;
      if (panelButtonModes.has(name)) {
        panelButtons.set(mode, { cap: node, restZ: node.position.z, timer: undefined });
      }
    }
    if (node.userData.name === '25 mm corner post' || node.userData.name === 'Inset top panel') {
      enclosure.expandByObject(node);
    }
    if (exteriorPanels.has(node.userData.name) && node.material?.isMeshStandardMaterial) {
      const original = node.material;
      if (!panelFinishes.has(original)) panelFinishes.set(original, original.clone());
      node.material = panelFinishes.get(original);
    }
    for (const [id, name] of Object.entries(doorNames)) {
      if (node.userData.name === name) {
        node.userData.door = id;
        doors[id] = { hinge: node, closedAngle: node.rotation.y, open: false, progress: 0, closingLatching: false };
      }
    }
  });
  if (Object.keys(doors).length !== 3) throw new Error('The cabinet is missing a door hinge');

  const bounds = new Box3().setFromObject(cabinet);
  const center = bounds.getCenter(new Vector3());
  const size = bounds.getSize(new Vector3());
  const framingPoints = [];
  if (mobileBridge) {
    cabinet.traverse(node => {
      if (!node.isMesh) return;
      if (!node.geometry.boundingBox) node.geometry.computeBoundingBox();
      const { min, max } = node.geometry.boundingBox;
      for (const x of [min.x, max.x]) {
        for (const y of [min.y, max.y]) {
          for (const z of [min.z, max.z]) {
            framingPoints.push(new Vector3(x, y, z).applyMatrix4(node.matrixWorld).sub(center));
          }
        }
      }
    });
  }
  const camera = new PerspectiveCamera(30, 1, 0.01, 25);
  const orbit = new OrbitControls(camera, canvas);
  orbit.target.copy(center);
  orbit.rotateSpeed = 0.6;
  orbit.enablePan = true;
  orbit.screenSpacePanning = true;
  orbit.zoomToCursor = true;
  orbit.mouseButtons.MIDDLE = orbit.mouseButtons.RIGHT;
  orbit.enableDamping = false;
  orbit.maxPolarAngle = Math.PI * 0.88;
  orbit.minPolarAngle = Math.PI * 0.13;
  orbit.minDistance = 0.25;
  orbit.maxDistance = 7;
  const homeDirection = new Vector3().setFromSphericalCoords(
    1, MathUtils.degToRad(77), MathUtils.degToRad(24),
  );
  let homeDistance;
  let frame = null;
  let previousFrame;
  let cordGrab;

  function requestRender() {
    if (frame === null && !document.hidden) frame = requestAnimationFrame(render);
  }

  function touchFit(tangent) {
    const right = new Vector3().crossVectors(camera.up, homeDirection).normalize();
    const up = new Vector3().crossVectors(homeDirection, right);
    const horizontal = tangent * camera.aspect * 0.87;
    const vertical = tangent * 0.71;
    // Fit the posed cabinet and its floor-level cord within the page controls.
    let distance = 0;
    for (const point of framingPoints) {
      distance = Math.max(distance, point.dot(homeDirection) + Math.max(
        Math.abs(point.dot(right)) / horizontal,
        Math.abs(point.dot(up)) / vertical,
      ));
    }
    return distance;
  }

  function updateHomeDistance() {
    const tangent = Math.tan(MathUtils.degToRad(camera.fov / 2));
    if (mobileBridge) {
      homeDistance = touchFit(tangent);
    } else {
      const fitHeight = Math.max(size.y / 0.73, Math.hypot(size.x, size.z) / (camera.aspect * 0.88));
      homeDistance = fitHeight / (2 * tangent) + size.z * 0.4;
    }
    orbit.maxDistance = Math.max(7, homeDistance * 1.5);
  }

  function resize() {
    const { clientWidth: width, clientHeight: height } = canvas;
    if (!width || !height) return;
    const previousFit = homeDistance;
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
    updateHomeDistance();
    if (previousFit === undefined) {
      camera.position.copy(center).addScaledVector(homeDirection, homeDistance);
    } else {
      camera.position.sub(orbit.target).multiplyScalar(homeDistance / previousFit).add(orbit.target);
    }
    orbit.update();
    requestRender();
  }
  const homeCameraPos = new Vector3();
  const homeTarget = new Vector3();
  function saveHomeCamera() {
    homeCameraPos.copy(camera.position);
    homeTarget.copy(orbit.target);
  }
  new ResizeObserver(resize).observe(canvas);
  resize();
  saveHomeCamera();

  if (windowsBridge) {
    let controlHeld = false;
    let shiftHeld = false;
    const setModifiers = (control, shift) => {
      controlHeld = control;
      shiftHeld = shift;
    };
    window.setCabinetWheelModifiers = setModifiers;
    const updateModifiers = event => setModifiers(event.ctrlKey, event.shiftKey);
    window.addEventListener('keydown', updateModifiers);
    window.addEventListener('keyup', updateModifiers);
    window.addEventListener('blur', () => setModifiers(false, false));

    const movement = new Vector3();
    const cameraUp = new Vector3();
    const forward = new Vector3();
    canvas.addEventListener('wheel', event => {
      event.preventDefault();
      event.stopImmediatePropagation();
      if (cordGrab) return;
      const rect = canvas.getBoundingClientRect();
      if (!rect.width || !rect.height) return;
      const units = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? rect.height : 1;
      let dx = event.deltaX * units;
      let dy = event.deltaY * units;
      const distance = orbit.getDistance();

      if (event.ctrlKey || controlHeld) {
        const nextDistance = MathUtils.clamp(distance * Math.pow(0.95, -dy / 100),
          orbit.minDistance, orbit.maxDistance);
        camera.getWorldDirection(forward);
        movement.set(2 * (event.clientX - rect.left) / rect.width - 1,
          1 - 2 * (event.clientY - rect.top) / rect.height, 0.5);
        // Dolly along the pointer ray so the detail under it stays in place.
        movement.unproject(camera).sub(camera.position);
        movement.multiplyScalar((distance - nextDistance) / movement.dot(forward));
        camera.position.add(movement);
        orbit.target.copy(camera.position).addScaledVector(forward, nextDistance);
      } else {
        if ((event.shiftKey || shiftHeld) && dx === 0) {
          dx = dy;
          dy = 0;
        }
        const metersPerPixel = 2 * distance *
          Math.tan(MathUtils.degToRad(camera.fov / 2)) / (rect.height * camera.zoom);
        movement.setFromMatrixColumn(camera.matrixWorld, 0).multiplyScalar(-dx * metersPerPixel);
        cameraUp.setFromMatrixColumn(camera.matrixWorld, 1);
        movement.addScaledVector(cameraUp, dy * metersPerPixel);
        camera.position.add(movement);
        orbit.target.add(movement);
      }
      orbit.update();
    }, { capture: true, passive: false });
  }

  const cord = createCordPhysics(cabinet, bounds.min.y);
  const parcels = createParcelPhysics(cabinet, bounds.min.y, reducedMotion);
  const footprint = enclosure.isEmpty() ? bounds : enclosure;
  const rain = createRainEffects(scene, cabinet, footprint, bounds.min.y, rainTargets, { mobile: Boolean(mobileBridge) });
  const flood = createFloodEffects(scene, footprint, bounds.min.y, { mobile: Boolean(mobileBridge) });
  const floodPhysics = createFloodPhysics(scene, cabinet, footprint, bounds.min.y, doors, flood, Boolean(mobileBridge));
  const outdoor = createOutdoorEnvironment(scene, camera, { ambient, key, fill }, footprint, bounds.min.y);
  const display = createCabinetDisplay(lcdGlass, requestRender, attachScannerLight(scannerStrip));
  let parcelCount;
  let displayState;
  let drag;
  const downPointers = new Set();

  function setEnvironment(environment) {
    if (!environment) return;
    const { daylight } = environment;
    const motion = !reducedMotion && environment.motion !== false;
    const weather = outdoor.setConditions(daylight, environment.weather, motion);
    if (!weather) return;
    const wet = weather === 'rain' || weather === 'storm';
    document.body.dataset.daylight = daylight;
    document.body.dataset.weather = weather;
    flood.setActive(environment.flood === true, motion, daylight);
    rain.setImpactHeight(flood.surfaceY);
    rain.setWeather(weather, motion);
    for (const [dry, exterior] of panelFinishes) {
      exterior.roughness = wet ? Math.min(dry.roughness, 0.26) : dry.roughness;
      exterior.color.copy(dry.color).multiplyScalar(wet ? 0.85 : 1);
    }
  }

  let hasDoorState = false;
  let backgroundTapEnabled = false;
  receive(state => {
    if (!state || typeof state !== 'object') return;
    const canCycleDaylight = state.backgroundTapEnabled === true;
    if (backgroundTapEnabled !== canCycleDaylight) {
      backgroundTapEnabled = canCycleDaylight;
      if (canCycleDaylight) {
        canvas.tabIndex = 0;
        canvas.setAttribute('aria-description', 'Tap the background or press Enter to change time of day.');
      } else {
        canvas.removeAttribute('tabindex');
        canvas.removeAttribute('aria-description');
      }
    }
    if (typeof state.soundEnabled === 'boolean') {
      setSoundEnabled(state.soundEnabled);
    }
    setEnvironment(state.environment);
    let changedDoorOpen;
    if (state.doors) {
      for (const [id, door] of Object.entries(doors)) {
        const open = state.doors[id] === true;
        if (hasDoorState && open !== door.open) {
          changedDoorOpen = open || changedDoorOpen === true;
          const pan = id === 'top' ? -0.2 : id === 'pickup' ? -0.15 : 0.25;
          if (open) {
            playDoorOpen(pan);
            door.closingLatching = false;
          } else {
            playDoorCloseSwing(pan);
            door.closingLatching = true;
          }
        }
        door.open = open;
      }
      hasDoorState = true;
    }
    displayState = state.display;
    display?.update(displayState, floodPhysics.active ? undefined : changedDoorOpen);
    if (Number.isSafeInteger(state.parcels) && state.parcels >= 0) {
      const visibleCount = canCycleDaylight ? Math.max(3, state.parcels) : state.parcels;
      if (visibleCount !== parcelCount) {
        parcels.setCount(visibleCount);
        parcelCount = visibleCount;
      }
    }
    if (state.environment) {
      const flooded = state.environment.flood === true;
      if (flooded && !floodPhysics.active) finishCordGrab();
      floodPhysics.setActive(flooded, !reducedMotion && state.environment.motion !== false, parcelCount ?? 0);
      parcels.setVisible(!flooded);
    }
    requestRender();
  });

  const ray = new Raycaster();
  const pointer = new Vector2();
  const grabPoint = new Vector3();
  function setPointerRay(event) {
    const rect = canvas.getBoundingClientRect();
    pointer.set(2 * (event.clientX - rect.left) / rect.width - 1,
      1 - 2 * (event.clientY - rect.top) / rect.height);
    ray.setFromCamera(pointer, camera);
  }

  function hitAt(event) {
    setPointerRay(event);
    return ray.intersectObject(cabinet, true)[0];
  }

  function actionAt(hit) {
    if (!hit && backgroundTapEnabled) return 'background-tap';
    let node = hit?.object;
    while (node && node !== cabinet) {
      if (node.userData.panelButton && display) return node.userData.panelButton;
      if (node.userData.door) return node.userData.door;
      node = node.parent;
    }
    return null;
  }

  function activate(action) {
    if (action === 'background-tap') {
      send(action);
      return;
    }
    const button = panelButtons.get(action);
    if (!button) {
      if (Object.prototype.hasOwnProperty.call(doors, action)) {
        const door = doors[action];
        const nextOpen = !door.open;
        const pan = action === 'top' ? -0.2 : action === 'pickup' ? -0.15 : 0.25;
        if (nextOpen) {
          playDoorOpen(pan);
          door.closingLatching = false;
        } else {
          playDoorCloseSwing(pan);
          door.closingLatching = true;
        }
        if (floodPhysics.active) {
          const open = floodPhysics.toggleDoor(action);
          display?.update(displayState, open);
          requestRender();
        } else {
          send(action);
        }
      }
      return;
    }
    const pan = action === 'drop-off' ? 0.08 : 0.14;
    playButtonClick(pan);
    window.clearTimeout(button.timer);
    button.cap.position.z = button.restZ - 0.003;
    button.timer = window.setTimeout(() => {
      button.cap.position.z = button.restZ;
      playButtonRelease(pan);
      requestRender();
    }, 130);
    display?.press(action);
    requestRender();
  }

  function cordAt(event, hit) {
    if (floodPhysics.active) return null;
    const pixels = event.pointerType === 'touch' ? 13 : 4;
    const depth = hit?.distance ?? orbit.getDistance();
    const reach = 2 * depth * Math.tan(MathUtils.degToRad(camera.fov / 2)) * pixels / canvas.clientHeight;
    return cord?.pick(ray.ray, hit, Math.min(0.05, reach)) ?? null;
  }

  function pointerOnGrabPlane() {
    const { origin, direction } = ray.ray;
    const facing = direction.dot(cordGrab.normal);
    if (Math.abs(facing) < 0.0001) return null;
    const distance = grabPoint.subVectors(cordGrab.origin, origin).dot(cordGrab.normal) / facing;
    return distance >= 0 ? ray.ray.at(distance, grabPoint) : null;
  }

  function finishCordGrab() {
    if (!cordGrab) return;
    cord.release();
    cordGrab = null;
    orbit.enableRotate = true;
    orbit.enableZoom = true;
    canvas.style.cursor = '';
    requestRender();
  }

  canvas.addEventListener('pointerdown', event => {
    downPointers.add(event.pointerId);
    drag = null;
    if (downPointers.size > 1) finishCordGrab();
    if (downPointers.size !== 1 || !event.isPrimary || event.button !== 0 ||
        event.ctrlKey || event.metaKey || event.shiftKey) return;
    const hit = hitAt(event);
    const index = cordAt(event, hit);
    if (index !== null) {
      const origin = cord.grab(index);
      cordGrab = { id: event.pointerId, origin, normal: camera.getWorldDirection(new Vector3()) };
      const point = pointerOnGrabPlane();
      cordGrab.offset = point ? origin.clone().sub(point) : new Vector3();
      // OrbitControls still tracks the pointer so adding a finger can start a pinch.
      orbit.enableRotate = false;
      orbit.enableZoom = false;
      canvas.style.cursor = 'grabbing';
      return;
    }
    drag = { id: event.pointerId, x: event.clientX, y: event.clientY,
      action: actionAt(hit), moved: false, jostled: false };
  }, { capture: true });
  canvas.addEventListener('pointermove', event => {
    if (cordGrab) {
      if (event.pointerId !== cordGrab.id) return;
      setPointerRay(event);
      const point = pointerOnGrabPlane();
      if (point) {
        cord.pull(point.add(cordGrab.offset));
        requestRender();
      }
      return;
    }
    if (!drag) {
      if (event.pointerType === 'mouse') {
        const hit = hitAt(event);
        canvas.style.cursor = cordAt(event, hit) !== null ? 'grab' : actionAt(hit) ? 'pointer' : '';
      }
      return;
    }
    if (drag.id !== event.pointerId) return;
    const distance = Math.hypot(event.clientX - drag.x, event.clientY - drag.y);
    if (distance > 8) drag.moved = true;
    if (distance > 48 && !drag.jostled && doors.received.open &&
        camera.position.z < orbit.target.z) {
      drag.jostled = parcels.jostle();
      if (drag.jostled) requestRender();
    }
  });
  canvas.addEventListener('pointerup', event => {
    downPointers.delete(event.pointerId);
    if (cordGrab?.id === event.pointerId) {
      finishCordGrab();
      return;
    }
    if (!drag || drag.id !== event.pointerId) return;
    if (drag.action && !drag.moved && Math.hypot(event.clientX - drag.x, event.clientY - drag.y) <= 8 &&
        actionAt(hitAt(event)) === drag.action) {
      activate(drag.action);
    }
    drag = null;
  });
  const cancelPointer = event => {
    downPointers.delete(event.pointerId);
    if (cordGrab?.id === event.pointerId) finishCordGrab();
    if (drag?.id === event.pointerId) drag = null;
  };
  canvas.addEventListener('pointercancel', cancelPointer);
  canvas.addEventListener('lostpointercapture', cancelPointer);
  canvas.addEventListener('keydown', event => {
    if (backgroundTapEnabled && !event.repeat && (event.key === 'Enter' || event.key === ' ')) {
      event.preventDefault();
      activate('background-tap');
    }
  });
  window.addEventListener('blur', finishCordGrab);

  function render(now) {
    const frameTime = previousFrame === undefined ? 16.7 : now - previousFrame;
    const elapsed = Math.min(frameTime, 33.4);
    const floodElapsed = Math.min(frameTime, 100) / 1000;
    previousFrame = now;

    // Free interactive OrbitControls: User maintains 100% camera control (orbit, pan, zoom) at all times
    orbit.update();
    let doorsMoving = false;
    if (!floodPhysics.active) {
      const doorSpeed = (elapsed / 1000) / 1.25; // 1.25s slow, realistic mechanical swing
      for (const [id, door] of Object.entries(doors)) {
        const pan = id === 'top' ? -0.2 : id === 'pickup' ? -0.15 : 0.25;
        const targetProgress = door.open ? 1.0 : 0.0;
        if (reducedMotion) {
          door.progress = targetProgress;
        } else if (door.progress !== targetProgress) {
          if (door.progress < targetProgress) {
            door.progress = Math.min(targetProgress, door.progress + doorSpeed);
          } else {
            door.progress = Math.max(targetProgress, door.progress - doorSpeed);
          }
          doorsMoving = true;

          // When door arrives at frame on close, trigger solid close impact (thud + latch snap)
          if (door.progress <= 0.001 && door.closingLatching) {
            door.closingLatching = false;
            playDoorCloseImpact(pan);
          }
        }
        const t = door.progress;
        const eased = t * t * (3 - 2 * t); // Smoothstep curve
        door.hinge.rotation.y = door.closedAngle + eased * (Math.PI / 1.85);
      }
    }
    const rearDoor = doors.received;
    parcels.setRearOpen(rearDoor.open && rearDoor.hinge.rotation.y - rearDoor.closedAngle > 1);
    parcels.advance(now);
    const cordMoving = cord?.advance(now);
    const floodMoving = flood.advance(floodElapsed);
    const debrisMoving = floodPhysics.advance(floodElapsed);
    const { x, z } = cabinet.quaternion;
    const tilt = 1 - Math.abs(1 - 2 * (x * x + z * z));
    const floodZoom = 1 - 0.30 * MathUtils.smoothstep(tilt, 0.12, 0.85);
    if (camera.zoom !== floodZoom) {
      // Make room for a sideways cabinet while keeping the user's orbit and pan.
      camera.zoom = floodZoom;
      camera.updateProjectionMatrix();
    }
    rain.setImpactHeight(flood.surfaceY);
    const rainMoving = rain.advance(elapsed / 1000);
    const skyMoving = outdoor.advance(elapsed / 1000);
    renderer.render(scene, camera);
    frame = null;
    if (doorsMoving || cordMoving || parcels.hasMotion() || rainMoving || skyMoving || floodMoving || debrisMoving || !orbit.enabled) requestRender();
  }

  document.body.classList.add('ready');
  orbit.addEventListener('change', requestRender);
  document.addEventListener('visibilitychange', requestRender);
  requestRender();
  send('viewer-ready');
}
