import { DoubleSide, Mesh, PlaneGeometry, ShaderMaterial, Vector2, Vector3 } from './three-viewer-engine.js';

const waves = /* glsl */ `
  uniform vec2 flowDirection;
  uniform vec2 waterCenter, surgeFront;
  uniform vec3 wavePhase;
  uniform float surge;

  vec3 waterProfile(vec2 point, float time) {
    vec2 crossFlow = vec2(-flowDirection.y, flowDirection.x);
    vec2 p = vec2(dot(point, flowDirection), dot(point, crossFlow));
    vec3 phase = vec3(dot(p, vec2(10.2, 3.4)), dot(p, vec2(-4.8, 17.0)),
      dot(p, vec2(21.0, -13.3))) - time * vec3(3.6, 4.6, 5.2) + wavePhase;
    vec3 amplitude = vec3(0.013, 0.007, 0.003) * (1.0 + surge * 1.5);
    vec3 slope = cos(phase) * amplitude;
    vec2 gradient = dot(slope, vec3(10.2, -4.8, 21.0)) * flowDirection
      + dot(slope, vec3(3.4, 17.0, -13.3)) * crossFlow;
    float crestDistance = (dot(point - waterCenter, flowDirection) - surgeFront.x) / surgeFront.y;
    float crest = 0.076 * surge * exp(-crestDistance * crestDistance);
    gradient -= flowDirection * (2.0 * crestDistance * crest / surgeFront.y);
    return vec3(dot(sin(phase), amplitude) + crest, gradient);
  }
`;

const vertexShader = /* glsl */ `
  uniform float waterTime, rise;
  varying vec3 surface;
  ${waves}

  void main() {
    vec4 world = modelMatrix * vec4(position, 1.0);
    world.y += waterProfile(world.xz, waterTime).x * smoothstep(0.03, 0.24, rise);
    surface = world.xyz;
    gl_Position = projectionMatrix * viewMatrix * world;
  }
`;

const fragmentShader = /* glsl */ `
  uniform vec2 cabinetCenter, cabinetHalfSize;
  uniform float waterTime, rise, daylight, upright;
  varying vec3 surface;
  ${waves}

  float hashCell(vec2 cell) {
    vec2 h = fract(cell * vec2(0.1031, 0.11369));
    h += dot(h, h.yx + 19.19);
    return fract((h.x + h.y) * h.x);
  }

  float silt(vec2 point) {
    vec2 cell = floor(point);
    vec2 f = fract(point);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hashCell(cell), hashCell(cell + vec2(1, 0)), f.x),
      mix(hashCell(cell + vec2(0, 1)), hashCell(cell + 1.0), f.x), f.y);
  }

  void main() {
    vec2 point = surface.xz;
    vec3 profile = waterProfile(point, waterTime);
    vec3 normal = normalize(vec3(-profile.y, 1.0, -profile.z));
    vec3 view = normalize(cameraPosition - surface);
    float fresnel = pow(1.0 - clamp(abs(dot(normal, view)), 0.0, 1.0), 3.0);
    vec2 crossFlow = vec2(-flowDirection.y, flowDirection.x);
    vec2 drift = vec2(dot(point, flowDirection), dot(point, crossFlow));
    vec2 sedimentUV = drift * vec2(6.0, 17.0) - vec2(waterTime * 1.1, profile.x * 34.0);
    float current = 0.58 * silt(sedimentUV + wavePhase.xy) + 0.42 * silt(sedimentUV * 1.6 - wavePhase.yz);
    vec3 deep = vec3(0.116, 0.063, 0.027);
    vec3 shallow = vec3(0.30, 0.173, 0.068);
    vec3 reflection = vec3(0.37, 0.30, 0.24);
    vec3 water = mix(deep, shallow, current * 0.84);
    water = mix(water, reflection, 0.21 * fresnel);

    float crest = smoothstep(0.016, 0.041, profile.x) * smoothstep(0.49, 0.85, current);
    vec2 inset = abs(point - cabinetCenter) - cabinetHalfSize;
    float edge = length(max(inset, 0.0)) + min(max(inset.x, inset.y), 0.0);
    float foam = (1.0 - smoothstep(0.008, 0.066, abs(edge))) * (0.46 + current * 0.54) * upright;
    vec3 foamColor = vec3(0.66, 0.54, 0.35);
    water = mix(water, foamColor, max(crest * 0.36, foam * 0.64));

    // Fade out at the boundary where the water meets the distant scene.
    float range = 1.0 - smoothstep(2.9, 4.0, length(point - waterCenter));
    float alpha = (0.87 + fresnel * 0.12) * smoothstep(0.0, 0.12, rise) * range;
    gl_FragColor = vec4(water * daylight, alpha);
    #include <colorspace_fragment>
    #include <premultiplied_alpha_fragment>
  }
`;

export function createFloodEffects(scene, cabinet, floorY, { mobile = false } = {}) {
  const segments = mobile ? 48 : 64;
  const geometry = new PlaneGeometry(8, 8, segments, segments).rotateX(-Math.PI / 2);
  const center = new Vector2((cabinet.min.x + cabinet.max.x) / 2, (cabinet.min.z + cabinet.max.z) / 2);
  const uniforms = {
    waterCenter: { value: center },
    cabinetCenter: { value: center.clone() },
    cabinetHalfSize: { value: new Vector2((cabinet.max.x - cabinet.min.x) / 2, (cabinet.max.z - cabinet.min.z) / 2) },
    waterTime: { value: 0 },
    rise: { value: 0 },
    daylight: { value: 1 },
    flowDirection: { value: new Vector2(1, 0) },
    surgeFront: { value: new Vector2(0, 0.4) },
    wavePhase: { value: new Vector3() },
    surge: { value: 0 },
    upright: { value: 1 },
  };
  const water = new Mesh(geometry, new ShaderMaterial({
    vertexShader, fragmentShader, uniforms,
    side: DoubleSide, transparent: true, depthWrite: false,
    toneMapped: false, premultipliedAlpha: true, forceSinglePass: true,
  }));
  water.name = 'Flood surface';
  water.position.set(center.x, floorY, center.y);
  water.renderOrder = -1;
  water.visible = false;
  scene.add(water);

  const peak = Math.min(0.52, (cabinet.max.y - floorY) * 0.40);
  let depth = 0;
  let flooding = false;
  let motion = false;
  let surgeStart = 0;
  let surgeDuration = 0;
  let surgeSpeed = 0;

  function draw() {
    water.position.y = floorY + depth;
    uniforms.rise.value = depth / peak;
    water.visible = depth > 0;
    if (!water.visible) uniforms.waterTime.value = 0;
  }

  return {
    setActive(active, animate, daylight) {
      if (active && !flooding) {
        const bearing = Math.random() * Math.PI * 2;
        uniforms.flowDirection.value.set(Math.cos(bearing), Math.sin(bearing));
        uniforms.wavePhase.value.set(...Array.from({ length: 3 }, () => Math.random() * Math.PI * 2));
        uniforms.waterTime.value = 0;
        uniforms.surge.value = 0;
        surgeStart = 20 + Math.random() * 4;
        surgeDuration = 3 + Math.random() * 1.5;
        surgeSpeed = 0.72 + Math.random() * 0.30;
        uniforms.surgeFront.value.y = 0.34 + Math.random() * 0.22;
      }
      flooding = active;
      motion = animate;
      uniforms.daylight.value = daylight === 'night' ? 0.60 : daylight === 'day' ? 1 : 0.82;
      if (!motion) {
        depth = flooding ? peak : 0;
        draw();
      }
    },
    advance(elapsed) {
      if (!motion || (depth === 0 && !flooding)) return false;
      uniforms.waterTime.value += elapsed;
      const surgeProgress = (uniforms.waterTime.value - surgeStart) / surgeDuration;
      uniforms.surge.value = flooding && surgeProgress > 0 && surgeProgress < 1
        ? Math.sin(Math.PI * surgeProgress) ** 2 : 0;
      uniforms.surgeFront.value.x = (surgeProgress - 0.40) * surgeDuration * surgeSpeed;
      const target = flooding ? peak + uniforms.surge.value * 0.12 : 0;
      depth += Math.max(-elapsed * 0.56, Math.min(elapsed * 0.29, target - depth));
      draw();
      return water.visible;
    },
    get surfaceY() {
      return water.position.y;
    },
    get flowDirection() { return uniforms.flowDirection.value; },
    get pressure() { return uniforms.surge.value; },
    surfaceAt(x, z) {
      const axis = uniforms.flowDirection.value;
      const p = x * axis.x + z * axis.y;
      const q = -x * axis.y + z * axis.x;
      const time = uniforms.waterTime.value;
      const phase = uniforms.wavePhase.value;
      const front = uniforms.surgeFront.value;
      const surge = uniforms.surge.value;
      const crestDistance = (p - center.dot(axis) - front.x) / front.y;
      const crest = 0.076 * surge * Math.exp(-(crestDistance ** 2));
      const waveFade = Math.min(1, Math.max(0, (depth / peak - 0.03) / 0.21));
      const waves = (1 + surge * 1.5) * (
        0.013 * Math.sin(10.2 * p + 3.4 * q - 3.6 * time + phase.x) +
        0.007 * Math.sin(-4.8 * p + 17 * q - 4.6 * time + phase.y) +
        0.003 * Math.sin(21 * p - 13.3 * q - 5.2 * time + phase.z));
      return water.position.y + (waves + crest) * waveFade ** 2 * (3 - 2 * waveFade);
    },
    setCabinetPose(x, z, upright) {
      uniforms.cabinetCenter.value.set(x, z);
      uniforms.upright.value = upright;
    },
  };
}
