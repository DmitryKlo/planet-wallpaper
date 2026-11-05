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
const vec3 AXIS = vec3(0.213, 0.854, 0.475);

float pigmentHash(vec3 p) {
    p = fract(p*0.1031);
    p += dot(p,p.yzx+33.33);
    return fract((p.x+p.y)*p.z);
}
float pigmentNoise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(mix(mix(pigmentHash(i),pigmentHash(i+vec3(1,0,0)),f.x),
                   mix(pigmentHash(i+vec3(0,1,0)),pigmentHash(i+vec3(1,1,0)),f.x),f.y),
               mix(mix(pigmentHash(i+vec3(0,0,1)),pigmentHash(i+vec3(1,0,1)),f.x),
                   mix(pigmentHash(i+vec3(0,1,1)),pigmentHash(i+vec3(1,1,1)),f.x),f.y),f.z);
}

vec3 decodeState(vec2 uv) {
    vec4 packed = texture(atmosphereMap,uv);
    float aByte = floor(packed.a*255.0+0.5);
    vec3 bits = vec3(floor(aByte/16.0),mod(floor(aByte/4.0),4.0),mod(aByte,4.0));
    return (floor(packed.rgb*255.0+0.5)*4.0+bits)/1023.0;
}
vec3 atmosphere(vec2 uv) {
    // Matches the retained SaturnAtmosphere grid; also supports Qt's ESSL100 target.
    vec2 size = vec2(256.0,128.0);
    vec2 pos = uv*size-0.5;
    vec2 base = floor(pos), f = fract(pos);
    vec2 a = (base+0.5)/size, b = (base+1.5)/size;
    a = vec2(fract(a.x),clamp(a.y,0.5/size.y,1.0-0.5/size.y));
    b = vec2(fract(b.x),clamp(b.y,0.5/size.y,1.0-0.5/size.y));
    return mix(mix(decodeState(a),decodeState(vec2(b.x,a.y)),f.x),
               mix(decodeState(vec2(a.x,b.y)),decodeState(b),f.x),f.y);
}

float ringDensity(float r) {
    float inner = smoothstep(1.18, 1.27, r);
    float outer = 1.0 - smoothstep(1.96, 2.02, r);
    float cassini = 1.0 - 0.92 * (smoothstep(1.68, 1.70, r)
                                    - smoothstep(1.75, 1.77, r));
    // Broad translucent C, dense B and quieter A ring, with restrained grain.
    float division = mix(0.33,0.93,smoothstep(1.29,1.39,r));
    division = mix(division,0.73,smoothstep(1.76,1.82,r));
    division *= 0.97+0.018*sin(r*98.0)+0.012*sin(r*213.0);
    return inner * outer * cassini * division;
}

void main() {
    float aspect = ubuf.screenWidth / ubuf.screenHeight;
    vec2 visibleSize = aspect > ART_ASPECT ? vec2(1.0, ART_ASPECT/aspect)
                                           : vec2(aspect/ART_ASPECT, 1.0);
    vec2 uv = (qt_TexCoord0-0.5)*visibleSize+0.5;
    vec3 color = texture(skyMap, uv).rgb;
    vec2 p = (vec2(uv.x*ART_ASPECT, uv.y)-vec2(1.20,0.55))/0.235;
    p.y = -p.y;
    float r2 = dot(p,p);
    float aa = 1.8/(ubuf.screenHeight*0.235);
    float disk = 1.0-smoothstep(1.0-aa,1.0+aa,sqrt(r2));
    float z = sqrt(max(0.0,1.0-r2));
    vec3 light = normalize(vec3(-0.55,0.65,1.4));
    // The same inclined plane is used for visibility, ring shading and both shadows.
    float ringZ = -dot(AXIS.xy,p)/AXIS.z;
    vec3 ringPoint = vec3(p,ringZ);
    float ringR = length(ringPoint);
    float density = ringDensity(ringR);
    float ringAlpha = clamp(density*0.87,0.0,0.82);
    vec3 ringColor = mix(vec3(0.48,0.37,0.29),vec3(0.79,0.70,0.53),
                        smoothstep(1.25,1.60,ringR));
    ringColor *= 0.96+0.018*sin(ringR*47.0);
    float closest = dot(ringPoint,light);
    float shadowDistance = length(ringPoint-light*closest);
    float planetShadow = (1.0-smoothstep(0.94,1.07,shadowDistance))
                         * (1.0-smoothstep(-0.08,0.08,closest));
    ringColor *= 1.0-0.74*planetShadow;
    bool front = ringZ > z;
    if (!front) color = mix(color,ringColor,ringAlpha);
    if (disk > 0.0) {
        vec3 n = normalize(vec3(p,z));
        vec3 east = normalize(cross(AXIS,vec3(0,0,1)));
        vec3 meridian = cross(east,AXIS);
        float latitude = clamp(dot(n,AXIS),-1.0,1.0);
        float longitude = atan(dot(n,east),dot(n,meridian));
        vec2 sphereUV = vec2(fract(longitude/(2.0*PI)+0.5+ubuf.phase),
                             acos(latitude)/PI);
        vec3 field = atmosphere(sphereUV);
        float warp = (field.g-0.5)*0.25;
        float bands = 0.58*field.r+0.42*(0.5+0.5*sin((latitude+warp)*31.0));
        vec3 clouds = mix(vec3(0.65,0.48,0.36),vec3(0.89,0.79,0.61),
                          smoothstep(0.15,0.85,bands));
        float coolBelt = 0.5+0.5*sin(latitude*14.0+1.1);
        clouds = mix(clouds,vec3(0.58,0.65,0.64),0.20*coolBelt*field.b);
        clouds += (field.g-0.5)*vec3(0.31,0.21,0.13);
        // Quiet spherical pigment follows rotation, never wall-clock noise.
        float lon = (sphereUV.x-0.5)*2.0*PI;
        float ringLat = sqrt(max(0.0,1.0-latitude*latitude));
        vec3 material = vec3(sin(lon)*ringLat,latitude,cos(lon)*ringLat);
        float pigment = 0.65*pigmentNoise(material*vec3(22,48,22))
                       +0.35*pigmentNoise(material*vec3(57,89,57)+7.0);
        clouds += (pigment-0.5)*vec3(0.095,0.078,0.057);
        float illumination = 0.52+0.48*max(dot(n,light),0.0);
        clouds *= illumination*(0.86+0.14*sqrt(max(n.z,0.0)));
        float hit = -dot(AXIS,n)/dot(AXIS,light);
        float shadowR = length(n+hit*light);
        float ringShadow = ringDensity(shadowR)*smoothstep(0.0,0.07,hit);
        clouds *= 1.0-0.37*ringShadow;
        color = mix(color,clouds,disk);
    }
    if (front) color = mix(color,ringColor,ringAlpha);
    fragColor = vec4(clamp(color,0.0,1.0),1.0)*ubuf.qt_Opacity;
}
