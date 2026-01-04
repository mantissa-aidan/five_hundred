extern vec2 canvasSize;
extern number time;

// Config
const float CURVATURE = 6.0; // Flatter screen (higher val = less curve)
const float VIGNETTE_STRENGTH = 0.3;
const float SCAN_STRENGTH = 0.05; // Faint scanlines
const float ABERRATION_STRENGTH = 1.0; // Minimal aberration

vec2 curve(vec2 uv) {
    uv = (uv - 0.5) * 2.0;
    uv *= 1.1; 
    uv.x *= 1.0 + pow((abs(uv.y) / CURVATURE), 2.0);
    uv.y *= 1.0 + pow((abs(uv.x) / CURVATURE), 2.0);
    uv  = (uv / 2.0) + 0.5;
    uv =  uv * 0.92 + 0.04;
    return uv;
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec2 uv = texture_coords;
    
    // 1. Curvature
    uv = curve(uv);
    
    // Bounds check
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }
    
    // 2. Chromatic Aberration
    float aber = ABERRATION_STRENGTH / canvasSize.x;
    vec4 result;
    result.r = Texel(texture, vec2(uv.x - aber, uv.y)).r;
    result.g = Texel(texture, vec2(uv.x, uv.y)).g;
    result.b = Texel(texture, vec2(uv.x + aber, uv.y)).b;
    result.a = 1.0;
    
    // 3. Scanlines
    float scan = sin(uv.y * canvasSize.y * 3.1415 * 0.5 + time * 5.0);
    scan = (scan * 0.5 + 0.5) * SCAN_STRENGTH + (1.0 - SCAN_STRENGTH);
    result.rgb *= scan;
    
    // 4. Vignette
    vec2 v_uv = uv * (1.0 - uv.yx); 
    float vig = v_uv.x * v_uv.y * 15.0; 
    vig = pow(vig, VIGNETTE_STRENGTH); 
    result.rgb *= vig;
    
    // Increase brightness slightly to compensate for scanlines
    result.rgb *= 1.1;
    
    return result * color;
}
