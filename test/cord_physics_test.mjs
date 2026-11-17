import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { createCordPhysics } from '../assets/dropbox/cord-physics.js';
import { Box3, GLTFLoader, Raycaster, Vector3 } from '../assets/dropbox/three-viewer-engine.js';

test('the cabinet cord stays attached, follows a pull and settles on the ground', async () => {
  const file = await readFile(new URL('../assets/dropbox/smart-parcel-dropbox.glb', import.meta.url));
  const { scene } = await new GLTFLoader().parseAsync(
    file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength), '',
  );
  const floor = new Box3().setFromObject(scene).min.y;
  const cord = createCordPhysics(scene, floor);
  assert.ok(cord);

  const parts = new Map();
  scene.traverse(part => parts.set(part.userData.name, part));
  const plug = parts.get('Wall plug · two flat blades');
  const positions = parts.get('Flexible mains cable').geometry.getAttribute('position');
  function ringCenter(firstVertex) {
    const center = new Vector3();
    const vertex = new Vector3();
    for (let spoke = 0; spoke < 10; spoke++) {
      center.add(vertex.fromBufferAttribute(positions, firstVertex + spoke));
    }
    return center.multiplyScalar(0.1);
  }
  const anchor = ringCenter(0);
  const center = ringCenter(80 * 11);
  const ray = new Raycaster(center.clone().add(new Vector3(0, 0, -1)), new Vector3(0, 0, 1));
  const middle = cord.pick(ray.ray, undefined, 0.02);
  assert.ok(middle > 0);
  assert.ok(cord.grab(middle).distanceTo(center) < 0.065);

  const end = cord.pick(ray.ray, { object: plug.children[0] }, 0.02);
  assert.ok(end > middle);
  cord.grab(end);
  let time = 0;
  function advance(seconds) {
    let active;
    for (let i = 0; i < seconds * 90; i++) active = cord.advance(time += 1000 / 90);
    return active;
  }

  cord.pull(new Vector3(0.68, 0.65, -0.63));
  advance(0.6);
  assert.ok(plug.position.x > 0.6 && plug.position.y > 0.58);
  cord.pull(new Vector3(20, 8, -14));
  advance(1);
  assert.ok(ringCenter(positions.count - 11).distanceTo(anchor) < 1.58);
  assert.ok(ringCenter(0).distanceTo(anchor) < 0.00001);

  cord.release();
  assert.equal(advance(6), false);
  const bottom = new Box3().setFromObject(plug).min.y;
  assert.ok(Math.abs(bottom - floor) < 0.004);
  for (let i = 0; i < positions.count; i++) {
    const y = positions.getY(i);
    if (y > 0.005 && y < 1.195) {
      assert.ok(Math.abs(positions.getX(i)) >= 0.299 || Math.abs(positions.getZ(i)) >= 0.299);
    }
  }
});
