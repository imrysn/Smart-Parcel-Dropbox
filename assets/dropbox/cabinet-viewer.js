import {
  ACESFilmicToneMapping, Box3, DirectionalLight, GLTFLoader,
  HemisphereLight, MathUtils, OrbitControls,
  PerspectiveCamera, Raycaster, Scene, Vector2, Vector3, WebGLRenderer,
} from './three-viewer-engine.js';
import { createParcelPhysics } from './parcel-physics.js';

const canvas = document.querySelector('canvas');
const doorNames = {
  top: 'Upper door hinge pivot',
  pickup: 'Front pickup door hinge pivot',
  received: 'Rear left retrieval door hinge pivot',
};
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const mobileBridge = window.SpdDoorSelection;
const windowsBridge = window.chrome?.webview;

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

try {
  await startViewer();
} catch (error) {
  console.error('Dropbox viewer could not start', error);
  send('viewer-error');
}

async function startViewer() {
  const renderer = new WebGLRenderer({ canvas, alpha: true, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.toneMapping = ACESFilmicToneMapping;
  const scene = new Scene();
  scene.add(new HemisphereLight(0xffffff, 0xb6a796, 2.6));
  const key = new DirectionalLight(0xfff4e7, 2.3);
  key.position.set(3, 5, 4);
  scene.add(key);
  const fill = new DirectionalLight(0xffffff, 1.2);
  fill.position.set(-3, 3, -4);
  scene.add(fill);

  const { scene: cabinet } = await new GLTFLoader().loadAsync('smart-parcel-dropbox.glb');
  scene.add(cabinet);
  const doors = {};
  cabinet.traverse(node => {
    for (const [id, name] of Object.entries(doorNames)) {
      if (node.userData.name === name) {
        node.userData.door = id;
        doors[id] = { hinge: node, closedAngle: node.rotation.y, open: false };
      }
    }
  });
  if (Object.keys(doors).length !== 3) throw new Error('The cabinet is missing a door hinge');

  const bounds = new Box3().setFromObject(cabinet);
  const center = bounds.getCenter(new Vector3());
  const size = bounds.getSize(new Vector3());
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
  let homeDistance;

  function showSide(rear = false) {
    orbit.target.copy(center);
    camera.position.copy(center).add(new Vector3().setFromSphericalCoords(
      homeDistance, MathUtils.degToRad(77), MathUtils.degToRad(rear ? 162 : 24),
    ));
    orbit.update();
  }

  function resize() {
    const { clientWidth: width, clientHeight: height } = canvas;
    if (!width || !height) return;
    const previousFit = homeDistance;
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
    const fitHeight = Math.max(size.y / 0.73, Math.hypot(size.x, size.z) / (camera.aspect * 0.88));
    homeDistance = fitHeight / (2 * Math.tan(MathUtils.degToRad(camera.fov / 2))) + size.z * 0.4;
    orbit.maxDistance = Math.max(7, homeDistance * 1.5);
    if (previousFit === undefined) {
      showSide();
    } else {
      camera.position.sub(orbit.target).multiplyScalar(homeDistance / previousFit).add(orbit.target);
      orbit.update();
    }
  }
  new ResizeObserver(resize).observe(canvas);
  resize();

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
      const rect = canvas.getBoundingClientRect();
      if (!rect.width || !rect.height) return;
      const units = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? rect.height : 1;
      let dx = event.deltaX * units;
      let dy = event.deltaY * units;
      const distance = orbit.getDistance();

      if (event.ctrlKey || controlHeld) {
        const nextDistance = MathUtils.clamp(distance * Math.pow(0.95, dy / 100),
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
          Math.tan(MathUtils.degToRad(camera.fov / 2)) / rect.height;
        movement.setFromMatrixColumn(camera.matrixWorld, 0).multiplyScalar(dx * metersPerPixel);
        cameraUp.setFromMatrixColumn(camera.matrixWorld, 1);
        movement.addScaledVector(cameraUp, -dy * metersPerPixel);
        camera.position.add(movement);
        orbit.target.add(movement);
      }
      orbit.update();
    }, { capture: true, passive: false });
  }

  const parcels = createParcelPhysics(cabinet, bounds.min.y, reducedMotion);
  let parcelCount;
  let drag;

  let view;
  receive(state => {
    if (!state || typeof state !== 'object') return;
    for (const [id, door] of Object.entries(doors)) door.open = state.doors?.[id] === true;
    if (Number.isSafeInteger(state.parcels) && state.parcels >= 0 && state.parcels !== parcelCount) {
      parcels.setCount(state.parcels);
      parcelCount = state.parcels;
    }
    if (state.view && state.view.id !== view) {
      view = state.view.id;
      if (homeDistance !== undefined) showSide(state.view.side === 'rear');
    }
  });

  const ray = new Raycaster();
  const pointer = new Vector2();
  function doorAt(event) {
    const rect = canvas.getBoundingClientRect();
    pointer.set(2 * (event.clientX - rect.left) / rect.width - 1,
      1 - 2 * (event.clientY - rect.top) / rect.height);
    ray.setFromCamera(pointer, camera);
    let node = ray.intersectObject(cabinet, true)[0]?.object;
    while (node && node !== cabinet) {
      if (node.userData.door) return node.userData.door;
      node = node.parent;
    }
    return null;
  }

  canvas.addEventListener('pointerdown', event => {
    drag = event.isPrimary && event.button === 0 &&
      !(event.ctrlKey || event.metaKey || event.shiftKey)
      ? { id: event.pointerId, x: event.clientX, y: event.clientY, moved: false, jostled: false }
      : null;
  });
  canvas.addEventListener('pointermove', event => {
    if (!drag) {
      if (event.pointerType === 'mouse') canvas.style.cursor = doorAt(event) ? 'pointer' : '';
      return;
    }
    if (drag.id !== event.pointerId) return;
    const distance = Math.hypot(event.clientX - drag.x, event.clientY - drag.y);
    if (distance > 8) drag.moved = true;
    if (distance > 48 && !drag.jostled && doors.received.open &&
        camera.position.z < orbit.target.z) {
      drag.jostled = parcels.jostle();
    }
  });
  canvas.addEventListener('pointerup', event => {
    if (!drag || drag.id !== event.pointerId) return;
    if (!drag.moved && Math.hypot(event.clientX - drag.x, event.clientY - drag.y) <= 8) {
      const door = doorAt(event);
      if (door) send(door);
    }
    drag = null;
  });
  canvas.addEventListener('pointercancel', () => { drag = null; });
  canvas.addEventListener('lostpointercapture', () => { drag = null; });

  function render(now) {
    orbit.update();
    for (const door of Object.values(doors)) {
      const target = door.closedAngle + (door.open ? Math.PI / 1.85 : 0);
      door.hinge.rotation.y = reducedMotion ? target : MathUtils.lerp(door.hinge.rotation.y, target, 0.17);
    }
    const rearDoor = doors.received;
    parcels.setRearOpen(rearDoor.open && rearDoor.hinge.rotation.y - rearDoor.closedAngle > 1);
    parcels.advance(now);
    renderer.render(scene, camera);
  }

  document.body.classList.add('ready');
  renderer.setAnimationLoop(render);
  send('viewer-ready');
}
