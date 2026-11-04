#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float phase;
    float fullGlobe;
    float cloudAmount;
    float cloudPhase;
    float skyBrightness;
    float diagnosticMode;
    float screenWidth;
    float screenHeight;
    float surfaceSoftness;
    float cityGlow;
    float cloudTime;
    float cloudType;
    float planetVisualVersion;
    float sunTipBoost;
    float weatherTime;
} ubuf;
layout(binding = 1) uniform sampler2D skyMap;
layout(binding = 2) uniform sampler2D surfaceMap;
layout(binding = 3) uniform sampler2D emissionMap;
layout(binding = 4) uniform sampler2D cloudLowMap;
layout(binding = 5) uniform sampler2D cloudHighMap;
const float PI = 3.141592653589793;
const float TAU = 6.283185307179586;
const float ART_ASPECT = 1672.0 / 941.0;

vec2 artworkUv(vec2 uv) {
    float aspect = ubuf.screenWidth / ubuf.screenHeight;
    vec2 visibleSize = aspect > ART_ASPECT
        ? vec2(1.0, ART_ASPECT / aspect) : vec2(aspect / ART_ASPECT, 1.0);
    return (uv - 0.5) * visibleSize + 0.5;
}

vec2 geographicUv(vec3 normal) {
    float cameraLatitude = radians(mix(-12.0, 12.0, ubuf.fullGlobe));
    float y = cos(cameraLatitude) * normal.y + sin(cameraLatitude) * normal.z;
    float z = -sin(cameraLatitude) * normal.y + cos(cameraLatitude) * normal.z;
    float longitude = atan(normal.x, z) + radians(15.0) - TAU * fract(ubuf.phase);
    return vec2(fract(longitude / TAU + 0.5),
                clamp(0.5 - asin(clamp(y, -1.0, 1.0)) / PI, 0.0, 1.0));
}

vec2 seamDerivative(vec2 derivative) {
    derivative.x -= floor(derivative.x + 0.5);
    return derivative;
}

vec3 surfaceTap(vec2 uv, vec2 dx, vec2 dy) {
    return textureGrad(surfaceMap, vec2(fract(uv.x), clamp(uv.y, 0.0, 1.0)), dx, dy).rgb;
}

float emissionTap(vec2 uv, vec2 dx, vec2 dy) {
    return textureGrad(emissionMap, vec2(fract(uv.x), clamp(uv.y, 0.0, 1.0)), dx, dy).r;
}

vec3 softenedSurface(vec2 uv, vec2 dx, vec2 dy) {
    if (ubuf.planetVisualVersion < 6.5) {
        // Restore the saved v6 material filter and its original city falloff.
        vec2 stepX = dx * ubuf.surfaceSoftness;
        vec2 stepY = dy * ubuf.surfaceSoftness;
        vec3 soft = surfaceTap(uv, dx, dy) * 0.25;
        soft += (surfaceTap(uv + stepX, dx, dy) + surfaceTap(uv - stepX, dx, dy)
               + surfaceTap(uv + stepY, dx, dy) + surfaceTap(uv - stepY, dx, dy)) * 0.125;
        soft += (surfaceTap(uv + stepX + stepY, dx, dy) + surfaceTap(uv + stepX - stepY, dx, dy)
               + surfaceTap(uv - stepX + stepY, dx, dy) + surfaceTap(uv - stepX - stepY, dx, dy)) * 0.0625;
        float nearEmission = max(surfaceTap(uv, dx * 4.0, dy * 4.0).r - 0.025, 0.0);
        float farEmission = max(surfaceTap(uv, dx * 9.0, dy * 9.0).r - 0.025, 0.0);
        return soft + ubuf.cityGlow * (nearEmission * vec3(0.70, 0.39, 0.12)
                                    + farEmission * vec3(0.30, 0.14, 0.055));
    }
    // Smooth the baked gold cores as well as their halo. A filtered city mask
    // widens this kernel only near lights; coastlines and terrain keep their
    // established softness. Everything stays in the rotating geographic UVs.
    float core = emissionTap(uv, dx * 3.0, dy * 3.0);
    float cityMask = smoothstep(0.008, 0.12, core);
    float softness = mix(ubuf.surfaceSoftness, max(ubuf.surfaceSoftness, 2.4), cityMask);
    vec2 stepX = dx * softness;
    vec2 stepY = dy * softness;
    vec2 filteredDx = dx * mix(1.0, 2.2, cityMask);
    vec2 filteredDy = dy * mix(1.0, 2.2, cityMask);
    vec3 soft = surfaceTap(uv, filteredDx, filteredDy) * 0.25;
    soft += (surfaceTap(uv + stepX, filteredDx, filteredDy) + surfaceTap(uv - stepX, filteredDx, filteredDy)
           + surfaceTap(uv + stepY, filteredDx, filteredDy) + surfaceTap(uv - stepY, filteredDx, filteredDy)) * 0.125;
    soft += (surfaceTap(uv + stepX + stepY, filteredDx, filteredDy) + surfaceTap(uv + stepX - stepY, filteredDx, filteredDy)
           + surfaceTap(uv - stepX + stepY, filteredDx, filteredDy) + surfaceTap(uv - stepX - stepY, filteredDx, filteredDy)) * 0.0625;

    // Coloured terrain must not become a source of artificial city light.
    float nearEmission = max(emissionTap(uv, dx * 4.0, dy * 4.0) - 0.025, 0.0);
    float farEmission = max(emissionTap(uv, dx * 9.0, dy * 9.0) - 0.025, 0.0);
    float outsideCore = 1.0 - smoothstep(0.16, 0.65, core);
    soft += ubuf.cityGlow * outsideCore * (nearEmission * vec3(1.25, 0.64, 0.19)
                                        + farEmission * vec3(1.05, 0.46, 0.10));
    return soft * (1.0 - 0.16 * smoothstep(0.45, 0.95, core));
}

vec3 decodeClouds(vec4 value) {
    vec4 b=floor(value*255.0+.5);
    return (b.rgb*4.0+vec3(floor(b.a/16.0),mod(floor(b.a/4.0),4.0),mod(b.a,4.0)))/1023.0;
}
vec3 weatherPixel(sampler2D field,vec2 pixel) {
    vec2 uv=(pixel+.5)/vec2(768.0,384.0);
    return decodeClouds(texture(field,vec2(fract(uv.x),clamp(uv.y,.5/384.0,1.0-.5/384.0))));
}
vec3 weatherAt(sampler2D field,vec2 uv) {
    vec2 p=uv*vec2(768.0,384.0)-.5;
    vec2 i=floor(p),f=fract(p);
    return mix(mix(weatherPixel(field,i),weatherPixel(field,i+vec2(1,0)),f.x),
               mix(weatherPixel(field,i+vec2(0,1)),weatherPixel(field,i+vec2(1,1)),f.x),f.y);
}
vec3 weatherTap(sampler2D field, vec2 uv, vec2 dx, vec2 dy) {
    // Unpack before filtering. A small footprint filter keeps thin fibres from
    // sparkling where the sphere compresses many weather texels at its rim.
    vec2 size=vec2(768.0,384.0);
    if(max(length(dx*size),length(dy*size))>1.5) {
        dx=clamp(dx,vec2(-.01),vec2(.01))*.35;
        dy=clamp(dy,vec2(-.01),vec2(.01))*.35;
        return (weatherAt(field,uv+dx+dy)+weatherAt(field,uv+dx-dy)
               +weatherAt(field,uv-dx+dy)+weatherAt(field,uv-dx-dy))*.25;
    }
    return weatherAt(field,uv);
}

float selectedType(float value, float kind) {
    return ubuf.cloudType < 0.5 || abs(ubuf.cloudType - kind) < 0.5 ? value : 0.0;
}

float unionDensity(vec3 low, vec3 high) {
    return max(max(max(low.r, low.g), low.b), max(max(high.r, high.g), high.b));
}

float bandHash(vec2 p) {
    vec3 q=fract(vec3(p.xyx)*.1031);
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
float bandNoise(vec2 p,float repeatX) {
    vec2 i=floor(p),f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(bandHash(vec2(mod(i.x,repeatX),i.y)),
                   bandHash(vec2(mod(i.x+1.0,repeatX),i.y)),f.x),
               mix(bandHash(vec2(mod(i.x,repeatX),i.y+1.0)),
                   bandHash(vec2(mod(i.x+1.0,repeatX),i.y+1.0)),f.x),f.y);
}
float cirrusDetail(vec2 uv) {
    // Sub-grid rendering of the model's upper ice field. This adds no cloud
    // mass: the simulated high.r field still gates every visible filament.
    // Retained weather time freezes with the solver, independently of rotation.
    float t=ubuf.weatherTime;
    uv.x-=.00000135*sin((uv.y-.5)*TAU*2.0)*t;
    float longitude=uv.x*TAU;
    float bend=.30*sin(longitude*3.0+t*TAU/43200.0)
              +.13*sin(longitude*11.0+uv.y*9.0+t*TAU/21600.0);
    float rows=uv.y*105.0+bend+.90*sin(uv.y*TAU*7.0+.20*sin(longitude*2.0))
               +.35*bandNoise(uv*vec2(16.0,23.0),16.0);
    float distanceToFibre=abs(fract(rows)-.5);
    float feather=clamp(fwidth(rows)*.65,.012,.14);
    float width=.045+.070*bandNoise(uv*vec2(33.0,19.0),33.0);
    float fibre=1.0-smoothstep(width-feather,width+feather,distanceToFibre);
    // Irregular spacing, tapering and gaps avoid a ruler-like latitude grid.
    float breakup=bandNoise(uv*vec2(96.0,31.0),96.0);
    return fibre*smoothstep(.42,.67,breakup);
}

void main() {
    vec2 uv = artworkUv(qt_TexCoord0);
    vec3 color = texture(skyMap, uv).rgb * ubuf.skyBrightness;
    float radius = mix(2.30, 0.435, ubuf.fullGlobe);
    vec2 center = vec2(0.520 * ART_ASPECT, mix(2.691, 0.530, ubuf.fullGlobe));
    vec2 point = vec2(uv.x * ART_ASPECT, uv.y) - center;
    vec2 projected = vec2(point.x, -point.y) / radius;
    float r2 = dot(projected, projected);
    float radial = sqrt(r2);
    float pixel = 1.0 / (ubuf.screenHeight * radius);
    float surface = 1.0 - smoothstep(1.0 - pixel, 1.0 + pixel, radial);
    float cloudAlpha = 0.0;
    vec3 horizonIllumination = vec3(0.0);
    if (surface > 0.0) {
        vec3 normal = vec3(projected, sqrt(max(0.0, 1.0 - r2)));
        // One geographic transform drives ground AND weather: the same axis,
        // latitude, phase and angular speed. Winds advect the weather itself.
        vec2 geo = geographicUv(normal);
        vec2 dx = seamDerivative(dFdx(geo)), dy = seamDerivative(dFdy(geo));
        vec3 ground = softenedSurface(geo, dx, dy);
        vec3 material = textureGrad(emissionMap, geo, dx, dy).rgb;
        ground *= 0.85 + 0.15 * sqrt(normal.z);
        vec3 sunDirection = normalize(vec3(0.0, 0.91, -0.41));
        float sunlight = max(dot(normal, sunDirection), 0.0);
        float sunArc = exp(-pow((uv.x - 0.52) / 0.33, 2.0));
        float sourceLight = sunlight * (0.35 + 0.65 * sunArc);
        float fresnel = pow(1.0 - normal.z, 5.0);
        float reflection = mix(0.09 + ground.b * 0.05 + fresnel * 0.35,
                               0.26 + material.b * 0.52, material.g);
        float surfaceDepth = max((1.0 - radial) * radius, 0.0);
        float haze = exp(-surfaceDepth * 18.0);
        float topCap = pow(clamp(normal.y, 0.0, 1.0), 4.0) * sunArc;
        float edgeLight = exp(-surfaceDepth * 90.0 * (1.0 - ubuf.sunTipBoost * topCap));
        // Illumination uses moving terrain reflectivity. It never replaces
        // the landscape with a fixed painted glow or a screen-space patch.
        ground *= vec3(1.0) + sourceLight * reflection * vec3(0.28, 0.65, 0.95);
        ground += vec3(0.10, 0.48, 0.76) * haze * sourceLight * (0.25 + reflection * 0.75)
                  * (1.0 + ubuf.sunTipBoost * 0.5 * topCap);

        vec3 low = weatherTap(cloudLowMap, geo, dx, dy);
        vec3 high = weatherTap(cloudHighMap, geo, dx, dy);
        float cumulus = selectedType(smoothstep(0.14, 0.75, low.r) * 0.78, 1.0);
        float stratus = selectedType(smoothstep(0.16, 0.68, low.g) * 0.36, 2.0);
        float stratocumulus = selectedType(smoothstep(0.14, 0.70, low.b) * 0.68, 3.0);
        float cirrus = selectedType(smoothstep(0.025, 0.30, high.r) * 0.60
                       * mix(.045,1.0,cirrusDetail(geo)), 4.0);
        float lenticular = selectedType(smoothstep(0.16, 0.75, high.g) * 0.64, 5.0);
        float storm = selectedType(smoothstep(0.10, 0.78, high.b) * 0.88, 6.0);
        cloudAlpha = (1.0 - (1.0 - cumulus) * (1.0 - stratus) * (1.0 - stratocumulus)
                    * (1.0 - cirrus) * (1.0 - lenticular) * (1.0 - storm)) * ubuf.cloudAmount;

        vec2 lightOffset = vec2(-0.7 / 768.0, -0.9 / 384.0);
        vec3 lowAhead = weatherTap(cloudLowMap, geo + lightOffset, dx, dy);
        vec3 highAhead = weatherTap(cloudHighMap, geo + lightOffset, dx, dy);
        float slope = unionDensity(low, high) - unionDensity(lowAhead, highAhead);
        float shapeLight = clamp(0.60 + slope * 1.25, 0.0, 1.0);
        vec3 cloudColor = mix(vec3(0.055, 0.13, 0.35), vec3(0.48, 0.64, 0.89), shapeLight);
        cloudColor *= 0.82 + 0.35 * sunlight;
        cloudColor += vec3(0.08, 0.22, 0.28) * haze * sourceLight;
        float shadow = smoothstep(0.18, 0.75, unionDensity(lowAhead, highAhead));
        ground *= 1.0 - shadow * ubuf.cloudAmount * 0.15;
        ground = mix(ground, cloudColor * vec3(0.86, 0.92, 1.02), stratus * ubuf.cloudAmount);
        ground = mix(ground, cloudColor, stratocumulus * ubuf.cloudAmount);
        ground = mix(ground, cloudColor * vec3(0.98, 1.02, 1.04), cumulus * ubuf.cloudAmount);
        ground = mix(ground, cloudColor * vec3(0.90, 0.94, 1.05), storm * ubuf.cloudAmount);
        ground = mix(ground, cloudColor * vec3(1.07, 1.00, 1.06), lenticular * ubuf.cloudAmount);
        ground = mix(ground, vec3(0.43, 0.61, 0.83) * (0.88 + sunlight * 0.3), cirrus * ubuf.cloudAmount);

        float cloudReflection = clamp(unionDensity(low, high) * ubuf.cloudAmount, 0.0, 1.0);
        float rimMaterial = 0.48 + reflection * 0.80 + cloudReflection * 0.42;
        horizonIllumination = (vec3(0.42, 1.05, 1.40)
            + vec3(0.18, 0.20, 0.20) * pow(sunArc, 5.0))
            * edgeLight * (0.25 + 0.75 * sourceLight) * rimMaterial
            * (1.0 + ubuf.sunTipBoost * topCap);
        ground += horizonIllumination;

        if (ubuf.diagnosticMode > 2.5) {
            fragColor = vec4(horizonIllumination * surface, 1.0);
            return;
        }
        if (ubuf.diagnosticMode > 1.5) {
            fragColor = vec4(material.g, material.r, material.b, 1.0);
            return;
        }
        color = mix(color, ground, surface);
    }
    if (ubuf.diagnosticMode > 0.5) {
        fragColor = vec4(cloudAlpha * surface, surface, 0.0, 1.0);
        return;
    }
    float altitude = max(radial - 1.0, 0.0) * radius;
    vec3 rimNormal = vec3(projected / max(length(projected), 0.00001), 0.0);
    vec2 rimGeo = geographicUv(rimNormal);
    vec2 rimDx = seamDerivative(dFdx(rimGeo)), rimDy = seamDerivative(dFdy(rimGeo));
    vec3 rimMaterialMap = textureGrad(emissionMap, rimGeo, rimDx, rimDy).rgb;
    float rimReflection = mix(0.12, 0.26 + rimMaterialMap.b * 0.52, rimMaterialMap.g);
    float rimClouds = unionDensity(weatherTap(cloudLowMap, rimGeo, rimDx, rimDy),
                                   weatherTap(cloudHighMap, rimGeo, rimDx, rimDy));
    float outerLight = (0.55 + rimReflection * 0.55 + rimClouds * ubuf.cloudAmount * 0.30)
        * (1.0 - smoothstep(0.003, 0.005, max(radial - 1.0, 0.0)));
    float rimTop = pow(clamp(rimNormal.y, 0.0, 1.0), 4.0)
        * exp(-pow((uv.x - 0.52) / 0.33, 2.0));
    outerLight *= 1.0 + ubuf.sunTipBoost * rimTop;
    color += exp(-altitude * 190.0) * vec3(0.08, 0.30, 0.48) * (1.0 - surface) * outerLight;
    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0) * ubuf.qt_Opacity;
}
