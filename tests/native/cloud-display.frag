#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf { mat4 qt_Matrix; float qt_Opacity; } ubuf;
layout(binding=1) uniform sampler2D field;
void main() {
    vec4 b=floor(texture(field,qt_TexCoord0)*255.0+.5);
    vec3 density=(b.rgb*4.0+vec3(floor(b.a/16.0),mod(floor(b.a/4.0),4.0),mod(b.a,4.0)))/1023.0;
    fragColor=vec4(density,1.0);
}
