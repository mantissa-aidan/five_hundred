uniform float time;
uniform vec2 resolution;

// Simple 2D noise
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
{
    vec2 uv = screen_coords / resolution;
    uv = uv - vec2(0.5);
    
    float aspect = resolution.x / resolution.y;
    uv.x *= aspect;
    
    // Turbulence
    // Slower time scale for noise so it evolves organically
    // Lower frequency (uv * 2.0) for larger organic shapes
    float turb = fbm(uv * 2.0 + time * 0.009);
    
    // High distortion amount
    float distortion = (turb - 0.5) * 4.0; 
    
    float radius = length(uv) + 1e-4;
    float angle = atan(uv.y, uv.x);
    
    // Distort both angle and radius for organic feel
    angle += distortion;
    radius += distortion * 0.2;
    
    // Spiral Params
    float arms = 2.0; // Reduced arms
    float density = 5.0; // Reduced density for looser feel
    float speed = 0.01; // Extremely slow rotation
    
    float val = sin(angle * arms + log(radius) * density - time * speed);
    
    float pattern = smoothstep(-0.5, 0.5, val);
    
    vec3 col1 = color.rgb * 0.7; 
    vec3 col2 = color.rgb * 1.0; 
    
    vec3 final_rgb = mix(col1, col2, pattern);
    
    float v_radius = length(uv / vec2(aspect, 1.0));
    float vignette = 1.0 - smoothstep(0.5, 1.2, v_radius);
    final_rgb *= vignette;
    
    return vec4(final_rgb, 1.0);
}
