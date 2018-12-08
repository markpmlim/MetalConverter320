//
//  Shaders.metal
//
//  Created by Mark Lim Pak Mun on 06/12/2018.
//  Copyright © Incremental Innovation 2018 . All rights reserved.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;


// Vertex shader outputs and per-fragment inputs.
typedef struct
{
    float2 position;
    float2 texCoord;
} Vertex;

typedef struct
{
    float4 position [[position]];   // in clip space
    float2 texCoord;
} RasterizerData;


vertex RasterizerData
vertexShader(       uint        vertexID    [[ vertex_id ]],
             const device Vertex *vertices  [[ buffer(0)]])
{
    RasterizerData out;
    
    float2 position = vertices[vertexID].position;
    // convert incoming position into clip space
    out.position.xy = position;
    out.position.z  = 0.0;
    out.position.w  = 1.0;

    // pass thru to the fragment shader
    out.texCoord = vertices[vertexID].texCoord;
    
    return out;
}

// Fragment function
fragment half4
fragmentShader(RasterizerData in            [[stage_in]],
               texture2d<half> colorTexture [[ texture(0) ]])
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);

    // Sample the texture and return the color to colorSample
    const half4 colorSample = colorTexture.sample(textureSampler,
                                                  in.texCoord);
    // We return the color of the texture
    return colorSample;
}

/// ============ kernel function ============
#define bytesPerScanLine    160
#define sizeOfColorTable    16                  // in terms of 16-bit words

/*
 Converts a IIGS "pixel" to an ordinary rgba pixel.
 */
kernel void convert320(const device uchar *iigsBitmap           [[buffer(0)]],
                       const device uchar *scbs                 [[buffer(1)]],
                       const device ushort *colorTables         [[buffer(2)]],
                       texture2d<half, access::write> output    [[texture(0)]],
                       uint2 gid                                [[thread_position_in_grid]])
{
    uint width = output.get_width();
    uint height = output.get_height();
    if ((gid.x >= width) || (gid.y >= height))
    {
        // Return early if the pixel is out of bounds
        return;
    }

    uint col = gid.x;                           // 0 - 319 for standard Apple IIGS 320x200 graphics
    uint row = gid.y;                           // 0 - 199
    uint whichColorTable = scbs[row] & 0x0f;    // 0 - 15
    uint bitmapIndex = row * bytesPerScanLine + col/2;
    uchar pixels = iigsBitmap[bitmapIndex];     // 2 IIGS 4-bit "pixels"/byte
    uint whichColorEntry;                       // 0 - 15
    if (col % 2) {
        // odd column # - pixel #1 (bits 0-3)
        whichColorEntry = pixels & 0x0f;
    }
    else {
        // even column # - pixel #0 (bits 4-7)
        whichColorEntry = (pixels >> 4) & 0x0f;
    }
    uint colorTableIndex = sizeOfColorTable*whichColorTable + whichColorEntry;
    ushort color = colorTables[colorTableIndex];
    ushort red = (color & 0x0f00) >> 8;         // 0 - 15
    ushort green = (color & 0x00f0) >> 4;
    ushort blue = (color & 0x000f);
    // Scale the values [0,15] to [0,255]
    red *= 17;                                  // 0, 17, 34, ... , 238, 255
    green *= 17;
    blue *= 17;

    // Compute the rbga8888 colour of the pixel ...
    half4 color4 = half4(red, green, blue, 255);
    // ... and scale its values to [0, 1.0]
    color4 *= 1/255.0;
    // Write the pixel to the texture.
    output.write(color4, gid);
}

