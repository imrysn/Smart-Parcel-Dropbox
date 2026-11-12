import { BoxGeometry, Group, Mesh, MeshStandardMaterial, Vector3 } from './three-viewer-engine.js';
import { Body, Box, Material, Plane, SAPBroadphase, Vec3, World } from './cannon-es.min.js';

const stepSeconds = 1 / 120;
const rearEdge = -0.30;
const parcelSize = [0.093, 0.075, 0.076];

export function createParcelPhysics(cabinet, groundHeight, reducedMotion) {
  const group = new Group();
  cabinet.add(group);
  const geometry = new BoxGeometry(1, 1, 1);
  const material = new MeshStandardMaterial({ color: 0x17181c, roughness: 0.92 });
  const cardboard = new Material({ friction: 0.52, restitution: 0.2 });
  const world = new World({ gravity: new Vec3(0, -9.81, 0), allowSleep: true });
  world.broadphase = new SAPBroadphase(world);
  world.solver.iterations = 12;
  world.defaultContactMaterial.friction = 0.14;
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
    surface.material = new Material({ friction: 0, restitution: 0.02 });
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
    const { body, mesh } = parcel;
    body.position.set(
      ((columns - 1) / 2 - index % columns) * 0.113 / density,
      0.018 + (Math.floor(index / (columns * rows)) + 0.5) * parcelSize[1] / density,
      -0.255 + (Math.floor(index / columns) % rows + 0.5) * 0.118 / density,
    );
    body.quaternion.set(0, 0, 0, 1);
    body.sleep();
    body.aabbNeedsUpdate = true;
    mesh.position.copy(body.position);
    mesh.quaternion.copy(body.quaternion);
  }

  function addParcel(animate) {
    const mesh = new Mesh(geometry, material);
    mesh.scale.set(...parcelSize).divideScalar(density);
    group.add(mesh);
    const body = new Body({
      mass: 0.25,
      material: cardboard,
      shape: new Box(new Vec3(mesh.scale.x / 2, mesh.scale.y / 2, mesh.scale.z / 2)),
      linearDamping: 0.18,
      angularDamping: 0.35,
      sleepSpeedLimit: 0.04,
      sleepTimeLimit: 0.65,
    });
    const parcel = { mesh, body, pending: animate };
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

  function advance(now) {
    const elapsed = previousFrame === undefined ? 0 : (now - previousFrame) / 1000;
    previousFrame = now;
    if (!parcels.length || reducedMotion || (!pendingCount && !world.hasActiveBodies && !tiltRemaining)) return;
    accumulated += Math.min(elapsed, 0.05);
    while (accumulated >= stepSeconds) {
      arrivalDelay -= stepSeconds;
      if (pendingCount && arrivalDelay <= 0) {
        const index = parcels.findIndex(parcel => parcel.pending);
        const { mesh, body } = parcels[index];
        const lane = (index % 3) - 1;
        body.position.set(-0.12 + lane * 0.037, 0.89, 0.185);
        body.quaternion.setFromEuler(-0.43, lane * 0.1, 0.035);
        body.velocity.set(0, 0, -0.45);
        world.addBody(body);
        parcels[index].pending = false;
        pendingCount--;
        mesh.visible = true;
        arrivalDelay = 0.45;
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

  return { setCount, setRearOpen, jostle, advance };
}
