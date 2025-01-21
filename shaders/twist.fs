#version 330 core

in vec2 TexCoords;  // Input texture coordinates
out vec4 fragColor; // Output fragment color

uniform sampler2D texture0;            // The input texture

void main()
{
    vec2 resolution = vec2(1920, 1080);
    // Center the UV coordinates
    vec2 uv = (gl_FragCoord.xy / resolution) - vec2(0.5);

    // Hardcoded strength and time
    float strength = 60.0;          // Intensity of the twist
    float time = 2.0;              // Static time-like value for effect variation

    // Calculate the distance from the center
    float distance = length(uv);

    // Apply a twist based on the distance
    float angle = strength * distance * sin(time);

    // Rotate the UV coordinates
    float sinAngle = sin(angle);
    float cosAngle = cos(angle);
    vec2 twistedUV = vec2(
        uv.x * cosAngle - uv.y * sinAngle,
        uv.x * sinAngle + uv.y * cosAngle
    );

    // Restore the UV coordinates to the original space
    twistedUV += vec2(0.5);

    // Sample the texture with the twisted UV coordinates
    fragColor = vec4(texture(texture0, twistedUV).rgb, 1);
}
