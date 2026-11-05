#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float deltaSeconds;
    float evolutionTime;
    float initialize;
} ubuf;
layout(binding=1) uniform sampler2D previousState;
const float TAU = 6.28318530718;
const float DAY = 38520.0;
const vec2 SIZE = vec2(256.0, 128.0);

vec4 encodeState(vec3 state) {
    vec3 q = floor(clamp(state, 0.0, 1.0) * 1023.0 + 0.5);
    float tail = mod(q.r, 4.0)*16.0 + mod(q.g, 4.0)*4.0 + mod(q.b, 4.0);
    return vec4(floor(q / 4.0), tail) / 255.0;
}
vec3 decodeState(vec4 value) {
    vec4 b = floor(value * 255.0 + 0.5);
    return (b.rgb * 4.0 + vec3(floor(b.a / 16.0), mod(floor(b.a / 4.0), 4.0), mod(b.a, 4.0))) / 1023.0;
}
vec3 pixel(vec2 p) {
    vec2 uv = (p + 0.5) / SIZE;
    return decodeState(texture(previousState, vec2(fract(uv.x), clamp(uv.y, 0.5/SIZE.y, 1.0-0.5/SIZE.y))));
}
vec3 history(vec2 uv) {
    vec2 p = uv * SIZE - 0.5, i = floor(p), f = fract(p);
    return mix(mix(pixel(i), pixel(i+vec2(1,0)), f.x),
               mix(pixel(i+vec2(0,1)), pixel(i+vec2(1,1)), f.x), f.y);
}
float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float noise(vec2 p, float period) {
    vec2 i = floor(p), f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(mix(hash(vec2(mod(i.x,period),i.y)), hash(vec2(mod(i.x+1.0,period),i.y)), f.x),
               mix(hash(vec2(mod(i.x,period),i.y+1.0)), hash(vec2(mod(i.x+1.0,period),i.y+1.0)), f.x), f.y);
}
vec3 seed(vec2 uv) {
    float broad = noise(vec2(0.0, uv.y*18.0), 1.0);
    float stripe = 0.5 + 0.5*sin(uv.y*TAU*20.0 + broad*3.0);
    float detail = noise(uv*vec2(32.0,36.0),32.0);
    float elongated = noise(uv*vec2(20.0,45.0),20.0);
    return vec3(0.31 + 0.33*broad + 0.18*stripe + 0.22*(detail-0.5),
                0.18 + 0.62*elongated + 0.22*(detail-0.5),
                0.25 + 0.46*broad + 0.17*(detail-0.5));
}
vec2 flow(vec2 uv) {
    float latitude = (0.5-uv.y)*3.14159265359;
    // Alternating, persistent jets relative to the rotating planet.
    float jet = 0.055*cos(latitude*9.0) + 0.022*cos(latitude*17.0)
                + 0.045*exp(-latitude*latitude/0.08);
    vec2 velocity = vec2(jet, 0.0);
    // Long-lived elliptical vortices embedded in, and deformed by, the jets.
    for (int n=0; n<6; ++n) {
        float k = float(n);
        vec2 center = vec2(fract(0.12+k*0.167), 0.20+0.115*k);
        vec2 d = uv-center;
        d.x -= floor(d.x+0.5);
        vec2 radius = vec2(0.060,0.026);
        float r2 = dot(d/radius,d/radius);
        float strength = (mod(k,2.0)<0.5 ? 1.0 : -1.0)*0.024*exp(-r2*0.7);
        velocity += strength*vec2(-d.y/radius.y, d.x/radius.x)*vec2(1.0,0.35);
    }
    velocity.y *= smoothstep(0.0,0.08,min(uv.y,1.0-uv.y));
    return velocity / DAY;
}
void main() {
    vec2 uv = qt_TexCoord0;
    if (ubuf.initialize > 0.5) {
        fragColor = encodeState(seed(uv));
        return;
    }
    float dt = clamp(ubuf.deltaSeconds, 0.0, DAY/4.0);
    vec2 back = uv - flow(uv)*dt;
    vec3 state = history(back);
    vec2 texel = 1.0/SIZE;
    vec3 neighbours = (history(back+vec2(texel.x,0)) + history(back-vec2(texel.x,0))
                     + history(back+vec2(0,texel.y)) + history(back-vec2(0,texel.y)))*0.25;
    state = mix(state, neighbours, min(dt/DAY*0.018, 0.025));
    // Weak local forcing maintains the latitude belts while retained eddies
    // are advected and decay over many rotations.
    vec3 equilibrium = seed(vec2(0.0, uv.y));
    state = mix(state, equilibrium, 1.0-exp(-dt/(DAY*35.0)));
    fragColor = encodeState(state);
}
