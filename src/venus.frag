#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float phase;
    float screenWidth;
    float screenHeight;
} ubuf;
layout(binding = 1) uniform sampler2D skyMap;
layout(binding = 2) uniform sampler2D atmosphereMap;
const float PI = 3.141592653589793;
const float ART_ASPECT = 1672.0 / 941.0;
float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash31(i), hash31(i + vec3(1,0,0)), f.x),
                   mix(hash31(i + vec3(0,1,0)), hash31(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(hash31(i + vec3(0,0,1)), hash31(i + vec3(1,0,1)), f.x),
                   mix(hash31(i + vec3(0,1,1)), hash31(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
    float v = 0.0, a = 0.55;
    for (int i = 0; i < 5; ++i) {
        v += a * noise3(p);
        p = p * 2.02 + vec3(8.1, 3.7, 5.2);
        a *= 0.48;
    }
    return v;
}
float decodeState(vec2 uv) {
    vec2 bytes = floor(texture(atmosphereMap, uv).rg * 255.0 + 0.5);
    return (bytes.r * 256.0 + bytes.g) / 65535.0;
}
float atmosphere(vec2 uv) {
    // Packed scalar precision is retained by interpolating decoded texels.
    // Fixed solver grid also supports Qt's default ESSL 100 shader target.
    vec2 size = vec2(384.0, 192.0);
    vec2 p = uv * size - 0.5;
    vec2 base = floor(p);
    vec2 f = fract(p);
    vec2 a = (base + 0.5) / size;
    vec2 b = (base + 1.5) / size;
    a = vec2(fract(a.x), clamp(a.y, 0.5 / size.y, 1.0 - 0.5 / size.y));
    b = vec2(fract(b.x), clamp(b.y, 0.5 / size.y, 1.0 - 0.5 / size.y));
    return mix(mix(decodeState(a), decodeState(vec2(b.x, a.y)), f.x),
               mix(decodeState(vec2(a.x, b.y)), decodeState(b), f.x), f.y);
}
void main() {
    float aspect = ubuf.screenWidth / ubuf.screenHeight;
    vec2 visibleSize = aspect > ART_ASPECT ? vec2(1.0, ART_ASPECT / aspect)
                                            : vec2(aspect / ART_ASPECT, 1.0);
    vec2 uv = (qt_TexCoord0 - 0.5) * visibleSize + 0.5;
    vec3 color = texture(skyMap, uv).rgb;
    // Keep the castle in the original navy sky. A slightly smaller, rightward
    // disc gives this scene its own composition without cropping the globe.
    vec2 p = (vec2(uv.x * ART_ASPECT, uv.y) - vec2(1.29, 0.555)) / 0.335;
    float r = length(p);
    float edgeWidth = max(fwidth(r), 1.2 / (ubuf.screenHeight * 0.335));
    float edge = 1.0 - smoothstep(1.0 - edgeWidth, 1.0 + edgeWidth, r);
    if (edge > 0.0) {
        vec3 n = vec3(p.x, -p.y, sqrt(max(0.0, 1.0 - r*r)));
        float angle = ubuf.phase * 2.0 * PI;
        vec3 q = vec3(cos(angle)*n.x + sin(angle)*n.z, n.y,
                      -sin(angle)*n.x + cos(angle)*n.z);
        vec2 atmosphereUv = vec2(fract(atan(q.z, q.x) / (2.0 * PI) + 0.5),
                                 acos(clamp(q.y, -1.0, 1.0)) / PI);
        float density = atmosphere(atmosphereUv);
        // Both tone and flow distortion come from the retained solver. Static
        // spherical pigment adds a quiet painted grain without a time-noise
        // animation or a longitude seam.
        vec3 w = q + vec3(0.10, 0.14, 0.10) * (density - 0.5);
        float pigment = fbm(w * vec3(9.0, 24.0, 9.0) + 9.0);
        float tone = clamp(0.90 * density + 0.10 * pigment, 0.0, 1.0);
        vec3 amber = vec3(0.72, 0.59, 0.44);
        vec3 ochre = vec3(0.89, 0.77, 0.57);
        vec3 cream = vec3(0.99, 0.95, 0.83);
        vec3 clouds = mix(amber, ochre, smoothstep(0.15, 0.58, tone));
        clouds = mix(clouds, cream, smoothstep(0.39, 0.80, tone) * 0.83);
        // Quiet, short horizontal brush marks follow the spherical material.
        // A few pigment levels give the interior a painted pixel character;
        // neither their coordinates nor their seed depend on wall-clock time.
        float strokes = noise3(w * vec3(29.0, 98.0, 29.0) + 21.0);
        float fine = noise3(w * vec3(71.0, 175.0, 71.0) + 37.0);
        float steppedPigment = floor(strokes * 7.0) / 6.0 - 0.5;
        float brush = 0.026 * steppedPigment + 0.012 * (fine - 0.5);
        float strokeFade = smoothstep(0.02, 0.25, n.z);
        clouds += strokeFade * brush * vec3(1.0, 0.91, 0.73);
        float diffuse = clamp(dot(n, normalize(vec3(-0.36, 0.70, 0.72))), 0.0, 1.0);
        float light = 0.63 + 0.37 * diffuse;
        clouds = mix(clouds, clouds * vec3(0.91, 0.95, 1.04), (1.0 - diffuse) * 0.36);
        clouds *= light * (0.88 + 0.12 * sqrt(n.z));
        float sunTip = pow(max(0.0, dot(n, normalize(vec3(-0.27, 0.88, 0.38)))), 9.0);
        clouds += sunTip * vec3(0.085, 0.067, 0.039);
        color = mix(color, clouds, edge);
    }
    float glow = exp(-max(r - 1.0, 0.0) * 53.0) * (1.0 - edge);
    float topLight = 0.50 + 0.50 * clamp(-p.y, 0.0, 1.0);
    color += glow * topLight * vec3(0.15, 0.10, 0.045);
    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0) * ubuf.qt_Opacity;
}
