#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(binding=1) uniform sampler2D field;
void main() {
    vec2 bytes = floor(texture(field, qt_TexCoord0).rg * 255.0 + 0.5);
    float value = (bytes.x * 256.0 + bytes.y) / 65535.0;
    fragColor = vec4(vec3(value), 1.0);
}
