#version 330 core
in vec2 fragTexCoord;                  // Texture coordinates from vertex shader
out vec4 fragColor;

uniform sampler2D texture0;            // The input texture

void main()
{
    vec2 resolution = vec2(1920, 1080);
    float intensity = 1.1;

    vec2 texel = 1.0 / resolution;
    vec2 uv = gl_FragCoord.xy / resolution;

    vec3 color = texture(texture0, uv).rgb;

    const int range = 5;

    vec2 found_pixel = vec2(0);
    float min_length = 100;

    // Accumulate bloom effect
    if(color == vec3(0.0)) {
        for (int i = -range; i <= range; i++) {
            for (int j = -range; j <= range; j++) {
                vec3 sub_og_color = texture(texture0, uv + vec2(i, j) * texel).rgb;

                if(sub_og_color != vec3(0.0)) {
                    color = sub_og_color;
                    found_pixel = vec2(float(i), float(j));
                    float len = length(found_pixel);

                    if(min_length > len) {
                        min_length = len;
                    }
                }
            }
        }
    }

    if (found_pixel != vec2(0)) {
        color = color / (1 + min_length);
    }

    fragColor = vec4(color, 1.0);
}

