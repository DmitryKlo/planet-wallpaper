#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float simulationTime;
    float deltaSeconds;
    float initialize;
} ubuf;
layout(binding=1) uniform sampler2D previousClimate;
layout(binding=2) uniform sampler2D terrainMap;
const float TAU=6.283185307179586;

vec3 decodeClimate(vec4 value) {
    vec4 bytes=floor(value*255.0+.5);
    return vec3(bytes.r/255.0,
                (bytes.g*16.0+floor(bytes.a/16.0))/4095.0,
                (bytes.b*16.0+mod(bytes.a,16.0))/4095.0);
}
vec3 climatePixel(vec2 pixel) {
    vec2 uv=(pixel+.5)/vec2(384.0,192.0);
    uv=vec2(fract(uv.x),clamp(uv.y,.5/192.0,1.0-.5/192.0));
    return decodeClimate(texture(previousClimate,uv));
}
vec3 previous(vec2 uv) {
    vec2 p=uv*vec2(384.0,192.0)-.5;
    vec2 i=floor(p),f=fract(p);
    return mix(mix(climatePixel(i),climatePixel(i+vec2(1,0)),f.x),
               mix(climatePixel(i+vec2(0,1)),climatePixel(i+vec2(1,1)),f.x),f.y);
}
vec4 encodeClimate(vec3 state) {
    vec3 q=floor(clamp(state,0.0,1.0)*vec3(255.0,4095.0,4095.0)+.5);
    float residual=mod(q.g,16.0)*16.0+mod(q.b,16.0);
    return vec4(q.r,floor(q.g/16.0),floor(q.b/16.0),residual)/255.0;
}
float saturation(float temperature) { return .25+.52*temperature; }
float hash3(vec3 p) {
    p=fract(p*.1031);
    p+=dot(p,p.yzx+33.33);
    return fract((p.x+p.y)*p.z);
}
float airMass(vec3 p) {
    vec3 i=floor(p),f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),
                   mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),
               mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),
                   mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
vec3 equilibrium(vec2 uv) {
    float land=texture(terrainMap,uv).g;
    float latitude=(.5-uv.y)*3.141592653589793;
    float tropical=cos(latitude)*cos(latitude);
    float solarPhase=(uv.x-.5)*TAU+ubuf.simulationTime*TAU/86400.0;
    float responseTime=mix(28800.0,7200.0,land);
    float frequency=TAU/86400.0*responseTime;
    float thermalWave=cos(solarPhase-atan(frequency))/sqrt(1.0+frequency*frequency);
    float temperature=clamp(.10+.75*tropical+thermalWave*mix(.022,.080,land),.05,.96);

    // Smooth moist/dry air masses supply boundary conditions to the water
    // solver. Spherical coordinates avoid a seam or pinched polar cloud grid.
    // This is moisture forcing, never a cloud sprite or visible density mask.
    float drift=.00000060*sin((uv.y-.5)*TAU*2.0)*ubuf.simulationTime;
    float longitude=(uv.x-.5-drift)*TAU;
    vec3 sphere=vec3(cos(latitude)*cos(longitude),sin(latitude),cos(latitude)*sin(longitude));
    // Gradual deformation of moist air masses drives front formation and
    // breakup over hours. It changes the boundary supply, never cloud colour.
    float t=ubuf.simulationTime;
    vec3 deformation=vec3(.13*sin(t*TAU/43200.0),.09*cos(t*TAU/28800.0),
                          .10*sin(t*TAU/64800.0));
    vec3 p=sphere+vec3(3.7,-2.1,5.3)+deformation;
    float moisture=.56*airMass(p*9.0)+.29*airMass(p*23.0)+.15*airMass(p*53.0);
    float humidity=clamp(.66+.15*(1.0-land)+.02*tropical+(moisture-.5)*1.25,.28,1.18);
    float capacity=saturation(temperature);
    // Start with a consistent vapour/liquid partition. Continued condensate
    // is produced by condensation, not by a separate prescribed cloud field.
    float water=max(0.0,humidity-.92)*capacity;
    return vec3(temperature,capacity*humidity,water);
}
vec2 flow(vec2 uv) {
    vec2 px=vec2(1.0/384.0,1.0/192.0);
    float north=previous(uv-vec2(0,px.y)).r;
    float south=previous(uv+vec2(0,px.y)).r;
    float west=previous(uv-vec2(px.x,0)).r;
    float east=previous(uv+vec2(px.x,0)).r;
    vec2 curl=vec2((south-north)/px.y,-(east-west)/px.x)*.000000025;
    return vec2(.00000060*sin((uv.y-.5)*TAU*2.0),
                .00000020*sin(uv.x*TAU*2.0+uv.y*7.0))+clamp(curl,vec2(-.00000010),vec2(.00000010));
}
void main() {
    vec2 uv=qt_TexCoord0;
    vec3 target=equilibrium(uv);
    if(ubuf.initialize>.5) {
        float initialVapour=target.g-target.b;
        fragColor=encodeClimate(vec3(target.r,initialVapour,target.b))*ubuf.qt_Opacity;
        return;
    }
    float dt=clamp(ubuf.deltaSeconds,0.0,7200.0);
    vec2 back=uv-flow(uv)*dt;
    vec3 state=previous(back);
    vec2 px=vec2(1.0/384.0,1.0/192.0);
    vec3 neighbours=(previous(back+vec2(px.x,0))+previous(back-vec2(px.x,0))
                    +previous(back+vec2(0,px.y))+previous(back-vec2(0,px.y)))*.25;
    state=mix(state,neighbours,min(dt*.00002,.10));
    state.r=mix(target.r,state.r,.10);
    // Moisture supply, condensation, dry-air evaporation and precipitation.
    state.g=mix(state.g,target.g,1.0-exp(-dt/4200.0));
    float capacity=saturation(state.r);
    float humidity=state.g/max(.10,capacity);
    float condensed=max(0.0,state.g-capacity*.92)*(1.0-exp(-dt/600.0));
    float evaporated=min(state.b,max(0.0,.87-humidity)*dt/900.0);
    state.g+=evaporated-condensed;
    state.b=(state.b+condensed-evaporated)*exp(-dt/5400.0);
    state.r+=condensed*.035;
    fragColor=encodeClimate(clamp(state,vec3(0.0),vec3(.999)))*ubuf.qt_Opacity;
}
