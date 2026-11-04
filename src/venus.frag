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
void main() {
    float aspect = ubuf.screenWidth / ubuf.screenHeight;
    vec2 visibleSize = aspect > ART_ASPECT ? vec2(1.0, ART_ASPECT / aspect)
                                            : vec2(aspect / ART_ASPECT, 1.0);
    vec2 uv = (qt_TexCoord0 - 0.5) * visibleSize + 0.5;
    vec3 color = texture(skyMap, uv).rgb;
    vec2 p = (vec2(uv.x * ART_ASPECT, uv.y) - vec2(1.23, 0.56)) / 0.355;
    float r = length(p);
    float edge = 1.0 - smoothstep(1.0 - 1.2 / (ubuf.screenHeight * 0.355),
                                  1.0 + 1.2 / (ubuf.screenHeight * 0.355), r);
    if (edge > 0.0) {
        vec3 n = vec3(p.x, -p.y, sqrt(max(0.0, 1.0 - r*r)));
        float angle = ubuf.phase * 2.0 * PI;
        vec3 q = vec3(cos(angle)*n.x + sin(angle)*n.z, n.y,
                      -sin(angle)*n.x + cos(angle)*n.z);
        vec3 warp = vec3(fbm(q*2.2 + 5.0), fbm(q*2.4 + 17.0), fbm(q*2.0 + 31.0)) - 0.5;
        vec3 w = q + 0.48 * warp;
        float broad = fbm(w * vec3(3.1, 5.2, 3.1) + 9.0);
        float streak = fbm(w * vec3(5.0, 12.0, 5.0) + vec3(2.0, 4.0, 3.0));
        float tone = clamp(0.62*broad + 0.38*streak, 0.0, 1.0);
        vec3 amber = vec3(0.68, 0.46, 0.27);
        vec3 ochre = vec3(0.88, 0.72, 0.49);
        vec3 cream = vec3(1.0, 0.93, 0.75);
        vec3 clouds = mix(amber, ochre, smoothstep(0.20, 0.61, tone));
        clouds = mix(clouds, cream, smoothstep(0.43, 0.75, tone) * 0.8);
        float light = 0.62 + 0.38 * clamp(dot(n, normalize(vec3(-0.45, 0.55, 0.75))), 0.0, 1.0);
        clouds *= light * (0.87 + 0.13 * sqrt(n.z));
        color = mix(color, clouds, edge);
    }
    float glow = exp(-max(r - 1.0, 0.0) * 48.0) * (1.0 - edge);
    color += glow * vec3(0.22, 0.12, 0.045);
    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0) * ubuf.qt_Opacity;
}
