import { Color, MathUtils, Mesh, PlaneGeometry, ShaderMaterial, Vector2 } from './three-viewer-engine.js';

const daylightPalettes = {
  day: {
    zenith: 0x4d9bd1, horizon: 0xd9edde, hills: 0x7eac99, ground: 0x98b98c,
    cloud: 0xf1f8fc, orb: 0xfff4c7, azimuth: -2.86, elevation: 0.65, moon: 0,
    ambient: 0xe3f2ff, bounce: 0xafb88d, sun: 0xfff2d5, ambientLevel: 2.6, keyLevel: 2.3, fillLevel: 1.03,
    keyX: 3.5, keyY: 5.5,
  },
  dawn: {
    zenith: 0x657eb5, horizon: 0xffc4a2, hills: 0x819c99, ground: 0x8ba18b,
    cloud: 0xf0cbd6, orb: 0xffecc2, azimuth: -2.57, elevation: 0.23, moon: 0,
    ambient: 0xc6d5f7, bounce: 0xaa9686, sun: 0xffbc88, ambientLevel: 2.1, keyLevel: 1.95, fillLevel: 0.91,
    keyX: -3.9, keyY: 2.1,
  },
  dusk: {
    zenith: 0x4c578c, horizon: 0xffb676, hills: 0x9c777d, ground: 0x8d817d,
    cloud: 0xeab1b2, orb: 0xffe4a3, azimuth: -2.87, elevation: 0.19, moon: 0,
    ambient: 0xc3c6f2, bounce: 0xa28b7f, sun: 0xffac73, ambientLevel: 2.0, keyLevel: 1.85, fillLevel: 0.87,
    keyX: 4.0, keyY: 2.0,
  },
  night: {
    zenith: 0x102441, horizon: 0x5a7493, hills: 0x425e71, ground: 0x3b555e,
    cloud: 0x546c89, orb: 0xecf9ff, azimuth: -2.85, elevation: 0.63, moon: 1,
    ambient: 0xc1d8ff, bounce: 0x8392a0, sun: 0xc9e3ff, ambientLevel: 1.9, keyLevel: 1.18, fillLevel: 0.84,
    keyX: 3.5, keyY: 4.1,
  },
};

const weatherPalettes = {
  unknown: { cover: 0.30, haze: 0.12, wet: 0, shade: 0 },
  clear: { cover: 0.27, haze: 0.10, wet: 0, shade: 0 },
  clouds: { cover: 0.72, haze: 0.29, wet: 0, shade: 0.27 },
  fog: { cover: 0.65, haze: 0.89, wet: 0, shade: 0.18 },
  rain: { cover: 0.91, haze: 0.48, wet: 0.72, shade: 0.39 },
  storm: { cover: 1, haze: 0.52, wet: 1, shade: 0.60 },
};

const colorFields = ['zenith', 'horizon', 'hills', 'ground', 'cloud', 'orb', 'ambient', 'bounce', 'sun'];

const skyVertex = /* glsl */ `
  varying vec2 screenUv;

  void main() {
    screenUv = uv;
    gl_Position = vec4(position.xy, 0.9999, 1.0);
  }
`;

const skyFragment = /* glsl */ `
  varying vec2 screenUv;
  uniform mat4 cameraWorld, inverseProjection;
  uniform vec2 cabinetCenter, cabinetHalfSize, shadowDirection;
  uniform float floorY, time;
  uniform vec3 zenith, horizon, hills, ground, cloud, orb;
  uniform float azimuth, elevation, moon, cover, haze, wet, shade;

  float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
  }

  float noise2(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
      mix(hash(cell + vec2(0.0, 1.0)), hash(cell + 1.0), f.x), f.y);
  }

  float hillHeight(float angle, float phase) {
    return 0.038 * sin(angle * 6.0 + phase) + 0.021 * sin(angle * 11.0 + phase)
      + 0.011 * sin(angle * 17.0 - phase);
  }

  float roundedFootprint(vec2 point, vec2 halfSize) {
    vec2 edge = abs(point) - halfSize;
    return length(max(edge, 0.0)) + min(max(edge.x, edge.y), 0.0);
  }

  float crater(vec2 point, vec2 center, float radius) {
    float distance = length(point - center) / radius;
    float basin = 1.0 - smoothstep(0.42, 0.96, distance);
    float rim = smoothstep(0.61, 0.88, distance) * (1.0 - smoothstep(0.88, 1.13, distance));
    return 0.12 * rim - 0.18 * basin;
  }

  vec3 paintCelestialBody(vec3 sky, vec2 viewPlane, float horizonLine) {
    // Use sky heading for placement and equal view-plane units for both axes.
    vec2 heading = vec2(sin(azimuth), cos(azimuth));
    float facing = dot(normalize(-cameraWorld[2].xz), heading);
    if (facing <= 0.0) return sky;
    float centerX = dot(cameraWorld[0].xz, heading) / facing;
    float centerY = (2.0 * mix(horizonLine, 1.0, elevation) - 1.0) * inverseProjection[1][1];
    float radius = mix(0.0146, 0.0156, moon);
    vec2 surfacePoint = (viewPlane - vec2(centerX, centerY)) / radius;
    float distance = length(surfacePoint);

    float halo = exp(-distance * mix(0.29, 0.44, moon)) * mix(0.29, 0.16, moon)
      + exp(-distance * distance * 0.34) * mix(0.18, 0.07, moon);
    sky = mix(sky, orb, halo * (1.0 - cover * 0.72));

    float aa = clamp(fwidth(distance) * 0.65, 0.02, 0.12);
    if (distance >= 1.0 + aa) return sky;
    float silhouette = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, distance);
    float depth = sqrt(max(0.0, 1.0 - distance * distance));
    vec3 normal = vec3(surfacePoint, depth);

    // The sun's warmer limb and brighter center follow the sphere normal.
    float granulation = noise2(surfacePoint * 10.0 + 5.1);
    vec3 limb = orb * vec3(0.98, 0.59, 0.32);
    vec3 core = mix(orb, vec3(1.0, 0.99, 0.93), 0.67);
    vec3 solarSurface = mix(limb, core, pow(depth, 0.56)) * mix(0.94, 1.0, granulation);

    // Side lighting forms a crescent on the shaded lunar sphere.
    float incidence = dot(normal, normalize(vec3(-0.84, 0.19, -0.51)));
    float daylight = smoothstep(-0.035, 0.045, incidence);
    float terrain = 0.69 + 0.27 * noise2(surfacePoint * 4.0 + vec2(8.0, 2.0));
    terrain += crater(surfacePoint, vec2(-0.66, 0.37), 0.20)
      + crater(surfacePoint, vec2(-0.77, -0.15), 0.15)
      + crater(surfacePoint, vec2(-0.55, -0.42), 0.12);
    float moonlight = mix(0.052, 0.68 + 0.41 * sqrt(max(0.0, incidence)), daylight);
    vec3 lunarSurface = orb * terrain * moonlight;
    float lunarOpacity = mix(0.38, 1.0, daylight);
    float visibility = silhouette * (1.0 - smoothstep(0.38, 0.94, cover));
    return mix(sky, mix(solarSurface, lunarSurface, moon), visibility * mix(1.0, lunarOpacity, moon));
  }

  void main() {
    vec4 local = inverseProjection * vec4(screenUv * 2.0 - 1.0, 1.0, 1.0);
    vec3 ray = normalize((cameraWorld * vec4(local.xyz, 0.0)).xyz);
    float angle = atan(ray.x, ray.z);
    float horizonLine = 0.51 + clamp(cameraWorld[2].y, -0.40, 0.65) * 0.31;
    float skyHeight = clamp((screenUv.y - horizonLine) / (1.0 - horizonLine), 0.0, 1.0);
    vec3 sky = mix(horizon, zenith, pow(skyHeight, 0.66));
    sky *= 1.0 - shade * 0.39;

    vec2 starGrid = vec2(angle * 96.0, screenUv.y * 67.0);
    vec2 starCell = floor(starGrid);
    float starSeed = hash(starCell);
    vec2 starOffset = 0.18 + 0.64 * vec2(hash(starCell + 5.0), hash(starCell + 11.0));
    float star = 1.0 - smoothstep(0.06, 0.19, length(fract(starGrid) - starOffset));
    star *= step(0.93, starSeed) * smoothstep(0.13, 0.53, skyHeight);
    sky = mix(sky, vec3(0.78, 0.90, 1.0), star * moon * (1.0 - cover) * 0.9);
    sky = paintCelestialBody(sky, local.xy / -local.z, horizonLine);

    vec2 cloudPoint = vec2(ray.x * 12.0 + ray.z * 4.6 - time * 0.046, skyHeight * 5.2 + 1.9);
    float cloudPattern = 0.67 * noise2(cloudPoint) + 0.33 * noise2(cloudPoint * 2.45 + 9.4);
    float clouds = smoothstep(0.58 - cover * 0.27, 0.75 - cover * 0.23, cloudPattern);
    clouds *= smoothstep(0.06, 0.32, skyHeight);
    sky = mix(sky, cloud * (1.0 - shade * 0.35), clouds * (0.43 + cover * 0.42));

    float farRidge = horizonLine + 0.047 + hillHeight(angle, 0.7);
    float nearRidge = horizonLine - 0.036 + hillHeight(angle, 2.4) * 0.64;
    float farMask = 1.0 - smoothstep(farRidge, farRidge + 0.008, screenUv.y);
    float nearMask = 1.0 - smoothstep(nearRidge, nearRidge + 0.007, screenUv.y);
    vec3 distant = mix(hills, horizon, 0.57 + haze * 0.35) * (1.0 - shade * 0.27);
    sky = mix(sky, distant, farMask * (1.0 - haze * 0.53));
    sky = mix(sky, hills * (1.0 - shade * 0.36), nearMask * (1.0 - haze * 0.48));

    // Intersect the camera ray with the same floor plane as the wheels and rain impacts.
    float distanceToFloor = clamp((cameraPosition.y - floorY) / max(-ray.y, 0.002), 0.0, 30.0);
    vec2 floorPoint = cameraPosition.xz + ray.xz * distanceToFloor;
    vec2 fromCabinet = floorPoint - cabinetCenter;
    float textureVariation = noise2(floorPoint * 2.9) - 0.5;
    vec3 foreground = ground * (1.0 + textureVariation * 0.14) * (1.0 - shade * 0.38);
    float wetGlint = exp(-length(fromCabinet - vec2(0.27, 0.32)) * 0.92);
    foreground = mix(foreground, horizon, wet * wetGlint * 0.17);
    float contact = 1.0 - smoothstep(-0.05, 0.14, roundedFootprint(fromCabinet, cabinetHalfSize));
    float shift = clamp(dot(fromCabinet, shadowDirection) / dot(shadowDirection, shadowDirection), 0.0, 1.0);
    float castShadow = 1.0 - smoothstep(-0.04, 0.19, roundedFootprint(fromCabinet - shift * shadowDirection, cabinetHalfSize));
    foreground *= 1.0 - max(contact * 0.48, castShadow * (0.32 - shade * 0.25) * (1.0 - shift * 0.42));
    float distanceHaze = smoothstep(3.5, 17.0, distanceToFloor);
    foreground = mix(foreground, distant, distanceHaze * (0.44 + haze * 0.51));
    vec3 environment = mix(sky, foreground, 1.0 - smoothstep(nearRidge - 0.11, nearRidge - 0.02, screenUv.y));

    // Keep the surrounding Flutter controls legible above and below the scene.
    float opacity = smoothstep(0.015, 0.145, screenUv.y) * (1.0 - smoothstep(0.865, 0.997, screenUv.y));
    gl_FragColor = vec4(environment, opacity);
    #include <colorspace_fragment>
    #include <premultiplied_alpha_fragment>
  }
`;

function sceneStyle(daylight, weather) {
  const style = { ...daylightPalettes[daylight], ...weatherPalettes[weather] };
  for (const name of colorFields) style[name] = new Color(style[name]);
  style.sun.lerp(new Color(0xd8e6f6), style.shade);
  style.keyLevel *= 1 - style.shade * 0.64;
  return style;
}

export function createOutdoorEnvironment(scene, camera, { ambient, key, fill }, footprint, floorY) {
  const boundsCenter = footprint.getCenter(camera.position.clone());
  const halfSize = footprint.getSize(camera.position.clone()).multiplyScalar(0.5);
  let current = sceneStyle('day', 'unknown');
  const uniforms = {
    ...Object.fromEntries(Object.entries(current).map(([name, value]) => [name, { value }])),
    cameraWorld: { value: camera.matrixWorld },
    inverseProjection: { value: camera.projectionMatrixInverse },
    cabinetCenter: { value: new Vector2(boundsCenter.x, boundsCenter.z) },
    cabinetHalfSize: { value: new Vector2(halfSize.x, halfSize.z) },
    shadowDirection: { value: new Vector2() },
    floorY: { value: floorY },
    time: { value: 0 },
  };
  const background = new Mesh(new PlaneGeometry(2, 2), new ShaderMaterial({
    vertexShader: skyVertex, fragmentShader: skyFragment, uniforms,
    depthTest: false, depthWrite: false, toneMapped: false, premultipliedAlpha: true,
  }));
  background.name = 'Outdoor environment';
  background.frustumCulled = false;
  background.renderOrder = -1000;
  scene.add(background);

  let previous;
  let target;
  let condition;
  let progress = 1;
  let animate = false;

  function drawStyle() {
    for (const [name, value] of Object.entries(current)) uniforms[name].value = value;
    ambient.color.copy(current.ambient);
    ambient.groundColor.copy(current.bounce);
    ambient.intensity = current.ambientLevel;
    key.color.copy(current.sun);
    key.intensity = current.keyLevel;
    key.position.set(current.keyX, current.keyY, 4.2);
    fill.intensity = current.fillLevel;
    const length = 0.26 / current.keyY;
    uniforms.shadowDirection.value.set(-current.keyX * length, -4.2 * length);
  }

  drawStyle();

  return {
    setConditions(daylight, weather, motion) {
      if (!Object.prototype.hasOwnProperty.call(daylightPalettes, daylight)) return;
      if (!Object.prototype.hasOwnProperty.call(weatherPalettes, weather)) weather = 'unknown';
      const next = `${daylight}/${weather}`;
      animate = motion;
      if (condition === next && (motion || progress === 1)) return weather;
      target = sceneStyle(daylight, weather);
      if (condition === undefined || !motion) {
        current = target;
        progress = 1;
        drawStyle();
      } else {
        previous = Object.fromEntries(Object.entries(current).map(([name, value]) => [name, value.isColor ? value.clone() : value]));
        progress = 0;
      }
      condition = next;
      return weather;
    },
    advance(elapsed) {
      if (animate) uniforms.time.value += elapsed;
      if (progress === 1) return false;
      progress = Math.min(1, progress + elapsed / 1.1);
      const eased = progress * progress * (3 - 2 * progress);
      for (const [name, destination] of Object.entries(target)) {
        if (destination.isColor) current[name].lerpColors(previous[name], destination, eased);
        else current[name] = MathUtils.lerp(previous[name], destination, eased);
      }
      drawStyle();
      return progress < 1;
    },
  };
}
