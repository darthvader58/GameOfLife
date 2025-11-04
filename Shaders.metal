#include <metal_stdlib>
using namespace metal;

// Conway's Game of Life compute shader
kernel void gameOfLife(
    texture2d<float, access::read> currentState [[texture(0)]],
    texture2d<float, access::write> nextState [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = currentState.get_width();
    uint height = currentState.get_height();
    
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // Count living neighbors
    int aliveNeighbors = 0;
    
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            
            // Wrap around edges (toroidal topology)
            int nx = (int(gid.x) + dx + int(width)) % int(width);
            int ny = (int(gid.y) + dy + int(height)) % int(height);
            
            float4 neighbor = currentState.read(uint2(nx, ny));
            if (neighbor.r > 0.5) {
                aliveNeighbors++;
            }
        }
    }
    
    // Read current cell state
    float4 current = currentState.read(gid);
    bool isAlive = current.r > 0.5;
    
    // Apply Conway's rules
    bool nextAlive = false;
    if (isAlive) {
        nextAlive = (aliveNeighbors == 2 || aliveNeighbors == 3);
    } else {
        nextAlive = (aliveNeighbors == 3);
    }
    
    // Write result with age tracking in green channel
    float age = isAlive ? min(current.g + 0.01, 1.0) : 0.0;
    float4 output = nextAlive ? float4(1.0, age, 0.0, 1.0) : float4(0.0, 0.0, 0.0, 1.0);
    nextState.write(output, gid);
}

// Initialize random pattern
kernel void randomize(
    texture2d<float, access::write> state [[texture(0)]],
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
    float4 color = alive ? float4(1.0, 0.0, 0.0, 1.0) : float4(0.0, 0.0, 0.0, 1.0);
    state.write(color, gid);
}

// Visualization shader with color cycling
kernel void visualize(
    texture2d<float, access::read> state [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float& time [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = state.get_width();
    uint height = state.get_height();
    
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    float4 cell = state.read(gid);
    bool isAlive = cell.r > 0.5;
    
    float4 color;
    if (isAlive) {
        // Color based on cell age
        float age = cell.g;
        float hue = fmod(time * 0.05 + age * 0.5 + float(gid.x + gid.y) * 0.001, 1.0);
        
        // HSV to RGB conversion
        float h = hue * 6.0;
        float c = 1.0;
        float x = c * (1.0 - abs(fmod(h, 2.0) - 1.0));
        
        float3 rgb;
        if (h < 1.0) rgb = float3(c, x, 0);
        else if (h < 2.0) rgb = float3(x, c, 0);
        else if (h < 3.0) rgb = float3(0, c, x);
        else if (h < 4.0) rgb = float3(0, x, c);
        else if (h < 5.0) rgb = float3(x, 0, c);
        else rgb = float3(c, 0, x);
        
        // Brightness based on age
        float brightness = 0.5 + 0.5 * age;
        color = float4(rgb * brightness, 1.0);
    } else {
        color = float4(0.01, 0.01, 0.02, 1.0);
    }
    
    output.write(color, gid);
}

// Clear all cells
kernel void clearGrid(
    texture2d<float, access::write> state [[texture(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = state.get_width();
    uint height = state.get_height();
    
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    state.write(float4(0.0, 0.0, 0.0, 1.0), gid);
}
