#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float simulationTime;
    float deltaSeconds;
    float initialize;
    float group;
} ubuf;
layout(binding=1) uniform sampler2D previousState;
layout(binding=2) uniform sampler2D climateState;
layout(binding=3) uniform sampler2D terrainMap;
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
    return decodeClimate(texture(climateState,uv));
}
vec3 climateAt(vec2 uv) {
    vec2 p=uv*vec2(384.0,192.0)-.5;
    vec2 i=floor(p),f=fract(p);
    return mix(mix(climatePixel(i),climatePixel(i+vec2(1,0)),f.x),
               mix(climatePixel(i+vec2(0,1)),climatePixel(i+vec2(1,1)),f.x),f.y);
}
// RGB store the high eight bits; alpha holds two residual bits per density.
// This retains sub-pixel transport at x1 on the RGBA8-only OpenGL backend.
vec4 encodeClouds(vec3 state) {
    vec3 q=floor(clamp(state,0.0,1.0)*1023.0+.5);
    float tail=mod(q.r,4.0)*16.0+mod(q.g,4.0)*4.0+mod(q.b,4.0);
    return vec4(floor(q/4.0),tail)/255.0;
}
vec3 decodeClouds(vec4 value) {
    vec4 b=floor(value*255.0+.5);
    return (b.rgb*4.0+vec3(floor(b.a/16.0),mod(floor(b.a/4.0),4.0),mod(b.a,4.0)))/1023.0;
}
vec3 cloudPixel(vec2 pixel) {
    vec2 uv=(pixel+.5)/vec2(768.0,384.0);
    return decodeClouds(texture(previousState,vec2(fract(uv.x),clamp(uv.y,.5/384.0,1.0-.5/384.0))));
}
vec3 history(vec2 uv) {
    vec2 p=uv*vec2(768.0,384.0)-.5;
    vec2 i=floor(p),f=fract(p);
    return mix(mix(cloudPixel(i),cloudPixel(i+vec2(1,0)),f.x),
               mix(cloudPixel(i+vec2(0,1)),cloudPixel(i+vec2(1,1)),f.x),f.y);
}

float hash(vec2 p) {
    vec3 q=fract(vec3(p.xyx)*.1031);
    q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
float noise(vec2 p,float repeatX) {
    vec2 i=floor(p),f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(hash(vec2(mod(i.x,repeatX),i.y)),hash(vec2(mod(i.x+1.0,repeatX),i.y)),f.x),
               mix(hash(vec2(mod(i.x,repeatX),i.y+1.0)),hash(vec2(mod(i.x+1.0,repeatX),i.y+1.0)),f.x),f.y);
}
float oval(vec2 p,vec2 radius,float feather) {
    return 1.0-smoothstep(1.0-feather,1.0+feather,length(p/radius));
}

float cirrusFibres(vec2 uv,float t) {
    // The curved, feathered fibres from v8, now replenished only where the
    // water solver provides condensate. Coordinates follow the upper jet.
    const vec2 grid=vec2(30.0,27.0);
    uv.x-=.00000135*sin((uv.y-.5)*TAU*2.0)*t;
    vec2 pos=uv*grid,base=floor(pos);
    float result=0.0;
    for(int y=-1;y<=1;y++) for(int x=-1;x<=1;x++) {
        vec2 cell=base+vec2(x,y);
        vec2 id=vec2(mod(cell.x,grid.x),cell.y);
        float h=hash(id+vec2(93.0,51.0));
        if(h<.35) continue;
        float h2=hash(id+19.7),h3=hash(id+57.2);
        vec2 p=(pos-cell-vec2(.16+.68*h2,.18+.64*h3))/(.85+.40*h3);
        // Slow shear bends and opens fibres on the same model clock as winds.
        float bend=.08*sin(t*TAU/21600.0+h*TAU);
        float curve=.09*sin(p.x*4.0+h2*4.0)+(.12+h2*.12+bend)*p.x*p.x;
        for(int k=0;k<4;k++) {
            float f=float(k),shift=(f-1.5)*.050;
            vec2 q=vec2(p.x+f*.045,p.y-curve-shift-.025*sin(p.x*7.0+f));
            result=max(result,oval(q,vec2(.56-f*.065,.025+f*.004),.65)*(1.0-f*.13));
        }
    }
    return result*smoothstep(.025,.09,min(uv.y,1.0-uv.y));
}

vec2 cloudStructure(vec2 uv,float t) {
    uv.x-=.00000060*sin((uv.y-.5)*TAU*2.0)*t;
    vec2 p=uv*vec2(52.0,30.0);
    float warp=noise(uv*vec2(24.0,14.0)+vec2(t/21600.0,0.0),24.0);
    float rolls=.5+.5*cos(uv.y*TAU*87.0+warp*5.0+sin(uv.x*TAU*3.0)*1.2);
    float broken=smoothstep(.26,.68,noise(p+vec2(0.0,t/43200.0),52.0));
    return vec2(.48+.52*broken,smoothstep(.52,.92,rolls)*(.35+.65*broken));
}
vec2 wind(vec2 uv,float t) {
    // Persistent weather state moves under latitude jets and thermal curls.
    // Planetary angular rotation belongs only to geographicUv.
    float speed=ubuf.group<.5 ? .00000060 : .00000135;
    vec2 px=vec2(1.0/384.0,1.0/192.0);
    float north=climateAt(uv-vec2(0,px.y)).r;
    float south=climateAt(uv+vec2(0,px.y)).r;
    float east=climateAt(uv+vec2(px.x,0)).r;
    float west=climateAt(uv-vec2(px.x,0)).r;
    vec2 curl=vec2((south-north)/px.y,-(east-west)/px.x)*.000000025;
    return speed*vec2(sin((uv.y-.5)*TAU*2.0)+.20*sin(uv.x*TAU*3.0+uv.y*9.0+t*TAU/43200.0),
                     .34*sin(uv.x*TAU*2.0+uv.y*7.0+t*TAU/21600.0))
                     +clamp(curl,vec2(-.00000010),vec2(.00000010));
}

void main() {
    vec2 uv=qt_TexCoord0;
    vec3 climate=climateAt(uv);
    vec3 terrain=texture(terrainMap,uv).rgb;
    vec2 px=vec2(1.0/384.0,1.0/192.0);
    vec3 north=climateAt(uv-vec2(0,px.y));
    vec3 south=climateAt(uv+vec2(0,px.y));
    vec3 east=climateAt(uv+vec2(px.x,0));
    vec3 west=climateAt(uv-vec2(px.x,0));

    // Condensed water supplies optical mass; sub-grid fibres/rolls give each
    // level structure. They cannot create a cloud in an empty water field.
    float capacity=.25+.52*climate.r;
    float liquidRatio=climate.b/max(.10,capacity);
    float mass=smoothstep(.012,.140,liquidRatio);
    // Upper-level detrainment spreads a small part of the simulated water
    // across a regional stencil. Thin ice fibres therefore extend beyond
    // compact rain clouds, without an unrelated all-planet cloud overlay.
    float upperWater=climate.b;
    if(ubuf.group>.5) {
        upperWater=(climate.b*2.0
            +climateAt(uv+vec2(.035,0)).b+climateAt(uv-vec2(.035,0)).b
            +climateAt(uv+vec2(0,.018)).b+climateAt(uv-vec2(0,.018)).b)/6.0;
    }
    float iceMass=smoothstep(.0002,.012,upperWater/max(.10,capacity));
    float convective=smoothstep(.48,.82,climate.r);
    float stable=1.0-convective;
    float front=clamp(length(vec2(east.b-west.b,south.b-north.b))*24.0,0.0,1.0);
    float shear=clamp(length(vec2(east.r-west.r,south.r-north.r))*18.0,0.0,1.0);
    vec3 favour=ubuf.group<.5
        ? vec3(.95*convective,
               .90*stable*(1.0-.5*front),
               .85*(.45+.55*stable)*(.45+.55*front))
        : vec3(.90*(.55+.45*max(front,shear))*(.65+.35*convective),
               .85*stable*terrain.g*(.4+.6*front),
               .95*convective*smoothstep(.45,.90,mass));
    vec3 target=mass*favour;
    vec2 structure=cloudStructure(uv,ubuf.simulationTime);
    if(ubuf.group<.5) {
        target.r*=structure.x;
        target.b*=.30+.70*structure.y;
    } else {
        target.r=iceMass*favour.r*(.25+.75*cirrusFibres(uv,ubuf.simulationTime));
        target.g*=structure.y;
    }
    if(ubuf.initialize>.5) {
        fragColor=encodeClouds(target);
        return;
    }

    float dt=clamp(ubuf.deltaSeconds,0.0,7200.0);
    vec2 back=uv-wind(uv,ubuf.simulationTime)*dt;
    vec3 advected=history(back);
    vec2 texel=vec2(1.0/768.0,1.0/384.0);
    vec3 diffusion=(history(back+vec2(texel.x,0))+history(back-vec2(texel.x,0))
                  +history(back+vec2(0,texel.y))+history(back-vec2(0,texel.y)))*.25;
    advected=mix(advected,diffusion,min(dt*.000005,.025));
    vec3 responseSeconds=ubuf.group<.5 ? vec3(900.0,1800.0,1200.0)
                                         : vec3(2700.0,1800.0,900.0);
    vec3 state=mix(advected,target,vec3(1.0)-exp(-dt/responseSeconds));
    // Let a cloud travel beyond its source and evaporate gradually. Clipping
    // every step to local mass pinned the outline to the moisture map.
    // Optical thickness is not a dryness measure: humid air can sustain a
    // thin cloud. Evaporate according to vapour deficit, not 1 - opacity.
    float humidity=climate.g/max(.10,capacity);
    float dryAir=1.0-smoothstep(.65,.89,humidity);
    vec3 evaporation=ubuf.group<.5 ? vec3(900.0,1800.0,1200.0)
                                   : vec3(5400.0,1800.0,900.0);
    state*=exp(-dt*dryAir/evaporation);
    fragColor=encodeClouds(state);
}
