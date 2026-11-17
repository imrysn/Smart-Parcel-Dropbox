import {
  BoxGeometry, CylinderGeometry, Group, Mesh, MeshStandardMaterial, Vector3,
} from './three-viewer-engine.js';
import { Body, Box, Plane, Vec3, World } from './cannon-es.min.js';

const dt = 1 / 90;
const debrisKinds = ['leaf', 'twig', 'bottle', 'wrapper'];
const buoyancyPoints = [-1, 1].flatMap(x => [-1, 1].flatMap(y => [-1, 1].map(z => new Vec3(x, y, z))));
const hingeOpening = Math.PI / 1.85;
const floatMask = 2;
const cabinetMask = 4;

const randomBetween = (min, max) => min + Math.random() * (max - min);
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

export function createFloodPhysics(scene, cabinet, footprint, floorY, doors, water, mobile) {
  const center = footprint.getCenter(new Vector3());
  center.y = (footprint.max.y + floorY) / 2;
  const size = footprint.getSize(new Vector3());
  size.y = footprint.max.y - floorY;
  const restPosition = cabinet.position.clone();
  const restRotation = cabinet.quaternion.clone();
  const localCenter = cabinet.worldToLocal(center.clone());
  const rotCenter = new Vector3();
  const anchors = Object.fromEntries(Object.entries(doors).map(([id, door]) => [
    id, { ...door, angle: 0, speed: 0, open: false, loose: false, latch: 0 },
  ]));
  let plug;
  cabinet.traverse(node => {
    if (node.userData.name === 'Wall plug · two flat blades') plug = node;
  });

  const props = new Group();
  props.name = 'Flood debris';
  scene.add(props);
  const box = new BoxGeometry(1, 1, 1);
  const round = new CylinderGeometry(0.5, 0.5, 1, 12);
  const paint = Object.fromEntries(Object.entries({
    leaf: 0x869941, twig: 0x59351f, bottle: 0x70bfd2, cap: 0xe4edf2,
    wrapper: 0xc53d24, stripe: 0xffcc60, slipper: 0xf2cd4d, strap: 0x3f2895,
    parcel: 0xbc884d, tape: 0xe3cba5,
  }).map(([key, color]) => [key, new MeshStandardMaterial({ color, roughness: 0.8 })]));

  function part(group, color, dimensions, position = [0, 0, 0], cylinder = false) {
    const mesh = new Mesh(cylinder ? round : box, paint[color]);
    mesh.scale.set(...dimensions);
    mesh.position.set(...position);
    group.add(mesh);
    return mesh;
  }

  function makeProp(kind) {
    const mesh = new Group();
    mesh.name = kind === 'parcel' ? 'Floating demo parcel' : `Flood ${kind}`;
    let dimensions;
    switch (kind) {
      case 'leaf':
        dimensions = [0.055, 0.012, 0.095];
        part(mesh, 'leaf', dimensions, undefined, true);
        part(mesh, 'twig', [0.003, 0.003, 0.081], [0, 0.006, 0]);
        break;
      case 'twig':
        dimensions = [0.022, 0.018, 0.17];
        part(mesh, 'twig', dimensions);
        part(mesh, 'twig', [0.012, 0.012, 0.073], [0.018, 0.004, 0.027]).rotation.y = 0.63;
        break;
      case 'bottle':
        dimensions = [0.073, 0.064, 0.135];
        part(mesh, 'bottle', [0.068, 0.108, 0.057], undefined, true).rotation.x = Math.PI / 2;
        part(mesh, 'cap', [0.030, 0.028, 0.030], [0, 0, 0.063], true).rotation.x = Math.PI / 2;
        break;
      case 'wrapper':
        dimensions = [0.076, 0.019, 0.132];
        part(mesh, 'wrapper', dimensions);
        part(mesh, 'stripe', [0.072, 0.004, 0.032], [0, 0.01, 0.017]);
        break;
      case 'slipper':
        dimensions = [0.08, 0.024, 0.17];
        part(mesh, 'slipper', dimensions, undefined, true);
        for (const sign of [-1, 1]) {
          part(mesh, 'strap', [0.014, 0.014, 0.057], [sign * 0.015, 0.018, 0.027]).rotation.y = sign * 0.49;
        }
        break;
      default:
        dimensions = [0.095, 0.075, 0.082];
        part(mesh, 'parcel', dimensions);
        part(mesh, 'tape', [0.028, 0.003, 0.081], [0, 0.039, 0]);
    }
    const scale = kind === 'slipper' ? 1 : randomBetween(0.82, 1.14);
    mesh.scale.setScalar(scale);
    return { mesh, dimensions: dimensions.map(dimension => dimension * scale) };
  }

  let world;
  let hull;
  let active = false;
  let motion = false;
  let elapsed = 0;
  let accumulator = 0;
  let spawnIn = 0;
  let breakaway = 0;
  let resistance = 0;
  let tipped = false;
  let slipperSpawned = false;
  let nextParcel = 0;
  const heldParcels = [];
  const floaters = [];
  const limit = mobile ? 29 : 42;
  const current = new Vec3();
  const point = new Vec3();
  const arm = new Vec3();
  const force = new Vec3();
  const velocity = new Vec3();
  const plugPosition = new Vector3();
  const openDoorEdge = new Vector3();
  const snagPosition = new Vector3();
  const up = new Vec3(0, 1, 0);
  const doorUp = new Vec3();
  const doorX = size.x * 0.39;
  const doorDepth = size.z * 0.5 + 0.077;

  function makeFloater(kind, visible, x, y, z) {
    const { mesh, dimensions } = visible;
    const half = dimensions.map(length => length / 2);
    const body = new Body({
      mass: kind === 'parcel' ? 0.26 : 0.10,
      position: new Vec3(x, y, z),
      shape: new Box(new Vec3(...half)),
      linearDamping: 0.24, angularDamping: 0.58,
      collisionFilterGroup: floatMask,
    });
    body.quaternion.setFromEuler(randomBetween(-0.18, 0.18), randomBetween(0, Math.PI * 2), randomBetween(-0.18, 0.18));
    body.velocity.set(current.x * 0.75, randomBetween(-0.04, 0.13), current.z * 0.75);
    body.angularVelocity.set(randomBetween(-0.9, 0.9), randomBetween(-1.3, 1.3), randomBetween(-0.7, 0.7));
    props.add(mesh);
    mesh.position.copy(body.position);
    world.addBody(body);
    floaters.push({ kind, mesh, body, halfHeight: half[1], snag: null, snagTime: 0, alreadySnagged: false });
  }

  function spawn() {
    if (floaters.length >= limit) return;
    const heading = water.flowDirection;
    const inSurge = water.pressure > 0.2;
    const offset = inSurge ? randomBetween(-0.68, 0.68) : randomBetween(-1.35, 1.35);
    const distance = inSurge ? randomBetween(0.9, 1.8) : randomBetween(1.25, 1.9);
    const x = center.x - distance * heading.x + offset * heading.y;
    const z = center.z - distance * heading.y - offset * heading.x;
    const kind = !slipperSpawned && elapsed > 5
      ? 'slipper' : debrisKinds[Math.floor(Math.random() * debrisKinds.length)];
    slipperSpawned ||= kind === 'slipper';
    makeFloater(kind, makeProp(kind), x, water.surfaceAt(x, z) + 0.025, z);
  }

  function initialize(count) {
    world = new World({ gravity: new Vec3(0, -9.81, 0) });
    world.defaultContactMaterial.friction = 0.28;
    world.defaultContactMaterial.restitution = 0.15;
    const ground = new Body({ shape: new Plane(), position: new Vec3(0, floorY, 0) });
    ground.quaternion.setFromEuler(-Math.PI / 2, 0, 0);
    world.addBody(ground);
    hull = new Body({
      mass: 39, type: Body.KINEMATIC,
      shape: new Box(new Vec3(size.x / 2, size.y / 2, size.z / 2)),
      position: new Vec3(center.x, center.y + 0.007, center.z),
      linearDamping: 0.53, angularDamping: 0.45, collisionFilterGroup: cabinetMask,
    });
    hull.addEventListener('collide', event => {
      if (!tipped && water.pressure > 0.3 && event.body.collisionFilterGroup === floatMask) {
        breakaway += Math.min(0.025, Math.abs(event.contact.getImpactVelocityAlongNormal()) * 0.024);
      }
    });
    world.addBody(hull);
    for (const [id, hinge] of Object.entries(anchors)) {
      hinge.open = doors[id].open;
      hinge.angle = hinge.hinge.rotation.y - hinge.closedAngle;
      hinge.speed = 0;
      hinge.loose = false;
      hinge.latch = randomBetween(0.63, 0.86);
    }
    for (let i = 0; i < Math.min(Math.max(count, 3), 9); i++) {
      const parcel = makeProp('parcel');
      const door = i % 3 === 0 ? 'pickup' : 'received';
      parcel.mesh.position.set(0.025 + (i % 3) * 0.085, 0.053 + Math.floor(i / 6) * 0.083,
        door === 'pickup' ? 0.18 : -0.21);
      cabinet.add(parcel.mesh);
      heldParcels.push({ ...parcel, door });
    }
    elapsed = accumulator = breakaway = nextParcel = 0;
    spawnIn = 0.35;
    resistance = randomBetween(0.16, 0.28);
    tipped = slipperSpawned = false;
  }

  function reset() {
    for (const { mesh } of heldParcels) mesh.removeFromParent();
    heldParcels.length = 0;
    floaters.length = 0;
    props.clear();
    world = hull = undefined;
    cabinet.position.copy(restPosition);
    cabinet.quaternion.copy(restRotation);
    cabinet.updateMatrixWorld(true);
    water.setCabinetPose(center.x, center.z, 1);
  }

  function moveCabinet() {
    const pressure = water.pressure;
    const heading = water.flowDirection;
    if (!tipped) {
      const slope = water.surfaceAt(center.x + 0.28 * heading.x, center.z + 0.28 * heading.y)
        - water.surfaceAt(center.x - 0.28 * heading.x, center.z - 0.28 * heading.y);
      const rock = -slope * 0.45 + pressure * 0.10;
      hull.quaternion.setFromEuler(heading.y * rock, 0, -heading.x * rock);
      breakaway += Math.max(0, pressure - 0.33) * dt;
      if (breakaway < resistance) return;
      // Flood pressure and debris impulses have overcome the support at the casters.
      tipped = true;
      hull.type = Body.DYNAMIC;
      hull.updateMassProperties();
      hull.aabbNeedsUpdate = true;
      hull.velocity.set(current.x * 0.28, 0.31, current.z * 0.28);
      const angularImpulse = 3.1 + pressure * 1.35;
      hull.angularVelocity.set(heading.y * angularImpulse, randomBetween(-0.34, 0.34), -heading.x * angularImpulse);
    }

    for (const corner of buoyancyPoints) {
      arm.set(corner.x * size.x * 0.37, corner.y * size.y * 0.39, corner.z * size.z * 0.37);
      hull.quaternion.vmult(arm, arm);
      hull.position.vadd(arm, point);
      const submerged = clamp((water.surfaceAt(point.x, point.z) - point.y + 0.10) / 0.20, 0, 1);
      hull.getVelocityAtWorldPoint(point, velocity);
      force.set(0, hull.mass * submerged * (2.22 * 9.81 - velocity.y * 5.5) / buoyancyPoints.length, 0);
      hull.applyForce(force, arm);
    }
    hull.force.x += hull.mass * ((current.x * 0.21 - hull.velocity.x) * 1.55 + (center.x - hull.position.x) * 0.70);
    hull.force.z += hull.mass * ((current.z * 0.21 - hull.velocity.z) * 1.55 + (center.z - hull.position.z) * 0.70);
  }

  function moveDoors() {
    hull.quaternion.vmult(up, doorUp);
    for (const door of Object.values(anchors)) {
      if (tipped && !door.loose && Math.abs(doorUp.y) < door.latch) {
        door.open = door.loose = true;
        door.speed += 1.4 + 2 * water.pressure;
      }
      const swing = door.loose ? Math.sin(elapsed * 2.4 + door.latch * 16) * 0.20 : 0;
      const target = door.open ? hingeOpening + swing : 0;
      door.speed += ((target - door.angle) * 17 - door.speed * 4.5) * dt;
      door.angle = clamp(door.angle + door.speed * dt, 0, hingeOpening + 0.18);
      door.hinge.rotation.y = door.closedAngle + door.angle;
    }
  }

  function releaseParcel() {
    if (elapsed < nextParcel || water.surfaceY < floorY + 0.16) return;
    const index = heldParcels.findIndex(parcel => anchors[parcel.door].angle > 0.75);
    if (index < 0) return;
    const [parcel] = heldParcels.splice(index, 1);
    const direction = parcel.door === 'pickup' ? 1 : -1;
    const position = cabinet.localToWorld(new Vector3(parcel.door === 'pickup' ? 0.015 : doorX * 0.63, 0.125, direction * doorDepth));
    makeFloater('parcel', parcel, position.x, position.y, position.z);
    const { body } = floaters.at(-1);
    hull.quaternion.vmult(new Vec3(0, 0.08, direction * 0.48), velocity);
    body.velocity.vadd(velocity, body.velocity);
    body.collisionFilterMask = ~cabinetMask;
    floaters.at(-1).clearOfCabinetAt = elapsed + 0.6;
    nextParcel = elapsed + randomBetween(0.28, 0.64);
  }

  function moveFloater(item) {
    const { kind, body, halfHeight } = item;
    const position = body.position;
    if (item.clearOfCabinetAt && elapsed >= item.clearOfCabinetAt) {
      body.collisionFilterMask = -1;
      item.clearOfCabinetAt = 0;
    }
    const surge = water.pressure;
    const lateral = Math.sin(elapsed * 1.48 + position.x * 3.1 - position.z * 2.6) * (0.10 + surge * 0.19);
    const heading = water.flowDirection;
    const surface = Math.max(floorY, water.surfaceAt(position.x, position.z));
    body.force.x += body.mass * (current.x + lateral * heading.y - body.velocity.x) * 2.7;
    body.force.z += body.mass * (current.z - lateral * heading.x - body.velocity.z) * 2.7;
    const immersion = clamp((surface - position.y + halfHeight) / (2 * halfHeight), 0, 1);
    body.force.y += body.mass * immersion * Math.max(0, 16.2 - body.velocity.y * 8);

    if (kind !== 'wrapper') return;
    if (!item.alreadySnagged && surge < 0.60) {
      plug?.getWorldPosition(plugPosition);
      if (plug && plugPosition.distanceToSquared(position) < 0.19 ** 2) {
        item.snag = { anchor: plug, offset: new Vector3() };
      }
      for (const door of Object.values(anchors)) {
        if (door.angle <= 0.72) continue;
        const edge = openDoorEdge.set(-0.15, 0.13, 0);
        door.hinge.localToWorld(edge);
        if (edge.distanceToSquared(position) >= 0.20 ** 2) continue;
        item.snag = { anchor: door.hinge, offset: new Vector3(-0.15, 0.13, 0) };
        break;
      }
      if (item.snag) {
        item.alreadySnagged = true;
        item.snagTime = randomBetween(0.85, 1.8);
      }
    }
    if (!item.snag) return;
    item.snagTime -= dt;
    if (surge > 0.72 || item.snagTime <= 0) {
      item.snag = null;
      return;
    }
    item.snag.anchor.localToWorld(snagPosition.copy(item.snag.offset));
    body.force.x += body.mass * ((snagPosition.x - position.x) * 20 - body.velocity.x * 6);
    body.force.z += body.mass * ((snagPosition.z - position.z) * 20 - body.velocity.z * 6);
  }

  function syncCabinet() {
    cabinet.quaternion.copy(hull.quaternion);
    rotCenter.copy(localCenter).applyQuaternion(cabinet.quaternion);
    cabinet.position.copy(hull.position).sub(rotCenter);
    cabinet.updateMatrixWorld(true);
    water.setCabinetPose(hull.position.x, hull.position.z, clamp((doorUp.y - 0.3) / 0.7, 0, 1));
  }

  function step() {
    elapsed += dt;
    const pressure = water.pressure;
    const heading = water.flowDirection;
    const speed = 0.29 + 0.08 * Math.sin(elapsed * 0.68) + pressure * 1.53;
    current.set(heading.x * speed, 0, heading.y * speed);
    spawnIn -= dt;
    if (spawnIn <= 0 && water.surfaceY > floorY + 0.055) {
      spawn();
      spawnIn = pressure > 0.2 ? randomBetween(0.08, 0.27) : randomBetween(0.44, 1.12);
    }
    moveCabinet();
    moveDoors();
    releaseParcel();
    for (const item of floaters) moveFloater(item);
    world.step(dt);
    for (let i = floaters.length - 1; i >= 0; i--) {
      const { body, mesh } = floaters[i];
      if ((body.position.x - center.x) ** 2 + (body.position.z - center.z) ** 2 > 3.25 ** 2) {
        world.removeBody(body);
        mesh.removeFromParent();
        floaters.splice(i, 1);
      }
    }
  }

  return {
    setActive(enabled, animate, count) {
      motion = animate;
      if (enabled === active) return;
      active = enabled;
      if (active) initialize(count);
      else reset();
    },
    advance(delta) {
      if (!active || !motion) return false;
      accumulator += delta;
      while (accumulator >= dt) {
        step();
        syncCabinet();
        accumulator -= dt;
      }
      for (const item of floaters) {
        item.mesh.position.copy(item.body.position);
        item.mesh.quaternion.copy(item.body.quaternion);
      }
      return true;
    },
    toggleDoor(id) {
      const door = anchors[id];
      door.open = !door.open;
      if (!motion) {
        door.angle = door.open ? hingeOpening : 0;
        door.hinge.rotation.y = door.closedAngle + door.angle;
      }
      return door.open;
    },
    get active() { return active; },
  };
}
