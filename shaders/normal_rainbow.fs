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
    if (color != vec3(0.0)) {
        color = vec3(uv.x, uv.y, abs(uv.x - uv.y));
    }

    vec3 bloom = vec3(0.0);

    // Gaussian blur kernel weights
    float weight[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

    const int range = 10;
    // Accumulate bloom effect
    for (int i = -range; i <= range; i++) {
        for (int j = -range; j <= range; j++) {
            float w = weight[abs(i)] * weight[abs(j)];
            vec3 addition = vec3(uv.x, uv.y, abs(uv.x - uv.y)).rgb;
            vec3 sub_og_color = texture(texture0, uv + vec2(i, j) * texel).rgb;

            if(sub_og_color != vec3(0.0)) {
                bloom += addition * w;
            }
        }
    }

    bloom *= intensity;

    fragColor = vec4(color + bloom, 1.0);
}

