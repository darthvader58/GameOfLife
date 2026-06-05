#include <metal_stdlib>
using namespace metal;

struct RenderUniforms {
    uint gridWidth;
    uint gridHeight;
    uint viewportWidth;
    uint viewportHeight;
    float time;
    float zoom;
    float panX;
    float panY;
};

static uint wrapCoordinate(int value, uint size)
{
    return uint((value + int(size)) % int(size));
}

static float3 heatColor(float intensity)
{
    float t = clamp(intensity, 0.0, 1.0);
    float3 cold = float3(0.02, 0.04, 0.08);
    float3 mid = float3(0.10, 0.66, 0.72);
    float3 hot = float3(1.00, 0.86, 0.35);

    if (t < 0.5) {
        return mix(cold, mid, t * 2.0);
    }

    return mix(mid, hot, (t - 0.5) * 2.0);
}

// Conway's Game of Life compute shader
kernel void gameOfLife(
    texture2d<uint, access::read> currentState [[texture(0)]],
    texture2d<uint, access::write> nextState [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = currentState.get_width();
    uint height = currentState.get_height();
    
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    uint aliveNeighbors = 0;
    
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            
            uint nx = wrapCoordinate(int(gid.x) + dx, width);
            uint ny = wrapCoordinate(int(gid.y) + dy, height);
            
            if (currentState.read(uint2(nx, ny)).r > 0) {
                aliveNeighbors++;
            }
        }
    }
    
    bool isAlive = currentState.read(gid).r > 0;
    
    bool nextAlive = isAlive
        ? (aliveNeighbors == 2 || aliveNeighbors == 3)
        : (aliveNeighbors == 3);
    
    nextState.write(nextAlive ? 255 : 0, gid);
}

// Initialize random pattern
kernel void randomize(
    texture2d<uint, access::write> state [[texture(0)]],
    constant float& density [[buffer(0)]],
    constant uint& seed [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = state.get_width();
    uint height = state.get_height();
    
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // Simple hash-based random
    uint hash = gid.x * 73856093 ^ gid.y * 19349663 ^ seed * 83492791;
    float random = float(hash % 10000) / 10000.0;
    
    bool alive = random < density;
    state.write(alive ? 255 : 0, gid);
}

// Render the toroidal plane into the current drawable.
kernel void visualize(
    texture2d<uint, access::read> state [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant RenderUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }

    float aspect = float(uniforms.viewportWidth) / max(float(uniforms.viewportHeight), 1.0);
    float2 uv = (float2(gid) + 0.5) / float2(uniforms.viewportWidth, uniforms.viewportHeight);
    float2 centered = uv - 0.5;

    centered.x *= aspect;
    centered /= max(uniforms.zoom, 1.0);
    centered += float2(uniforms.panX, uniforms.panY);

    float2 wrapped = fract(centered + 0.5);
    uint2 cell = uint2(
        wrapped.x * float(uniforms.gridWidth),
        wrapped.y * float(uniforms.gridHeight)
    );
    
    bool isAlive = state.read(cell).r > 0;

    uint neighbors = 0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            uint nx = wrapCoordinate(int(cell.x) + dx, uniforms.gridWidth);
            uint ny = wrapCoordinate(int(cell.y) + dy, uniforms.gridHeight);
            neighbors += state.read(uint2(nx, ny)).r > 0 ? 1 : 0;
        }
    }

    neighbors -= isAlive ? 1 : 0;
    
    float4 color;
    if (isAlive) {
        float pulse = 0.88 + 0.12 * sin(uniforms.time * 2.2 + float(cell.x ^ cell.y) * 0.03);
        color = float4(heatColor(float(neighbors) / 8.0) * pulse, 1.0);
    } else {
        float gridLine = min(fract(wrapped.x * float(uniforms.gridWidth)),
                             fract(wrapped.y * float(uniforms.gridHeight)));
        float line = uniforms.zoom > 8.0 && gridLine < 0.035 ? 0.035 : 0.0;
        float glow = float(neighbors) * 0.018;
        color = float4(float3(0.006, 0.009, 0.014) + glow + line, 1.0);
    }
    
    output.write(color, gid);
}

// Clear all cells
kernel void clearGrid(
    texture2d<uint, access::write> state [[texture(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = state.get_width();
    uint height = state.get_height();
    
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    state.write(0, gid);
}
