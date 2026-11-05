#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float evolutionTime;
    float deltaSeconds;
    float initialize;
} ubuf;
layout(binding=1) uniform sampler2D previousState;
const float TAU = 6.28318530718;
const float DAY = 345600.0;
const vec2 SIZE = vec2(384.0, 192.0);

vec4 encode(float v) {
    float n = floor(clamp(v, 0.0, 1.0) * 65535.0 + 0.5);
    return vec4(floor(n / 256.0), mod(n, 256.0), 0.0, 255.0) / 255.0;
}
float pixel(vec2 p) {
    vec2 uv = (p + 0.5) / SIZE;
    uv = vec2(fract(uv.x), clamp(uv.y, 0.5 / SIZE.y, 1.0 - 0.5 / SIZE.y));
    vec2 b = floor(texture(previousState, uv).rg * 255.0 + 0.5);
    return (b.x * 256.0 + b.y) / 65535.0;
}
float history(vec2 uv) {
    vec2 p = uv * SIZE - 0.5, i = floor(p), f = fract(p);
    return mix(mix(pixel(i), pixel(i + vec2(1,0)), f.x),
               mix(pixel(i + vec2(0,1)), pixel(i + vec2(1,1)), f.x), f.y);
}
// All longitudinal frequencies are integers, so the seam is periodic.
float pattern(vec2 uv, float t) {
    float x = TAU * uv.x, y = TAU * (uv.y - 0.5);
    float phase = TAU * t / (DAY * 5.0);
    float warp = 0.8 * sin(2.0*x + 1.3*sin(y*1.7) + phase);
    float broad = sin(2.0*x + 2.4*sin(y*1.3) + 0.4*sin(phase));
    float band = sin(3.0*x + 5.0*y + warp - phase*0.7);
    float second = cos(x - 7.0*y + 0.7*sin(2.0*x) + phase*0.5);
    return clamp(0.50 + 0.18*broad + 0.12*band + 0.09*second, 0.02, 0.98);
}
void main() {
    vec2 uv = qt_TexCoord0;
    if (ubuf.initialize > 0.5) {
        fragColor = encode(pattern(uv, 0.0));
        return;
    }
    float dt = clamp(ubuf.deltaSeconds, 0.0, DAY / 8.0);
    float lat = (uv.y - 0.5) * 3.14159265359;
    float t = ubuf.evolutionTime;
    // Mean superrotation is rendered by the globe. This is only differential
    // transport relative to that frame, with weak meridional circulation.
    float shear = 0.20 * sin(2.0*lat) + 0.10*cos(3.0*lat);
    float meridional = 0.035*sin(2.0*lat) + 0.015*sin(TAU*uv.x + TAU*t/(DAY*4.0))*cos(lat);
    vec2 back = uv - dt/DAY * vec2(shear, meridional);
    float value = history(back);
    // Slowly replace tracer to represent formation and loss without flicker.
    float target = pattern(uv, t);
    value = mix(value, target, 1.0-exp(-dt/(DAY*2.5)));
    fragColor = encode(value);
}
