#version 330

uniform sampler2D texture0;

out vec4 fragColor;

void main() {
    // Hardcoded resolution (e.g., 800x450) and intensity
    vec2 resolution = vec2(1920, 1080);
    float intensity = 25.1;

    vec2 texel = 1.0 / resolution;
    vec2 uv = gl_FragCoord.xy / resolution;

    vec3 color = texture(texture0, uv).rgb;
    vec3 bloom = vec3(0.0);

    // Gaussian blur kernel weights
    float weight[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

    const int range = 8;
    // Accumulate bloom effect
    for (int i = -range; i <= range; i++) {
        for (int j = -range; j <= range; j++) {
            float w = weight[abs(i)] * weight[abs(j)];
            bloom += texture(texture0, uv + vec2(i, j) * texel).rgb * w;
        }
    }

    bloom *= intensity;

    fragColor = vec4(color + bloom, 1.0);
}
