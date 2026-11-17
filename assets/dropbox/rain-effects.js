import {
  Box3, BufferAttribute, BufferGeometry, DynamicDrawUsage, LineBasicMaterial, LineSegments,
  Raycaster, Vector3,
} from './three-viewer-engine.js';

const splashLifetime = 0.28;
const sprayCount = 5;
const rippleSegments = 12;
const ripple = Array.from({ length: rippleSegments + 1 }, (_, i) => {
  const angle = i * Math.PI * 2 / rippleSegments;
  return [Math.cos(angle), Math.sin(angle)];
});

function createBatch(scene, name, capacity) {
  const geometry = new BufferGeometry();
  const positions = new BufferAttribute(new Float32Array(capacity * 6), 3);
  const colors = new BufferAttribute(new Float32Array(capacity * 8), 4);
  geometry.setAttribute('position', positions.setUsage(DynamicDrawUsage));
  geometry.setAttribute('color', colors.setUsage(DynamicDrawUsage));
  const mesh = new LineSegments(geometry, new LineBasicMaterial({
    vertexColors: true, transparent: true, depthWrite: false, toneMapped: false,
  }));
  mesh.name = name;
  mesh.frustumCulled = false;
  mesh.visible = false;
  scene.add(mesh);

  let vertices = 0;
  return {
    mesh,
    line(x, y, z, endX, endY, endZ, alpha, endAlpha) {
      positions.setXYZ(vertices, x, y, z);
      colors.setXYZW(vertices++, 0.66, 0.83, 1, alpha);
      positions.setXYZ(vertices, endX, endY, endZ);
      colors.setXYZW(vertices++, 0.66, 0.83, 1, endAlpha);
    },
    flush() {
      geometry.setDrawRange(0, vertices);
      if (vertices > 0) {
        positions.needsUpdate = true;
        colors.needsUpdate = true;
      }
      vertices = 0;
    },
  };
}

export function createRainEffects(scene, cabinet, footprint, floorY, surfaces, { mobile = false } = {}) {
  const rainCount = mobile ? 260 : 370;
  const stormCount = Math.round(rainCount * 1.55);
  const splashCount = mobile ? 42 : 64;
  const drops = Array.from({ length: stormCount }, () => ({
    position: new Vector3(), direction: new Vector3(), speed: 0, length: 0, alpha: 0,
  }));
  const splashes = Array.from({ length: splashCount }, () => ({
    position: new Vector3(), normal: new Vector3(), surface: null,
    age: splashLifetime, rotation: 0, strength: 0,
  }));
  const rain = createBatch(scene, 'Rain drops', stormCount);
  const impacts = createBatch(scene, 'Rain splashes', splashCount * (sprayCount + rippleSegments));
  const raycaster = new Raycaster();
  const ray = raycaster.ray;
  const contact = new Vector3();
  const center = footprint.getCenter(new Vector3());
  const spawnY = footprint.max.y + 0.85;
  const radius = 1.24;
  const collisionBounds = new Box3();
  const panelBounds = new Box3();
  const intersections = [];
  const inverse = cabinet.matrixWorld.clone();
  const splashCenter = new Vector3();
  const normal = new Vector3();
  const tangent = new Vector3();
  const bitangent = new Vector3();
  const splashStart = new Vector3();
  const splashEnd = new Vector3();
  const up = new Vector3(0, 1, 0);
  const forward = new Vector3(0, 0, 1);
  let count = 0;
  let moving = false;
  let nextSplash = 0;
  let impactHeight = floorY;

  for (const surface of surfaces) {
    if (!surface.geometry.boundingBox) surface.geometry.computeBoundingBox();
  }

  function updateCollisionBounds() {
    cabinet.updateWorldMatrix(true, true);
    collisionBounds.makeEmpty();
    for (const surface of surfaces) {
      panelBounds.copy(surface.geometry.boundingBox).applyMatrix4(surface.matrixWorld);
      collisionBounds.union(panelBounds);
    }
  }

  function spawn(drop, spread = false) {
    drop.position.set(
      center.x + (Math.random() * 2 - 1) * radius,
      spread ? impactHeight + Math.random() * (spawnY - impactHeight) : spawnY + Math.random() * 0.3,
      center.z + (Math.random() * 2 - 1) * radius,
    );
    if (spread && collisionBounds.containsPoint(drop.position)) {
      drop.position.y = collisionBounds.max.y + Math.random() * 0.2;
    }
    const wind = count === stormCount ? 1.65 : 1;
    drop.direction.set((0.06 + Math.random() * 0.08) * wind, -1, (Math.random() - 0.42) * 0.14).normalize();
    drop.speed = 3.5 + Math.random() * 3;
    drop.length = 0.05 + Math.random() * 0.115;
    drop.alpha = 0.43 + Math.random() * 0.49;
  }

  function splash(position, hit = null) {
    const impact = splashes[nextSplash];
    nextSplash = (nextSplash + 1) % splashes.length;
    impact.surface = hit?.object ?? null;
    impact.position.copy(position);
    if (impact.surface) {
      inverse.copy(impact.surface.matrixWorld).invert();
      impact.position.applyMatrix4(inverse);
      impact.normal.copy(hit.face.normal);
    }
    impact.age = 0;
    impact.rotation = Math.random() * Math.PI * 2;
    impact.strength = 0.65 + Math.random() * 0.55;
  }

  function moveDrop(drop, elapsed) {
    const { position, direction, speed } = drop;
    const travel = speed * elapsed;
    const surfaceDistance = Math.max(0, (impactHeight - position.y) / direction.y);
    const stopDistance = Math.min(travel, surfaceDistance);
    ray.set(position, direction);
    if (collisionBounds.containsPoint(position) ||
        (ray.intersectBox(collisionBounds, contact) && contact.distanceToSquared(position) <= stopDistance * stopDistance)) {
      // Use the bounds only to avoid raycasting drops that cannot reach a panel this frame.
      raycaster.far = stopDistance;
      intersections.length = 0;
      const hit = raycaster.intersectObjects(surfaces, false, intersections)[0];
      if (hit) {
        splash(hit.point, hit);
        spawn(drop);
        return;
      }
    }
    if (surfaceDistance <= travel) {
      ray.at(surfaceDistance, contact);
      contact.y = impactHeight;
      if (Math.random() < 0.18) splash(contact);
      spawn(drop);
    } else {
      position.addScaledVector(direction, travel);
    }
  }

  function splashLine(x, z, lift, endX, endZ, endLift, alpha, endAlpha) {
    splashStart.copy(splashCenter).addScaledVector(tangent, x).addScaledVector(bitangent, z).addScaledVector(normal, lift);
    splashEnd.copy(splashCenter).addScaledVector(tangent, endX).addScaledVector(bitangent, endZ).addScaledVector(normal, endLift);
    impacts.line(splashStart.x, splashStart.y, splashStart.z, splashEnd.x, splashEnd.y, splashEnd.z, alpha, endAlpha);
  }

  function drawSplash(impact) {
    splashCenter.copy(impact.position);
    if (impact.surface) {
      const matrix = impact.surface.matrixWorld;
      splashCenter.applyMatrix4(matrix);
      inverse.copy(matrix).invert().transpose();
      normal.copy(impact.normal).transformDirection(inverse);
      if (splashCenter.y < impactHeight) return;
    } else {
      splashCenter.y = impactHeight;
      normal.copy(up);
    }
    tangent.crossVectors(Math.abs(normal.y) > 0.99 ? forward : up, normal).normalize();
    bitangent.crossVectors(normal, tangent);
    const age = impact.age / splashLifetime;
    const size = impact.strength;
    const fade = 1 - age;
    const spread = (0.008 + age * 0.043) * size;
    // Near-vertical surfaces shed water immediately, so show spray without a standing ring.
    const opacity = fade * 0.56 * Math.max(0, (normal.y - 0.25) / 0.75);
    for (let i = 0; opacity > 0 && i < rippleSegments; i++) {
      const [cos, sin] = ripple[i];
      const [nextCos, nextSin] = ripple[i + 1];
      splashLine(
        cos * spread, sin * spread, 0.002,
        nextCos * spread, nextSin * spread, 0.002, opacity, opacity,
      );
    }
    if (age > 0.8) return;
    const height = (0.005 + age * (1 - age) * 0.165) * size;
    for (let i = 0; i < sprayCount; i++) {
      const angle = impact.rotation + i * Math.PI * 2 / sprayCount;
      const dx = Math.cos(angle) * spread;
      const dz = Math.sin(angle) * spread;
      const lift = height * (0.6 + i * 0.12);
      splashLine(dx, dz, 0.002 + lift,
        dx * 0.74, dz * 0.74, 0.002 + lift * 0.7, fade * 0.91, fade * 0.18);
    }
  }

  function draw(elapsed) {
    if (count > 0) updateCollisionBounds();
    for (let i = 0; i < count; i++) {
      const drop = drops[i];
      if (elapsed > 0) moveDrop(drop, elapsed);
      else if (drop.position.y < impactHeight) spawn(drop, true);
      const { position: { x, y, z }, direction, length, alpha } = drop;
      rain.line(x, y, z, x - direction.x * length, y - direction.y * length,
        z - direction.z * length, alpha, alpha * 0.06);
    }
    for (const impact of splashes) {
      if (impact.age >= splashLifetime) continue;
      impact.age += elapsed;
      if (impact.age < splashLifetime) drawSplash(impact);
    }
    rain.flush();
    impacts.flush();
  }

  return {
    setImpactHeight(height) {
      if (impactHeight === height) return;
      impactHeight = height;
      if (!moving && count > 0) draw(0);
    },
    setWeather(weather, motion) {
      const nextCount = weather === 'storm' ? stormCount : weather === 'rain' ? rainCount : 0;
      const nextMoving = Boolean(nextCount && motion);
      if (count === nextCount && moving === nextMoving) return;
      const previousCount = count;
      count = nextCount;
      moving = nextMoving;
      rain.mesh.visible = count > 0;
      impacts.mesh.visible = moving;
      if (count > previousCount) updateCollisionBounds();
      for (let i = previousCount; i < count; i++) spawn(drops[i], true);
      if (!moving) for (const impact of splashes) impact.age = splashLifetime;
      draw(0);
    },
    advance(elapsed) {
      if (!moving) return false;
      draw(elapsed);
      return true;
    },
  };
}
