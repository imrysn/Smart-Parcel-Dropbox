import assert from 'node:assert/strict';
import test from 'node:test';
import { Box3, Group, Scene, Vector3 } from '../assets/dropbox/three-viewer-engine.js';
import { createFloodEffects } from '../assets/dropbox/flood-effects.js';
import { createFloodPhysics } from '../assets/dropbox/flood-physics.js';

const floor = -0.105;
const frameTime = 1 / 60;

function makeScene(mobile) {
  const scene = new Scene();
  const cabinet = new Group();
  const doors = {};
  scene.add(cabinet);
  for (const [id, position] of [
    ['top', [0.04, 0.99, 0.3]],
    ['pickup', [0.18, 0.2, 0.3]],
    ['received', [0.29, 0.2, -0.3]],
  ]) {
    const hinge = new Group();
    hinge.position.set(...position);
    cabinet.add(hinge);
    doors[id] = { hinge, closedAngle: 0, open: false };
  }
  const bounds = new Box3(new Vector3(-0.3, 0, -0.3), new Vector3(0.3, 1.2, 0.3));
  const water = createFloodEffects(scene, bounds, floor, { mobile });
  const physics = createFloodPhysics(scene, cabinet, bounds, floor, doors, water, mobile);
  return { water, physics, doors, cabinet, debris: scene.getObjectByName('Flood debris') };
}

function run(seed, openPickup, mobile) {
  const originalRandom = Math.random;
  let state = seed;
  Math.random = () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 2 ** 32;
  };
  try {
    const { water, physics, cabinet, doors, debris } = makeScene(mobile);
    water.setActive(true, true, 'day');
    physics.setActive(true, true, 0);
    if (openPickup) assert.equal(physics.toggleDoor('pickup'), true);
    const bearing = water.flowDirection.toArray();
    const upright = new Vector3();
    let firstEscape;
    let tippedAt;
    let peakCount = 0;
    for (let step = 1; step <= 32 * 60; step++) {
      water.advance(frameTime);
      physics.advance(frameTime);
      upright.set(0, 1, 0).applyQuaternion(cabinet.quaternion);
      if (Math.abs(upright.y) < 0.73) tippedAt ??= step * frameTime;
      if (debris.getObjectByName('Floating demo parcel')) firstEscape ??= step * frameTime;
      peakCount = Math.max(peakCount, debris.children.length);
    }
    assert.ok(tippedAt >= 20 && tippedAt <= 30, `Tip time: ${tippedAt}`);
    assert.ok(Math.abs(upright.y) < 0.24, 'cabinet floats on its side');
    const hullCenter = cabinet.localToWorld(new Vector3(0, (1.2 + floor) / 2, 0));
    assert.ok(Math.abs(hullCenter.y - water.surfaceAt(hullCenter.x, hullCenter.z)) < 0.12);
    assert.ok(doors.pickup.hinge.rotation.y > 1 && doors.received.hinge.rotation.y > 1);
    assert.ok(peakCount >= 18);
    if (openPickup) assert.ok(firstEscape < 3);
    else assert.ok(firstEscape >= tippedAt && firstEscape < 30);

    physics.setActive(false, true, 0);
    assert.equal(physics.active, false);
    assert.deepEqual(cabinet.position.toArray(), [0, 0, 0]);
    assert.deepEqual(cabinet.quaternion.toArray(), [0, 0, 0, 1]);
    assert.equal(cabinet.children.length, 3);
    assert.equal(debris.children.length, 0);
    return { bearing, tippedAt };
  } finally {
    Math.random = originalRandom;
  }
}

test('the flood tips and floats the cabinet across runs and releases parcels through open doors', () => {
  const closed = run(1, false, false);
  const open = run(10399, true, true);
  assert.notDeepEqual(closed.bearing, open.bearing);
  assert.notEqual(closed.tippedAt, open.tippedAt);
});

test('reduced motion holds the water and cabinet still while keeping local doors usable', () => {
  const { water, physics, doors, cabinet, debris } = makeScene(true);
  water.setActive(true, false, 'day');
  physics.setActive(true, false, 0);
  assert.ok(water.surfaceY > floor + 0.4);
  assert.equal(physics.toggleDoor('received'), true);
  assert.ok(doors.received.hinge.rotation.y > 1);
  assert.equal(water.advance(30), false);
  assert.equal(physics.advance(30), false);
  assert.deepEqual(cabinet.position.toArray(), [0, 0, 0]);
  assert.equal(debris.children.length, 0);
});
