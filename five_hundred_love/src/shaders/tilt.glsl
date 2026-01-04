extern number pitch;
extern number roll;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    // vertex_position is in local space (centered ideally)
    
    float cX = cos(pitch);
    float sX = sin(pitch);
    float cY = cos(roll);
    float sY = sin(roll);
    
    // Original Position (assume z=0)
    vec4 pos = vertex_position;
    
    // Rotate around X (Pitch)
    // y' = y*cX - z*sX  (z=0 => y*cX)
    // z' = y*sX + z*cX  (z=0 => y*sX)
    float y1 = pos.y * cX;
    float z1 = pos.y * sX;
    
    // Rotate around Y (Roll)
    // x'' = x*cY + z'*sY
    // z'' = -x*sY + z'*cY
    float x2 = pos.x * cY + z1 * sY;
    float y2 = y1;
    float z2 = -pos.x * sY + z1 * cY;
    
    // Perspective Projection
    // Objects deeper (positive z? depends on handedness) should preserve scale?
    // Let's assume camera is at -500 z.
    float fov = 500.0;
    
    // If z2 is positive (towards screen/viewer with this rotation?), we usually want z to act as depth.
    // In this math, z2 varies. If z2 goes "back", scale decreases.
    // Let's rely on standard perspective divide: scale = d / (d - z) or similar.
    // Here, let's say "out of screen" (z<0?) -> larger.
    // Let's standardize: z2 is depth relative to center pivot.
    // We shift it "away" by fov distance to avoid div by zero.
    
    float scale = fov / (fov + z2);
    
    pos.x = x2 * scale;
    pos.y = y2 * scale;
    
    // Leave z/w alone for now as we are doing 2D draw
    
    return transform_projection * pos;
}
