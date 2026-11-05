#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix; float qt_Opacity; } ubuf;
layout(binding=1) uniform sampler2D stateTexture;

vec3 decodeState(vec4 value) {
    vec4 b=floor(value*255.0+0.5);
    return (b.rgb*4.0+vec3(floor(b.a/16.0),mod(floor(b.a/4.0),4.0),mod(b.a,4.0)))/1023.0;
}
void main() {
    // Display the actual retained RGBA8 texture. Alpha stores the low two
    // bits of each packed 10-bit channel, so decode before visual inspection.
    vec3 state=decodeState(texture(stateTexture,qt_TexCoord0));
    fragColor=vec4(state,1.0)*ubuf.qt_Opacity;
}
