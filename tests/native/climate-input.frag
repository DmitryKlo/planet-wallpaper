#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix; float qt_Opacity; float condensate; } ubuf;
vec4 encodeClimate(vec3 state) {
    vec3 q=floor(clamp(state,0.0,1.0)*vec3(255.0,4095.0,4095.0)+.5);
    float residual=mod(q.g,16.0)*16.0+mod(q.b,16.0);
    return vec4(q.r,floor(q.g/16.0),floor(q.b/16.0),residual)/255.0;
}
void main() {
    fragColor=encodeClimate(vec3(.10+.75*qt_TexCoord0.x,.30+.55*qt_TexCoord0.y,ubuf.condensate))*ubuf.qt_Opacity;
}
