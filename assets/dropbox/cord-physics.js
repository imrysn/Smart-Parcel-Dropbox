import { Box3, Vector3 } from './three-viewer-engine.js';

const ringSize = 11; // Ten sides and the duplicated seam in the GLB's tube.
const radius = 0.0035;
const step = 1 / 90;
const segmentStride = 4;
const axes = ['x', 'y', 'z'];

export function createCordPhysics(cabinet, floor) {
  let cable;
  let plug;
  cabinet.traverse(node => {
    if (node.userData.name === 'Flexible mains cable') cable = node;
    if (node.userData.name === 'Wall plug · two flat blades') plug = node;
  });
  if (!cable?.isMesh || !plug || cable.parent !== plug.parent) return null;
  const positions = cable.geometry.getAttribute('position');
  const normals = cable.geometry.getAttribute('normal');
  if (!positions || !normals || positions.count % ringSize !== 0) return null;

  const ringCount = positions.count / ringSize;
  const end = Math.ceil((ringCount - 1) / segmentStride);
  if (end < 2) return null;
  const points = [];
  const lengths = [0];
  const vertex = new Vector3();
  for (let i = 0; i <= end; i++) {
    const ring = Math.min(i * segmentStride, ringCount - 1);
    const point = new Vector3();
    for (let spoke = 0; spoke < ringSize - 1; spoke++) {
      point.add(vertex.fromBufferAttribute(positions, ring * ringSize + spoke));
    }
    point.divideScalar(ringSize - 1);
    if (i) lengths.push(lengths[i - 1] + point.distanceTo(points[i - 1]));
    points.push(point);
  }

  const previous = points.map(point => point.clone());
  const anchor = points[0].clone();
  const restDirection = points[end].clone().sub(points[end - 1]).normalize();
  const plugOrientation = plug.quaternion.clone();
  const plugOffset = plug.position.clone().sub(points[end]);
  const plugRotation = plug.quaternion.clone();
  const plugCorners = [];
  const plugMeshes = new Set();
  plug.traverse(node => {
    if (!node.isMesh) return;
    plugMeshes.add(node);
    if (!node.geometry.boundingBox) node.geometry.computeBoundingBox();
    const { min, max } = node.geometry.boundingBox;
    for (const x of [min.x, max.x]) {
      for (const y of [min.y, max.y]) {
        for (const z of [min.z, max.z]) {
          plugCorners.push(node.localToWorld(new Vector3(x, y, z)).sub(points[end]));
        }
      }
    }
  });
  const endDirection = new Vector3();

  const body = new Box3(new Vector3(-0.3, 0, -0.3), new Vector3(0.3, 1.2, 0.3));
  const obstacles = [body];
  cabinet.traverse(node => {
    if (/^(Front unbraked swivel caster|Rear swivel caster with brake) ·/.test(node.userData.name ?? '')) {
      obstacles.push(new Box3().setFromObject(node));
    }
  });
  const delta = new Vector3();
  const next = new Vector3();
  const target = new Vector3();
  let held = null;
  let pulled = false;
  let active = false;
  let quiet = 0;
  let releaseTime = 0;
  let lastFrame;
  let accumulated = 0;

  function plugFloorClearance() {
    endDirection.subVectors(points[end], points[end - 1]).normalize();
    plugRotation.setFromUnitVectors(restDirection, endDirection);
    let clearance = radius;
    for (const corner of plugCorners) {
      clearance = Math.max(clearance, -delta.copy(corner).applyQuaternion(plugRotation).y);
    }
    return clearance;
  }

  function wake() {
    quiet = 0;
    if (active) return;
    active = true;
    lastFrame = undefined;
    accumulated = 0;
  }

  function grab(index) {
    held = index;
    pulled = false;
    target.copy(points[index]);
    previous[index].copy(points[index]);
    return points[index].clone();
  }

  function pull(position) {
    if (held === null) return;
    target.copy(position);
    delta.subVectors(target, anchor).clampLength(0, lengths[held] * 0.995);
    target.copy(anchor).add(delta);
    target.y = Math.max(target.y, floor + (held === end ? plugFloorClearance() : radius));
    if (!pulled && target.distanceToSquared(points[held]) < 0.001 ** 2) return;
    pulled = true;
    wake();
  }

  function release() {
    held = null;
    if (pulled) {
      pulled = false;
      releaseTime = 0;
      wake();
    }
  }

  function pick(ray, hit, reach) {
    if (plugMeshes.has(hit?.object)) return end;
    const onCable = hit?.object === cable;
    const limit = onCable ? Infinity : reach;
    let bestDistance = limit ** 2;
    let best = null;
    for (let i = 1; i <= end; i++) {
      const a = points[i - 1];
      const b = points[i];
      const distance = ray.distanceSqToSegment(a, b, next, delta);
      const depth = next.distanceTo(ray.origin);
      if (distance >= bestDistance || depth > (hit?.distance ?? Infinity) + radius * 2) continue;
      bestDistance = distance;
      best = Math.max(1, delta.distanceToSquared(a) < delta.distanceToSquared(b) ? i - 1 : i);
    }
    return best;
  }

  function collide(point, from, clearance) {
    for (const obstacle of obstacles) {
      if (point.x <= obstacle.min.x - clearance || point.x >= obstacle.max.x + clearance ||
          point.y <= obstacle.min.y - clearance || point.y >= obstacle.max.y + clearance ||
          point.z <= obstacle.min.z - clearance || point.z >= obstacle.max.z + clearance) continue;
      let nearest = Infinity;
      let side;
      let coordinate;
      for (const axis of axes) {
        const low = obstacle.min[axis] - clearance;
        const high = obstacle.max[axis] + clearance;
        // Prefer the face crossed during this step to keep the cord outside the enclosure.
        const lowDistance = point[axis] - low - (from[axis] <= low ? 2 : 0);
        const highDistance = high - point[axis] - (from[axis] >= high ? 2 : 0);
        if (lowDistance < nearest) { nearest = lowDistance; side = axis; coordinate = low; }
        if (highDistance < nearest) { nearest = highDistance; side = axis; coordinate = high; }
      }
      point[side] = coordinate;
    }
  }

  function simulate() {
    let speed = 0;
    for (let i = 1; i <= end; i++) {
      const point = points[i];
      if (i === held) {
        next.subVectors(target, point).clampLength(0, 0.055).add(point);
      } else {
        next.subVectors(point, previous[i]).multiplyScalar(0.92).clampLength(0, 0.055).add(point);
        next.y -= 9.81 * step ** 2;
      }
      previous[i].copy(point);
      point.copy(next);
    }

    const plugFloor = floor + plugFloorClearance();
    for (let pass = 0; pass < 18; pass++) {
      for (let i = 1; i <= end; i++) {
        delta.subVectors(points[i], points[i - 1]);
        const length = delta.length();
        if (length < 1e-8) continue;
        const left = i === 1 || i - 1 === held ? 0 : 1;
        const right = i === held ? 0.12 : i === end ? 0.65 : 1;
        delta.multiplyScalar((length - (lengths[i] - lengths[i - 1])) / (length * (left + right)));
        points[i - 1].addScaledVector(delta, left);
        points[i].addScaledVector(delta, -right);
      }
      for (let i = 1; i <= end; i++) {
        const point = points[i];
        collide(point, previous[i], i === end ? 0.022 : radius);
        point.y = Math.max(point.y, i === end ? plugFloor : floor + radius);
      }
    }

    points[end].y = Math.max(points[end].y, floor + plugFloorClearance());
    for (let i = 1; i <= end; i++) {
      const point = points[i];
      speed = Math.max(speed, point.distanceToSquared(previous[i]));
      if (point.y <= (i === end ? plugFloor : floor + radius) + 0.002) previous[i].lerp(point, 0.24);
    }
    quiet = speed < 0.00045 ** 2 ? quiet + 1 : 0;
    if (held === null) releaseTime += step;
    if (quiet > 24 || (held === null && releaseTime > 5)) active = false;
  }

  const tangent = new Vector3();
  const normal = new Vector3();
  const binormal = new Vector3();
  const center = new Vector3();
  const radial = new Vector3();
  const worldUp = new Vector3(0, 1, 0);
  const worldRight = new Vector3(1, 0, 0);
  const circle = Array.from({ length: ringSize }, (_, i) => {
    const angle = 2 * Math.PI * i / (ringSize - 1);
    return [Math.cos(angle), Math.sin(angle)];
  });

  function updateMesh() {
    for (let ring = 0; ring < ringCount; ring++) {
      const index = Math.min(Math.floor(ring / segmentStride), end - 1);
      const portion = (ring - index * segmentStride) / Math.min(segmentStride, ringCount - 1 - index * segmentStride);
      center.copy(points[index]).lerp(points[index + 1], portion);
      tangent.subVectors(points[index + 1], points[index]).normalize();
      if (ring === 0) normal.crossVectors(tangent, Math.abs(tangent.y) < 0.9 ? worldUp : worldRight).normalize();
      binormal.crossVectors(tangent, normal).normalize();
      if (binormal.lengthSq() < 0.5) {
        binormal.crossVectors(tangent, Math.abs(tangent.y) < 0.9 ? worldUp : worldRight).normalize();
      }
      normal.crossVectors(binormal, tangent).normalize();
      for (const [side, [cos, sin]] of circle.entries()) {
        radial.copy(normal).multiplyScalar(-cos).addScaledVector(binormal, sin);
        vertex.copy(center).addScaledVector(radial, radius);
        const index = ring * ringSize + side;
        positions.setXYZ(index, vertex.x, vertex.y, vertex.z);
        normals.setXYZ(index, radial.x, radial.y, radial.z);
      }
    }
    positions.needsUpdate = true;
    normals.needsUpdate = true;
    cable.geometry.computeBoundingBox();
    cable.geometry.computeBoundingSphere();

    tangent.subVectors(points[end], points[end - 1]).normalize();
    plugRotation.setFromUnitVectors(restDirection, tangent);
    plug.quaternion.copy(plugRotation).multiply(plugOrientation);
    plug.position.copy(points[end]).add(delta.copy(plugOffset).applyQuaternion(plugRotation));
  }

  function advance(now) {
    if (!active) return false;
    accumulated += lastFrame === undefined ? step : Math.min((now - lastFrame) / 1000, 0.05);
    lastFrame = now;
    while (accumulated >= step && active) {
      simulate();
      accumulated -= step;
    }
    updateMesh();
    return active;
  }

  return { pick, grab, pull, release, advance };
}
