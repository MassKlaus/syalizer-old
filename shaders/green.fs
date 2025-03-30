#version 330 core
in vec2 fragTexCoord;                  // Texture coordinates from vertex shader
out vec4 fragColor;

uniform sampler2D texture0;            // The input texture

void main()
{
    fragColor = vec4(vec3(0.0, 1.0, 0.0), 1.0);
}

