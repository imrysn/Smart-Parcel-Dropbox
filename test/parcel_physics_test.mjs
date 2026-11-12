import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { createParcelPhysics } from '../assets/dropbox/parcel-physics.js';
import { Box3, GLTFLoader } from '../assets/dropbox/three-viewer-engine.js';

const glb = await readFile(new URL('../assets/dropbox/smart-parcel-dropbox.glb', import.meta.url));

async function setup(reducedMotion = false) {
  const data = glb.buffer.slice(glb.byteOffset, glb.byteOffset + glb.byteLength);
  const { scene } = await new GLTFLoader().parseAsync(data, '');
  const ground = new Box3().setFromObject(scene).min.y;
  const physics = createParcelPhysics(scene, ground, reducedMotion);
  let time = 0;
  return {
    physics,
    meshes: scene.children.at(-1).children,
    ground,
    advance(seconds) {
      for (let frame = 0; frame < seconds * 60; frame++) physics.advance(time += 1000 / 60);
    },
  };
}

test('deliveries slide down the chute and settle against the bin and other parcels', async () => {
  const { physics, meshes, advance } = await setup();
  physics.setCount(0);
  physics.setCount(10);
  advance(0.3);
  assert.ok(meshes[0].visible && meshes[0].position.y > 0.65);

  advance(8);
  assert.equal(meshes.length, 10);
  for (const parcel of meshes) {
    assert.ok(parcel.visible);
    assert.ok(parcel.position.y > 0.05 && parcel.position.y < 0.35);
    assert.ok(parcel.position.z > -0.3 && parcel.position.z < -0.035);
  }
  assert.ok(meshes.some(parcel => parcel.position.y > 0.115), 'At least one parcel settled on another');
});

test('dragging can spill a parcel through the open rear door and closing restores the count', async () => {
  const { physics, meshes, advance, ground } = await setup();
  physics.setCount(0);
  physics.setCount(1);
  advance(3);
  assert.equal(physics.jostle(), false);

  physics.setRearOpen(true);
  assert.equal(physics.jostle(), true);
  advance(2.5);
  assert.ok(meshes[0].position.z < -0.33);
  assert.ok(Math.abs(meshes[0].position.y - (ground + meshes[0].scale.y / 2)) < 0.015);
  assert.ok(Math.abs(meshes[0].quaternion.w) < 0.99);

  physics.setRearOpen(false);
  assert.equal(meshes.length, 1);
  assert.ok(meshes[0].position.z > -0.27 && meshes[0].position.y > 0.05);
  physics.setCount(0);
  assert.equal(meshes.length, 0);
});

test('reduced motion displays the current count without simulating a spill', async () => {
  const { physics, meshes, advance } = await setup(true);
  physics.setCount(0);
  physics.setCount(3);
  const positions = meshes.map(parcel => parcel.position.toArray());
  assert.equal(meshes.filter(parcel => parcel.visible).length, 3);
  physics.setRearOpen(true);
  assert.equal(physics.jostle(), false);
  advance(2);
  assert.deepEqual(meshes.map(parcel => parcel.position.toArray()), positions);
});
