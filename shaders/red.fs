#version 330 core
in vec2 fragTexCoord;                  // Texture coordinates from vertex shader
out vec4 fragColor;

uniform sampler2D texture0;            // The input texture

void main()
{
    vec2 resolution = vec2(1920, 1080);
    vec2 uv = gl_FragCoord.xy / resolution;
    vec3 color = texture(texture0, uv).rgb;

    float alpha = 1.0;

    if(color == vec3(0.0)) {
        alpha = 0.0;
    }

    fragColor = vec4(color, alpha);
}

