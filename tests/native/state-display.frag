#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix; float qt_Opacity; } ubuf;
layout(binding=1) uniform sampler2D low;
layout(binding=2) uniform sampler2D high;
layout(binding=3) uniform sampler2D climate;
vec3 decodeClouds(vec4 value) {
    vec4 b=floor(value*255.0+.5);
    return (b.rgb*4.0+vec3(floor(b.a/16.0),mod(floor(b.a/4.0),4.0),mod(b.a,4.0)))/1023.0;
}
vec3 decodeClimate(vec4 value) {
    vec4 bytes=floor(value*255.0+.5);
    return vec3(bytes.r/255.0,
                (bytes.g*16.0+floor(bytes.a/16.0))/4095.0,
                (bytes.b*16.0+mod(bytes.a,16.0))/4095.0);
}
vec3 climatePixel(vec2 pixel) {
    vec2 uv=(pixel+.5)/vec2(384.0,192.0);
    uv=vec2(fract(uv.x),clamp(uv.y,.5/192.0,1.0-.5/192.0));
    return decodeClimate(texture(climate,uv));
}
vec3 climateAt(vec2 uv) {
    vec2 p=uv*vec2(384.0,192.0)-.5;
    vec2 i=floor(p),f=fract(p);
    return mix(mix(climatePixel(i),climatePixel(i+vec2(1,0)),f.x),
               mix(climatePixel(i+vec2(0,1)),climatePixel(i+vec2(1,1)),f.x),f.y);
}
void main() {
    vec2 uv=vec2(fract(qt_TexCoord0.x*3.0),qt_TexCoord0.y);
    vec3 state=qt_TexCoord0.x<1.0/3.0 ? decodeClouds(texture(low,uv))
        : (qt_TexCoord0.x<2.0/3.0 ? decodeClouds(texture(high,uv)) : climateAt(uv));
    bool invalid=any(isnan(state))||any(isinf(state))||any(lessThan(state,vec3(-.001)))||any(greaterThan(state,vec3(1.001)));
    fragColor=vec4(invalid ? vec3(1,0,1) : state,1.0)*ubuf.qt_Opacity;
}
