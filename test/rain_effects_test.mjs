import assert from 'node:assert/strict';
import test from 'node:test';
import {
  Box3, BoxGeometry, Group, Mesh, MeshStandardMaterial, Scene, Vector3,
} from '../assets/dropbox/three-viewer-engine.js';
import { createRainEffects } from '../assets/dropbox/rain-effects.js';

test('rain splashes track a tilted panel while water ripples stay level', () => {
  const originalRandom = Math.random;
  let seed = 73;
  Math.random = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed / 2 ** 32;
  };
  try {
    const scene = new Scene();
    const cabinet = new Group();
    const panel = new Mesh(new BoxGeometry(0.88, 0.03, 0.78), new MeshStandardMaterial());
    panel.position.y = 0.66;
    panel.rotation.z = Math.PI / 4;
    cabinet.add(panel);
    scene.add(cabinet);

    const bounds = new Box3().setFromObject(cabinet);
    const rain = createRainEffects(scene, cabinet, bounds, 0, [panel]);
    const waterHeight = 0.16;
    rain.setImpactHeight(waterHeight);
    rain.setWeather('storm', true);
    const geometry = scene.getObjectByName('Rain splashes').geometry;
    const positions = geometry.getAttribute('position');
    const normal = new Vector3(0, 1, 0).transformDirection(panel.matrixWorld);
    const origin = panel.localToWorld(new Vector3(0, 0.015, 0));
    const start = new Vector3();
    const end = new Vector3();
    function slopedRing() {
      for (let i = 0; i < geometry.drawRange.count; i += 2) {
        start.fromBufferAttribute(positions, i);
        end.fromBufferAttribute(positions, i + 1);
        if (Math.abs(start.y - end.y) < 0.0001) continue;
        if ([start, end].every(point => Math.abs(point.sub(origin).dot(normal) - 0.002) < 0.00002)) {
          return i;
        }
      }
      return null;
    }

    let ring;
    let waterRipple = false;
    for (let frame = 0; frame < 90; frame++) {
      rain.advance(1 / 60);
      for (let i = 0; i < geometry.drawRange.count; i += 2) {
        const y = positions.getY(i);
        const endY = positions.getY(i + 1);
        if (Math.abs(y - endY) < 0.00001) {
          assert.ok(Math.abs(y - bounds.max.y - 0.002) > 0.00002, 'no ring on the invisible bounding box');
          waterRipple ||= Math.abs(y - waterHeight - 0.002) < 0.00002;
        }
      }
      ring = slopedRing();
      if (waterRipple && ring !== null) break;
    }
    assert.ok(waterRipple);
    assert.notEqual(ring, null, 'a ring follows the panel slope');
    const y = positions.getY(ring);

    panel.position.y += 0.08;
    rain.advance(0);
    assert.ok(Math.abs(positions.getY(ring) - y - 0.08) < 0.00002, 'the ring moves with the panel');
  } finally {
    Math.random = originalRandom;
  }
});
